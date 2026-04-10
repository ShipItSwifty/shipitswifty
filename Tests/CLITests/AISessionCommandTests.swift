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
        let command = try AISessionCommand.parseAsRoot([
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
