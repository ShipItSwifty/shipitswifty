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

    /// The `emulator` executable to invoke. See ``init(context:executablePath:)`` for resolution.
    public let executablePath: String

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    // MARK: - Init

    /// Creates an `Emulator` command family bound to a shell context.
    ///
    /// - Parameters:
    ///   - context: Shell execution context.
    ///   - executablePath: Explicit `emulator` path. When `nil`, uses
    ///     `$ANDROID_HOME/emulator/emulator` (or `$ANDROID_SDK_ROOT/…`) from the shell context's
    ///     environment if it exists — the SDK does not put `emulator/` on `PATH` — and otherwise
    ///     falls back to `emulator` on `PATH`.
    public init(context: ShellContext = .init(), executablePath: String? = nil) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.arguments = []
        self.executablePath = executablePath ?? Self.resolveExecutable(environment: context.environment)
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        arguments: [String],
        executablePath: String
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.arguments = arguments
        self.executablePath = executablePath
    }

    /// Resolves the SDK's `emulator` binary from `ANDROID_HOME` / `ANDROID_SDK_ROOT`, falling back
    /// to `emulator` on `PATH`.
    static func resolveExecutable(
        environment: [String: String],
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            guard let root = environment[key], !root.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: root).appendingPathComponent("emulator/emulator").path
            if fileExists(candidate) { return candidate }
        }
        return "emulator"
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
        let base = Command(executablePath)
            .args(arguments)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)
        return config.apply(to: base)
    }

    // MARK: - Subcommands

    /// `emulator -avd <name> [options]` — Start an AVD.
    ///
    /// - Parameters:
    ///   - avd: AVD name (as returned by ``list()`` or `avdmanager list avd`).
    ///   - headless: Pass `-no-window -no-audio -no-boot-anim` for headless CI operation. Required
    ///     on machines without a display, where a windowed emulator exits immediately.
    ///   - gpu: GPU acceleration mode (e.g. `"swiftshader_indirect"` for CI without GPU).
    ///   - noSnapshot: Pass `-no-snapshot` to cold boot and not save state on exit, so every run
    ///     starts from the same device state.
    ///   - wipeData: Pass `-wipe-data` to reset user data to factory state.
    ///   - readOnly: Pass `-read-only` so several emulators can run from the same AVD concurrently.
    ///   - port: Pass `-port <n>` to pin the console port, which fixes the serial to
    ///     `emulator-<n>` (must be an even number between 5554 and 5682).
    public func start(
        avd: String,
        headless: Bool = false,
        gpu: String? = nil,
        noSnapshot: Bool = false,
        wipeData: Bool = false,
        readOnly: Bool = false,
        port: Int? = nil
    ) -> Self {
        var args = ["-avd", avd]
        if headless {
            args += ["-no-window", "-no-audio", "-no-boot-anim"]
        }
        if let gpu {
            args += ["-gpu", gpu]
        }
        if noSnapshot { args.append("-no-snapshot") }
        if wipeData { args.append("-wipe-data") }
        if readOnly { args.append("-read-only") }
        if let port { args += ["-port", String(port)] }
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
            arguments: arguments,
            executablePath: executablePath
        )
    }
}
