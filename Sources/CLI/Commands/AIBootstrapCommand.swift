import ArgumentParser
import Foundation
import ShipItKit

struct AIBootstrapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai-bootstrap",
        abstract: "Bundle inspect, schema, suggestion, and validation into one response"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Goal to optimize for: local, beta, or release")
    var goal: SuggestionGoal = .beta

    @Option(name: .long, help: "Root path to inspect")
    var path: String = FileManager.default.currentDirectoryPath

    func run() async throws {
        let inspection = try await ProjectInspector(rootPath: path).inspect()
        let suggestion = ShipfileSuggester().suggest(goal: goal, from: inspection)

        let resolvedShipfilePath = URL(fileURLWithPath: path).appendingPathComponent(global.shipfile).path
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

        switch global.output {
        case .json:
            let reporter = JSONReporter()
            let status = validationReport.isValid ? "success" : "failure"
            print(try reporter.encode(ActionResultEnvelope(action: "ai-bootstrap", status: status, payload: payload)))
        case .human:
            let formatter = makeHumanFormatter(global: global)
            formatter.printHeader("AI Bootstrap")
            formatter.printKV("Goal", goal.rawValue)
            formatter.printKV("Validation Source", source)
            formatter.printKV("Suggested Scheme", inspection.suggestedAppConfig.scheme ?? "(not set)")
            formatter.printKV("Suggested Bundle ID", inspection.suggestedAppConfig.bundleID ?? "(not set)")
            formatter.printKV("Suggested Team ID", inspection.suggestedAppConfig.teamID ?? "(not set)")
            formatter.printKV("Suggested YAML Valid", validationReport.isValid ? "yes" : "no")

            if !suggestion.missingValues.isEmpty {
                formatter.printHeader("Missing Values")
                for missing in suggestion.missingValues {
                    let suffix = missing.envVar.map { " [env: \($0)]" } ?? ""
                    formatter.printKV(missing.keyPath, missing.reason + suffix)
                }
            }

            if !validationReport.issues.isEmpty {
                formatter.printHeader("Validation")
                for issue in validationReport.issues {
                    let line = "\(issue.path): \(issue.message)"
                    switch issue.severity {
                    case .error:
                        formatter.printError(line)
                    case .warning:
                        formatter.printWarning(line)
                    }
                }
            }

            formatter.printHeader("YAML")
            formatter.print(suggestion.yaml)
        }

        if !validationReport.isValid {
            throw ExitCode(2)
        }
    }
}
