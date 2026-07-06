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
/// shipit build --scheme MyApp
/// shipit build --platform android
/// shipit archive --scheme MyApp --export-method app-store
/// shipit run beta --ci --output json
/// shipit run beta --platform android --ci --output json
/// ```
@main
struct ShipItCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shipit",
        abstract: "Swift-native CLI for iOS and Android app release automation.",
        subcommands: subcommandTypes,
        defaultSubcommand: nil
    )

    private static var subcommandTypes: [ParsableCommand.Type] {
        var commands: [ParsableCommand.Type] = [
            GenerateCommand.self,
            SchemaCommand.self,
            InspectCommand.self,
            SuggestConfigCommand.self,
            AISessionCommand.self,
            ValidateCommand.self,
            BuildCommand.self,
            TestCommand.self,
            TestResultsCommand.self,
            CoverageCommand.self,
            ArchiveCommand.self,
            LintCommand.self,
            PlayStoreCommand.self,
            NotifyCommand.self,
            RunCommand.self,
            EnvCommand.self,
        ]
        #if os(macOS)
        commands.append(contentsOf: [
            VersionCommand.self,
            DoctorCommand.self,
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
    static let versionString = "0.3.0"

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
