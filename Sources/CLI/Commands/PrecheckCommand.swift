import ArgumentParser
import ShipItKit

/// Validate metadata against App Store guidelines before submission.
struct PrecheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "precheck",
        abstract: "Validate metadata against App Store guidelines before submission"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Local directory containing metadata files")
    var directory: String?

    @Flag(name: .long, help: "Fail on warnings in addition to errors")
    var failOnWarnings: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun)
            )
            let context = try await buildActionContext(config: config)

            let options = PrecheckAction.Options(
                directory: directory,
                failOnWarnings: failOnWarnings ? true : nil
            )

            let result = try await PrecheckAction().run(with: options, context: context)
            outputResult(action: "precheck", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
