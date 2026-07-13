#if os(macOS)
import ArgumentParser
import ShipItKit

/// Overlay device frames on screenshots.
struct FrameCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frame",
        abstract: "Overlay device frames on screenshots"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Directory containing raw screenshots")
    var screenshotsDirectory: String?

    @Option(name: .long, help: "Output directory for framed screenshots")
    var outputDirectory: String?

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config, verbose: global.verbose)

            let options = FrameAction.Options(
                screenshotsDirectory: screenshotsDirectory,
                outputDirectory: outputDirectory
            )

            if global.dryRun {
                try outputDryRun(
                    action: "frame",
                    message: "Would frame screenshots from '\(screenshotsDirectory ?? config.screenshotOutputDirectory)'",
                    global: global
                )
                return
            }

            let result = try await FrameAction().run(with: options, context: context)
            outputResult(action: "frame", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
#endif
