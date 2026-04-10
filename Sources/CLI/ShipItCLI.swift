import ArgumentParser
import Foundation

/// The main CLI entry point for ShipItSwifty.
///
/// `shipit` is a Swift-native CLI toolkit for automating iOS app release workflows.
/// It orchestrates building, code signing, screenshots, metadata management,
/// and distribution to App Store / TestFlight.
///
/// ## Usage
/// ```
/// shipit <command> [options]
/// shipit build --scheme MyApp
/// shipit archive --scheme MyApp --export-method app-store
/// shipit run beta --ci --output json
/// ```
@main
struct ShipItCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shipit",
        abstract: "Swift-native CLI for iOS app release automation.",
        version: "1.0.0",
        subcommands: [
            InitCommand.self,
            SchemaCommand.self,
            InspectCommand.self,
            SuggestConfigCommand.self,
            AIBootstrapCommand.self,
            ValidateCommand.self,
            BuildCommand.self,
            TestCommand.self,
            ArchiveCommand.self,
            ExportCommand.self,
            UploadCommand.self,
            TestFlightCommand.self,
            SnapshotCommand.self,
            FrameCommand.self,
            SignCommand.self,
            VersionCommand.self,
            MetadataCommand.self,
            PrecheckCommand.self,
            ProvisionCommand.self,
            NotifyCommand.self,
            RunCommand.self,
            EnvCommand.self,
            DoctorCommand.self,
        ],
        defaultSubcommand: nil
    )
}

// MARK: - Global Options Mixin

/// Shared options available on every `shipit` subcommand.
struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Path to config file. Defaults to ./Shipfile.yml and must exist for config-backed commands")
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

    var effectiveColorMode: ConsoleColorMode {
        noColor ? .never : color
    }
}

/// Narrow option set for JSON-only AI bootstrap flows.
struct AIBootstrapOptions: ParsableArguments {
    @Option(name: .long, help: "Path to config file. Defaults to ./Shipfile.yml when checking for an existing Shipfile")
    var shipfile: String = "./Shipfile.yml"

    @Flag(name: .long, help: "Enable debug logging")
    var verbose: Bool = false

    @Flag(name: .long, help: "Enable CI mode (non-interactive, strict errors)")
    var ci: Bool = false
}

/// Output format selection.
enum OutputFormat: String, ExpressibleByArgument, Sendable {
    case human
    case json
}
