import Foundation

public enum BuiltInSchemaCatalog {
    public static func shipfileFields() -> [SchemaField] {
        [
            .object(
                "app",
                description: "Core app identity and Xcode container settings.",
                properties: [
                    .string("workspace", description: "Path to the Xcode workspace.", example: .string("MyApp.xcworkspace"), envVar: "SHIPIT_APP__WORKSPACE"),
                    .string("project", description: "Path to the Xcode project when no workspace is used.", example: .string("MyApp.xcodeproj"), envVar: "SHIPIT_APP__PROJECT"),
                    .string("scheme", description: "Xcode scheme used for build, test, archive, and release automation.", example: .string("MyApp"), envVar: "SHIPIT_APP__SCHEME"),
                    .string("bundle_id", description: "App bundle identifier. Optional when ShipIt can infer it from build settings.", example: .string("com.example.myapp"), envVar: "SHIPIT_APP__BUNDLE_ID"),
                    .string("team_id", description: "Apple Developer Team ID. Optional when ShipIt can infer it from build settings.", example: .string("ABCDE12345"), envVar: "SHIPIT_APP__TEAM_ID"),
                ]
            ),
            .object(
                "app_store_connect",
                description: "App Store Connect API credentials for ASC-backed actions.",
                properties: [
                    .string("key_id", description: "App Store Connect API key identifier.", example: .string("ABC123XYZ9"), envVar: "ASC_KEY_ID", isSecret: true),
                    .string("issuer_id", description: "App Store Connect issuer identifier.", example: .string("00000000-1111-2222-3333-444444444444"), envVar: "ASC_ISSUER_ID", isSecret: true),
                    .string("key_path", description: "Path to the local .p8 key file.", example: .string("./.secrets/AuthKey_ABC123XYZ9.p8"), envVar: "ASC_PRIVATE_KEY_PATH", notes: ["Provide exactly one private key source."]),
                    .string("private_key", description: "Raw App Store Connect .p8 key contents.", envVar: "ASC_PRIVATE_KEY", isSecret: true, notes: ["Prefer environment variables for CI secrets.", "Provide exactly one private key source."]),
                ]
            ),
            .object(
                "code_signing",
                description: "Code signing strategy and certificate storage configuration.",
                properties: [
                    .string("type", description: "Signing mode.", defaultValue: .string("vault"), allowedValues: ["automatic", "vault", "manual"], example: .string("automatic")),
                    .string("storage", description: "Certificate storage backend for vault mode.", defaultValue: .string("git"), allowedValues: ["git", "s3", "gcs"], example: .string("git")),
                    .string("git_url", description: "Git repository URL used for certificate storage.", example: .string("git@github.com:yourteam/certs.git"), envVar: "SHIPIT_CODE_SIGNING__GIT_URL"),
                    .string("app_identifier", description: "Bundle identifier used when matching signing assets.", example: .string("com.example.myapp")),
                    .string("profile_type", description: "Provisioning profile type.", allowedValues: ["appstore", "adhoc", "development", "enterprise"], example: .string("appstore")),
                ]
            ),
            .object(
                "build",
                description: "Shared xcodebuild settings.",
                properties: [
                    .string("configuration", description: "Build configuration name.", defaultValue: .string("Release"), example: .string("Release"), envVar: "SHIPIT_BUILD__CONFIGURATION"),
                    .string("derived_data_path", description: "DerivedData directory override.", example: .string("./DerivedData"), envVar: "SHIPIT_BUILD__DERIVED_DATA_PATH"),
                    .object(
                        "xcargs",
                        description: "Additional xcodebuild settings written as key/value pairs.",
                        example: .object(["SWIFT_TREAT_WARNINGS_AS_ERRORS": .string("YES")]),
                        allowsAdditionalProperties: true,
                        additionalProperties: .string("<build-setting>", description: "String build setting value.")
                    ),
                ]
            ),
            .object(
                "archive",
                description: "Archive output settings.",
                properties: [
                    .string("export_method", description: "Distribution method used for archive/export operations.", defaultValue: .string("app-store"), allowedValues: ["app-store", "ad-hoc", "development", "enterprise"], example: .string("app-store"), envVar: "SHIPIT_ARCHIVE__EXPORT_METHOD"),
                    .boolean("include_symbols", description: "Include dSYMs when archiving.", defaultValue: .bool(true), example: .bool(true)),
                    .boolean("include_bitcode", description: "Include bitcode in export options when supported.", example: .bool(false)),
                    .string("output_path", description: "Output path for the .xcarchive.", example: .string("./build/MyApp.xcarchive"), envVar: "SHIPIT_ARCHIVE__OUTPUT_PATH"),
                ]
            ),
            .object(
                "export",
                description: "IPA export configuration.",
                properties: [
                    .string("archive_path", description: "Path to the input .xcarchive.", example: .string("./build/MyApp.xcarchive")),
                    .string("output_directory", description: "Directory where the exported IPA will be written.", example: .string("./build/export")),
                ]
            ),
            .object(
                "testflight",
                description: "Default TestFlight distribution settings.",
                properties: [
                    .boolean("skip_waiting_for_build_processing", description: "Skip waiting for Apple's processing state.", defaultValue: .bool(false), example: .bool(false)),
                    .boolean("distribute_external", description: "Distribute to external beta testers.", defaultValue: .bool(false), example: .bool(true)),
                    .array("groups", description: "Default beta group names.", defaultValue: .array([]), example: .array([.string("Internal QA")]), items: .string("group", description: "Beta group name.")),
                    .string("changelog", description: "Default TestFlight release notes.", example: .string("Bug fixes and improvements")),
                ]
            ),
            .object(
                "screenshots",
                description: "Screenshot capture defaults.",
                properties: [
                    .array("devices", description: "Simulator device names to capture screenshots on.", defaultValue: .array([]), example: .array([.string("iPhone 16")]), items: .string("device", description: "Simulator device name.")),
                    .array("locales", description: "Locale identifiers to capture.", defaultValue: .array([.string("en-US")]), example: .array([.string("en-US"), .string("ja")]), items: .string("locale", description: "Locale identifier.")),
                    .string("scheme", description: "UI test scheme used for screenshots.", example: .string("MyAppScreenshots")),
                    .string("output_directory", description: "Directory where screenshots are written.", defaultValue: .string("./screenshots"), example: .string("./screenshots")),
                ]
            ),
            .object(
                "metadata",
                description: "Metadata sync and App Store review defaults.",
                properties: [
                    .string("directory", description: "Directory containing metadata files.", defaultValue: .string("./metadata"), example: .string("./metadata")),
                    .boolean("submit_for_review", description: "Submit for review after metadata push or upload.", defaultValue: .bool(false), example: .bool(false)),
                    .boolean("automatic_release", description: "Automatically release after approval.", defaultValue: .bool(false), example: .bool(false)),
                    .boolean("phased_release", description: "Use phased release after approval.", defaultValue: .bool(false), example: .bool(true)),
                ]
            ),
            .object(
                "versioning",
                description: "Version bump defaults. ShipItSwifty follows Apple's two-version model: CFBundleShortVersionString is the user-facing MAJOR.MINOR.PATCH marketing version; CFBundleVersion is the plain-integer internal build counter incremented on every beta run.",
                properties: [
                    .string("strategy", description: "How CFBundleVersion is incremented. `sequential` adds 1 each run (guarantees a plain integer, required by Apple). `timestamp` uses YYYYMMDDHHmm format.", defaultValue: .string("sequential"), allowedValues: ["sequential", "timestamp", "commitCount"], example: .string("sequential")),
                    .string("source", description: "Where CFBundleVersion and CFBundleShortVersionString are read and written. `xcodeproj` reads/writes Xcode build settings directly in the .xcodeproj file. `asc` reads the current build number from App Store Connect.", defaultValue: .string("xcodeproj"), allowedValues: ["xcodeproj", "asc"], example: .string("xcodeproj")),
                ]
            ),
            .object(
                "notifications",
                description: "Notification defaults.",
                properties: [
                    .object(
                        "slack",
                        description: "Slack notification defaults.",
                        properties: [
                            .string("webhook_url", description: "Incoming Slack webhook URL.", example: .string("${SLACK_WEBHOOK_URL}"), envVar: "SLACK_WEBHOOK_URL", isSecret: true),
                            .string("channel", description: "Default Slack channel.", example: .string("#releases")),
                            .boolean("on_success", description: "Send Slack notifications on success.", example: .bool(true)),
                            .boolean("on_failure", description: "Send Slack notifications on failure.", example: .bool(true)),
                        ]
                    ),
                ]
            ),
            .object(
                "workflows",
                description: "Named workflows executed with `shipit run <workflow>`.",
                notes: ["Workflow names are dynamic keys.", "Each workflow is an ordered list of action steps."],
                allowsAdditionalProperties: true,
                additionalProperties: .array(
                    "<workflow>",
                    description: "Ordered action steps for a workflow.",
                    items: workflowStepField()
                )
            ),
        ]
    }

