import ArgumentParser
import ShipItKit
import Foundation

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
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            let options = BuildAction.Options(
                scheme: scheme,
                configuration: configuration.map { BuildAction.BuildConfiguration(rawValue: $0) } ?? nil,
                clean: clean ? true : nil
            )

            if global.dryRun {
                if config.platform == .android {
                    formatter.print("DRY RUN: Would run gradlew assemble\(config.androidBuildVariant.capitalized) in module '\(config.androidModule)'")
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
