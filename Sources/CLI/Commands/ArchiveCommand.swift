import ArgumentParser
import ShipItKit

/// Archive the app using `xcodebuild archive`.
struct ArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive the app using xcodebuild archive"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Xcode scheme to archive")
    var scheme: String?

    @Option(name: .long, help: "Build configuration (default: Release)")
    var configuration: String?

    @Option(name: .long, help: "Export method: app-store | ad-hoc | development | enterprise")
    var exportMethod: String?

    @Option(name: .long, help: "Output path for the .xcarchive")
    var outputPath: String?

    @Option(name: .long, help: "Gradle module to archive (Android) or KMP shared module (iOS KMP)")
    var module: String?

    @Option(name: .long, help: "Gradle build variant to bundle (Android, default: release)")
    var buildVariant: String?

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(
                    scheme: scheme, configuration: configuration, ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = ArchiveAction.Options(
                scheme: scheme,
                configuration: configuration,
                exportMethod: exportMethod,
                outputPath: outputPath,
                module: module,
                buildVariant: buildVariant
            )

            if global.dryRun {
                if config.platform == .android {
                    formatter.print(
                        "DRY RUN: Would run Gradle bundle for module '\(module ?? config.androidModule)' variant '\(buildVariant ?? config.androidBuildVariant)'"
                    )
                } else if config.iosBuildSystem == .kmp {
                    formatter.print(
                        "DRY RUN: Would link KMP module '\(module ?? config.kmpSharedModule)' target '\(config.kmpArchiveTarget)' then archive scheme '\(scheme ?? config.appScheme ?? "unknown")'"
                    )
                } else {
                    formatter.print("DRY RUN: Would archive scheme '\(scheme ?? config.appScheme ?? "unknown")'")
                }
                return
            }

            let result = try await ArchiveAction().run(with: options, context: context)
            outputResult(action: "archive", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