    public static func shipfileSections() -> [SchemaSection] {
        shipfileFields().map {
            SchemaSection(name: $0.name, description: $0.description, fields: $0.propertyValues)
        }
    }

    public static func actionSchemas() -> [ActionSchema] {
        [
            actionSchema(name: BuildAction.name, description: BuildAction.description, options: buildOptions(), example: buildExample()),
            actionSchema(name: TestAction.name, description: TestAction.description, options: testOptions(), example: testExample()),
            actionSchema(name: CoverageAction.name, description: CoverageAction.description, options: coverageOptions(), example: coverageExample()),
            actionSchema(name: ArchiveAction.name, description: ArchiveAction.description, options: archiveOptions(), example: archiveExample()),
            actionSchema(name: LintAction.name, description: LintAction.description, options: lintOptions(), example: lintExample()),
            actionSchema(name: PlayStoreAction.name, description: PlayStoreAction.description, options: playStoreOptions(), example: playStoreExample()),
            actionSchema(name: ValidateBundleAction.name, description: ValidateBundleAction.description, options: validateBundleOptions(), example: validateBundleExample()),
            actionSchema(name: ExportAction.name, description: ExportAction.description, options: exportOptions(), example: exportExample()),
            actionSchema(name: SignAction.name, description: SignAction.description, options: signOptions(), example: signExample()),
            actionSchema(name: UploadAction.name, description: UploadAction.description, options: uploadOptions(), example: uploadExample()),
            actionSchema(name: TestFlightAction.name, description: TestFlightAction.description, options: testFlightOptions(), example: testFlightExample()),
            actionSchema(name: SnapshotAction.name, description: SnapshotAction.description, options: snapshotOptions(), example: snapshotExample()),
            actionSchema(name: FrameAction.name, description: FrameAction.description, options: frameOptions(), example: frameExample()),
            actionSchema(name: VersionAction.name, description: VersionAction.description, options: versionOptions(), example: versionExample()),
            actionSchema(name: MetadataAction.name, description: MetadataAction.description, options: metadataOptions(), example: metadataExample()),
            actionSchema(name: PrecheckAction.name, description: PrecheckAction.description, options: precheckOptions(), example: precheckExample()),
            actionSchema(name: ValidateArchiveAction.name, description: ValidateArchiveAction.description, options: validateArchiveOptions(), example: validateArchiveExample()),
            actionSchema(name: ProvisionAction.name, description: ProvisionAction.description, options: provisionOptions(), example: provisionExample()),
            actionSchema(name: NotifyAction.name, description: NotifyAction.description, options: notifyOptions(), example: notifyExample()),
            actionSchema(name: GitAction.name, description: GitAction.description, options: gitOptions(), example: gitExample()),
            actionSchema(name: DsymAction.name, description: DsymAction.description, options: dsymOptions(), example: dsymExample()),
        ].sorted { $0.name < $1.name }
    }

