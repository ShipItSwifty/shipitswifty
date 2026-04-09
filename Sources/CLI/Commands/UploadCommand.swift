import ArgumentParser
import ShipItKit

/// Upload IPA and metadata to App Store Connect.
struct UploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload",
        abstract: "Upload IPA and metadata to App Store Connect"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Path to the .ipa file to upload")
    var ipa: String?

    @Flag(name: .long, help: "Submit for App Review after upload")
    var submitForReview: Bool = false

    @Flag(name: .long, help: "Enable phased release")
    var phasedRelease: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = UploadAction.Options(
                ipaPath: ipa,
                submitForReview: submitForReview ? true : nil,
                phasedRelease: phasedRelease ? true : nil
            )

            if global.dryRun {
                formatter.print("DRY RUN: Would upload IPA '\(ipa ?? "unknown")'")
                return
            }

            let result = try await UploadAction().run(with: options, context: context)
            outputResult(action: "upload", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
