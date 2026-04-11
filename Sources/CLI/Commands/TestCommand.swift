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

    @Option(name: .long, help: "Simulator or device destination (e.g. 'platform=iOS Simulator,name=iPhone 16')")
    var destination: String?

    @Option(name: .long, help: "Build configuration (default: Debug)")
    var configuration: String?

    @Flag(name: .long, help: "Enable code coverage collection (auto-generates result bundle path if --result-bundle-path is not set)")
    var codeCoverage: Bool = false

    @Option(name: .long, help: "Path to write the .xcresult bundle")
    var resultBundlePath: String?

    @Option(name: .long, help: "Test plan name to run")
    var testPlan: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Restrict run to specific test targets or test cases (repeatable, e.g. MyAppTests/MyFeatureTests)"
    )
    var onlyTesting: [String] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Skip specific test targets or test cases (repeatable)"
    )
    var skipTesting: [String] = []

    @Flag(name: .long, help: "Retry failing tests once before reporting failure")
    var retryOnFailure: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(scheme: scheme, ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = TestAction.Options(
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                enableCodeCoverage: codeCoverage ? true : nil,
                resultBundlePath: resultBundlePath,
                testPlan: testPlan,
                onlyTesting: onlyTesting.isEmpty ? nil : onlyTesting,
                skipTesting: skipTesting.isEmpty ? nil : skipTesting,
                retryOnFailure: retryOnFailure ? true : nil
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
