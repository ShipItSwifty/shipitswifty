import ArgumentParser
import ShipItKit

struct SchemaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Print the Shipfile and workflow action schema"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Filter to schema relevant for a specific goal: local, beta, release")
    var workflow: SuggestionGoal?

    func run() async throws {
        let allSections = BuiltInSchemaCatalog.shipfileSections()
        let allActions = BuiltInSchemaCatalog.actionSchemas()

        let sections: [SchemaSection]
        let actions: [ActionSchema]

        if let goal = workflow {
            sections = allSections.filter { relevantSections(for: goal).contains($0.name) }
            let actionNames = relevantActions(for: goal)
            actions = allActions.filter { actionNames.contains($0.name) }
        } else {
            sections = allSections
            actions = allActions
        }

        let payload: JSONValue = .object([
            "shipfile": schemaSectionsJSON(sections),
            "actions": .array(actions.map(actionSchemaJSON)),
        ])

        switch global.output {
        case .json:
            let reporter = JSONReporter()
            print(try reporter.encode(ActionResultEnvelope(action: "schema", status: "success", payload: payload)))
        case .human:
            let formatter = makeHumanFormatter(global: global)
            if let goal = workflow {
                formatter.printHeader("Schema — \(goal.rawValue) workflow")
            } else {
                formatter.printHeader("Schema")
            }
            for section in sections {
                formatter.printKV(section.name, "\(section.fields.count) field(s)")
            }
            formatter.printHeader("Actions")
            for action in actions {
                formatter.printKV(action.name, "\(action.options.count) option(s)")
            }
        }
    }

    // MARK: - Goal-scoped filtering

    /// Shipfile sections relevant to a given goal.
    private func relevantSections(for goal: SuggestionGoal) -> Set<String> {
        switch goal {
        case .local:
            return ["app", "build", "code_signing", "archive", "export", "versioning"]
        case .beta:
            return ["app", "app_store_connect", "build", "code_signing", "archive", "export", "testflight", "versioning", "notifications"]
        case .release:
            return ["app", "app_store_connect", "build", "code_signing", "archive", "export", "testflight", "metadata", "screenshots", "versioning", "notifications"]
        }
    }

    /// Action names relevant to a given goal.
    private func relevantActions(for goal: SuggestionGoal) -> Set<String> {
        switch goal {
        case .local:
            return ["build", "test", "archive", "export", "sign", "git"]
        case .beta:
            return ["build", "test", "archive", "export", "testflight", "sign", "version", "notify", "git"]
        case .release:
            return ["build", "archive", "export", "upload", "testflight", "precheck", "metadata", "sign", "version", "notify", "git"]
        }
    }
}
