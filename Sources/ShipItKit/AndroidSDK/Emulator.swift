import Foundation
import SwiftyShell

/// A fluent wrapper for the Android `emulator` command-line tool.
///
/// Used to start and manage Android Virtual Devices (AVDs) in CI environments.
///
/// ## Usage
/// ```swift
/// // Start emulator headless (CI mode)
/// let emulator = Emulator(context: context.shell).start(avd: "test_device", headless: true)
/// let output = try await emulator.run()
///
/// // Wait for boot (separate adb call)
/// let booted = try await Adb(context: context.shell)
///     .shell("getprop sys.boot_completed")
///     .run()
/// ```
public struct Emulator: RunnableCommandFamily {

    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration

    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination

    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination

    /// Arguments for the `emulator` command.
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    // MARK: - Init

    /// Creates an `Emulator` command family bound to a shell context.
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

    /// Redirects stdout.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination, arguments: arguments)
    }

    /// Redirects stderr.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination, arguments: arguments)
    }

    /// Builds the raw `emulator` command.
    public func command() -> Command {
        let base = Command("emulator")
            .args(arguments)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)
        return config.apply(to: base)
    }

    // MARK: - Subcommands

    /// `emulator -avd <name> [options]` — Start an AVD.
    ///
    /// - Parameters:
    ///   - avd: AVD name (as returned by `avdmanager list avd`).
    ///   - headless: Pass `-no-window -no-audio -no-boot-anim` for headless CI operation.
    ///   - gpu: GPU acceleration mode (e.g. `"swiftshader_indirect"` for CI without GPU).
    public func start(avd: String, headless: Bool = false, gpu: String? = nil) -> Self {
        var args = ["-avd", avd]
        if headless {
            args += ["-no-window", "-no-audio", "-no-boot-anim"]
        }
        if let gpu {
            args += ["-gpu", gpu]
        }
        return copy(arguments: args)
    }

    /// `emulator -list-avds` — List all available AVDs.
    public func list() -> Self {
        copy(arguments: ["-list-avds"])
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
