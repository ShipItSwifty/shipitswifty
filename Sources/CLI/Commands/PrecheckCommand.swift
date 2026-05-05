#if os(macOS)
import ArgumentParser
import ShipItKit

/// Backwards-compatible alias for `shipit validate metadata`.
///
/// Validates App Store metadata against precheck rules.
/// Prefer `shipit validate metadata` for new scripts; this alias is kept for compatibility.
struct PrecheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "precheck",
        abstract: "Validate metadata against App Store guidelines (alias for: validate metadata)"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Local directory containing metadata files")
    var directory: String?

    @Flag(name: .long, help: "Fail on warnings in addition to errors")
    var failOnWarnings: Bool = false

    func run() async throws {
        // Delegate entirely to ValidateMetadataCommand so behaviour is identical
        var metadataCommand = ValidateMetadataCommand()
        metadataCommand.global = global
        metadataCommand.directory = directory
        metadataCommand.failOnWarnings = failOnWarnings
        try await metadataCommand.run()
    }
}
#endif
