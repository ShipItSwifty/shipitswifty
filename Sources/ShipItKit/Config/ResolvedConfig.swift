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

    /// Path to the resolved `.p12` certificate for manual signing.
    public let codeSigningP12Path: String?

    /// Decoded `.p12` certificate content for manual signing when provided via base64.
    public let codeSigningP12Data: Data?

    /// Password for the resolved `.p12` certificate.
    public let codeSigningP12Password: String?

    /// Path to the resolved `.mobileprovision` file for manual signing.
    public let codeSigningProvisioningProfilePath: String?

    /// Decoded `.mobileprovision` content for manual signing when provided via base64.
    public let codeSigningProvisioningProfileData: Data?

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

    /// Path to the project spec file for `project_spec` versioning source.
    public let versioningSpecPath: String?

    /// YAML key for the build number in the project spec (default: `CURRENT_PROJECT_VERSION`).
    public let versioningBuildKey: String

    /// YAML key for the marketing version in the project spec (default: `MARKETING_VERSION`).
    public let versioningMarketingKey: String

    // MARK: - Project Generation

    /// Project generation tool name (e.g. `xcodegen`, `tuist`).
    public let projectGenerationTool: String?

    /// Shell command to run for project generation.
    public let projectGenerationCommand: String?

    /// Path to the project spec file (e.g. `project.yml`).
    public let projectGenerationSpecPath: String?

    /// Path to the generated output project (e.g. `MyApp.xcodeproj`).
    public let projectGenerationOutputProject: String?

    /// Whether to auto-generate the project when the output is missing.
    public let projectGenerationAutoGenerate: Bool

    // MARK: - Notifications

    /// Slack webhook URL for notifications.
    public let slackWebhookUrl: String?

    /// Default Slack channel for notifications.
    public let slackChannel: String?

    // MARK: - Workflows

    /// Named release workflows from the Shipfile.
    public let workflows: [String: WorkflowConfig]

    /// User-defined composite actions from the Shipfile.
    public let customActions: [String: CustomActionConfig]

    // MARK: - Platform

    /// Resolved target platform.
    public let platform: Platform

    /// Resolved iOS build system. ``BuildSystem/native`` for Swift-only Xcode projects;
    /// `.flutter`, `.reactNative`, or `.kmp` when the iOS app is produced by a cross-platform tool.
    public let iosBuildSystem: BuildSystem

    /// Resolved Android build system. ``BuildSystem/native`` for pure Gradle projects;
    /// `.flutter`, `.reactNative`, or `.kmp` when the Android app is produced by a cross-platform tool.
    public let androidBuildSystem: BuildSystem

    /// Whether the current run is in CI mode.
    public let ci: Bool

    /// Directory used for project-relative tool execution. Defaults to the Shipfile directory.
    public let projectRoot: String

    /// KMP Gradle module containing shared iOS framework tasks.
    public let kmpSharedModule: String

    /// KMP iOS framework target used for local builds.
    public let kmpBuildTarget: String

    /// KMP iOS framework target used for archives.
    public let kmpArchiveTarget: String

    /// KMP iOS test Gradle task.
    public let kmpTestTask: String

    // MARK: - Android

    /// Gradle module name (e.g. `app`).
    public let androidModule: String

    /// Default Android Gradle test scope.
    public let androidScope: GradleTaskScope

    /// Default Android test kind.
    public let androidTestKind: TestKind

    /// Default Android test device configuration.
    public let androidTestDevices: TestDeviceConfig

    /// Default Android build variant (e.g. `release`, `debug`).
    public let androidBuildVariant: String

    /// Default Android artifact type.
    public let androidBuildType: AndroidBuildType

    /// Explicit path to the `gradlew` wrapper script.
    public let gradlewPath: String?

    /// Directory containing the Gradle root project.
    public let gradleProjectDir: String

    /// Additional Gradle flags applied to Android Gradle invocations.
    public let androidGradleFlags: [String]

    /// Path to the Android keystore file.
    public let androidKeystorePath: String?

    /// Keystore password (from environment — never stored in Shipfile).
    public let androidKeystorePassword: String?

    /// Signing key alias within the keystore.
    public let androidKeyAlias: String?

    /// Key password (from environment — never stored in Shipfile).
    public let androidKeyPassword: String?

    /// Android application package name (e.g. `com.example.myapp`).
    public let androidPackageName: String?

    /// Staged rollout fraction (0.0–1.0). `nil` means full rollout.
    public let androidRolloutFraction: Double?

    /// Additional Gradle `-P` project properties.
    public let androidGradleProperties: [String: String]

    /// Raw service account JSON data for Google Play authentication.
    public let googlePlayServiceAccountData: Data?

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
        codeSigningP12Path: String? = nil,
        codeSigningP12Data: Data? = nil,
        codeSigningP12Password: String? = nil,
        codeSigningProvisioningProfilePath: String? = nil,
        codeSigningProvisioningProfileData: Data? = nil,
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
        versioningSpecPath: String? = nil,
        versioningBuildKey: String = "CURRENT_PROJECT_VERSION",
        versioningMarketingKey: String = "MARKETING_VERSION",
        projectGenerationTool: String? = nil,
        projectGenerationCommand: String? = nil,
        projectGenerationSpecPath: String? = nil,
        projectGenerationOutputProject: String? = nil,
        projectGenerationAutoGenerate: Bool = true,
        slackWebhookUrl: String? = nil,
        slackChannel: String? = nil,
        workflows: [String: WorkflowConfig] = [:],
        customActions: [String: CustomActionConfig] = [:],
        platform: Platform = .ios,
        iosBuildSystem: BuildSystem = .native,
        androidBuildSystem: BuildSystem = .native,
        ci: Bool = false,
        projectRoot: String = ".",
        kmpSharedModule: String = "shared",
        kmpBuildTarget: String = "IosSimulatorArm64",
        kmpArchiveTarget: String = "IosArm64",
        kmpTestTask: String = "iosSimulatorArm64Test",
        androidModule: String = "app",
        androidScope: GradleTaskScope = .module,
        androidTestKind: TestKind = .unit,
        androidTestDevices: TestDeviceConfig = TestDeviceConfig(strategy: .none),
        androidBuildVariant: String = "release",
        androidBuildType: AndroidBuildType = .aab,
        gradlewPath: String? = nil,
        gradleProjectDir: String? = nil,
        androidGradleFlags: [String] = [],
        androidKeystorePath: String? = nil,
        androidKeystorePassword: String? = nil,
        androidKeyAlias: String? = nil,
        androidKeyPassword: String? = nil,
        androidPackageName: String? = nil,
        androidRolloutFraction: Double? = nil,
        androidGradleProperties: [String: String] = [:],
        googlePlayServiceAccountData: Data? = nil
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
        self.codeSigningP12Path = codeSigningP12Path
        self.codeSigningP12Data = codeSigningP12Data
        self.codeSigningP12Password = codeSigningP12Password
        self.codeSigningProvisioningProfilePath = codeSigningProvisioningProfilePath
        self.codeSigningProvisioningProfileData = codeSigningProvisioningProfileData
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
        self.versioningSpecPath = versioningSpecPath
        self.versioningBuildKey = versioningBuildKey
        self.versioningMarketingKey = versioningMarketingKey
        self.projectGenerationTool = projectGenerationTool
        self.projectGenerationCommand = projectGenerationCommand
        self.projectGenerationSpecPath = projectGenerationSpecPath
        self.projectGenerationOutputProject = projectGenerationOutputProject
        self.projectGenerationAutoGenerate = projectGenerationAutoGenerate
        self.slackWebhookUrl = slackWebhookUrl
        self.slackChannel = slackChannel
        self.workflows = workflows
        self.customActions = customActions
        self.platform = platform
        self.iosBuildSystem = iosBuildSystem
        self.androidBuildSystem = androidBuildSystem
        self.ci = ci
        self.projectRoot = projectRoot
        self.kmpSharedModule = kmpSharedModule
        self.kmpBuildTarget = kmpBuildTarget
        self.kmpArchiveTarget = kmpArchiveTarget
        self.kmpTestTask = kmpTestTask
        self.androidModule = androidModule
        self.androidScope = androidScope
        self.androidTestKind = androidTestKind
        self.androidTestDevices = androidTestDevices
        self.androidBuildVariant = androidBuildVariant
        self.androidBuildType = androidBuildType
        self.gradlewPath = gradlewPath
        self.gradleProjectDir = gradleProjectDir ?? projectRoot
        self.androidGradleFlags = androidGradleFlags
        self.androidKeystorePath = androidKeystorePath
        self.androidKeystorePassword = androidKeystorePassword
        self.androidKeyAlias = androidKeyAlias
        self.androidKeyPassword = androidKeyPassword
        self.androidPackageName = androidPackageName
        self.androidRolloutFraction = androidRolloutFraction
        self.androidGradleProperties = androidGradleProperties
        self.googlePlayServiceAccountData = googlePlayServiceAccountData
    }

    // MARK: - Workflow-Level Overrides

    /// Returns a copy of this config with the specified Android build variant and/or flavor overridden.
    ///
    /// Used by `Workflow.run()` to apply per-workflow overrides before passing the context to steps.
    ///
    /// - Parameters:
    ///   - buildVariant: If non-nil, replaces `androidBuildVariant`.
    ///   - flavor: If non-nil, sets or replaces the `"flavor"` key in `androidGradleProperties`.
    /// - Returns: A new `ResolvedConfig` with the specified overrides applied.
    public func overriding(gradleProjectDir dir: String) -> ResolvedConfig {
        return ResolvedConfig(
            processedFiles: processedFiles, appWorkspace: appWorkspace, appProject: appProject,
            appScheme: appScheme, bundleID: bundleID,
            bundleIDFromTargetBuildSettings: bundleIDFromTargetBuildSettings, teamID: teamID,
            teamIDFromTargetBuildSettings: teamIDFromTargetBuildSettings, ascKeyID: ascKeyID,
            ascIssuerID: ascIssuerID, ascPrivateKeyData: ascPrivateKeyData,
            buildConfiguration: buildConfiguration, derivedDataPath: derivedDataPath,
            xcargs: xcargs, archiveExportMethod: archiveExportMethod,
            archiveIncludeSymbols: archiveIncludeSymbols, archiveOutputPath: archiveOutputPath,
            exportArchivePath: exportArchivePath, exportOutputDirectory: exportOutputDirectory,
            codeSigningType: codeSigningType, automaticCodeSigning: automaticCodeSigning,
            codeSigningStorage: codeSigningStorage, codeSigningGitUrl: codeSigningGitUrl,
            vaultPassword: vaultPassword, codeSigningP12Path: codeSigningP12Path,
            codeSigningP12Data: codeSigningP12Data, codeSigningP12Password: codeSigningP12Password,
            codeSigningProvisioningProfilePath: codeSigningProvisioningProfilePath,
            codeSigningProvisioningProfileData: codeSigningProvisioningProfileData,
            skipWaitingForBuildProcessing: skipWaitingForBuildProcessing,
            distributeExternal: distributeExternal, testFlightGroups: testFlightGroups,
            testFlightChangelog: testFlightChangelog, screenshotDevices: screenshotDevices,
            screenshotLocales: screenshotLocales, screenshotScheme: screenshotScheme,
            screenshotOutputDirectory: screenshotOutputDirectory,
            metadataDirectory: metadataDirectory, submitForReview: submitForReview,
            automaticRelease: automaticRelease, phasedRelease: phasedRelease,
            versioningStrategy: versioningStrategy, versioningSource: versioningSource,
            versioningSpecPath: versioningSpecPath, versioningBuildKey: versioningBuildKey,
            versioningMarketingKey: versioningMarketingKey,
            projectGenerationTool: projectGenerationTool,
            projectGenerationCommand: projectGenerationCommand,
            projectGenerationSpecPath: projectGenerationSpecPath,
            projectGenerationOutputProject: projectGenerationOutputProject,
            projectGenerationAutoGenerate: projectGenerationAutoGenerate,
            slackWebhookUrl: slackWebhookUrl, slackChannel: slackChannel,
            workflows: workflows, customActions: customActions, platform: platform,
            iosBuildSystem: iosBuildSystem, androidBuildSystem: androidBuildSystem, ci: ci,
            projectRoot: projectRoot, kmpSharedModule: kmpSharedModule,
            kmpBuildTarget: kmpBuildTarget, kmpArchiveTarget: kmpArchiveTarget,
            kmpTestTask: kmpTestTask, androidModule: androidModule, androidScope: androidScope,
            androidTestKind: androidTestKind, androidTestDevices: androidTestDevices,
            androidBuildVariant: androidBuildVariant, androidBuildType: androidBuildType,
            gradlewPath: gradlewPath, gradleProjectDir: dir,
            androidGradleFlags: androidGradleFlags, androidKeystorePath: androidKeystorePath,
            androidKeystorePassword: androidKeystorePassword, androidKeyAlias: androidKeyAlias,
            androidKeyPassword: androidKeyPassword, androidPackageName: androidPackageName,
            androidRolloutFraction: androidRolloutFraction,
            androidGradleProperties: androidGradleProperties,
            googlePlayServiceAccountData: googlePlayServiceAccountData
        )
    }

    public func overriding(buildVariant: String? = nil, flavor: String? = nil) -> ResolvedConfig {
        var updatedProperties = androidGradleProperties
        if let flavor {
            updatedProperties["flavor"] = flavor
        }
        return ResolvedConfig(
            processedFiles: processedFiles,
            appWorkspace: appWorkspace,
            appProject: appProject,
            appScheme: appScheme,
            bundleID: bundleID,
            bundleIDFromTargetBuildSettings: bundleIDFromTargetBuildSettings,
            teamID: teamID,
            teamIDFromTargetBuildSettings: teamIDFromTargetBuildSettings,
            ascKeyID: ascKeyID,
            ascIssuerID: ascIssuerID,
            ascPrivateKeyData: ascPrivateKeyData,
            buildConfiguration: buildConfiguration,
            derivedDataPath: derivedDataPath,
            xcargs: xcargs,
            archiveExportMethod: archiveExportMethod,
            archiveIncludeSymbols: archiveIncludeSymbols,
            archiveOutputPath: archiveOutputPath,
            exportArchivePath: exportArchivePath,
            exportOutputDirectory: exportOutputDirectory,
            codeSigningType: codeSigningType,
            automaticCodeSigning: automaticCodeSigning,
            codeSigningStorage: codeSigningStorage,
            codeSigningGitUrl: codeSigningGitUrl,
            vaultPassword: vaultPassword,
            codeSigningP12Path: codeSigningP12Path,
            codeSigningP12Data: codeSigningP12Data,
            codeSigningP12Password: codeSigningP12Password,
            codeSigningProvisioningProfilePath: codeSigningProvisioningProfilePath,
            codeSigningProvisioningProfileData: codeSigningProvisioningProfileData,
            skipWaitingForBuildProcessing: skipWaitingForBuildProcessing,
            distributeExternal: distributeExternal,
            testFlightGroups: testFlightGroups,
            testFlightChangelog: testFlightChangelog,
            screenshotDevices: screenshotDevices,
            screenshotLocales: screenshotLocales,
            screenshotScheme: screenshotScheme,
            screenshotOutputDirectory: screenshotOutputDirectory,
            metadataDirectory: metadataDirectory,
            submitForReview: submitForReview,
            automaticRelease: automaticRelease,
            phasedRelease: phasedRelease,
            versioningStrategy: versioningStrategy,
            versioningSource: versioningSource,
            versioningSpecPath: versioningSpecPath,
            versioningBuildKey: versioningBuildKey,
            versioningMarketingKey: versioningMarketingKey,
            projectGenerationTool: projectGenerationTool,
            projectGenerationCommand: projectGenerationCommand,
            projectGenerationSpecPath: projectGenerationSpecPath,
            projectGenerationOutputProject: projectGenerationOutputProject,
            projectGenerationAutoGenerate: projectGenerationAutoGenerate,
            slackWebhookUrl: slackWebhookUrl,
            slackChannel: slackChannel,
            workflows: workflows,
            customActions: customActions,
            platform: platform,
            iosBuildSystem: iosBuildSystem,
            androidBuildSystem: androidBuildSystem,
            ci: ci,
            projectRoot: projectRoot,
            kmpSharedModule: kmpSharedModule,
            kmpBuildTarget: kmpBuildTarget,
            kmpArchiveTarget: kmpArchiveTarget,
            kmpTestTask: kmpTestTask,
            androidModule: androidModule,
            androidScope: androidScope,
            androidTestKind: androidTestKind,
            androidTestDevices: androidTestDevices,
            androidBuildVariant: buildVariant ?? androidBuildVariant,
            androidBuildType: androidBuildType,
            gradlewPath: gradlewPath,
            gradleProjectDir: gradleProjectDir,
            androidGradleFlags: androidGradleFlags,
            androidKeystorePath: androidKeystorePath,
            androidKeystorePassword: androidKeystorePassword,
            androidKeyAlias: androidKeyAlias,
            androidKeyPassword: androidKeyPassword,
            androidPackageName: androidPackageName,
            androidRolloutFraction: androidRolloutFraction,
            androidGradleProperties: updatedProperties,
            googlePlayServiceAccountData: googlePlayServiceAccountData
        )
    }
}
