import ArgumentParser
import ShipItKit

struct SchemaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Print the Shipfile and workflow action schema"
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let payload: JSONValue = .object([
            "shipfile": schemaSectionsJSON(BuiltInSchemaCatalog.shipfileSections()),
            "actions": .array(BuiltInSchemaCatalog.actionSchemas().map(actionSchemaJSON)),
        ])

        switch global.output {
        case .json:
            let reporter = JSONReporter()
            print(try reporter.encode(ActionResultEnvelope(action: "schema", status: "success", payload: payload)))
        case .human:
            let formatter = makeHumanFormatter(global: global)
            formatter.printHeader("Schema")
            for section in BuiltInSchemaCatalog.shipfileSections() {
                formatter.printKV(section.name, "\(section.fields.count) field(s)")
            }
            formatter.printHeader("Actions")
            for action in BuiltInSchemaCatalog.actionSchemas() {
                formatter.printKV(action.name, "\(action.options.count) option(s)")
            }
        }
    }
}
