import Foundation
import OSLog
import SwiftyShell

/// Coordinates the IPA upload to App Store Connect / TestFlight.
///
/// Uses `xcrun altool --upload-app` (the standard Apple CLI tool) to upload
/// the binary, then resolves the resulting build ID from the ASC REST API.
/// The `/v1/builds` REST endpoint does not support `CREATE`; all actual IPA
/// uploads must go through altool / Transporter.
///
/// **Key file placement:** `altool --apiKey` looks for the p8 key at
/// `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.  If the key isn't
/// already there, this service writes it to that path for the duration of the
/// upload and removes it on completion.
public struct IPAUploadService: Sendable {
    private let client: AppStoreConnectClient
    private let pollMaxAttempts: Int
    private let pollDelaySeconds: UInt64
    private let logger = Logger.forType(subsystem: "ShipItSwifty", IPAUploadService.self)

    /// Creates an `IPAUploadService` bound to an ASC client.
    ///
    /// - Parameters:
    ///   - client: The ASC client used for app and build lookups.
    ///   - pollMaxAttempts: Maximum number of times to poll ASC for the build after upload. Default: 10.
    ///   - pollDelaySeconds: Seconds between poll attempts. Default: 15.
    public init(
        client: AppStoreConnectClient,
        pollMaxAttempts: Int = 10,
        pollDelaySeconds: UInt64 = 15
    ) {
        self.client = client
        self.pollMaxAttempts = pollMaxAttempts
        self.pollDelaySeconds = pollDelaySeconds
    }

    /// Result of a completed IPA upload.
    public struct Result: Codable, Sendable {
        /// The App Store Connect app ID the IPA was uploaded to, if resolved.
        public let appID: String?
        /// The build ID assigned by App Store Connect, if resolved.
        public let buildID: String?
        /// The original IPA file name.
        public let fileName: String

        /// Creates an `IPAUploadService.Result`.
        public init(appID: String? = nil, buildID: String? = nil, fileName: String) {
            self.appID = appID
            self.buildID = buildID
            self.fileName = fileName
        }
    }

    /// Uploads an IPA file for the given bundle identifier.
    ///
    /// - Parameters:
    ///   - ipaURL: Local path to the IPA file.
    ///   - bundleID: App bundle identifier used to resolve the ASC app.
    ///   - context: Current action context (provides shell, config, and credentials).
    ///   - resolveBuildID: Whether to resolve the uploaded build ID from ASC after `altool` succeeds.
    /// - Returns: The uploaded build metadata.
    public func uploadIPA(
        at ipaURL: URL,
        bundleID: String,
        context: ActionContext,
        resolveBuildID: Bool = true
    ) async throws -> Result {
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            throw ShipItError.uploadFailed(
                asset: ipaURL.lastPathComponent,
                reason: "IPA file not found at: \(ipaURL.path)"
            )
        }

        guard let keyID = context.config.ascKeyID else {
            throw ShipItError.invalidConfiguration(
                reason: "ASC key ID is required for IPA upload. Set ASC_KEY_ID or app_store_connect.key_id in Shipfile.yml."
            )
        }
        guard let issuerID = context.config.ascIssuerID else {
            throw ShipItError.invalidConfiguration(
                reason: "ASC issuer ID is required for IPA upload. Set ASC_ISSUER_ID or app_store_connect.issuer_id in Shipfile.yml."
            )
        }
        guard let keyData = context.config.ascPrivateKeyData else {
            throw ShipItError.invalidConfiguration(
                reason: "ASC private key is required for IPA upload. Set ASC_PRIVATE_KEY or ASC_PRIVATE_KEY_PATH."
            )
        }

        logger.info("Uploading IPA '\(ipaURL.lastPathComponent)' for bundle ID '\(bundleID)'")

        // altool looks for the p8 key at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8.
        // Stage it there if it isn't already present.
        let keyDir = context.shell.homeDirectory
            .appendingPathComponent(".appstoreconnect/private_keys", isDirectory: true)
        try FileManager.default.createDirectory(at: keyDir, withIntermediateDirectories: true)
        let standardKeyPath = keyDir.appendingPathComponent("AuthKey_\(keyID).p8")
        let wroteKey = !FileManager.default.fileExists(atPath: standardKeyPath.path)
        if wroteKey {
            logger.debug("Writing p8 key to standard altool location: \(standardKeyPath.path)")
            try keyData.write(to: standardKeyPath, options: [.atomic])
        }
        defer {
            if wroteKey {
                logger.debug("Removing staged p8 key from altool location")
                try? FileManager.default.removeItem(at: standardKeyPath)
            }
        }

