import Foundation

/// The top-level structure of a `Shipfile.yml` configuration file.
///
/// A `Shipfile` defines app metadata, build settings, code signing configuration,
/// distribution targets, and named workflow lanes. It is decoded from YAML using Yams.
///
/// ## Example
/// ```yaml
/// app:
///   workspace: MyApp.xcworkspace
///   scheme: MyApp
///   bundle_id: com.mycompany.myapp
/// workflows:
///   beta:
///     - action: archive
///     - action: testflight
/// ```
public struct Shipfile: Codable, Sendable {

    /// Core app identity configuration.
    public var app: AppConfig?

    /// App Store Connect API credentials.
    public var appStoreConnect: AppStoreConnectConfig?

    /// Code signing settings.
    public var codeSigning: CodeSigningConfig?

    /// Build settings.
    public var build: BuildConfig?

    /// Archive settings.
    public var archive: ArchiveConfig?

    /// IPA export settings.
    public var export: ExportConfig?

    /// TestFlight distribution settings.
    public var testflight: TestFlightConfig?

    /// Screenshot capture settings.
    public var screenshots: ScreenshotsConfig?

    /// App Store metadata settings.
    public var metadata: MetadataConfig?

    /// Versioning strategy settings.
    public var versioning: VersioningConfig?

    /// Notification settings.
    public var notifications: NotificationsConfig?

    /// Named release workflows.
    public var workflows: [String: WorkflowConfig]?

    /// iOS-specific overrides merged on top of shared config when platform resolves to `.ios`.
    ///
    /// Useful for monorepo projects containing both iOS and Android targets.
    public var ios: IOSConfig?

    /// Android-specific configuration merged on top of shared config when platform resolves to `.android`.
    ///
    /// ## Example
    /// ```yaml
    /// android:
    ///   module: app
    ///   package_name: com.example.myapp
    ///   build_type: aab
    ///   play_track: qa
    /// ```
    public var android: AndroidConfig?

    /// Creates a `Shipfile` with all optional configuration sections.
    public init(
        app: AppConfig? = nil,
        appStoreConnect: AppStoreConnectConfig? = nil,
        codeSigning: CodeSigningConfig? = nil,
        build: BuildConfig? = nil,
        archive: ArchiveConfig? = nil,
        export: ExportConfig? = nil,
        testflight: TestFlightConfig? = nil,
        screenshots: ScreenshotsConfig? = nil,
        metadata: MetadataConfig? = nil,
        versioning: VersioningConfig? = nil,
        notifications: NotificationsConfig? = nil,
        workflows: [String: WorkflowConfig]? = nil,
        ios: IOSConfig? = nil,
        android: AndroidConfig? = nil
    ) {
        self.app = app
        self.appStoreConnect = appStoreConnect
        self.codeSigning = codeSigning
        self.build = build
        self.archive = archive
        self.export = export
        self.testflight = testflight
        self.screenshots = screenshots
        self.metadata = metadata
        self.versioning = versioning
        self.notifications = notifications
        self.workflows = workflows
        self.ios = ios
        self.android = android
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case appStoreConnect = "app_store_connect"
        case codeSigning = "code_signing"
        case build
        case archive
        case export
        case testflight
        case screenshots
        case metadata
        case versioning
        case notifications
        case workflows
        case ios
        case android
    }
}

// MARK: - Nested Config Types

/// Core app identity and Xcode project settings.
public struct AppConfig: Codable, Sendable {
    /// Path to the Xcode workspace (e.g. `MyApp.xcworkspace`).
    public var workspace: String?

    /// Path to the Xcode project (e.g. `MyApp.xcodeproj`). Used if `workspace` is nil.
    public var project: String?

    /// The Xcode scheme to build and test.
    public var scheme: String?

    /// The app bundle identifier (e.g. `com.mycompany.myapp`).
    public var bundleId: String?

    /// The Apple Developer Team ID (e.g. `ABCDE12345`).
    public var teamId: String?

    /// Creates an `AppConfig`.
    public init(
        workspace: String? = nil,
        project: String? = nil,
        scheme: String? = nil,
        bundleId: String? = nil,
        teamId: String? = nil
    ) {
        self.workspace = workspace
        self.project = project
        self.scheme = scheme
        self.bundleId = bundleId
        self.teamId = teamId
    }

    private enum CodingKeys: String, CodingKey {
        case workspace
        case project
        case scheme
        case bundleId = "bundle_id"
        case teamId = "team_id"
    }
}

