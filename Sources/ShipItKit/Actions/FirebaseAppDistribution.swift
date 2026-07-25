import Foundation
import Logging

/// Uploads a signed IPA or APK to Firebase App Distribution and releases it to tester groups.
///
/// Runs the upload → poll → release-notes → distribute sequence against the App Distribution
/// v1 API. Works on both iOS and Android; the platform is derived from the Firebase app ID
/// and checked against the artifact's extension so a mismatched build fails before upload.
///
/// ## Credentials
/// The service-account key is resolved, in order, from the `service_account_path` option, the
/// `FIREBASE_SERVICE_ACCOUNT_JSON` environment variable (raw JSON), or
/// `GOOGLE_APPLICATION_CREDENTIALS` (Application Default Credentials path). Inline credentials
/// in a Shipfile are never accepted.
///
/// ## Usage
/// ```yaml
/// - action: firebase-app-distribution
///   options:
///     app_id: ${FIREBASE_IOS_QA_APP_ID}
///     artifact_path: ./build/staging-export/App.ipa
///     groups:
///       - qa-testers
///     release_notes: Staging candidate
/// ```
///
/// ## Topics
/// ### Configuration
/// - ``Options``
/// ### Results
/// - ``Result``
public struct FirebaseAppDistributionAction: Action {
    /// The registered name used in Shipfile workflows.
    public static let name = "firebase-app-distribution"

    /// Human-readable description for `--help` output.
    public static let description =
        "Upload a signed IPA or APK to Firebase App Distribution and release it to tester groups"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", FirebaseAppDistributionAction.self)

    /// Injected client used by tests. When nil, a client is built from resolved credentials.
    private let clientOverride: FirebaseAppDistributionClient?

    /// Injected sleep hook used by tests to avoid real polling delays.
    private let sleepHook: (@Sendable (Duration) async throws -> Void)?

    /// Creates a `FirebaseAppDistributionAction`.
    public init() {
        self.clientOverride = nil
        self.sleepHook = nil
    }

    /// Creates an action with an injected client, for tests.
    init(
        client: FirebaseAppDistributionClient,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) {
        self.clientOverride = client
        self.sleepHook = sleep
    }

    /// Configuration options for the Firebase App Distribution action.
    public struct Options: Codable, Sendable {
        /// The Firebase app ID, e.g. `1:1234567890:ios:abc123`. Required.
        ///
        /// Deliberately explicit rather than derived from a local `GoogleService-Info.plist`
        /// or `google-services.json`: deriving it would let a stale or wrong-environment
        /// config file silently redirect a release to another Firebase project.
        public var appId: String?

        /// Path to the `.ipa` or `.apk` to upload. Required.
        public var artifactPath: String?

        /// Tester group aliases to distribute to.
        public var groups: [String]?

        /// Individual tester emails to distribute to.
        public var testers: [String]?

        /// Release notes shown to testers.
        public var releaseNotes: String?

        /// Path to a Google service-account JSON key. Overrides environment credentials.
        public var serviceAccountPath: String?

        /// When true, validate everything and report the planned distribution without uploading.
        public var dryRun: Bool?

        /// Seconds to wait for the upload to finish processing. Defaults to 300.
        public var timeoutSeconds: Int?

        /// Creates `Options` for the Firebase App Distribution action.
        public init(
            appId: String? = nil,
            artifactPath: String? = nil,
            groups: [String]? = nil,
            testers: [String]? = nil,
            releaseNotes: String? = nil,
            serviceAccountPath: String? = nil,
            dryRun: Bool? = nil,
            timeoutSeconds: Int? = nil
        ) {
            self.appId = appId
            self.artifactPath = artifactPath
            self.groups = groups
            self.testers = testers
            self.releaseNotes = releaseNotes
            self.serviceAccountPath = serviceAccountPath
            self.dryRun = dryRun
            self.timeoutSeconds = timeoutSeconds
        }
    }

    /// Result of a Firebase App Distribution release.
    public struct Result: Codable, Sendable {
        /// The release resource name, or `nil` for a dry run.
        public let releaseName: String?

        /// The Firebase app ID that was targeted.
        public let appId: String

        /// The artifact that was uploaded.
        public let artifactPath: String

        /// Tester group aliases the release was distributed to.
        public let groups: [String]

        /// Number of individual testers the release was distributed to.
        ///
        /// A count rather than the addresses themselves — tester emails are personal data and
        /// must not reach CI logs or JSON output.
        public let testerCount: Int

        /// The link testers open to install this release, when the API returned one.
        public let testingUri: String?

        /// Firebase console deep link for this release, when the API returned one.
        public let consoleUri: String?

        /// Whether this was a dry run.
        public let dryRun: Bool

        /// Creates a `Result`.
        public init(
            releaseName: String?,
            appId: String,
            artifactPath: String,
            groups: [String],
            testerCount: Int,
            testingUri: String?,
            consoleUri: String?,
            dryRun: Bool
        ) {
            self.releaseName = releaseName
            self.appId = appId
            self.artifactPath = artifactPath
            self.groups = groups
            self.testerCount = testerCount
            self.testingUri = testingUri
            self.consoleUri = consoleUri
            self.dryRun = dryRun
        }
    }

