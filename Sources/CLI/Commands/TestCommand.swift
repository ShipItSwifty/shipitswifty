import ArgumentParser
import ShipItKit

/// Run unit and UI tests using `xcodebuild test`.
struct TestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run unit and UI tests using xcodebuild test"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Xcode scheme to test")
    var scheme: String?

    @Option(name: .long, help: "Simulator destination (e.g. 'iPhone 16')")
    var destination: String?

    @Flag(name: .long, help: "Enable code coverage collection")
    var codeCoverage: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(scheme: scheme, ci: global.ci, dryRun: global.dryRun)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = TestAction.Options(
                scheme: scheme,
                destination: destination,
                enableCodeCoverage: codeCoverage ? true : nil
            )

            if global.dryRun {
                formatter.print("DRY RUN: Would test scheme '\(scheme ?? config.appScheme ?? "unknown")'")
                return
            }

            let result = try await TestAction().run(with: options, context: context)
            outputResult(action: "test", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