/// App Store Connect API key configuration.
public struct AppStoreConnectConfig: Codable, Sendable {
    /// The API key identifier from App Store Connect.
    public var keyId: String?

    /// The issuer ID from App Store Connect.
    public var issuerId: String?

    /// Path to the `.p8` private key file (local development only; do not commit).
    public var keyPath: String?

    /// Raw `.p8` private key contents (use env var for CI).
    public var privateKey: String?

    /// Creates an `AppStoreConnectConfig`.
    public init(
        keyId: String? = nil,
        issuerId: String? = nil,
        keyPath: String? = nil,
        privateKey: String? = nil
    ) {
        self.keyId = keyId
        self.issuerId = issuerId
        self.keyPath = keyPath
        self.privateKey = privateKey
    }

    private enum CodingKeys: String, CodingKey {
        case keyId = "key_id"
        case issuerId = "issuer_id"
        case keyPath = "key_path"
        case privateKey = "private_key"
    }
}

/// Code signing configuration.
public struct CodeSigningConfig: Codable, Sendable {
    /// Signing type: `automatic`, `vault` (default), or `manual`.
    public var type: String?

    /// Storage backend: `git` (default), `s3`, or `gcs`.
    public var storage: String?

    /// Git URL of the encrypted certificate repository.
    public var gitUrl: String?

    /// App identifier for certificate/profile matching.
    public var appIdentifier: String?

    /// Provisioning profile type.
    public var profileType: String?

    /// Creates a `CodeSigningConfig`.
    public init(
        type: String? = nil,
        storage: String? = nil,
        gitUrl: String? = nil,
        appIdentifier: String? = nil,
        profileType: String? = nil
    ) {
        self.type = type
        self.storage = storage
        self.gitUrl = gitUrl
        self.appIdentifier = appIdentifier
        self.profileType = profileType
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case storage
        case gitUrl = "git_url"
        case appIdentifier = "app_identifier"
        case profileType = "profile_type"
    }
}

/// Xcode build settings.
public struct BuildConfig: Codable, Sendable {
    /// Build configuration name (e.g. `Release`).
    public var configuration: String?

    /// Path to derived data directory.
    public var derivedDataPath: String?

    /// Additional xcargs passed to `xcodebuild`.
    public var xcargs: [String: String]?

    /// Creates a `BuildConfig`.
    public init(
        configuration: String? = nil,
        derivedDataPath: String? = nil,
        xcargs: [String: String]? = nil
    ) {
        self.configuration = configuration
        self.derivedDataPath = derivedDataPath
        self.xcargs = xcargs
    }

    private enum CodingKeys: String, CodingKey {
        case configuration
        case derivedDataPath = "derived_data_path"
        case xcargs
    }
}

/// Archive configuration.
public struct ArchiveConfig: Codable, Sendable {
    /// Export method for the IPA.
    public var exportMethod: String?

    /// Whether to include bitcode in the archive.
    public var includeBitcode: Bool?

    /// Whether to include debug symbols.
    public var includeSymbols: Bool?

    /// Output path for the `.xcarchive`.
    public var outputPath: String?

    /// Creates an `ArchiveConfig`.
    public init(
        exportMethod: String? = nil,
        includeBitcode: Bool? = nil,
        includeSymbols: Bool? = nil,
        outputPath: String? = nil
    ) {
        self.exportMethod = exportMethod
        self.includeBitcode = includeBitcode
        self.includeSymbols = includeSymbols
        self.outputPath = outputPath
    }

    private enum CodingKeys: String, CodingKey {
        case exportMethod = "export_method"
        case includeBitcode = "include_bitcode"
        case includeSymbols = "include_symbols"
        case outputPath = "output_path"
    }
}

/// IPA export configuration.
public struct ExportConfig: Codable, Sendable {
    /// Path to the `.xcarchive` to export.
    public var archivePath: String?

    /// Directory to write the exported IPA.
    public var outputDirectory: String?

    /// Creates an `ExportConfig`.
    public init(archivePath: String? = nil, outputDirectory: String? = nil) {
        self.archivePath = archivePath
        self.outputDirectory = outputDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case archivePath = "archive_path"
        case outputDirectory = "output_directory"
    }
}

/// TestFlight distribution configuration.
public struct TestFlightConfig: Codable, Sendable {
    /// Skip waiting for Apple's processing before distribution.
    public var skipWaitingForBuildProcessing: Bool?

    /// Whether to distribute to external beta groups.
    public var distributeExternal: Bool?

    /// Beta group names to distribute to.
    public var groups: [String]?

    /// Release notes / changelog for this build.
    public var changelog: String?

