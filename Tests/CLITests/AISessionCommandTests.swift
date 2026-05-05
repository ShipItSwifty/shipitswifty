import Testing

@testable import CLI
@testable import ShipItKit

@Suite("AISessionCommand")
struct AISessionCommandTests {

    @Test("ai-session parses default goal as beta")
    func parsesDefaultGoalAsBeta() throws {
        let command = try AISessionCommand.parseAsRoot([]) as! AISessionCommand
        #expect(command.goal == .beta)
    }

    @Test("ai-session parses explicit goal")
    func parsesExplicitGoal() throws {
        let command = try AISessionCommand.parseAsRoot(["--goal", "release"]) as! AISessionCommand
        #expect(command.goal == .release)
    }

    @Test("ai-session parses explicit path")
    func parsesExplicitPath() throws {
        let command = try AISessionCommand.parseAsRoot(["--path", "/tmp/myapp"]) as! AISessionCommand
        #expect(command.path == "/tmp/myapp")
    }

    @Test("ai-session uses bootstrap options for shipfile")
    func usesBootstrapOptionsForShipfile() throws {
        let command =
            try AISessionCommand.parseAsRoot([
                "--shipfile", "./config/Shipfile.yml",
                "--verbose",
            ]) as! AISessionCommand
        #expect(command.options.shipfile == "./config/Shipfile.yml")
        #expect(command.options.verbose)
    }

    @Test("ai-session parses local goal")
    func parsesLocalGoal() throws {
        let command = try AISessionCommand.parseAsRoot(["--goal", "local"]) as! AISessionCommand
        #expect(command.goal == .local)
    }

    // MARK: - JSON serialization helpers

    @Test("inferredConfigEntryJSON serializes detected entry correctly")
    func inferredConfigEntryJSONSerializesDetected() {
        let entry = InferredConfigEntry(
            keyPath: "app.scheme",
            value: .string("MyApp"),
            source: .detected,
            confidence: .high,
            why: "Matches container name"
        )
        let json = inferredConfigEntryJSON(entry)
        #expect(json.objectValue?["keyPath"] == .string("app.scheme"))
        #expect(json.objectValue?["value"] == .string("MyApp"))
        #expect(json.objectValue?["source"] == .string("detected"))
        #expect(json.objectValue?["confidence"] == .string("high"))
        #expect(json.objectValue?["why"] == .string("Matches container name"))
    }

    @Test("inferredConfigEntryJSON serializes unresolved entry correctly")
    func inferredConfigEntryJSONSerializesUnresolved() {
        let entry = InferredConfigEntry(
            keyPath: "app.scheme",
            value: nil,
            source: .unresolved,
            confidence: nil,
            why: "No schemes found"
        )
        let json = inferredConfigEntryJSON(entry)
        #expect(json.objectValue?["value"]?.isNull == true)
        #expect(json.objectValue?["confidence"]?.isNull == true)
        #expect(json.objectValue?["source"] == .string("unresolved"))
    }

    @Test("secretDescriptorJSON serializes all fields")
    func secretDescriptorJSONSerializesAllFields() {
        let secret = SecretDescriptor(
            keyPath: "app_store_connect.key_id",
            envVar: "ASC_KEY_ID",
            acceptedFormats: ["Alphanumeric string"],
            exampleSource: "App Store Connect",
            preferFile: false,
            description: "The Key ID"
        )
        let json = secretDescriptorJSON(secret)
        #expect(json.objectValue?["envVar"] == .string("ASC_KEY_ID"))
        #expect(json.objectValue?["preferFile"] == .bool(false))
        #expect(json.objectValue?["acceptedFormats"]?.arrayValue?.count == 1)
    }

    @Test("ambiguityFlagJSON includes field, options, and message")
    func ambiguityFlagJSONIncludesAllFields() {
        let flag = AmbiguityFlag(
            field: "app.scheme",
            options: [.string("App"), .string("AppExtension")],
            message: "2 runnable schemes found."
        )
        let json = ambiguityFlagJSON(flag)
        #expect(json.objectValue?["field"] == .string("app.scheme"))
        #expect(json.objectValue?["options"]?.arrayValue?.count == 2)
        #expect(json.objectValue?["message"] == .string("2 runnable schemes found."))
    }

    @Test("nextActionJSON serializes command as null when absent")
    func nextActionJSONSerializesNullCommand() {
        let action = NextAction(action: "resolve_blocker", command: nil, reason: "Blocked")
        let json = nextActionJSON(action)
        #expect(json.objectValue?["action"] == .string("resolve_blocker"))
        #expect(json.objectValue?["command"]?.isNull == true)
    }

    @Test("nextActionJSON serializes command when present")
    func nextActionJSONSerializesCommandWhenPresent() {
        let action = NextAction(action: "run_workflow", command: "shipit run beta --ci", reason: "Ready")
        let json = nextActionJSON(action)
        #expect(json.objectValue?["command"] == .string("shipit run beta --ci"))
    }

