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

    /// Target platform for this Shipfile. CLI `--platform` and `SHIPIT_PLATFORM` override this value.
    public var platform: Platform?

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

    /// Project generation configuration (e.g. XcodeGen, Tuist).
    public var projectGeneration: ProjectGenerationConfig?

    /// Notification settings.
    public var notifications: NotificationsConfig?

    /// Named release workflows.
    public var workflows: [String: WorkflowConfig]?

    /// User-defined composite actions — reusable, parameterized sequences of built-in
    /// actions (or other custom actions). Invoked from workflow steps by name, just
    /// like built-in actions. See ``CustomActionConfig``.
    ///
    /// ## Example
    /// ```yaml
    /// custom_actions:
    ///   build_and_sign:
    ///     description: "Test, archive, and export the app."
    ///     parameters:
    ///       method:
    ///         type: string
    ///         required: true
    ///     steps:
    ///       - action: test
    ///       - action: archive
    ///       - action: export
    ///         options:
    ///           method: "{{param.method}}"
    /// ```
    public var customActions: [String: CustomActionConfig]?

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
        platform: Platform? = nil,
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
        projectGeneration: ProjectGenerationConfig? = nil,
        notifications: NotificationsConfig? = nil,
        workflows: [String: WorkflowConfig]? = nil,
        customActions: [String: CustomActionConfig]? = nil,
        ios: IOSConfig? = nil,
        android: AndroidConfig? = nil
    ) {
        self.platform = platform
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
        self.projectGeneration = projectGeneration
        self.notifications = notifications
        self.workflows = workflows
        self.customActions = customActions
        self.ios = ios
        self.android = android
    }

    private enum CodingKeys: String, CodingKey {
        case platform
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
        case projectGeneration = "project_generation"
        case notifications
        case workflows
        case customActions = "custom_actions"
        case ios
        case android
    }
}

/// A user-defined reusable sequence of action steps.
///
/// Custom actions let you factor out duplicated step sequences (for example
/// `test` → `archive` → `export`) so that multiple workflows can reference
/// a single named composite instead of repeating the steps.
///
/// Custom actions are invoked exactly like built-in actions — a workflow step
/// uses `action: <name>` and forwards options as the custom action's call-site
/// parameters. Inside each step's `options:` block, string values can reference
/// declared parameters using the `{{param.NAME}}` syntax (evaluated *after*
/// Shipfile env expansion and independent of CI template syntaxes like
/// GitHub Actions' `${{ }}` or CircleCI's `<< >>`).
public struct CustomActionConfig: Codable, Sendable {
    /// Optional human-readable description surfaced in schema and AI prompts.
    public var description: String?

    /// Declared parameters that call sites may pass in as `options:`.
    ///
    /// Keys are parameter names referenced via `{{param.<name>}}`.
    public var parameters: [String: CustomActionParameter]?

    /// The ordered sequence of step invocations the composite expands to.
    public var steps: [WorkflowStepConfig]

    public init(
        description: String? = nil,
        parameters: [String: CustomActionParameter]? = nil,
        steps: [WorkflowStepConfig]
    ) {
        self.description = description
        self.parameters = parameters
        self.steps = steps
    }
}

/// A declared parameter on a ``CustomActionConfig``.
///
/// Used for validation (required vs. defaulted), defaulting, and surfacing
/// the shape of custom actions to AI agents via `shipit ai-session`.
public struct CustomActionParameter: Codable, Sendable {
    /// Value kind: `"string"` (default), `"bool"`, `"int"`, `"number"`, `"array"`, or `"any"`.
    public var type: String?

    /// Whether the parameter must be supplied at the call site. Defaults to
    /// `true` when no `defaultValue` is set, otherwise `false`.
    public var required: Bool?

    /// Fallback value applied when the call site omits the parameter.
    public var defaultValue: JSONValue?

    /// Optional human-readable description.
    public var description: String?

    public init(
        type: String? = nil,
        required: Bool? = nil,
        defaultValue: JSONValue? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case required
        case defaultValue = "default"
        case description
    }

