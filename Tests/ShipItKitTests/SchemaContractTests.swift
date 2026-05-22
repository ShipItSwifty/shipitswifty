import Testing

@testable import ShipItKit

@Suite("Schema contract")
struct SchemaContractTests {
    private let builtInActionNames: Set<String> = [
        ArchiveAction.name,
        BuildAction.name,
        CoverageAction.name,
        DsymAction.name,
        ExportAction.name,
        FrameAction.name,
        GenerateProjectAction.name,
        GitAction.name,
        LintAction.name,
        MetadataAction.name,
        NotifyAction.name,
        PlayStoreAction.name,
        PrecheckAction.name,
        ProvisionAction.name,
        SignAction.name,
        SnapshotAction.name,
        TestAction.name,
        TestFlightAction.name,
        UploadAction.name,
        ValidateArchiveAction.name,
        ValidateBundleAction.name,
        VersionAction.name,
    ]

    @Test("Every built-in action has an action schema entry")
    func everyBuiltInActionHasSchemaEntry() {
        let schemaNames = Set(BuiltInSchemaCatalog.actionSchemas().map(\.name))
        #expect(schemaNames == builtInActionNames)
    }

    @Test("Validation schemas include every built-in action")
    func validationSchemasIncludeEveryBuiltInAction() {
        let validationNames = Set(BuiltInSchemaCatalog.validationActionSchemas().map(\.name))
        #expect(validationNames == builtInActionNames)
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
}
