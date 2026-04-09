import Testing
@testable import CLI
@testable import ShipItKit

@Suite("AI CLI Commands")
struct AICommandParsingTests {

    @Test("Suggest config parses goal option")
    func suggestConfigParsesGoal() throws {
        let command = try SuggestConfigCommand.parseAsRoot([
            "--goal",
            "release",
        ]) as! SuggestConfigCommand

        #expect(command.goal == .release)
    }

    @Test("Inspect project parses explicit path")
    func inspectProjectParsesPath() throws {
        let command = try InspectCommand.Project.parseAsRoot([
            "--path",
            "/tmp/example",
        ]) as! InspectCommand.Project

        #expect(command.path == "/tmp/example")
    }

    @Test("AI bootstrap parses goal and path")
    func aiBootstrapParsesGoalAndPath() throws {
        let command = try AIBootstrapCommand.parseAsRoot([
            "--goal",
            "local",
            "--path",
            "/tmp/project",
        ]) as! AIBootstrapCommand

        #expect(command.goal == .local)
        #expect(command.path == "/tmp/project")
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
