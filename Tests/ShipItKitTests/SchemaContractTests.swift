import Testing

@testable import ShipItKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Schema contract")
struct SchemaContractTests {
    private let builtInActionNames: Set<String> = [
        ArchiveAction.name,
        BuildAction.name,
        CoverageAction.name,
        GitAction.name,
        LintAction.name,
        NotifyAction.name,
        PlayStoreAction.name,
        TestResultsAction.name,
        TestAction.name,
        ValidateBundleAction.name,
        VersionAction.name,
    ]

    private let nonHostBuiltInActionNames: Set<String> = [
        "dsym",
        "export",
        "frame",
        "generate_project",
        "metadata",
        "precheck",
        "provision",
        "sign",
        "snapshot",
        "testflight",
        "upload",
        "validate_archive",
    ]

    #if os(macOS)
    private let macOSOnlyActionNames: Set<String> = [
        DsymAction.name,
        ExportAction.name,
        FrameAction.name,
        GenerateProjectAction.name,
        MetadataAction.name,
        PrecheckAction.name,
        ProvisionAction.name,
        SignAction.name,
        SnapshotAction.name,
        TestFlightAction.name,
        UploadAction.name,
        ValidateArchiveAction.name,
    ]
    #endif

    private var hostActionNames: Set<String> {
        var names = builtInActionNames
        #if os(macOS)
        names.formUnion(macOSOnlyActionNames)
        #endif
        return names
    }

    @Test("Every built-in action has an action schema entry")
    func everyBuiltInActionHasSchemaEntry() {
        let schemaNames = Set(BuiltInSchemaCatalog.actionSchemas().map(\.name))
        #expect(schemaNames == hostActionNames)
    }

    @Test("Validation schemas include every built-in action")
    func validationSchemasIncludeEveryBuiltInAction() {
        let validationNames = Set(BuiltInSchemaCatalog.validationActionSchemas().map(\.name))
        #expect(validationNames == builtInActionNames.union(nonHostBuiltInActionNames))
        #if os(macOS)
        #expect(validationNames.isSuperset(of: macOSOnlyActionNames))
        #endif
    }

    @Test("Build schema retains critical option keys")
    func buildSchemaRetainsCriticalKeys() {
        let fields = BuiltInSchemaCatalog.optionSchema(for: BuildAction.name)
        let names = Set(fields.map(\.name))
        #expect(names.contains("scheme"))
        #expect(names.contains("configuration"))
        #expect(names.contains("clean"))
        #expect(names.contains("module"))
        #expect(names.contains("build_variant"))
        #expect(names.contains("gradle_properties"))
        #expect(fields.first(where: { $0.name == "gradle_properties" })?.type == .object)
    }

    @Test("Test schema retains Android kind, scope, and device keys")
    func testSchemaRetainsAndroidKindScopeAndDeviceKeys() {
        let fields = BuiltInSchemaCatalog.optionSchema(for: TestAction.name)
        let names = Set(fields.map(\.name))
        #expect(names.contains("module"))
        #expect(names.contains("kind"))
        #expect(names.contains("scope"))
        #expect(names.contains("task"))
        #expect(names.contains("devices"))
        #expect(names.contains("infrastructure_retry"))
        #expect(names.contains("rerun_failed_tests"))
        #expect(names.contains("report_path"))
        #expect(fields.first(where: { $0.name == "kind" })?.type == .string)
        #expect(fields.first(where: { $0.name == "scope" })?.type == .string)
        #expect(fields.first(where: { $0.name == "devices" })?.type == .object)
        #expect(fields.first(where: { $0.name == "infrastructure_retry" })?.type == .object)
        #expect(fields.first(where: { $0.name == "rerun_failed_tests" })?.type == .object)
    }

    @Test("Test-results schema retains artifact and report keys")
    func testResultsSchemaRetainsCriticalKeys() {
        let fields = BuiltInSchemaCatalog.optionSchema(for: TestResultsAction.name)
        let names = Set(fields.map(\.name))
        #expect(names.contains("xcresult_path"))
        #expect(names.contains("report_path"))
        #expect(names.contains("failed_only"))
        #expect(names.contains("report_output_path"))
    }

    @Test("Archive schema retains critical option keys")
    func archiveSchemaRetainsCriticalKeys() {
        let fields = BuiltInSchemaCatalog.optionSchema(for: ArchiveAction.name)
        let names = Set(fields.map(\.name))
        #expect(names.contains("scheme"))
        #expect(names.contains("output_path"))
        #expect(names.contains("include_symbols"))
        #expect(names.contains("include_bitcode"))
        #expect(names.contains("module"))
        #expect(names.contains("build_variant"))
        #expect(fields.first(where: { $0.name == "gradle_properties" })?.type == .object)
    }

    #if os(macOS)
    @Test("TestFlight schema retains documented option keys")
    func testFlightSchemaRetainsCriticalKeys() {
        let names = Set(BuiltInSchemaCatalog.optionSchema(for: TestFlightAction.name).map(\.name))
        #expect(names.contains("ipa"))
        #expect(names.contains("groups"))
        #expect(names.contains("changelog"))
        #expect(names.contains("skip_waiting_for_build_processing"))
        #expect(names.contains("distribute_external"))
    }

    @Test("Validate bundle schema retains artifact and failure-control keys")
    func validateBundleSchemaRetainsCriticalKeys() {
        let names = Set(BuiltInSchemaCatalog.optionSchema(for: ValidateBundleAction.name).map(\.name))
        #expect(names.contains("aab_path"))
        #expect(names.contains("apk_path"))
        #expect(names.contains("fail_on_warnings"))
    }

    @Test("Generate project schema retains command and path keys")
    func generateProjectSchemaRetainsCriticalKeys() {
        let names = Set(BuiltInSchemaCatalog.optionSchema(for: GenerateProjectAction.name).map(\.name))
        #expect(names.contains("command"))
        #expect(names.contains("spec_path"))
        #expect(names.contains("output_project"))
        #expect(names.contains("force"))
    }
    #endif
}
