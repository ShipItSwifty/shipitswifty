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
                description: "Version bump defaults.",
                properties: [
                    .string("strategy", description: "Build number strategy.", defaultValue: .string("sequential"), allowedValues: ["sequential", "timestamp", "commitCount"], example: .string("sequential")),
                    .string("source", description: "Version source.", defaultValue: .string("xcodeproj"), allowedValues: ["xcodeproj", "asc"], example: .string("xcodeproj")),
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
            actionSchema(name: ArchiveAction.name, description: ArchiveAction.description, options: archiveOptions(), example: archiveExample()),
            actionSchema(name: ExportAction.name, description: ExportAction.description, options: exportOptions(), example: exportExample()),
            actionSchema(name: SignAction.name, description: SignAction.description, options: signOptions(), example: signExample()),
            actionSchema(name: UploadAction.name, description: UploadAction.description, options: uploadOptions(), example: uploadExample()),
            actionSchema(name: TestFlightAction.name, description: TestFlightAction.description, options: testFlightOptions(), example: testFlightExample()),
            actionSchema(name: SnapshotAction.name, description: SnapshotAction.description, options: snapshotOptions(), example: snapshotExample()),
            actionSchema(name: FrameAction.name, description: FrameAction.description, options: frameOptions(), example: frameExample()),
            actionSchema(name: VersionAction.name, description: VersionAction.description, options: versionOptions(), example: versionExample()),
            actionSchema(name: MetadataAction.name, description: MetadataAction.description, options: metadataOptions(), example: metadataExample()),
            actionSchema(name: PrecheckAction.name, description: PrecheckAction.description, options: precheckOptions(), example: precheckExample()),
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
            .string("scheme", description: "Xcode scheme to build.", example: .string("MyApp")),
            .string("configuration", description: "Build configuration.", allowedValues: ["Debug", "Release"], example: .string("Release")),
            .string("workspace", description: "Xcode workspace path.", example: .string("MyApp.xcworkspace")),
            .string("project", description: "Xcode project path.", example: .string("MyApp.xcodeproj")),
            .string("derived_data_path", description: "DerivedData path override.", example: .string("./DerivedData")),
            .object(
                "xcargs",
                description: "Additional xcodebuild settings.",
                example: .object(["SWIFT_TREAT_WARNINGS_AS_ERRORS": .string("YES")]),
                allowsAdditionalProperties: true,
                additionalProperties: .string("<build-setting>", description: "String build setting value.")
            ),
            .boolean("clean", description: "Run `xcodebuild clean` before build.", example: .bool(true)),
        ]
    }

    private static func testOptions() -> [SchemaField] {
        [
            .string("scheme", description: "Xcode scheme containing tests.", example: .string("MyApp")),
            .string("destination", description: "xcodebuild destination string.", example: .string("platform=iOS Simulator,name=iPhone 16")),
            .string("configuration", description: "Build configuration for tests.", example: .string("Debug")),
            .boolean("enable_code_coverage", description: "Enable code coverage collection.", example: .bool(true)),
            .string("result_bundle_path", description: "Path for the .xcresult bundle.", example: .string("./build/TestResults.xcresult")),
            .string("test_plan", description: "Xcode test plan name.", example: .string("Regression")),
        ]
    }

    private static func archiveOptions() -> [SchemaField] {
        [
            .string("scheme", description: "Xcode scheme to archive.", example: .string("MyApp")),
            .string("configuration", description: "Archive build configuration.", example: .string("Release")),
            .string("export_method", description: "Distribution method.", allowedValues: ["app-store", "ad-hoc", "development", "enterprise"], example: .string("app-store")),
            .string("output_path", description: "Output .xcarchive path.", example: .string("./build/MyApp.xcarchive")),
            .boolean("include_symbols", description: "Include dSYMs.", example: .bool(true)),
            .boolean("include_bitcode", description: "Include bitcode when supported.", example: .bool(false)),
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
            .string("bump", required: true, description: "Version component to bump.", allowedValues: ["build", "patch", "minor", "major", "set"], example: .string("build")),
            .string("version", description: "Explicit marketing version when `bump` is `set`.", example: .string("2.4.0")),
            .string("build_number", description: "Explicit build number override.", example: .string("240")),
            .string("strategy", description: "Build number strategy override.", allowedValues: ["sequential", "timestamp", "commitCount"], example: .string("sequential")),
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

    private static func testExample() -> JSONValue? {
        workflowExample(action: "test", options: ["destination": .string("platform=iOS Simulator,name=iPhone 16")])
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

    private static func workflowExample(action: String, options: [String: JSONValue]) -> JSONValue {
        .object([
            "action": .string(action),
            "options": .object(options),
        ])
    }
}