    public static func optionSchema(for actionName: String) -> [SchemaField] {
        actionSchemas().first(where: { $0.name == actionName })?.options ?? []
    }

    private static func actionSchema(name: String, description: String, options: [SchemaField], example: JSONValue?) -> ActionSchema {
        ActionSchema(name: name, description: description, options: options, example: example)
    }

    private static func workflowStepField() -> SchemaField {
        .object(
            "step",
            description: "A single workflow step.",
            properties: [
                .string("action", required: true, description: "Registered action name.", example: .string("archive")),
                .object(
                    "options",
                    description: "Action-specific options.",
                    allowsAdditionalProperties: true,
                    additionalProperties: .any("<option>", description: "Action-specific workflow option value.")
                ),
            ]
        )
    }

    private static func buildOptions() -> [SchemaField] {
        [
            // iOS (xcodebuild) fields
            .string("scheme", description: "Xcode scheme to build (iOS). Ignored on Android.", example: .string("MyApp")),
            .string("configuration", description: "Build configuration (iOS: Debug/Release; Android: maps to build variant).", allowedValues: ["Debug", "Release"], example: .string("Release")),
            .string("workspace", description: "Xcode workspace path (iOS only).", example: .string("MyApp.xcworkspace")),
            .string("project", description: "Xcode project path (iOS only).", example: .string("MyApp.xcodeproj")),
            .string("derived_data_path", description: "DerivedData path override (iOS only).", example: .string("./DerivedData")),
            .object(
                "xcargs",
                description: "Additional xcodebuild settings (iOS only).",
                example: .object(["SWIFT_TREAT_WARNINGS_AS_ERRORS": .string("YES")]),
                allowsAdditionalProperties: true,
                additionalProperties: .string("<build-setting>", description: "String build setting value.")
            ),
            .boolean("clean", description: "Run `xcodebuild clean` before build (iOS only).", example: .bool(true)),
            // Android (Gradle) fields
            .string("android_module", description: "Gradle module to assemble (Android). Defaults to 'app'.", example: .string("app")),
            .string("android_build_variant", description: "Gradle build variant to assemble (Android). Defaults to 'release'.", example: .string("release")),
            .array(
                "gradle_properties",
                description: "Additional -P key=value properties passed to Gradle (Android).",
                example: .array([.string("versionCode=42")]),
                items: .string("property", description: "Gradle property as key=value string.")
            ),
        ]
    }