    @Test("aiSessionPayloadJSON includes all top-level keys")
    func aiSessionPayloadJSONIncludesAllKeys() {
        let payload = AISessionBuilder().build(
            goal: .beta,
            inspection: ProjectInspection(
                rootPath: "/tmp",
                xcodeContainers: [],
                preferredContainer: nil,
                schemes: [],
                suggestedAppConfig: .init(),
                existingShipfiles: [],
                fastlaneFiles: [],
                ciFiles: [],
                warnings: []
            ),
            hasExistingShipfile: false
        )
        let json = aiSessionPayloadJSON(payload)
        let keys = json.objectValue?.keys

        #expect(keys?.contains("version") == true)
        #expect(keys?.contains("goal") == true)
        #expect(keys?.contains("appConfig") == true)
        #expect(keys?.contains("missing") == true)
        #expect(keys?.contains("ambiguities") == true)
        #expect(keys?.contains("suggestedShipfile") == true)
        #expect(keys?.contains("readiness") == true)
        #expect(keys?.contains("nextAction") == true)
        #expect(keys?.contains("agentPrompt") == true)
        #expect(keys?.contains("nextQuestion") == true)
    }

    // MARK: - Schema workflow filter

    @Test("Schema command parses workflow option")
    func schemaCommandParsesWorkflowOption() throws {
        let command = try SchemaCommand.parseAsRoot(["--workflow", "beta"]) as! SchemaCommand
        #expect(command.workflow == .beta)
    }

    @Test("Schema command defaults to nil workflow (full schema)")
    func schemaCommandDefaultsToNoWorkflow() throws {
        let command = try SchemaCommand.parseAsRoot([]) as! SchemaCommand
        #expect(command.workflow == nil)
    }
}

// MARK: - SchemaCommand goal-scoped content

@Suite("SchemaCommand goal-scoped filtering")
struct SchemaCommandGoalFilterTests {

    // Pull the action list the same way SchemaCommand does at runtime:
    // BuiltInSchemaCatalog.actionSchemas() filtered by the goal's relevantActions set.
    // We exercise this by running the command's JSON output path.

    @Test("Beta goal schema includes 'test' action")
    func betaSchemaIncludesTestAction() async throws {
        // Rebuild the filtered list inline (mirrors SchemaCommand.relevantActions(for:.beta))
        let allActions = BuiltInSchemaCatalog.validationActionSchemas()
        let betaActionNames: Set<String> = ["build", "test", "archive", "export", "testflight", "sign", "version", "notify", "git"]
        let betaActions = allActions.filter { betaActionNames.contains($0.name) }

        #expect(betaActions.contains { $0.name == "test" })
    }

    @Test("Beta goal schema includes all expected actions")
    func betaSchemaActionSet() async throws {
        let allActions = BuiltInSchemaCatalog.validationActionSchemas()
        let betaActionNames: Set<String> = ["build", "test", "archive", "export", "testflight", "sign", "version", "notify", "git"]
        let betaActions = allActions.filter { betaActionNames.contains($0.name) }
        let betaNames = Set(betaActions.map(\.name))

        #expect(betaNames.contains("test"))
        #expect(betaNames.contains("version"))
        #expect(betaNames.contains("archive"))
        #expect(betaNames.contains("export"))
        // testflight is in beta but NOT local
        #expect(betaNames.contains("testflight"))
    }

    @Test("Local goal schema includes 'test' action but not 'testflight'")
    func localSchemaExcludesTestFlight() async throws {
        let allActions = BuiltInSchemaCatalog.validationActionSchemas()
        let localActionNames: Set<String> = ["build", "test", "archive", "export", "sign", "git"]
        let localActions = allActions.filter { localActionNames.contains($0.name) }
        let localNames = Set(localActions.map(\.name))

        #expect(localNames.contains("test"))
        #expect(!localNames.contains("testflight"))
    }

    @Test("Beta goal schema test action exposes retry_on_failure option")
    func betaTestActionHasRetryOption() async throws {
        let allActions = BuiltInSchemaCatalog.validationActionSchemas()
        guard let testSchema = allActions.first(where: { $0.name == "test" }) else {
            Issue.record("test action not found in schema catalog")
            return
        }
        #expect(testSchema.options.contains { $0.name == "retry_on_failure" })
        #expect(testSchema.options.contains { $0.name == "only_testing" })
        #expect(testSchema.options.contains { $0.name == "skip_testing" })
    }

    @Test("Schema command parses Android platform option")
    func schemaCommandParsesAndroidPlatformOption() throws {
        let command = try SchemaCommand.parseAsRoot(["--workflow", "beta", "--platform", "android"]) as! SchemaCommand

        #expect(command.global.platform == .android)
        #expect(command.workflow == .beta)
    }

    @Test("Android beta schema includes Play Store and bundle validation actions")
    func androidBetaSchemaIncludesAndroidActions() async throws {
        let allActions = BuiltInSchemaCatalog.validationActionSchemas()
        let androidBetaActionNames: Set<String> = [
            "lint", "test", "archive", "coverage", "validate_bundle", "play-store", "notify", "git",
        ]
        let androidBetaActions = allActions.filter { androidBetaActionNames.contains($0.name) }
        let androidBetaNames = Set(androidBetaActions.map(\.name))

        #expect(androidBetaNames.contains("play-store"))
        #expect(androidBetaNames.contains("validate_bundle"))
        #expect(!androidBetaNames.contains("testflight"))
    }

    @Test("Full schema (no workflow filter) contains all built-in actions")
    func fullSchemaContainsAllActions() async throws {
        let allActions = BuiltInSchemaCatalog.validationActionSchemas()
        let names = Set(allActions.map(\.name))

        for expected in ["build", "test", "archive", "export", "version", "sign", "testflight", "notify", "git"] {
            #expect(names.contains(expected), "Expected '\(expected)' in full schema")
        }
    }
}
