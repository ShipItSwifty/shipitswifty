import ArgumentParser
import Foundation
import ShipItKit

struct CICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ci", abstract: "Export native CI jobs from ShipIt workflows", subcommands: [CIExportCommand.self])
}
struct CIExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "export", abstract: "Export a runnable CI job with artifact publication")
    @OptionGroup var global: GlobalOptions
    @Option(name: .long) var provider: String = "github-actions"
    @Option(name: .long) var workflow: String
    @Option(name: .long, help: "Explicit provider runner label") var runner: String
    @Option(name: .customLong("setup-command"), help: "Toolchain/setup command, repeatable") var setupCommands: [String] = []
    @Option(name: .long) var executable: String = "shipit"
    @Option(name: .long, help: "Write YAML to a new file instead of stdout") var exportPath: String?
    func run() async throws {
        let config = try await resolveRequiredConfig(global: global, cliOptions: .init())
        guard let workflowConfig = config.workflows[workflow] else { throw ValidationError("Unknown workflow: \(workflow)") }
        let provider = try CIProviderRegistry().provider(named: provider)
        let yaml = try provider.export(
            workflow: workflow, config: workflowConfig,
            job: .init(runner: runner, setupCommands: setupCommands, executable: executable, shipfile: global.shipfile))
        if let path = exportPath {
            guard !FileManager.default.fileExists(atPath: path) else { throw ValidationError("Export path already exists: \(path)") }
            if global.dryRun {
                print(yaml)
                return
            }
            try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            print(yaml)
        }
    }
}
