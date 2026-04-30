import ArgumentParser
import Foundation
import ShipItKit

struct SuggestConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "suggest-config",
        abstract: "Generate a suggested Shipfile for a release goal"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Goal to optimize for: local, beta, or release")
    var goal: SuggestionGoal = .beta

    @Option(name: .long, help: "Root path to inspect")
    var path: String = FileManager.default.currentDirectoryPath

    func run() async throws {
        let inspection = try await ProjectInspector(rootPath: path).inspect()
        let platform = global.platform ?? inspection.detectedPlatform
        let suggestion = ShipfileSuggester().suggest(goal: goal, platform: platform, from: inspection)

        switch global.output {
        case .json:
            let reporter = JSONReporter()
            print(
                try reporter.encode(
                    ActionResultEnvelope(
                        action: "suggest-config", status: "success", payload: suggestedShipfileJSON(suggestion))
                ))
        case .human:
            let formatter = makeHumanFormatter(global: global)
            formatter.printHeader("Suggested Config")
            formatter.printKV("Goal", suggestion.goal.rawValue)
            formatter.printKV("Platform", platform.rawValue)
            if !suggestion.missingValues.isEmpty {
                formatter.printHeader("Missing Values")
                for missing in suggestion.missingValues {
                    let suffix = missing.envVar.map { " [env: \($0)]" } ?? ""
                    formatter.printKV(missing.keyPath, missing.reason + suffix)
                }
            }
            for warning in suggestion.warnings {
                formatter.printWarning(warning)
            }
            formatter.printHeader("YAML")
            formatter.print(suggestion.yaml)
        }
    }
}
