import Testing

@testable import CLI
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

  @Test("Generate prints inspection status only for human TTY output")
  func generateInspectionStatusOutputMode() {
    #expect(shouldPrintGenerateInspectionStatus(output: .human, isStderrTTY: true))
    #expect(!shouldPrintGenerateInspectionStatus(output: .human, isStderrTTY: false))
    #expect(!shouldPrintGenerateInspectionStatus(output: .json, isStderrTTY: true))
  }

  @Test("Generate prompt resolves defaults on empty answer")
  func generatePromptResolvesDefaults() {
    #expect(resolvedPromptValue(answer: "", defaultValue: "MyApp") == "MyApp")
    #expect(resolvedPromptValue(answer: "CustomApp", defaultValue: "MyApp") == "CustomApp")
    #expect(resolvedPromptValue(answer: "", defaultValue: nil) == "")
  }

  @Test("Generate confirmation default echo matches chosen answer")
  func generateConfirmationDefaultEcho() {
    #expect(defaultConfirmationEcho(defaultAnswer: true) == "yes")
    #expect(defaultConfirmationEcho(defaultAnswer: false) == "no")
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

  @Test("AI bootstrap parses goal and path")
  func aiBootstrapParsesGoalAndPath() throws {
    let command =
      try AIBootstrapCommand.parseAsRoot([
        "--goal",
        "local",
        "--path",
        "/tmp/project",
      ]) as! AIBootstrapCommand

    #expect(command.goal == .local)
    #expect(command.path == "/tmp/project")
  }

  @Test("AI bootstrap uses narrow bootstrap options")
  func aiBootstrapUsesBootstrapOptions() throws {
    let command =
      try AIBootstrapCommand.parseAsRoot([
        "--shipfile",
        "./Config/Shipfile.yml",
        "--verbose",
      ]) as! AIBootstrapCommand

    #expect(command.options.shipfile == "./Config/Shipfile.yml")
    #expect(command.options.verbose)
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
