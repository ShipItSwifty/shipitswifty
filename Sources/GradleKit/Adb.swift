import Foundation
import SwiftyShell

/// A fluent wrapper for the Android Debug Bridge (`adb`) command.
///
/// Provides typed methods for common `adb` operations. All execution goes through
/// the injected `ShellContext`.
///
/// ## Usage
/// ```swift
/// // Install an APK
/// let output = try await Adb(context: context.shell)
///     .install(apk: "./build/app-release.apk", replace: true)
///     .run()
///
/// // List connected devices
/// let devices = try await Adb(context: context.shell).devices().run()
/// ```
public struct Adb: RunnableCommandFamily {

    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration

    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination

    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination

    /// Positional arguments and subcommand arguments.
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    // MARK: - Init

    /// Creates an `Adb` command family bound to a shell context.
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

    // MARK: - RunnableCommandFamily

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(
        _ update: (ToolConfiguration) -> ToolConfiguration
    ) -> Self {
        copy(config: update(config), arguments: arguments)
    }

    /// Redirects stdout for the built `adb` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination, arguments: arguments)
    }

    /// Redirects stderr for the built `adb` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination, arguments: arguments)
    }

    /// Builds the raw `adb` command.
    public func command() -> Command {
        let base = Command("adb")
            .args(arguments)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)
        return config.apply(to: base)
    }

    // MARK: - Subcommands

    /// `adb devices` — List connected devices.
    public func devices() -> Self {
        copy(arguments: ["devices"])
    }

    /// `adb install [-r] <apk>` — Install an APK on the connected device.
    ///
    /// - Parameters:
    ///   - apk: Path to the APK file.
    ///   - replace: Pass `-r` to replace an existing installation.
    public func install(apk: String, replace: Bool = false) -> Self {
        var args = ["install"]
        if replace { args.append("-r") }
        args.append(apk)
        return copy(arguments: args)
    }

    /// `adb uninstall <package>` — Uninstall the given package.
    public func uninstall(package: String) -> Self {
        copy(arguments: ["uninstall", package])
    }

    /// `adb shell <command>` — Execute a shell command on the device.
    public func shell(_ command: String) -> Self {
        copy(arguments: ["shell", command])
    }

    /// `adb push <local> <remote>` — Push a local file to the device.
    public func push(local: String, remote: String) -> Self {
        copy(arguments: ["push", local, remote])
    }

    /// `adb pull <remote> <local>` — Pull a file from the device.
    public func pull(remote: String, local: String) -> Self {
        copy(arguments: ["pull", remote, local])
    }

    /// `adb logcat` — Stream logcat output.
    ///
    /// - Parameter filters: Optional filter specifications (e.g. `["*:E"]` for errors only).
    public func logcat(filters: [String] = []) -> Self {
        copy(arguments: ["logcat"] + filters)
    }

    /// `adb wait-for-device` — Block until a device is connected and available.
    public func waitForDevice() -> Self {
        copy(arguments: ["wait-for-device"])
    }

    // MARK: - Private

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        arguments: [String]
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            arguments: arguments
        )
    }
}
