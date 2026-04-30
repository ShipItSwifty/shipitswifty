import ArgumentParser
import ShipItKit

/// Upload Android release artifact to Google Play.
struct PlayStoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "play-store",
        abstract: "Upload Android release artifact to Google Play and assign to a distribution track"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Path to the .aab file to upload (preferred)")
    var aab: String?

    @Option(name: .long, help: "Path to the .apk file to upload")
    var apk: String?

    @Option(name: .long, help: "Google Play distribution track: internal | alpha | beta | production")
    var track: String?

    @Option(name: .long, help: "Android package name, e.g. com.example.myapp")
    var packageName: String?

    @Option(name: .long, help: "Staged rollout fraction (0.0–1.0); omit for full rollout")
    var rollout: Double?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Release notes in 'lang=text' format, e.g. en-US=\"Bug fixes\""
    )
    var notes: [String] = []

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config)
            let formatter = makeHumanFormatter(global: global)

            // Parse "lang=text" entries into a dictionary
            let releaseNotes: [String: String]? =
                notes.isEmpty
                ? nil
                : Dictionary(
                    uniqueKeysWithValues: notes.compactMap { entry -> (String, String)? in
                        guard let eq = entry.firstIndex(of: "=") else { return nil }
                        let lang = String(entry[entry.startIndex..<eq])
                        let text = String(entry[entry.index(after: eq)...])
                        return (lang, text)
                    }
                )

            let options = PlayStoreAction.Options(
                aabPath: aab,
                apkPath: apk,
                track: track,
                releaseNotes: releaseNotes,
                rolloutFraction: rollout,
                packageName: packageName
            )

            if global.dryRun {
                let artifact = aab ?? apk ?? "unknown"
                let effectiveTrack = track ?? config.androidPlayTrack
                formatter.print("DRY RUN: Would upload '\(artifact)' to Google Play track '\(effectiveTrack)'")
                return
            }

            let result = try await PlayStoreAction().run(with: options, context: context)
            outputResult(action: "play-store", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
