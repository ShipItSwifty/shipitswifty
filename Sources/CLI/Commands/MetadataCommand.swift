#if os(macOS)
import ArgumentParser
import ShipItKit

/// Pull/push App Store metadata from/to App Store Connect.
struct MetadataCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "metadata",
        abstract: "Pull/push App Store metadata from/to App Store Connect"
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Pull metadata from App Store Connect")
    var pull: Bool = false

    @Flag(name: .long, help: "Push local metadata to App Store Connect")
    var push: Bool = false

    @Option(name: .long, help: "Local directory containing metadata files")
    var directory: String?

    @Flag(name: .long, help: "Submit for App Review after pushing metadata")
    var submitForReview: Bool = false

    @Flag(name: .long, help: "Use automatic release after approval")
    var automaticRelease: Bool = false

    @Flag(name: .long, help: "Enable phased release")
    var phasedRelease: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config, verbose: global.verbose)

            let options = MetadataAction.Options(
                pull: pull ? true : nil,
                push: push ? true : nil,
                directory: directory,
                submitForReview: submitForReview ? true : nil,
                automaticRelease: automaticRelease ? true : nil,
                phasedRelease: phasedRelease ? true : nil
            )

            if global.dryRun {
                let op = push ? "push" : "pull"
                try outputDryRun(action: "metadata", message: "Would \(op) metadata", global: global)
                return
            }

            let result = try await MetadataAction().run(with: options, context: context)
            outputResult(action: "metadata", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
#endif
