import Foundation
import OSLog

/// Uploads a build to TestFlight and manages beta distribution.
///
/// Uploads an IPA, optionally waits for Apple's processing, then distributes
/// to the specified beta groups.
///
/// ## Usage
/// ```swift
/// let result = try await TestFlightAction().run(
///     with: .init(ipaPath: "./build/MyApp.ipa", groups: ["Internal QA"]),
///     context: context
/// )
/// print("Distributed to \(result.distributedGroups.count) groups")
/// ```
public struct TestFlightAction: Action {
    public static let name = "testflight"
    public static let description = "Upload to TestFlight and manage beta distribution"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", TestFlightAction.self)

    /// Creates a `TestFlightAction`.
    public init() {}

    /// Configuration for the TestFlight action.
    public struct Options: Codable, Sendable {
        /// Path to the `.ipa` file to upload.
        public var ipa: String?

        /// Beta group names to distribute to after processing.
        public var groups: [String]?

        /// Release notes / changelog for testers.
        public var changelog: String?

        /// Whether to skip waiting for Apple's build processing.
        public var skipWaitingForBuildProcessing: Bool?

        /// Whether to distribute to external testers.
        public var distributeExternal: Bool?

        /// Creates `Options` for the TestFlight action.
        ///
        /// All parameters are optional; unset values fall back to `ResolvedConfig`.
        public init(
            ipa: String? = nil,
            groups: [String]? = nil,
            changelog: String? = nil,
            skipWaitingForBuildProcessing: Bool? = nil,
            distributeExternal: Bool? = nil
        ) {
            self.ipa = ipa
            self.groups = groups
            self.changelog = changelog
            self.skipWaitingForBuildProcessing = skipWaitingForBuildProcessing
            self.distributeExternal = distributeExternal
        }
    }

    /// Result of a TestFlight upload.
    public struct Result: Codable, Sendable {
        /// The App Store Connect build ID.
        public let buildID: String?

        /// The version string for the uploaded build.
        public let version: String?

        /// Names of groups the build was distributed to.
        public let distributedGroups: [String]

        /// Whether build processing was completed.
        public let processingComplete: Bool

        /// Creates a `Result`.
        public init(
            buildID: String? = nil,
            version: String? = nil,
            distributedGroups: [String] = [],
            processingComplete: Bool = false
        ) {
            self.buildID = buildID
            self.version = version
            self.distributedGroups = distributedGroups
            self.processingComplete = processingComplete
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .ios else {
            throw ShipItError.invalidConfiguration(reason: "TestFlightAction requires iOS platform")
        }
        let ipaPath = options.ipa ?? locateExportedIPA(context: context)
        guard let ipaPath else {
            throw ShipItError.invalidConfiguration(reason: "TestFlight requires an IPA path. Pass --ipa /path/to/App.ipa.")
        }
        guard let bundleID = context.config.bundleID else {
            throw ShipItError.invalidConfiguration(
                reason: "TestFlight requires app.bundle_id. Set app.bundle_id in Shipfile.yml or export SHIPIT_APP__BUNDLE_ID.")
        }

        let ipaURL = URL(fileURLWithPath: ipaPath)
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            throw ShipItError.uploadFailed(asset: ipaPath, reason: "IPA not found: \(ipaPath)")
        }

        let skipWaiting =
            options.skipWaitingForBuildProcessing
            ?? context.config.skipWaitingForBuildProcessing
        let groups = options.groups ?? context.config.testFlightGroups
        let needsBuildID = !skipWaiting || !groups.isEmpty

        logger.info("Uploading to TestFlight: \(ipaPath)")
        let uploadResult = try await IPAUploadService(client: context.appStoreConnect).uploadIPA(
            at: ipaURL,
            bundleID: bundleID,
            context: context,
            resolveBuildID: needsBuildID
        )

        let buildID = uploadResult.buildID

