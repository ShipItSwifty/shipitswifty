import ArgumentParser
import ShipItKit

/// Export IPA from a `.xcarchive` using `xcodebuild -exportArchive`.
struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export IPA from xcarchive"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Path to the .xcarchive to export")
    var archive: String?

    @Option(name: .long, help: "Output directory for the exported IPA")
    var outputDirectory: String?

    @Option(name: .long, help: "Export method: app-store | ad-hoc | development | enterprise")
    var exportMethod: String?

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = ExportAction.Options(
                archivePath: archive,
                outputDirectory: outputDirectory,
                exportMethod: exportMethod
            )

            if global.dryRun {
                formatter.print("DRY RUN: Would export archive '\(archive ?? config.exportArchivePath ?? "unknown")'")
                return
            }

            let result = try await ExportAction().run(with: options, context: context)
            outputResult(action: "export", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
