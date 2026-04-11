import ArgumentParser
import ShipItKit

/// Run static analysis and lint checks.
struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Run static analysis and lint checks (iOS: xcodebuild analyze, Android: gradlew lint)"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Xcode scheme to analyze (iOS only)")
    var scheme: String?

    @Option(name: .long, help: "Build configuration for analysis — default: Debug (iOS only)")
    var configuration: String?

    @Option(name: .long, help: "Gradle module to lint — default: app (Android only)")
    var module: String?

    @Option(name: .shortAndLong, help: "Build variant to lint, e.g. release (Android only)")
    var variant: String?

    @Option(name: .long, help: "Path to write the lint report (Android only)")
    var reportPath: String?

    @Flag(name: .long, help: "Do not fail the build on lint errors (Android only)")
    var noFailOnError: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = LintAction.Options(
                scheme: scheme,
                configuration: configuration,
                module: module,
                buildVariant: variant,
                reportPath: reportPath,
                failOnError: noFailOnError ? false : nil
            )

            if global.dryRun {
                switch config.platform {
                case .ios:
                    formatter.print("DRY RUN: Would run xcodebuild analyze on scheme '\(scheme ?? config.appScheme ?? "unknown")'")
                case .android:
                    formatter.print("DRY RUN: Would run gradlew lint on module '\(module ?? config.androidModule)'")
                }
                return
            }

            let result = try await LintAction().run(with: options, context: context)
            outputResult(action: "lint", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