    /// Creates a `TestFlightConfig`.
    public init(
        skipWaitingForBuildProcessing: Bool? = nil,
        distributeExternal: Bool? = nil,
        groups: [String]? = nil,
        changelog: String? = nil
    ) {
        self.skipWaitingForBuildProcessing = skipWaitingForBuildProcessing
        self.distributeExternal = distributeExternal
        self.groups = groups
        self.changelog = changelog
    }

    private enum CodingKeys: String, CodingKey {
        case skipWaitingForBuildProcessing = "skip_waiting_for_build_processing"
        case distributeExternal = "distribute_external"
        case groups
        case changelog
    }
}

/// Screenshot capture configuration.
public struct ScreenshotsConfig: Codable, Sendable {
    /// List of simulator device names to capture on.
    public var devices: [String]?

    /// List of locale identifiers to capture screenshots for.
    public var locales: [String]?

    /// Xcode scheme containing the screenshot UI tests.
    public var scheme: String?

    /// Directory to write organized screenshots.
    public var outputDirectory: String?

    /// Creates a `ScreenshotsConfig`.
    public init(
        devices: [String]? = nil,
        locales: [String]? = nil,
        scheme: String? = nil,
        outputDirectory: String? = nil
    ) {
        self.devices = devices
        self.locales = locales
        self.scheme = scheme
        self.outputDirectory = outputDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case devices
        case locales
        case scheme
        case outputDirectory = "output_directory"
    }
}

/// App Store metadata configuration.
public struct MetadataConfig: Codable, Sendable {
    /// Local directory containing metadata files.
    public var directory: String?

    /// Whether to submit for review after metadata push.
    public var submitForReview: Bool?

    /// Whether to release automatically after approval.
    public var automaticRelease: Bool?

    /// Whether to use phased release.
    public var phasedRelease: Bool?

    /// Creates a `MetadataConfig`.
    public init(
        directory: String? = nil,
        submitForReview: Bool? = nil,
        automaticRelease: Bool? = nil,
        phasedRelease: Bool? = nil
    ) {
        self.directory = directory
        self.submitForReview = submitForReview
        self.automaticRelease = automaticRelease
        self.phasedRelease = phasedRelease
    }

    private enum CodingKeys: String, CodingKey {
        case directory
        case submitForReview = "submit_for_review"
        case automaticRelease = "automatic_release"
        case phasedRelease = "phased_release"
    }
}

/// Build number and version bump strategy configuration.
public struct VersioningConfig: Codable, Sendable {
    /// Strategy for incrementing build numbers.
    public var strategy: String?

    /// Source of version information.
    public var source: String?

    /// Creates a `VersioningConfig`.
    public init(strategy: String? = nil, source: String? = nil) {
        self.strategy = strategy
        self.source = source
    }
}

/// Notification configuration.
public struct NotificationsConfig: Codable, Sendable {
    /// Slack notification settings.
    public var slack: SlackConfig?

    /// Creates a `NotificationsConfig`.
    public init(slack: SlackConfig? = nil) {
        self.slack = slack
    }
}

/// Slack notification settings.
public struct SlackConfig: Codable, Sendable {
    /// Incoming webhook URL for posting messages.
    public var webhookUrl: String?

    /// Default channel to post to.
    public var channel: String?

    /// Whether to notify on success.
    public var onSuccess: Bool?

    /// Whether to notify on failure.
    public var onFailure: Bool?

    /// Creates a `SlackConfig`.
    public init(
        webhookUrl: String? = nil,
        channel: String? = nil,
        onSuccess: Bool? = nil,
        onFailure: Bool? = nil
    ) {
        self.webhookUrl = webhookUrl
        self.channel = channel
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    private enum CodingKeys: String, CodingKey {
        case webhookUrl = "webhook_url"
        case channel
        case onSuccess = "on_success"
        case onFailure = "on_failure"
    }
}

/// A named workflow definition — an ordered list of steps.
public typealias WorkflowConfig = [WorkflowStepConfig]

/// A single step within a workflow definition from the Shipfile.
public struct WorkflowStepConfig: Codable, Sendable {
    /// The registered action name to execute.
    public let action: String

    /// Options to pass to the action, as a JSON-compatible dictionary.
    public let options: JSONValue?

    /// Creates a `WorkflowStepConfig`.
    ///
    /// - Parameters:
    ///   - action: The registered action name to execute.
    ///   - options: Optional JSON options passed to the action.
    public init(action: String, options: JSONValue? = nil) {
        self.action = action
        self.options = options
    }
}
