import ArgumentParser
import Foundation
import ShipItKit

/// Compile the app using `xcodebuild build` (iOS) or `./gradlew assembleRelease` (Android).
///
/// The target platform is auto-detected from project files or can be specified with `--platform`.
///
/// ## Usage
/// ```
/// shipit build --scheme MyApp
/// shipit build --scheme MyApp --configuration Debug
/// shipit build --platform android
/// shipit build --platform android --output json
/// ```
struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Compile the app (iOS: xcodebuild build, Android: gradlew assemble)"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Xcode scheme to build (iOS)")
    var scheme: String?

    @Option(name: .long, help: "Build configuration (Debug or Release)")
    var configuration: String?

    @Flag(name: .long, help: "Clean before building")
    var clean: Bool = false

    @Option(name: .long, help: "Gradle module to build (Android) or KMP shared module (iOS KMP)")
    var module: String?

    @Option(name: .long, help: "Gradle build variant to assemble (Android, default: release)")
    var buildVariant: String?

    @Option(name: .long, help: "Gradle task scope: module | root (Android)")
    var scope: GradleTaskScope?

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(
                    scheme: scheme,
                    configuration: configuration,
                    ci: global.ci,
                    dryRun: global.dryRun,
                    platform: global.platform
                )
            )
            let context = try await buildActionContext(
                config: config, verbose: global.verbose, jsonOutput: global.output == .json)
            let formatter = makeHumanFormatter(global: global)

            let options = BuildAction.Options(
                scheme: scheme,
                configuration: configuration.map { BuildAction.BuildConfiguration(rawValue: $0) } ?? nil,
                clean: clean ? true : nil,
                module: module,
                buildVariant: buildVariant,
                scope: scope
            )

            if global.dryRun {
                if config.platform == .android {
                    formatter.print(
                        "DRY RUN: Would run Gradle assemble for module '\(module ?? config.androidModule)' variant '\(buildVariant ?? config.androidBuildVariant)'"
                    )
                } else if config.iosBuildSystem == .kmp {
                    formatter.print(
                        "DRY RUN: Would link KMP module '\(module ?? config.kmpSharedModule)' target '\(config.kmpBuildTarget)' then build scheme '\(scheme ?? config.appScheme ?? "unknown")'"
                    )
                } else {
                    formatter.print("DRY RUN: Would build scheme '\(scheme ?? config.appScheme ?? "unknown")'")
                }
                return
            }

            let result = try await BuildAction().run(with: options, context: context)
            outputResult(action: "build", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
