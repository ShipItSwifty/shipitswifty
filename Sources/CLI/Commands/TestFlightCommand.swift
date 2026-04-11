import ArgumentParser
import ShipItKit

/// Upload to TestFlight and manage beta distribution.
struct TestFlightCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "testflight",
        abstract: "Upload to TestFlight and manage beta testers"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Path to the .ipa file to upload")
    var ipa: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Beta groups to distribute to")
    var groups: [String] = []

    @Option(name: .long, help: "What's new / changelog text for testers")
    var changelog: String?

    @Flag(name: .long, help: "Skip waiting for Apple's build processing")
    var skipWaiting: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = TestFlightAction.Options(
                ipa: ipa,
                groups: groups.isEmpty ? nil : groups,
                changelog: changelog,
                skipWaitingForBuildProcessing: skipWaiting ? true : nil
            )

            if global.dryRun {
                formatter.print("DRY RUN: Would upload '\(ipa ?? "unknown")' to TestFlight")
                return
            }

            let result = try await TestFlightAction().run(with: options, context: context)
            outputResult(action: "testflight", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