    /// The parameter is required when explicitly marked `required` *or*
    /// no default value was supplied.
    public var isRequired: Bool {
        if let required { return required }
        return defaultValue == nil
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

    /// Path to a local `.p12` certificate file for manual signing.
    public var p12Path: String?

    /// Base64-encoded `.p12` certificate content for CI/manual signing.
    public var p12Base64: String?

    /// Password for the `.p12` certificate.
    public var p12Password: String?

    /// Path to a local `.mobileprovision` file for manual signing.
    public var provisioningProfilePath: String?

    /// Base64-encoded `.mobileprovision` content for CI/manual signing.
    public var provisioningProfileBase64: String?

    /// Creates a `CodeSigningConfig`.
    public init(
        type: String? = nil,
        storage: String? = nil,
        gitUrl: String? = nil,
        appIdentifier: String? = nil,
        profileType: String? = nil,
        p12Path: String? = nil,
        p12Base64: String? = nil,
        p12Password: String? = nil,
        provisioningProfilePath: String? = nil,
        provisioningProfileBase64: String? = nil
    ) {
        self.type = type
        self.storage = storage
        self.gitUrl = gitUrl
        self.appIdentifier = appIdentifier
        self.profileType = profileType
        self.p12Path = p12Path
        self.p12Base64 = p12Base64
        self.p12Password = p12Password
        self.provisioningProfilePath = provisioningProfilePath
        self.provisioningProfileBase64 = provisioningProfileBase64
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case storage
        case gitUrl = "git_url"
        case appIdentifier = "app_identifier"
        case profileType = "profile_type"
        case p12Path = "p12_path"
        case p12Base64 = "p12_base64"
        case p12Password = "p12_password"
        case provisioningProfilePath = "provisioning_profile_path"
        case provisioningProfileBase64 = "provisioning_profile_base64"
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

    /// Source of version information (`xcodeproj`, `asc`, or `project_spec`).
    ///
    /// When `project_spec` is selected, version reads and writes target the
    /// project spec file (e.g. `project.yml` for XcodeGen) rather than the
    /// generated `.xcodeproj`. This keeps the source of truth file in sync.
    public var source: String?

    /// Path to the project spec file (e.g. `project.yml`). Required when
    /// `source` is `project_spec`.
    public var specPath: String?

    /// The YAML key path used for the build number in the project spec file.
    /// Defaults to `CURRENT_PROJECT_VERSION`.
    public var buildKey: String?

    /// The YAML key path used for the marketing version in the project spec file.
    /// Defaults to `MARKETING_VERSION`.
    public var marketingKey: String?

    /// Creates a `VersioningConfig`.
    public init(
        strategy: String? = nil,
        source: String? = nil,
        specPath: String? = nil,
        buildKey: String? = nil,
        marketingKey: String? = nil
    ) {
        self.strategy = strategy
        self.source = source
        self.specPath = specPath
        self.buildKey = buildKey
        self.marketingKey = marketingKey
    }

    private enum CodingKeys: String, CodingKey {
        case strategy
        case source
        case specPath = "spec_path"
        case buildKey = "build_key"
        case marketingKey = "marketing_key"
    }
}

/// Project generation configuration for spec-driven projects (e.g. XcodeGen, Tuist).
///
/// When configured, ShipIt auto-generates the Xcode project before any
/// action that requires it (build, test, archive, export, version).
///
/// ## Example
/// ```yaml
/// project_generation:
///   tool: xcodegen
///   command: xcodegen generate
///   spec_path: ./project.yml
///   output_project: ./MyApp.xcodeproj
///   auto_generate: true
/// ```
public struct ProjectGenerationConfig: Codable, Sendable {
    /// The project generation tool name (e.g. `xcodegen`, `tuist`).
    public var tool: String?

    /// The shell command to run for project generation.
    /// Defaults to `xcodegen generate` when `tool` is `xcodegen`.
    public var command: String?

    /// Path to the project spec file (e.g. `project.yml`).
    public var specPath: String?

    /// Path to the generated Xcode project (e.g. `MyApp.xcodeproj`).
    public var outputProject: String?

    /// Whether to automatically generate the project when the output is missing
    /// or stale. Defaults to `true`.
    public var autoGenerate: Bool?

    /// Creates a `ProjectGenerationConfig`.
    public init(
        tool: String? = nil,
        command: String? = nil,
        specPath: String? = nil,
        outputProject: String? = nil,
        autoGenerate: Bool? = nil
    ) {
        self.tool = tool
        self.command = command
        self.specPath = specPath
        self.outputProject = outputProject
        self.autoGenerate = autoGenerate
    }

    private enum CodingKeys: String, CodingKey {
        case tool
        case command
        case specPath = "spec_path"
        case outputProject = "output_project"
        case autoGenerate = "auto_generate"
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