    private static func testOptions() -> [SchemaField] {
        [
            .string("scheme", description: "Xcode scheme containing tests.", example: .string("MyApp")),
            .array(
                "destinations",
                description: """
                One or more xcodebuild destination strings. \
                Each entry is passed as -destination to a separate xcodebuild test invocation; \
                results are aggregated across all destinations. \
                Use `DestinationDiscovery` or `xcodebuild -showdestinations` to enumerate valid \
                values for your project before setting this field. \
                When both destinations and the legacy destination field are set, destinations wins. \
                At least one destination is required; the action fails rather than guessing a \
                simulator name that may not exist on the current machine.
                """,
                example: .array([
                    .string("platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2"),
                ]),
                items: .string("destination", description: "xcodebuild -destination string, e.g. platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2")
            ),
            .string(
                "destination",
                description: "Single xcodebuild destination string. Kept for backward compatibility with existing Shipfiles. Prefer destinations (array) for new configuration.",
                example: .string("platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2")
            ),
            .string("configuration", description: "Build configuration for tests.", defaultValue: .string("Debug"), example: .string("Debug")),
            .boolean("enable_code_coverage", description: "Enable code coverage collection. When true and result_bundle_path is unset, a default .xcresult path of ./build/<scheme>-tests.xcresult is used automatically.", example: .bool(true)),
            .string("result_bundle_path", description: "Path for the .xcresult bundle. Auto-derived when enable_code_coverage is true and this is not set. If a bundle already exists at this path it is removed before xcodebuild runs, making repeated runs safe without manual cleanup.", example: .string("./build/TestResults.xcresult")),
            .string("test_plan", description: "Xcode test plan name.", example: .string("Regression")),
            .array("only_testing", description: "Restrict the run to specific test targets or test cases. Each entry maps to a separate -only-testing argument.", example: .array([.string("MyAppTests/FeatureTests")]), items: .string("target", description: "Test target or test case identifier, e.g. MyAppTests/MyFeatureTests/testSomething.")),
            .array("skip_testing", description: "Skip specific test targets or test cases. Each entry maps to a separate -skip-testing argument.", example: .array([.string("MyAppTests/SlowTests")]), items: .string("target", description: "Test target or test case identifier to skip.")),
            .boolean("retry_on_failure", description: "Automatically retry failing tests once before reporting failure (-retry-tests-on-failure).", defaultValue: .bool(false), example: .bool(true)),
        ]
    }

