import ArgumentParser
import ShipItKit

/// Capture localized screenshots on simulators.
struct SnapshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Capture localized screenshots on simulators"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, parsing: .upToNextOption, help: "Simulator device names")
    var devices: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Locale identifiers (e.g. en-US, ja)")
    var locales: [String] = []

    @Option(name: .long, help: "Xcode scheme with screenshot UI tests")
    var scheme: String?

    @Option(name: .long, help: "Output directory for screenshots")
    var outputDirectory: String?

    @Flag(name: .long, help: "Clear previous screenshots before capture")
    var clear: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(scheme: scheme, ci: global.ci, dryRun: global.dryRun)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = SnapshotAction.Options(
                devices: devices.isEmpty ? nil : devices,
                locales: locales.isEmpty ? nil : locales,
                scheme: scheme,
                outputDirectory: outputDirectory,
                clear: clear ? true : nil
            )

            if global.dryRun {
                formatter.print("DRY RUN: Would capture screenshots for \(devices.count) device(s) and \(locales.count) locale(s)")
                return
            }

            let result = try await SnapshotAction().run(with: options, context: context)
            outputResult(action: "snapshot", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
