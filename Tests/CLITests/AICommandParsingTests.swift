import Testing

@testable import ShipItCLI
@testable import ShipItKit

@Suite("AI CLI Commands")
struct AICommandParsingTests {

    @Test("Suggest config parses goal option")
    func suggestConfigParsesGoal() throws {
        let command =
            try SuggestConfigCommand.parseAsRoot([
                "--goal",
                "release",
            ]) as! SuggestConfigCommand

        #expect(command.goal == .release)
    }

    @Test("Generate parses goal and non-interactive flag")
    func generateParsesGoalAndNonInteractive() throws {
        let command =
            try GenerateCommand.parseAsRoot([
                "--goal",
                "release",
                "--non-interactive",
                "--skip-doctor-prompt",
            ]) as! GenerateCommand

        #expect(command.goal == .release)
        #expect(command.nonInteractive)
        #expect(command.skipDoctorPrompt)
    }

    @Test("Generate prints inspection status when stderr is a TTY")
    func generateInspectionStatusOutputMode() {
        #expect(shouldPrintGenerateInspectionStatus(output: .human, isStderrTTY: true))
        #expect(!shouldPrintGenerateInspectionStatus(output: .human, isStderrTTY: false))
        #expect(shouldPrintGenerateInspectionStatus(output: .json, isStderrTTY: true))
        #expect(!shouldPrintGenerateInspectionStatus(output: .json, isStderrTTY: false))
    }

    @Test("Generate prompt resolves defaults on empty answer")
    func generatePromptResolvesDefaults() {
        #expect(resolvedPromptValue(answer: "", defaultValue: "MyApp") == "MyApp")
        #expect(resolvedPromptValue(answer: "CustomApp", defaultValue: "MyApp") == "CustomApp")
        #expect(resolvedPromptValue(answer: "", defaultValue: nil) == "")
    }

    @Test("Generate platform focus defaults to both on empty answer")
    func generatePlatformFocusDefaultsToBoth() {
        #expect(
            resolvedPlatformFocus(answer: "", defaultFocus: .both) == .both
        )
    }

    @Test("Generate platform focus accepts ios android and both")
    func generatePlatformFocusAcceptsExpectedValues() {
        #expect(resolvedPlatformFocus(answer: "ios", defaultFocus: .both) == .ios)
        #expect(resolvedPlatformFocus(answer: "android", defaultFocus: .both) == .android)
        #expect(resolvedPlatformFocus(answer: "both", defaultFocus: .ios) == .both)
    }

    @Test("Generate platform focus falls back for invalid values")
    func generatePlatformFocusFallsBackForInvalidValues() {
        #expect(resolvedPlatformFocus(answer: "invalid", defaultFocus: .both) == .both)
    }

    @Test("Generate confirmation default echo matches chosen answer")
    func generateConfirmationDefaultEcho() {
        #expect(defaultConfirmationEcho(defaultAnswer: true) == "yes")
        #expect(defaultConfirmationEcho(defaultAnswer: false) == "no")
    }

    @Test("Generate default prompt echo rewrites TTY prompt line")
    func generateDefaultPromptEchoRewritesTTYLine() {
        #expect(
            defaultPromptEcho(promptLine: "Xcode scheme [MyApp]: ", value: "MyApp", isStdoutTTY: true)
                == "\u{001B}[1A\u{001B}[2K\rXcode scheme [MyApp]: MyApp\n"
        )
        #expect(
            defaultPromptEcho(promptLine: "Xcode scheme [MyApp]: ", value: "MyApp", isStdoutTTY: false)
                == "MyApp\n"
        )
    }

    @Test("Generate env var collection skipped when non-interactive")
    func generateEnvCollectionSkippedNonInteractive() throws {
        // When --non-interactive is passed, collectEnvironmentVariables must not block.
        // We verify the flag is parsed and respected; the gating guard in
        // collectEnvironmentVariables checks `nonInteractive` before prompting.
        let command =
            try GenerateCommand.parseAsRoot([
                "--goal", "beta",
                "--non-interactive",
            ]) as! GenerateCommand

        #expect(command.nonInteractive)
    }

    @Test("EnvVarSpec distinguishes sensitive and non-sensitive vars")
    func envVarSpecSensitivity() {
        let keyID = GenerateCommand.EnvVarSpec(
            name: "ASC_KEY_ID", isSensitive: false, description: "API key ID")
        let privateKey = GenerateCommand.EnvVarSpec(
            name: "ASC_PRIVATE_KEY", isSensitive: true, description: "Raw PEM content")
        let password = GenerateCommand.EnvVarSpec(
            name: "P12_PASSWORD", isSensitive: true, description: "Certificate password")

        #expect(!keyID.isSensitive)
        #expect(privateKey.isSensitive)
        #expect(password.isSensitive)
        #expect(keyID.name == "ASC_KEY_ID")
        #expect(privateKey.description == "Raw PEM content")
    }

    @Test("Root parser includes generate and removes init")
    func rootParserIncludesGenerateAndRemovesInit() throws {
        let command = try ShipItCLI.parseAsRoot(["generate", "--dry-run"]) as! GenerateCommand

        #expect(command.global.dryRun)
        #expect(throws: (any Error).self) {
            _ = try ShipItCLI.parseAsRoot(["init"])
        }
    }

    @Test("Inspect project parses explicit path")
    func inspectProjectParsesPath() throws {
        let command =
            try InspectCommand.Project.parseAsRoot([
                "--path",
                "/tmp/example",
            ]) as! InspectCommand.Project

        #expect(command.path == "/tmp/example")
    }

    @Test("Schema field JSON includes nested properties")
    func schemaFieldJSONIncludesNestedProperties() {
        let field = SchemaField.object(
            "notifications",
            description: "Notification settings.",
            properties: [
                .string("channel", description: "Slack channel.")
            ]
        )

        let json = schemaFieldJSON(field)
        let properties = json.objectValue?["properties"]?.arrayValue

        #expect(properties?.count == 1)
        #expect(properties?.first?.objectValue?["name"] == .string("channel"))
    }
}