    private static func archiveOptions() -> [SchemaField] {
        [
            // iOS (xcodebuild) fields
            .string("scheme", description: "Xcode scheme to archive (iOS). Ignored on Android.", example: .string("MyApp")),
            .string("configuration", description: "Archive build configuration (iOS: Release; Android: maps to bundle variant).", example: .string("Release")),
            .string("export_method", description: "Distribution method (iOS only).", allowedValues: ["app-store", "ad-hoc", "development", "enterprise"], example: .string("app-store")),
            .string("output_path", description: "Output .xcarchive path (iOS) or .aab path (Android).", example: .string("./build/MyApp.xcarchive")),
            .boolean("include_symbols", description: "Include dSYMs (iOS only).", example: .bool(true)),
            .boolean("include_bitcode", description: "Include bitcode when supported (iOS only).", example: .bool(false)),
            // Android (Gradle bundle) fields
            .string("android_module", description: "Gradle module to bundle (Android). Defaults to 'app'.", example: .string("app")),
            .string("android_bundle_variant", description: "Gradle bundle variant (Android). Defaults to 'release'.", example: .string("release")),
            .array(
                "gradle_properties",
                description: "Additional -P key=value properties passed to Gradle bundle task (Android).",
                example: .array([.string("versionCode=42")]),
                items: .string("property", description: "Gradle property as key=value string.")
            ),
        ]
    }

    private static func exportOptions() -> [SchemaField] {
        [
            .string("archive_path", description: "Input .xcarchive path.", example: .string("./build/MyApp.xcarchive")),
            .string("output_directory", description: "Directory for exported IPA.", example: .string("./build/export")),
            .string("export_method", description: "Distribution method.", allowedValues: ["app-store", "ad-hoc", "development", "enterprise"], example: .string("app-store")),
        ]
    }

    private static func signOptions() -> [SchemaField] {
        [
            .string("operation", required: true, description: "Signing operation.", allowedValues: ["init", "sync", "import", "cleanup"], example: .string("sync")),
            .string("type", description: "Provisioning profile type.", allowedValues: ["development", "adhoc", "appstore", "enterprise"], example: .string("appstore")),
            .boolean("ci", description: "Run in CI mode.", example: .bool(true)),
            .string("git_url", description: "Git repository URL for signing assets.", example: .string("git@github.com:yourteam/certs.git")),
            .string("p12_path", description: "Path to the .p12 certificate for import.", example: .string("./certs/dist.p12")),
            .string("provisioning_profile_path", description: "Path to the .mobileprovision file for import.", example: .string("./profiles/AppStore.mobileprovision")),
        ]
    }

    private static func uploadOptions() -> [SchemaField] {
        [
            .string("ipa_path", description: "Path to the IPA file. Optional when a prior export step writes to the configured export directory.", example: .string("./build/export/MyApp.ipa")),
            .boolean("submit_for_review", description: "Submit the uploaded build for review.", example: .bool(true)),
            .boolean("phased_release", description: "Use phased release after approval.", example: .bool(true)),
        ]
    }

    private static func testFlightOptions() -> [SchemaField] {
        [
            .string("ipa", description: "Path to the IPA file. Optional when a prior export step writes to the configured export directory.", example: .string("./build/export/MyApp.ipa")),
            .array("groups", description: "Beta groups to distribute to.", example: .array([.string("Internal QA")]), items: .string("group", description: "Beta group name.")),
            .string("changelog", description: "Release notes for testers.", example: .string("Bug fixes and improvements")),
            .boolean("skip_waiting_for_build_processing", description: "Skip waiting for Apple's processing state.", example: .bool(false)),
            .boolean("distribute_external", description: "Distribute to external testers.", example: .bool(true)),
        ]
    }

    private static func snapshotOptions() -> [SchemaField] {
        [
            .array("devices", description: "Simulator device names.", example: .array([.string("iPhone 16")]), items: .string("device", description: "Simulator device name.")),
            .array("locales", description: "Locale identifiers.", example: .array([.string("en-US"), .string("ja")]), items: .string("locale", description: "Locale identifier.")),
            .string("scheme", description: "Screenshot UI test scheme.", example: .string("MyAppScreenshots")),
            .string("output_directory", description: "Screenshot output directory.", example: .string("./screenshots")),
            .boolean("clear", description: "Clear previous screenshots before capture.", example: .bool(true)),
        ]
    }

    private static func frameOptions() -> [SchemaField] {
        [
            .string("screenshots_directory", description: "Directory containing raw screenshots.", example: .string("./screenshots")),
            .string("output_directory", description: "Directory for framed screenshots.", example: .string("./screenshots_framed")),
            .boolean("force", description: "Overwrite existing output when supported.", example: .bool(true)),
        ]
    }