        var processingComplete = false
        if !skipWaiting, let buildID {
            logger.info("Waiting for build processing (build: \(buildID))...")
            processingComplete = try await waitForProcessing(buildID: buildID, context: context)
        }

        // Distribute to beta groups
        var distributedGroups: [String] = []

        if processingComplete && !groups.isEmpty, let buildID {
            distributedGroups = try await distributeToGroups(
                buildID: buildID,
                bundleID: bundleID,
                groupNames: groups,
                changelog: options.changelog ?? context.config.testFlightChangelog,
                context: context
            )
        }

        logger.info("TestFlight upload complete. Build: \(buildID ?? "unknown"), Groups: \(distributedGroups.joined(separator: ", "))")
        return Result(
            buildID: buildID,
            version: nil,
            distributedGroups: distributedGroups,
            processingComplete: processingComplete
        )
    }

    private func locateExportedIPA(context: ActionContext) -> String? {
        let outputDirectory = context.config.exportOutputDirectory ?? "./build/export"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: outputDirectory) else {
            return nil
        }
        guard let ipaName = contents.sorted().first(where: { $0.hasSuffix(".ipa") }) else {
            return nil
        }
        return (outputDirectory as NSString).appendingPathComponent(ipaName)
    }

    // MARK: - Private Helpers

    private func waitForProcessing(buildID: String, context: ActionContext) async throws -> Bool {
        let maxAttempts = 60
        let delaySeconds: UInt64 = 30

        for attempt in 1...maxAttempts {
            logger.debug("Checking build processing status (attempt \(attempt)/\(maxAttempts))")

            let build: ASCResponse<ASCBuild> = try await context.appStoreConnect.get("/v1/builds/\(buildID)")

            if let state = build.data.attributes?.processingState {
                switch state {
                case "VALID":
                    logger.info("Build \(buildID) processing complete")
                    return true
                case "INVALID":
                    throw ShipItError.uploadFailed(asset: buildID, reason: "Build processing failed: INVALID state")
                case "PROCESSING":
                    logger.debug("Build still processing... waiting \(delaySeconds)s")
                    try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                default:
                    logger.debug("Build state: \(state)")
                    try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                }
            } else {
                try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }

        logger.warning("Timed out waiting for build processing after \(maxAttempts * 30)s")
        return false
    }

    private func distributeToGroups(
        buildID: String,
        bundleID: String,
        groupNames: [String],
        changelog: String?,
        context: ActionContext
    ) async throws -> [String] {
        let apps: ASCListResponse<ASCApp> = try await context.appStoreConnect.get(
            "/v1/apps",
            query: ["filter[bundleId]": bundleID]
        )
        guard let app = apps.data.first else {
            throw ShipItError.apiError(statusCode: 404, body: "App with bundle ID '\(bundleID)' not found in App Store Connect")
        }

        // Fetch all beta groups for the app, then attach this build to the requested ones.
        let betaGroups: ASCListResponse<ASCBetaGroup> = try await context.appStoreConnect.get(
            "/v1/betaGroups",
            query: ["filter[app]": app.id]
        )

        var distributedTo: [String] = []

        for groupName in groupNames {
            guard let group = betaGroups.data.first(where: { $0.attributes?.name == groupName }) else {
                logger.warning("Beta group '\(groupName)' not found")
                continue
            }

            logger.info("Distributing build \(buildID) to group '\(groupName)'")

            let distributionBody = BetaGroupDistributionRequest(
                data: [.init(type: "builds", id: buildID)]
            )

            let _: NoContentResponse = try await context.appStoreConnect.post(
                "/v1/betaGroups/\(group.id)/relationships/builds",
                body: distributionBody
            )

            distributedTo.append(groupName)
        }

        return distributedTo
    }
}

private struct BetaGroupDistributionRequest: Encodable, Sendable {
    let data: [DataItem]

    struct DataItem: Encodable, Sendable {
        let type: String
        let id: String
    }
}
