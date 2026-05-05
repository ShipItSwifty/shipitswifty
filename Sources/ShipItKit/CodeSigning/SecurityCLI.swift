#if os(macOS)
import Foundation
import SwiftyShell

/// A typed wrapper for macOS `security` CLI commands.
///
/// Use this command family for all keychain and certificate operations instead of
/// constructing raw `Command("security", ...)` values at call sites.
public struct SecurityCLI: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination
    /// Typed `security` arguments for the selected operation.
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates a `security` command family bound to a shell context.
    public init(context: ShellContext = .init()) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.arguments = []
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        arguments: [String]
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.arguments = arguments
    }

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(
        _ update: (ToolConfiguration) -> ToolConfiguration
    ) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for the built `security` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `security` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Uses the `security help` subcommand.
    public func help(_ subject: String? = nil) -> Self {
        var values = ["help"]
        if let subject {
            values.append(subject)
        }
        return copy(arguments: values)
    }

    /// Uses the `security create-keychain` subcommand.
    public func createKeychain(name: String, password: String) -> Self {
        copy(arguments: ["create-keychain", "-p", password, name])
    }

    /// Uses the `security set-keychain-settings` subcommand.
    public func setKeychainSettings(name: String, timeout: Int) -> Self {
        copy(arguments: ["set-keychain-settings", "-lut", String(timeout), name])
    }

    /// Uses the `security list-keychains -d user -s ...` subcommand.
    public func setUserKeychainSearchList(_ keychains: [String]) -> Self {
        copy(arguments: ["list-keychains", "-d", "user", "-s"] + keychains)
    }

    /// Uses the `security import` subcommand for a certificate file.
    public func importCertificate(
        at path: String,
        keychainName: String,
        password: String,
        trustedApplications: [String]
    ) -> Self {
        var values = ["import", path, "-k", keychainName, "-P", password]
        for application in trustedApplications {
            values.append(contentsOf: ["-T", application])
        }
        return copy(arguments: values)
    }

    /// Uses the `security set-key-partition-list` subcommand.
    public func setKeyPartitionList(services: String, password: String, keychainName: String) -> Self {
        copy(arguments: ["set-key-partition-list", "-S", services, "-s", "-k", password, keychainName])
    }

    /// Uses the `security unlock-keychain` subcommand.
    public func unlockKeychain(name: String, password: String) -> Self {
        copy(arguments: ["unlock-keychain", "-p", password, name])
    }

    /// Uses the `security delete-keychain` subcommand.
    public func deleteKeychain(name: String) -> Self {
        copy(arguments: ["delete-keychain", name])
    }

    /// Builds the raw `security` command.
    public func command() -> Command {
        let base = Command("security")
            .args(arguments)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)

        return config.apply(to: base)
    }

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        arguments: [String]? = nil
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            arguments: arguments ?? self.arguments
        )
    }
}
#endif
