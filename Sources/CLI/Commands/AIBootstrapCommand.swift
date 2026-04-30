import ArgumentParser
import Foundation
import ShipItKit

struct AIBootstrapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai-bootstrap",
        abstract: "JSON-only bootstrap payload for AI agents"
    )

    @OptionGroup var options: AIBootstrapOptions

    @Option(name: .long, help: "Goal to optimize for: local, beta, or release")
    var goal: SuggestionGoal = .beta

    @Option(name: .long, help: "Root path to inspect")
    var path: String = FileManager.default.currentDirectoryPath

    func run() async throws {
        let inspection = try await ProjectInspector(rootPath: path).inspect()
        let platform = options.platform ?? inspection.detectedPlatform
        let suggestion = ShipfileSuggester().suggest(goal: goal, platform: platform, from: inspection)

        let resolvedShipfilePath = URL(fileURLWithPath: path).appendingPathComponent(options.shipfile)
            .path
        let validator = ShipfileValidator()
        let validationReport: ValidationReport
        let source: String

        if FileManager.default.fileExists(atPath: resolvedShipfilePath) {
            validationReport = await validator.validate(
                shipfilePath: resolvedShipfilePath,
                actionDescriptors: builtInActionDescriptors()
            )
            source = "existing_shipfile"
        } else {
            validationReport = await validator.validate(
                shipfileContents: suggestion.yaml,
                shipfilePath: "<suggested>",
                actionDescriptors: builtInActionDescriptors()
            )
            source = "suggested_yaml"
        }

        let payload: JSONValue = .object([
            "goal": .string(goal.rawValue),
            "inspection": projectInspectionJSON(inspection),
            "schema": .object([
                "shipfile": schemaSectionsJSON(BuiltInSchemaCatalog.shipfileSections()),
                "actions": .array(BuiltInSchemaCatalog.actionSchemas().map(actionSchemaJSON)),
            ]),
            "suggestion": suggestedShipfileJSON(suggestion),
            "validation": validationReportJSON(validationReport),
            "validationSource": .string(source),
        ])

        let reporter = JSONReporter()
        let status = validationReport.isValid ? "success" : "failure"
        print(
            try reporter.encode(
                ActionResultEnvelope(action: "ai-bootstrap", status: status, payload: payload)))

        if !validationReport.isValid {
            throw ExitCode(2)
        }
    }
}
