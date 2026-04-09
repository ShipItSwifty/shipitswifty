import ArgumentParser
import ShipItKit

/// Bump CFBundleVersion and/or CFBundleShortVersionString.
struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Bump CFBundleVersion and/or CFBundleShortVersionString"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "What to bump: build | patch | minor | major | set")
    var bump: String = "build"

    @Option(name: .long, help: "Specific version string (for --bump set)")
    var versionString: String?

    @Option(name: .long, help: "Specific build number (for --bump set)")
    var buildNumber: String?

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            guard let bumpType = VersionAction.BumpType(rawValue: bump) else {
                throw ShipItError.invalidConfiguration(reason: "Invalid bump type '\(bump)'. Valid values: build, patch, minor, major, set.")
            }

            let options = VersionAction.Options(
                bump: bumpType,
                version: versionString,
                buildNumber: buildNumber
            )

            if global.dryRun {
                formatter.print("DRY RUN: Would bump \(bump)")
                return
            }

            let result = try await VersionAction().run(with: options, context: context)
            outputResult(action: "version", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