    private static func versionOptions() -> [SchemaField] {
        [
            .string("bump", required: true, description: "Which version component to increment. `build` increments CFBundleVersion (integer build counter) only — CFBundleShortVersionString is left untouched. `patch`, `minor`, `major` increment the corresponding segment of CFBundleShortVersionString (MAJOR.MINOR.PATCH) and reset CFBundleVersion to 1. `set` writes an explicit marketing version.", allowedValues: ["build", "patch", "minor", "major", "set"], example: .string("build")),
            .string("version", description: "Explicit marketing version when `bump` is `set`.", example: .string("2.4.0")),
            .string("build_number", description: "Explicit build number override.", example: .string("240")),
            .string("strategy", description: "Build number strategy override for this step. Overrides the top-level versioning.strategy setting.", allowedValues: ["sequential", "timestamp", "commitCount"], example: .string("sequential")),
        ]
    }

    private static func metadataOptions() -> [SchemaField] {
        [
            .boolean("pull", description: "Pull metadata from App Store Connect.", example: .bool(true)),
            .boolean("push", description: "Push local metadata to App Store Connect.", example: .bool(true)),
            .string("directory", description: "Local metadata directory.", example: .string("./metadata")),
            .boolean("submit_for_review", description: "Submit for review after pushing metadata.", example: .bool(true)),
            .boolean("automatic_release", description: "Automatically release after approval.", example: .bool(false)),
            .boolean("phased_release", description: "Use phased release after approval.", example: .bool(true)),
        ]
    }

    private static func precheckOptions() -> [SchemaField] {
        [
            .string("directory", description: "Metadata directory to validate.", example: .string("./metadata")),
            .boolean("fail_on_warnings", description: "Treat warnings as failures when supported.", example: .bool(true)),
        ]
    }

    private static func provisionOptions() -> [SchemaField] {
        [
            .string("operation", required: true, description: "Provisioning operation.", allowedValues: ["createAppId", "registerDevices", "listDevices", "listBundleIds"], example: .string("createAppId")),
            .string("bundle_id", description: "Bundle identifier for `createAppId`.", example: .string("com.example.myapp")),
            .string("app_name", description: "Display name for the new bundle identifier.", example: .string("MyApp")),
            .array("device_udids", description: "Device UDIDs for registration.", example: .array([.string("00008110-0012345600AA001E")]), items: .string("udid", description: "Device UDID.")),
            .array("device_names", description: "Friendly names paired with `device_udids`.", example: .array([.string("QA iPhone")]), items: .string("name", description: "Device name.")),
        ]
    }

    private static func notifyOptions() -> [SchemaField] {
        [
            .object(
                "slack",
                description: "Slack notification settings.",
                properties: [
                    .string("message", required: true, description: "Slack message text.", example: .string("Beta uploaded")),
                    .string("channel", description: "Slack channel override.", example: .string("#releases")),
                    .string("webhook_url", description: "Slack webhook URL override.", example: .string("${SLACK_WEBHOOK_URL}")),
                ]
            ),
            .string("webhook_url", description: "Custom webhook URL.", example: .string("https://example.com/webhook")),
            .any("webhook_payload", description: "Arbitrary JSON payload posted to the custom webhook.", example: .object(["build": .string("123")]))
        ]
    }

    private static func gitOptions() -> [SchemaField] {
        [
            .string("operation", required: true, description: "Git operation.", allowedValues: ["ensureClean", "tag", "commit", "push", "log", "hash"], example: .string("tag")),
            .string("tag_name", description: "Annotated tag name.", example: .string("v1.2.3")),
            .string("tag_message", description: "Annotated tag message.", example: .string("Release 1.2.3")),
            .string("commit_message", description: "Git commit message.", example: .string("Bump build number")),
            .string("remote", description: "Remote name for push.", example: .string("origin")),
            .boolean("push_tags", description: "Push tags together with commits.", example: .bool(true)),
        ]
    }