    /// Execute the Firebase App Distribution release.
    ///
    /// - Parameters:
    ///   - options: Distribution options.
    ///   - context: Shared execution context.
    /// - Returns: The release result, including tester-facing URLs when available.
    /// - Throws: ``ShipItError/invalidConfiguration(reason:)`` when options, credentials, or the
    ///   artifact are unusable; ``ShipItError/uploadFailed(asset:reason:)`` when the API rejects
    ///   the upload or distribution.
    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard let rawAppID = options.appId, !rawAppID.isEmpty else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "firebase-app-distribution: 'app_id' is required. Specify it in the workflow step options (e.g. options: { app_id: ${FIREBASE_IOS_QA_APP_ID} })."
            )
        }
        guard let rawArtifactPath = options.artifactPath, !rawArtifactPath.isEmpty else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "firebase-app-distribution: 'artifact_path' is required. Point it at the signed .ipa or .apk produced earlier in the workflow."
            )
        }

        let appID = try FirebaseAppID(rawAppID)

        // Anchor relative paths against the shell's working directory so shipit can be
        // invoked from any directory and still locate the artifact.
        let workingDirectory = context.shell.workingDirectory ?? FileManager.default.currentDirectoryPath
        let artifactPath =
            (rawArtifactPath as NSString).isAbsolutePath
            ? rawArtifactPath
            : (workingDirectory as NSString).appendingPathComponent(rawArtifactPath)

        try Self.validateArtifact(at: artifactPath, matches: appID)

        let groups = options.groups ?? []
        let testers = options.testers ?? []
        guard !groups.isEmpty || !testers.isEmpty else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "firebase-app-distribution: specify at least one tester 'groups' alias or 'testers' email — a release with no audience would upload but reach nobody."
            )
        }

        if options.dryRun == true {
            logger.info(
                "Dry run — would upload \(URL(fileURLWithPath: artifactPath).lastPathComponent) to \(appID.platform.rawValue) app \(appID.rawValue) for \(groups.count) group(s) and \(testers.count) tester(s)"
            )
            return Result(
                releaseName: nil,
                appId: appID.rawValue,
                artifactPath: artifactPath,
                groups: groups,
                testerCount: testers.count,
                testingUri: nil,
                consoleUri: nil,
                dryRun: true
            )
        }

        let client = try clientOverride ?? Self.makeClient(serviceAccountPath: options.serviceAccountPath)
        let fileName = URL(fileURLWithPath: artifactPath).lastPathComponent
        let data = try Data(contentsOf: URL(fileURLWithPath: artifactPath))

        logger.info("Uploading \(fileName) to Firebase App Distribution app \(appID.rawValue)")
        let operationName = try await client.uploadRelease(
            appID: appID, fileName: fileName, data: data)

        let timeout = Duration.seconds(options.timeoutSeconds ?? 300)
        let response: FirebaseUploadReleaseResponse
        if let sleepHook {
            response = try await client.pollUpload(
                operationName: operationName, timeout: timeout, sleep: sleepHook)
        } else {
            response = try await client.pollUpload(operationName: operationName, timeout: timeout)
        }
        let release = response.release

        if let notes = options.releaseNotes, !notes.isEmpty {
            try await client.updateReleaseNotes(releaseName: release.name, notes: notes)
        }

        try await client.distribute(releaseName: release.name, groups: groups, testers: testers)

        logger.info(
            "Firebase App Distribution succeeded — \(response.result?.rawValue ?? "released") to \(groups.count) group(s) and \(testers.count) tester(s)"
        )

        return Result(
            releaseName: release.name,
            appId: appID.rawValue,
            artifactPath: artifactPath,
            groups: groups,
            testerCount: testers.count,
            testingUri: release.testingUri,
            consoleUri: release.firebaseConsoleUri,
            dryRun: false
        )
    }

    // MARK: - Private

    /// Validates that the artifact exists and its extension matches the app ID's platform.
    static func validateArtifact(at path: String, matches appID: FirebaseAppID) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "firebase-app-distribution: no artifact at '\(path)'. Check that an earlier build/export step produced it."
            )
        }

        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let expected: Set<String> = appID.platform == .ios ? ["ipa"] : ["apk", "aab"]
        guard expected.contains(ext) else {
            let expectedList = expected.sorted().map { ".\($0)" }.joined(separator: " or ")
            throw ShipItError.invalidConfiguration(
                reason:
                    "firebase-app-distribution: app ID '\(appID.rawValue)' is an \(appID.platform.rawValue) app, which needs a \(expectedList) artifact, but '\(path)' is a .\(ext) file."
            )
        }
    }

    /// Resolves service-account credentials from the option, then the environment.
    static func makeClient(serviceAccountPath: String?) throws -> FirebaseAppDistributionClient {
        if let serviceAccountPath, !serviceAccountPath.isEmpty {
            return try FirebaseAppDistributionClient(serviceAccountJSONPath: serviceAccountPath)
        }
        let environment = ProcessInfo.processInfo.environment
        if let json = environment["FIREBASE_SERVICE_ACCOUNT_JSON"], !json.isEmpty {
            return try FirebaseAppDistributionClient(serviceAccountJSON: Data(json.utf8))
        }
        if let path = environment["GOOGLE_APPLICATION_CREDENTIALS"], !path.isEmpty {
            return try FirebaseAppDistributionClient(serviceAccountJSONPath: path)
        }
        throw ShipItError.invalidConfiguration(
            reason: """
                firebase-app-distribution: no credentials found. Set GOOGLE_APPLICATION_CREDENTIALS to a \
                service-account key path, set FIREBASE_SERVICE_ACCOUNT_JSON to the key contents, or pass \
                the 'service_account_path' option. Never inline credentials in Shipfile.yml.
                """
        )
    }
}
