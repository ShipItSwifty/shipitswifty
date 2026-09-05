import ArgumentParser
import Foundation
import Logging
import ShipItKit

/// The main CLI entry point for ShipItSwifty.
///
/// `shipit` is a Swift-native CLI toolkit for automating iOS and Android app release workflows.
/// It orchestrates building, code signing, screenshots, metadata management,
/// and distribution to App Store / TestFlight (iOS) or Google Play (Android).
///
/// ## Usage
/// ```
/// shipit <command> [options]
/// shipit ai session --goal beta       # start here: inspect the project, see what's missing
/// shipit generate --goal beta         # write a Shipfile.yml from project inspection
/// shipit doctor                       # diagnose setup issues before running anything
/// shipit run beta --ci --output json  # execute a named workflow from Shipfile.yml
/// shipit build --scheme MyApp
/// shipit build --platform android
/// shipit archive --scheme MyApp --export-method app-store
/// shipit run beta --platform android --ci --output json
/// ```
///
/// See `shipit help <subcommand>` for detailed help on any command, and `shipit ai instructions`
/// for guidance aimed specifically at AI agents driving this CLI.
@main
struct ShipItCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shipit",
        abstract: "Swift-native CLI for iOS and Android app release automation.",
        discussion: """
            COMMON WORKFLOWS

              First time on a project:
                shipit ai session --goal beta       Inspect the project; see what's detected vs. missing
                shipit generate --goal beta         Write a starting Shipfile.yml
                shipit doctor                       Confirm the toolchain and config are ready

              Day to day:
                shipit validate yml                 Check Shipfile.yml against the schema
                shipit run beta --dry-run --output json   Preview a workflow's resolved steps
                shipit run beta --ci                Execute a named workflow

              For AI agents:
                shipit ai session                   Machine-readable project state + next step
                shipit ai prompt                     Just the recommended system prompt
                shipit ai instructions              How this CLI expects to be driven

            See 'shipit help <subcommand>' for detailed help on any command.
            """,
        subcommands: subcommandTypes,
        defaultSubcommand: nil
    )

    private static var subcommandTypes: [ParsableCommand.Type] {
        // Ordered by when a new user or agent is likely to need them, grouped loosely as:
        // get started -> inspect/validate -> build & test -> distribute -> workflow orchestration.
        var commands: [ParsableCommand.Type] = [
            AICommand.self,
            GenerateCommand.self,
            SchemaCommand.self,
            InspectCommand.self,
            SuggestConfigCommand.self,
            ValidateCommand.self,
            EnvCommand.self,
            BuildCommand.self,
            TestCommand.self,
            TestResultsCommand.self,
            CoverageCommand.self,
            ArchiveCommand.self,
            LintCommand.self,
            PlayStoreCommand.self,
            NotifyCommand.self,
            RunCommand.self,
            AndroidCLICommand.self,
        ]
        #if os(macOS)
        commands.append(contentsOf: [
            DoctorCommand.self,
            VersionCommand.self,
            ExportCommand.self,
            UploadCommand.self,
            TestFlightCommand.self,
            SnapshotCommand.self,
            FrameCommand.self,
            SignCommand.self,
            MetadataCommand.self,
            PrecheckCommand.self,  // backwards-compat alias for: validate metadata
            ProvisionCommand.self,
        ])
        #endif
        return commands
    }

    /// The version reported by `shipit --version`.
    ///
    /// For released binaries this is overwritten at build time by the release workflow, which
    /// stamps it from the git tag (see `.github/workflows/release.yml`). The literal below is the
    /// fallback for local/dev builds and should track the most recent release tag.
    static let versionString = "0.5.1"

    static func main(_ arguments: [String]?) async {
        let arguments = arguments ?? Array(CommandLine.arguments.dropFirst())
        if arguments == ["--version"] {
            print(versionString)
            return
        }

        // Bootstrap logging before parsing so every Logger created downstream respects --verbose.
        let isVerbose = arguments.contains("--verbose")
        let logLevel: Logger.Level = isVerbose ? .debug : .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = logLevel
            return handler
        }

        do {
            var command = try parseAsRoot(arguments)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }

    static func main() async {
        await main(nil)
    }
}

// MARK: - Global Options Mixin

/// Shared options available on every `shipit` subcommand.
struct GlobalOptions: ParsableArguments {
    @Option(
        name: .long,
        help:
            "Path to config file. Defaults to ./Shipfile.yml and must exist for config-backed commands")
    var shipfile: String = "./Shipfile.yml"

    @Option(name: .long, help: "Output format: human | json")
    var output: OutputFormat = .human

    @Option(name: .long, help: "Color output: auto | always | never")
    var color: ConsoleColorMode = .auto

    @Flag(name: .customLong("no-color"), help: "Disable color in human output")
    var noColor: Bool = false

    @Flag(name: .long, help: "Enable debug logging")
    var verbose: Bool = false

    @Flag(name: .long, help: "Enable CI mode (non-interactive, strict errors)")
    var ci: Bool = false

    @Flag(name: .long, help: "Preview actions without executing")
    var dryRun: Bool = false

    @Option(name: .long, help: "Target platform: ios | android (auto-detected if omitted)")
    var platform: Platform?

    var effectiveColorMode: ConsoleColorMode {
        noColor ? .never : color
    }
}

/// Narrow option set for JSON-only AI session flows.
struct AISessionOptions: ParsableArguments {
    @Option(
        name: .long,
        help: "Path to config file. Defaults to ./Shipfile.yml when checking for an existing Shipfile")
    var shipfile: String = "./Shipfile.yml"

    @Flag(name: .long, help: "Enable debug logging")
    var verbose: Bool = false

    @Option(name: .long, help: "Target platform: ios | android (auto-detected if omitted)")
    var platform: Platform?
}

/// Output format selection.
enum OutputFormat: String, ExpressibleByArgument, Sendable {
    case human
    case json
}