        // Run the upload. SwiftyShell throws ShellError on non-zero exit, so we
        // catch it here and convert to a domain-specific ShipItError.
        logger.info("Running xcrun altool --upload-app")
        do {
            _ = try await Altool(context: context.shell)
                .uploadApp(ipaPath: ipaURL.path, platform: "ios", apiKey: keyID, apiIssuer: issuerID)
                .run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let detail = shellOutput.stderr.isEmpty ? shellOutput.stdout : shellOutput.stderr
            throw ShipItError.uploadFailed(
                asset: ipaURL.lastPathComponent,
                reason: "altool upload failed (exit \(shellOutput.exitCode)): \(detail)"
            )
        }

        if !resolveBuildID {
            logger.info("altool upload completed; skipping App Store Connect build lookup")
            return Result(fileName: ipaURL.lastPathComponent)
        }

        logger.info("altool upload completed, locating build in App Store Connect")

        // Resolve the app.
        let apps: ASCListResponse<ASCApp> = try await client.get(
            "/v1/apps",
            query: ["filter[bundleId]": bundleID]
        )
        guard let app = apps.data.first else {
            throw ShipItError.apiError(
                statusCode: 404,
                body: "App with bundle ID '\(bundleID)' not found in App Store Connect"
            )
        }

        // Extract CFBundleVersion from the IPA so we can identify the build in ASC.
        let buildVersion = try await extractBuildVersion(from: ipaURL, shell: context.shell)
        logger.info("Looking for build version '\(buildVersion)' in App Store Connect (app: \(app.id))")

        // Poll for the build to appear — ASC registration is asynchronous.
        let buildID = try await pollForBuild(
            appID: app.id,
            buildVersion: buildVersion,
            maxAttempts: pollMaxAttempts,
            delaySeconds: pollDelaySeconds
        )

        logger.info("Completed IPA upload for build '\(buildID)'")
        return Result(appID: app.id, buildID: buildID, fileName: ipaURL.lastPathComponent)
    }

    // MARK: - Private Helpers

    /// Extracts `CFBundleVersion` from an IPA's embedded `Info.plist`.
    ///
    /// Runs `unzip -p` piped through `plutil` inside a bash subshell so that
    /// the glob `Payload/*.app/Info.plist` expands correctly.
    private func extractBuildVersion(from ipaURL: URL, shell: ShellContext) async throws -> String {
        // Single-quote the path to handle spaces; escape any embedded single quotes.
        let escapedPath = ipaURL.path.replacingOccurrences(of: "'", with: "'\\''")
        do {
            let output = try await Bash(context: shell)
                .script("unzip -p '\(escapedPath)' 'Payload/*.app/Info.plist' | plutil -extract CFBundleVersion raw -")
                .run()
            let version = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty else {
                throw ShipItError.uploadFailed(
                    asset: ipaURL.lastPathComponent,
                    reason: "CFBundleVersion is empty in IPA Info.plist"
                )
            }
            return version
        } catch let ShellError.exitFailure(_, shellOutput) {
            throw ShipItError.uploadFailed(
                asset: ipaURL.lastPathComponent,
                reason: "Could not extract CFBundleVersion from IPA (exit \(shellOutput.exitCode)): \(shellOutput.stderr)"
            )
        }
    }

    /// Polls the ASC API until the uploaded build appears, then returns its ID.
    ///
    /// Apple registers builds asynchronously after the altool upload completes,
    /// so a short poll loop is needed before the build is queryable.
    private func pollForBuild(
        appID: String,
        buildVersion: String,
        maxAttempts: Int,
        delaySeconds: UInt64
    ) async throws -> String {
        for attempt in 1...maxAttempts {
            logger.debug("Checking for build version '\(buildVersion)' (attempt \(attempt)/\(maxAttempts))")

            let builds: ASCListResponse<ASCBuild> = try await client.get(
                "/v1/builds",
                query: [
                    "filter[app]": appID,
                    "filter[version]": buildVersion,
                    "sort": "-uploadedDate",
                    "limit": "1",
                ]
            )

            if let build = builds.data.first {
                logger.info("Found build '\(build.id)' for version '\(buildVersion)'")
                return build.id
            }

            if attempt < maxAttempts {
                logger.debug("Build not yet visible in ASC, waiting \(delaySeconds)s…")
                try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }

        throw ShipItError.uploadFailed(
            asset: buildVersion,
            reason: "Build version '\(buildVersion)' not found in App Store Connect after \(maxAttempts) attempts (\(maxAttempts * Int(delaySeconds))s)"
        )
    }
}

private extension ShellContext {
    var homeDirectory: URL {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