    private static func coverageOptions() -> [SchemaField] {
        [
            // Shared options
            .string("format", description: "Output format.", defaultValue: .string("text"), allowedValues: ["text", "json", "markdown"], example: .string("json")),
            .boolean("first_party_only", description: "Suppress test bundles, SPM dependencies, and vendor frameworks. Recommended default.", defaultValue: .bool(true), example: .bool(true)),
            .boolean("summary", description: "Print a single overall coverage line and exit. No per-target/module detail.", example: .bool(true)),
            .boolean("show_targets", description: "Include per-target (iOS) or per-module (Android) breakdown.", example: .bool(true)),
            .boolean("show_files", description: "Include per-file breakdown within each target/module.", example: .bool(true)),
            .boolean("show_functions", description: "Include per-function breakdown when available (iOS only).", example: .bool(false)),
            .array("include_targets", description: "Explicitly include these target/module names. Overrides first-party filter.", example: .array([.string("MyFeatureKit")]), items: .string("name", description: "Target or module name.")),
            .array("exclude_targets", description: "Explicitly exclude these target/module names.", example: .array([.string("GoogleSignIn")]), items: .string("name", description: "Target or module name.")),
            .string("sort", description: "Sort order for output entries.", defaultValue: .string("coverage"), allowedValues: ["coverage", "name"], example: .string("coverage")),
            .integer("limit", description: "Limit the number of targets/modules shown.", example: .int(20)),
            // iOS-specific options
            .string("xcresult_path", description: "Explicit path to the .xcresult bundle (iOS). Auto-discovered from ./build/<scheme>-tests.xcresult when omitted.", example: .string("./build/MyApp-tests.xcresult")),
            // Android-specific options
            .string("report_path", description: "Explicit path to the JaCoCo XML report (Android). Auto-discovered from common Gradle output paths when omitted.", example: .string("./app/build/reports/jacoco/test/jacocoTestReport.xml")),
        ]
    }

    private static func dsymOptions() -> [SchemaField] {
        [
            .string("operation", required: true, description: "dSYM operation.", allowedValues: ["download", "upload"], example: .string("upload")),
            .string("app_id", description: "App Store Connect app identifier for downloads.", example: .string("1234567890")),
            .string("build_version", description: "Build version filter for downloads.", example: .string("240")),
            .string("output_directory", description: "Directory for downloaded dSYMs.", example: .string("./dsyms")),
            .string("dsym_path", description: "Path to a dSYM file or zip for upload.", example: .string("./build/MyApp.app.dSYM.zip")),
            .string("upload_url", description: "Crash service upload endpoint.", example: .string("https://example.com/dsym-upload")),
        ]
    }

    private static func buildExample() -> JSONValue? {
        workflowExample(action: "build", options: ["configuration": .string("Release")])
    }

    private static func coverageExample() -> JSONValue? {
        workflowExample(action: "coverage", options: [
            "first_party_only": .bool(true),
            "show_targets": .bool(true),
        ])
    }

    private static func testExample() -> JSONValue? {
        workflowExample(action: "test", options: [
            "destinations": .array([.string("platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2")]),
        ])
    }

    private static func archiveExample() -> JSONValue? {
        workflowExample(action: "archive", options: ["export_method": .string("app-store")])
    }

    private static func exportExample() -> JSONValue? {
        workflowExample(action: "export", options: ["output_directory": .string("./build/export")])
    }

    private static func signExample() -> JSONValue? {
        workflowExample(action: "sign", options: ["operation": .string("sync"), "type": .string("appstore")])
    }

    private static func uploadExample() -> JSONValue? {
        workflowExample(action: "upload", options: ["submit_for_review": .bool(true)])
    }

    private static func testFlightExample() -> JSONValue? {
        workflowExample(action: "testflight", options: ["groups": .array([.string("Internal QA")])])
    }

    private static func snapshotExample() -> JSONValue? {
        workflowExample(action: "snapshot", options: ["devices": .array([.string("iPhone 16")])])
    }

    private static func frameExample() -> JSONValue? {
        workflowExample(action: "frame", options: ["screenshots_directory": .string("./screenshots")])
    }

    private static func versionExample() -> JSONValue? {
        workflowExample(action: "version", options: ["bump": .string("build")])
    }

    private static func metadataExample() -> JSONValue? {
        workflowExample(action: "metadata", options: ["push": .bool(true)])
    }

    private static func precheckExample() -> JSONValue? {
        workflowExample(action: "precheck", options: ["directory": .string("./metadata")])
    }

