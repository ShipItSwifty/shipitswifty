import Foundation

/// Flat struct containing all resolved configuration values after merging
/// CLI flags, environment variables, Shipfile.yml, and built-in defaults.
///
/// `ResolvedConfig` is created by `ConfigResolver` and passed to actions
/// via `ActionContext`. Actions read from this struct rather than parsing
/// raw config sources themselves.
///
/// ## Priority
/// 1. CLI flags (highest)
/// 2. Environment variables (`SHIPIT_*`)
/// 3. Shipfile.yml values
/// 4. Built-in defaults (lowest)
public struct ResolvedConfig: Sendable {

    /// Files that were successfully read while resolving this configuration.
    public let processedFiles: [String]

    // MARK: - App Identity

    /// Path to the Xcode workspace.
    public let appWorkspace: String?

    /// Path to the Xcode project. Used when `appWorkspace` is nil.
    public let appProject: String?

    /// The Xcode scheme for building and testing.
    public let appScheme: String?

    /// The app bundle identifier.
    public let bundleID: String?

    /// Whether the bundle identifier was inferred from Xcode target build settings.
    public let bundleIDFromTargetBuildSettings: Bool

    /// The Apple Developer Team ID.
    public let teamID: String?

    /// Whether the team ID was inferred from Xcode target build settings.
    public let teamIDFromTargetBuildSettings: Bool

    // MARK: - App Store Connect

    /// App Store Connect API Key ID.
    public let ascKeyID: String?

    /// App Store Connect Issuer ID.
    public let ascIssuerID: String?

    /// Raw contents of the `.p8` private key.
    public let ascPrivateKeyData: Data?

    // MARK: - Build

    /// Build configuration name (e.g. `Release`, `Debug`).
    public let buildConfiguration: String

    /// Path to the derived data directory.
    public let derivedDataPath: String?

    /// Additional xcargs for xcodebuild.
    public let xcargs: [String: String]

    // MARK: - Archive

    /// Export method for IPA generation.
    public let archiveExportMethod: String

    /// Whether to include debug symbols.
    public let archiveIncludeSymbols: Bool

    /// Output path for the `.xcarchive`.
    public let archiveOutputPath: String?

    // MARK: - Export

    /// Input archive path for the export step.
    public let exportArchivePath: String?

    /// Output directory for the exported IPA.
    public let exportOutputDirectory: String?

    // MARK: - Code Signing

    /// Code signing type (`vault` or `manual`).
    public let codeSigningType: String

    /// Whether Xcode automatic signing should be used.
    public let automaticCodeSigning: Bool

    /// Certificate storage backend (`git`, `s3`, or `gcs`).
    public let codeSigningStorage: String

    /// Git URL of the encrypted certificate repository.
    public let codeSigningGitUrl: String?

    /// Passphrase for the encrypted certificate repository.
    public let vaultPassword: String?

    // MARK: - TestFlight

    /// Whether to skip waiting for build processing.
    public let skipWaitingForBuildProcessing: Bool

    /// Whether to distribute to external testers.
    public let distributeExternal: Bool

    /// Beta group names for TestFlight distribution.
    public let testFlightGroups: [String]

    /// Release notes for the TestFlight build.
    public let testFlightChangelog: String?

    // MARK: - Screenshots

    /// Simulator device names for screenshot capture.
    public let screenshotDevices: [String]

    /// Locale identifiers for screenshot capture.
    public let screenshotLocales: [String]

    /// Xcode scheme for screenshot UI tests.
    public let screenshotScheme: String?

    /// Output directory for organized screenshots.
    public let screenshotOutputDirectory: String

    // MARK: - Metadata

    /// Local directory containing metadata files.
    public let metadataDirectory: String

    /// Whether to submit for review after metadata push.
    public let submitForReview: Bool

    /// Whether to release automatically after approval.
    public let automaticRelease: Bool

    /// Whether to use phased release.
    public let phasedRelease: Bool

    // MARK: - Versioning

    /// Build number increment strategy.
    public let versioningStrategy: String

    /// Source of version information.
    public let versioningSource: String

    // MARK: - Notifications

    /// Slack webhook URL for notifications.
    public let slackWebhookUrl: String?

