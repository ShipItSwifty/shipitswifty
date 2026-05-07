import Foundation
import SwiftyShell

/// A fluent wrapper for the Android Debug Bridge (`adb`) command.
///
/// Provides typed methods for common `adb` operations. All execution goes through
/// the injected `ShellContext`. Device targeting, daemon lifecycle, app management,
/// activity manager (`am`), package manager (`pm`), capture (`screencap`,
/// `screenrecord`), input events, port forwarding, and emulator control are all
/// modelled as fluent methods so consumers do not have to compose raw shell strings.
///
/// ## Usage
/// ```swift
/// // Install an APK on a specific device
/// try await Adb(context: context)
///     .serial("emulator-5554")
///     .install(apk: "./build/app-release.apk", replace: true)
///     .run()
///
/// // Launch an activity
/// try await Adb(context: context)
///     .serial("emulator-5554")
///     .amStartActivity(component: "com.example/.MainActivity", extras: ["arg": "hello"])
///     .run()
///
/// // List installed packages
/// let output = try await Adb(context: context).pmListPackages().run()
/// ```
public struct Adb: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration

    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination

    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination

    /// Optional device serial used to target a specific device. When set, the
    /// generated `adb` command is prefixed with `-s <serial>`.
    public let serial: String?

    /// Positional arguments and subcommand arguments (excluding the `-s <serial>`
    /// prefix, which is applied in ``command()``).
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext {
        config.context
    }

    // MARK: - Init

    /// Creates an `Adb` command family bound to a shell context.
    ///
    /// The new client has no serial set and no subcommand selected. Chain a
    /// subcommand method (e.g. ``devices()``, ``install(apk:replace:)``) before
    /// calling ``run()``.
    ///
    /// - Parameter context: The shell context that supplies the executor,
    ///   environment, and search paths used at runtime.
    public init(context: ShellContext = .init()) {
        config = ToolConfiguration(context: context)
        stdoutDestination = .capture
        stderrDestination = .capture
        serial = nil
        arguments = []
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        serial: String?,
        arguments: [String]
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.serial = serial
        self.arguments = arguments
    }

    // MARK: - RunnableCommandFamily

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(
        _ update: (ToolConfiguration) -> ToolConfiguration
    ) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for the built `adb` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `adb` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Builds the raw `adb` command, prefixing `-s <serial>` when one is set.
    public func command() -> Command {
        var prefix: [String] = []
        if let serial, !serial.isEmpty {
            prefix = ["-s", serial]
        }
        let base = Command("adb")
            .args(prefix + arguments)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)
        return config.apply(to: base)
    }

    // MARK: - Device targeting

    /// Targets the given device serial. Subsequent invocations of ``command()``
    /// prefix the resulting `adb` command with `-s <serial>`.
    ///
    /// Pass `nil` to target whichever single device is connected (no `-s` prefix).
    ///
    /// - Parameter value: The ADB serial of the target device, e.g.
    ///   `"emulator-5554"` or `"R5CT2074MZ"`. Passing `nil` clears any previously
    ///   set serial.
    public func serial(_ value: String?) -> Self {
        Self(
            config: config,
            stdoutDestination: stdoutDestination,
            stderrDestination: stderrDestination,
            serial: value,
            arguments: arguments
        )
    }

    // MARK: - Daemon lifecycle

    /// `adb start-server` — Ensure the local adb daemon is running.
    public func startServer() -> Self {
        copy(arguments: ["start-server"])
    }

    /// `adb kill-server` — Stop the local adb daemon.
    public func killServer() -> Self {
        copy(arguments: ["kill-server"])
    }

    // MARK: - Device discovery

    /// `adb devices [-l]` — List connected devices.
    ///
    /// - Parameter long: Pass `-l` to include the device transport id and product
    ///   metadata.
    public func devices(long: Bool = false) -> Self {
        copy(arguments: long ? ["devices", "-l"] : ["devices"])
    }

    /// `adb wait-for-device` — Block until a device is connected and available.
    public func waitForDevice() -> Self {
        copy(arguments: ["wait-for-device"])
    }

    /// Uses explicit `adb` arguments for operations that are not yet modelled.
    ///
    /// Prefer the typed helpers on ``Adb`` when one fits. This method still routes
    /// through the `Adb` command family so device targeting, output redirection,
    /// and ``ShellContext`` injection remain consistent.
    ///
    /// - Parameter values: Arguments passed after the `adb` executable and any
    ///   configured `-s <serial>` prefix.
    public func rawArguments(_ values: [String]) -> Self {
        copy(arguments: values)
    }

    // MARK: - App lifecycle

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

    /// `adb shell am force-stop <package>` — Terminate the given app on the device.
    public func amForceStop(package: String) -> Self {
        copy(arguments: ["shell", "am", "force-stop", package])
    }

    /// `adb shell am start -n <component> [--es key value]...` — Launch an
    /// activity component with optional string extras.
    ///
    /// - Parameters:
    ///   - component: The `package/.Activity` component name to launch.
    ///   - extras: Optional string extras passed via repeated `--es key value`.
    ///     Useful for forwarding launch arguments to the app under test.
    public func amStartActivity(component: String, extras: [String: String] = [:]) -> Self {
        var args = ["shell", "am", "start", "-n", component]
        for (key, value) in extras.sorted(by: { $0.key < $1.key }) {
            args += ["--es", key, value]
        }
        return copy(arguments: args)
    }

    /// `adb shell am start -n <component> [--es arg value]...` — Launch an
    /// activity component with repeated launch argument extras.
    ///
    /// This is useful for test harnesses that forward argv-style values where
    /// order and duplicates matter.
    ///
    /// - Parameters:
    ///   - component: The `package/.Activity` component name to launch.
    ///   - arguments: Ordered values passed as repeated `--es arg <value>` extras.
    public func amStartActivity(component: String, arguments: [String]) -> Self {
        var args = ["shell", "am", "start", "-n", component]
        for argument in arguments {
            args += ["--es", "arg", argument]
        }
        return copy(arguments: args)
    }

    /// `adb shell am start -a android.intent.action.VIEW -d <url>` — Open a URL
    /// or deep link via the activity manager.
    ///
    /// - Parameter url: The URL to open. Callers should validate the URL scheme
    ///   against an allow-list before forwarding it; ADB sends the URL through
    ///   the device shell which will tokenise on whitespace and metacharacters.
    public func amStartViewURL(_ url: String) -> Self {
        copy(arguments: [
            "shell", "am", "start",
            "-a", "android.intent.action.VIEW",
            "-d", url,
        ])
    }

    // MARK: - Package manager

    /// `adb shell pm list packages` — List installed packages on the device.
    public func pmListPackages() -> Self {
        copy(arguments: ["shell", "pm", "list", "packages"])
    }

    /// `adb shell pm grant <package> <permission>` — Grant a runtime permission.
    public func pmGrantPermission(package: String, permission: String) -> Self {
        copy(arguments: ["shell", "pm", "grant", package, permission])
    }

    /// `adb shell pm revoke <package> <permission>` — Revoke a runtime permission.
    public func pmRevokePermission(package: String, permission: String) -> Self {
        copy(arguments: ["shell", "pm", "revoke", package, permission])
    }

    /// `adb shell cmd package resolve-activity --brief <package>` — Resolve the
    /// launchable activity component for a package.
    public func resolveLaunchableActivity(package: String) -> Self {
        copy(arguments: [
            "shell", "cmd", "package", "resolve-activity", "--brief", package,
        ])
    }

    // MARK: - Capture

    /// `adb shell screencap -p <remote-path>` — Capture a PNG screenshot to a
    /// path on the device.
    public func screencap(remotePath: String) -> Self {
        copy(arguments: ["shell", "screencap", "-p", remotePath])
    }

    /// `adb shell screenrecord <remote-path>` — Start recording the device
    /// display to an MP4 file. The command runs until interrupted (`SIGINT`) or
    /// the recording reaches the device-imposed maximum duration.
    public func screenrecord(remotePath: String) -> Self {
        copy(arguments: ["shell", "screenrecord", remotePath])
    }

    /// `adb shell pkill -INT <process>` — Send `SIGINT` to a process on the
    /// device by name.
    public func shellPkill(signal: String = "INT", process: String) -> Self {
        copy(arguments: ["shell", "pkill", "-\(signal)", process])
    }

    // MARK: - Input

    /// `adb shell input keyevent <keycode>` — Synthesize a hardware key event.
    public func inputKeyevent(_ keycode: String) -> Self {
        copy(arguments: ["shell", "input", "keyevent", keycode])
    }

    // MARK: - Display configuration

    /// `adb shell cmd uimode night <yes|no|auto>` — Set the device's dark/light
    /// appearance mode.
    public func cmdUimodeNight(_ value: UimodeNight) -> Self {
        copy(arguments: ["shell", "cmd", "uimode", "night", value.rawValue])
    }

    /// Values accepted by ``cmdUimodeNight(_:)``.
    public enum UimodeNight: String, Sendable, Equatable, Hashable {
        /// Dark mode (`yes`).
        case yes
        /// Light mode (`no`).
        case no
        /// System auto (`auto`).
        case auto
    }

    // MARK: - Port forwarding

    /// `adb forward tcp:<local> tcp:<remote>` — Forward a host TCP port to the
    /// device.
    public func forwardTCP(localPort: Int, remotePort: Int) -> Self {
        copy(arguments: ["forward", "tcp:\(localPort)", "tcp:\(remotePort)"])
    }

    /// `adb forward --remove tcp:<local>` — Remove a previously installed TCP
    /// port forward.
    public func removeForwardTCP(localPort: Int) -> Self {
        copy(arguments: ["forward", "--remove", "tcp:\(localPort)"])
    }

    // MARK: - File transfer

    /// `adb push <local> <remote>` — Push a local file to the device.
    public func push(local: String, remote: String) -> Self {
        copy(arguments: ["push", local, remote])
    }

    /// `adb pull <remote> <local>` — Pull a file from the device.
    public func pull(remote: String, local: String) -> Self {
        copy(arguments: ["pull", remote, local])
    }

    // MARK: - Shell

    /// `adb shell <command>` — Execute a free-form shell command on the device.
    ///
    /// Prefer the typed helpers (`amStartActivity`, `pmGrantPermission`, etc.)
    /// when one fits; this method exists as an escape hatch for commands that
    /// are not yet modelled. The argument is passed verbatim to the on-device
    /// shell, which will tokenise on whitespace and metacharacters.
    public func shell(_ command: String) -> Self {
        copy(arguments: ["shell", command])
    }

    // MARK: - Emulator control

    /// `adb emu kill` — Shut down the connected emulator.
    public func emuKill() -> Self {
        copy(arguments: ["emu", "kill"])
    }

    /// `adb emu geo fix <longitude> <latitude>` — Set the simulated GPS
    /// location on the connected emulator.
    ///
    /// > Important: The emulator console expects **longitude first**, then
    /// > latitude — the same order this method accepts.
    public func emuGeoFix(longitude: Double, latitude: Double) -> Self {
        copy(arguments: ["emu", "geo", "fix", String(longitude), String(latitude)])
    }

    // MARK: - Logcat

    /// `adb logcat [filters]` — Stream logcat output.
    ///
    /// - Parameter filters: Optional filter specifications (e.g. `["*:E"]` for
    ///   errors only).
    public func logcat(filters: [String] = []) -> Self {
        copy(arguments: ["logcat"] + filters)
    }

    // MARK: - Private

    /// Sentinel optional wrapper used by ``copy(serial:arguments:)`` so callers
    /// can distinguish "no change" (`nil`) from "explicitly clear the serial"
    /// (`Optional.some(nil)`).
    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        serial: String??? = nil,
        arguments: [String]? = nil
    ) -> Self {
        let resolvedSerial: String?
        switch serial {
        case let .some(value):
            resolvedSerial = value ?? nil
        case .none:
            resolvedSerial = self.serial
        }
        return Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            serial: resolvedSerial,
            arguments: arguments ?? self.arguments
        )
    }
}