    private static func provisionExample() -> JSONValue? {
        workflowExample(action: "provision", options: ["operation": .string("createAppId"), "bundle_id": .string("com.example.myapp")])
    }

    private static func notifyExample() -> JSONValue? {
        workflowExample(action: "notify", options: ["slack": .object(["message": .string("Release submitted")])])
    }

    private static func gitExample() -> JSONValue? {
        workflowExample(action: "git", options: ["operation": .string("tag"), "tag_name": .string("v1.2.3")])
    }

    private static func dsymExample() -> JSONValue? {
        workflowExample(action: "dsym", options: ["operation": .string("upload"), "dsym_path": .string("./build/App.dSYM.zip")])
    }

    private static func validateArchiveOptions() -> [SchemaField] {
        [
            .string("archive_path", description: "Path to the .xcarchive directory to validate.", example: .string("./build/MyApp.xcarchive")),
            .string("ipa_path", description: "Path to the .ipa file to validate.", example: .string("./build/export/MyApp.ipa")),
            .boolean("fail_on_warnings", description: "Treat warnings as failures.", example: .bool(false)),
        ]
    }

    private static func validateArchiveExample() -> JSONValue? {
        workflowExample(action: "validate_archive", options: ["archive_path": .string("./build/MyApp.xcarchive")])
    }

    // MARK: - Android action schemas

    private static func lintOptions() -> [SchemaField] {
        [
            .string("scheme", description: "Xcode scheme to analyze. (iOS only)", example: .string("MyApp")),
            .string("configuration", description: "Build configuration for iOS analysis. Default: Debug.", example: .string("Debug")),
            .string("module", description: "Gradle module to lint. Default: app. (Android only)", example: .string("app")),
            .string("build_variant", description: "Build variant to lint, e.g. release. (Android only)", example: .string("release")),
            .string("report_path", description: "Path to write the lint HTML report. (Android only)", example: .string("./build/reports/lint-results.html")),
            .boolean("fail_on_error", description: "Fail the build on lint errors. Default: true.", defaultValue: .bool(true), example: .bool(true)),
        ]
    }

    private static func lintExample() -> JSONValue? {
        workflowExample(action: "lint", options: ["module": .string("app"), "build_variant": .string("release")])
    }

    private static func playStoreOptions() -> [SchemaField] {
        [
            .string("aab_path", description: "Path to the .aab file to upload (preferred).", example: .string("./app/build/outputs/bundle/release/app-release.aab")),
            .string("apk_path", description: "Path to the .apk file to upload.", example: .string("./app/build/outputs/apk/release/app-release.apk")),
            .string("track", description: "Google Play distribution track.", defaultValue: .string("internal"), allowedValues: ["internal", "alpha", "beta", "production"], example: .string("beta")),
            .object(
                "release_notes",
                description: "Per-language release notes. Keys are BCP-47 language tags.",
                example: .object(["en-US": .string("Bug fixes and improvements")]),
                allowsAdditionalProperties: true,
                additionalProperties: .string("<lang>", description: "Release note text for the given language tag.")
            ),
            .any("rollout_fraction", description: "Staged rollout fraction (0.0–1.0). Omit for full rollout.", example: .double(0.1)),
            .string("package_name", description: "Android package name. Overrides android.package_name in Shipfile.", example: .string("com.example.myapp")),
        ]
    }

    private static func playStoreExample() -> JSONValue? {
        workflowExample(action: "play-store", options: [
            "aab_path": .string("./app/build/outputs/bundle/release/app-release.aab"),
            "track": .string("beta"),
        ])
    }

    private static func validateBundleOptions() -> [SchemaField] {
        [
            .string("aab_path", description: "Path to the .aab file to validate.", example: .string("./app/build/outputs/bundle/release/app-release.aab")),
            .string("apk_path", description: "Path to the .apk file to validate.", example: .string("./app/build/outputs/apk/release/app-release.apk")),
            .boolean("fail_on_warnings", description: "Treat warnings as failures.", example: .bool(false)),
        ]
    }

    private static func validateBundleExample() -> JSONValue? {
        workflowExample(action: "validate_bundle", options: ["aab_path": .string("./app/build/outputs/bundle/release/app-release.aab")])
    }

    private static func workflowExample(action: String, options: [String: JSONValue]) -> JSONValue {
        .object([
            "action": .string(action),
            "options": .object(options),
        ])
    }
}