    /// Default Slack channel for notifications.
    public let slackChannel: String?

    // MARK: - Workflows

    /// Named release workflows from the Shipfile.
    public let workflows: [String: WorkflowConfig]

    // MARK: - Init

    /// Creates a `ResolvedConfig` with all configuration values.
    public init(
        processedFiles: [String] = [],
        appWorkspace: String? = nil,
        appProject: String? = nil,
        appScheme: String? = nil,
        bundleID: String? = nil,
        bundleIDFromTargetBuildSettings: Bool = false,
        teamID: String? = nil,
        teamIDFromTargetBuildSettings: Bool = false,
        ascKeyID: String? = nil,
        ascIssuerID: String? = nil,
        ascPrivateKeyData: Data? = nil,
        buildConfiguration: String = "Release",
        derivedDataPath: String? = nil,
        xcargs: [String: String] = [:],
        archiveExportMethod: String = "app-store",
        archiveIncludeSymbols: Bool = true,
        archiveOutputPath: String? = nil,
        exportArchivePath: String? = nil,
        exportOutputDirectory: String? = nil,
        codeSigningType: String = "vault",
        automaticCodeSigning: Bool? = nil,
        codeSigningStorage: String = "git",
        codeSigningGitUrl: String? = nil,
        vaultPassword: String? = nil,
        skipWaitingForBuildProcessing: Bool = false,
        distributeExternal: Bool = false,
        testFlightGroups: [String] = [],
        testFlightChangelog: String? = nil,
        screenshotDevices: [String] = [],
        screenshotLocales: [String] = ["en-US"],
        screenshotScheme: String? = nil,
        screenshotOutputDirectory: String = "./screenshots",
        metadataDirectory: String = "./metadata",
        submitForReview: Bool = false,
        automaticRelease: Bool = false,
        phasedRelease: Bool = false,
        versioningStrategy: String = "sequential",
        versioningSource: String = "xcodeproj",
        slackWebhookUrl: String? = nil,
        slackChannel: String? = nil,
        workflows: [String: WorkflowConfig] = [:]
    ) {
        self.processedFiles = processedFiles
        self.appWorkspace = appWorkspace
        self.appProject = appProject
        self.appScheme = appScheme
        self.bundleID = bundleID
        self.bundleIDFromTargetBuildSettings = bundleIDFromTargetBuildSettings
        self.teamID = teamID
        self.teamIDFromTargetBuildSettings = teamIDFromTargetBuildSettings
        self.ascKeyID = ascKeyID
        self.ascIssuerID = ascIssuerID
        self.ascPrivateKeyData = ascPrivateKeyData
        self.buildConfiguration = buildConfiguration
        self.derivedDataPath = derivedDataPath
        self.xcargs = xcargs
        self.archiveExportMethod = archiveExportMethod
        self.archiveIncludeSymbols = archiveIncludeSymbols
        self.archiveOutputPath = archiveOutputPath
        self.exportArchivePath = exportArchivePath
        self.exportOutputDirectory = exportOutputDirectory
        self.codeSigningType = codeSigningType
        self.automaticCodeSigning = automaticCodeSigning ?? (codeSigningType == "automatic")
        self.codeSigningStorage = codeSigningStorage
        self.codeSigningGitUrl = codeSigningGitUrl
        self.vaultPassword = vaultPassword
        self.skipWaitingForBuildProcessing = skipWaitingForBuildProcessing
        self.distributeExternal = distributeExternal
        self.testFlightGroups = testFlightGroups
        self.testFlightChangelog = testFlightChangelog
        self.screenshotDevices = screenshotDevices
        self.screenshotLocales = screenshotLocales
        self.screenshotScheme = screenshotScheme
        self.screenshotOutputDirectory = screenshotOutputDirectory
        self.metadataDirectory = metadataDirectory
        self.submitForReview = submitForReview
        self.automaticRelease = automaticRelease
        self.phasedRelease = phasedRelease
        self.versioningStrategy = versioningStrategy
        self.versioningSource = versioningSource
        self.slackWebhookUrl = slackWebhookUrl
        self.slackChannel = slackChannel
        self.workflows = workflows
    }
}
