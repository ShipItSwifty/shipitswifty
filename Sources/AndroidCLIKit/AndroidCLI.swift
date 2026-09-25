import Foundation
import SwiftyShell

/// A typed, immutable wrapper around Google's preview `android` command-line tool (AndroidCLI).
///
/// AndroidCLI complements Gradle and ADB; it does not currently build release artifacts.
/// All execution is delegated to the injected ``ShellContext``. Each builder method returns a new
/// value, so a configured base (executable, SDK path, output destinations) can be reused for
/// several commands.
///
/// Subcommands are grouped by family in extensions:
/// - Project: ``create(name:output:template:minSDK:verbose:)``, ``describe(projectDirectory:)``,
///   ``info(field:)``, ``initialize()``, ``docsSearch(_:)``
/// - Deployment and UI: ``install(apks:device:installOptions:useDeltaInstall:verbose:)``,
///   ``run(apks:device:activity:type:installOptions:useDeltaInstall:debug:verbose:)``,
///   ``layout(device:output:diff:pretty:)``, ``screenCapture(device:output:annotate:)``
/// - Emulators: ``emulatorList(long:)``, ``emulatorStart(device:cold:)``, …
/// - SDK packages: ``sdkList(pattern:all:allVersions:beta:canary:)``, ``sdkInstall(packages:beta:canary:force:platform:)``, …
/// - Agent skills: ``skillsList(long:project:)``, ``skillsAdd(skill:all:agents:project:)``, …
/// - Android Studio: ``studioCheck()``, ``studioFindUsages(symbol:short:pid:project:)``, …
///
/// Commands that change the machine or a device (create, install, run, emulator and SDK
/// mutations, skills add/remove, update) are not gated here; ShipItKit's `android-*` actions and
/// the `shipit android-cli` command require an explicit opt-in (`allow_mutation` /
/// `--allow-mutation`) before running them.
///
/// ## Usage
/// ```swift
/// let cli = AndroidCLI(context: shell, sdkPath: "/opt/android-sdk")
///
/// // Structured project description
/// let description = try await cli.describe(projectDirectory: ".").run()
///
/// // Current UI tree as typed elements
/// let json = try await cli.layout(device: "emulator-5554").run().stdout
/// let elements = try AndroidCLIOutputParser.layoutElements(from: json)
/// ```
public struct AndroidCLI: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination
    /// Subcommand arguments, emitted after the global `--sdk` option.
    public let arguments: [String]
    /// The `android` executable to invoke. Defaults to `android` on `PATH`.
    public let executablePath: String
    /// Optional Android SDK root, passed as the global `--sdk=<path>` option.
    public let sdkPath: String?

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates an AndroidCLI command family bound to a shell context.
    ///
    /// - Parameters:
    ///   - context: Shell execution context.
    ///   - executablePath: The `android` executable. Defaults to `android` on `PATH`.
    ///   - sdkPath: Optional Android SDK root passed as `--sdk=<path>` to every command.
    public init(
        context: ShellContext = .init(),
        executablePath: String = "android",
        sdkPath: String? = nil
    ) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.arguments = []
        self.executablePath = executablePath
        self.sdkPath = sdkPath
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        arguments: [String],
        executablePath: String,
        sdkPath: String?
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.arguments = arguments
        self.executablePath = executablePath
        self.sdkPath = sdkPath
    }

    // MARK: - Configuration

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(_ update: (ToolConfiguration) -> ToolConfiguration) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for built commands.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for built commands.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Returns a copy that invokes the given `android` executable.
    public func settingExecutablePath(_ path: String) -> Self { copy(executablePath: path) }

    /// Returns a copy that passes `--sdk=<path>`, or omits it when `path` is `nil`.
    public func settingSDKPath(_ path: String?) -> Self { copy(sdkPath: path) }

    // MARK: - RunnableCommandFamily

    /// Builds the raw command: `<executable> [--sdk=<path>] <arguments…>`.
    public func command() -> Command {
        var allArguments: [String] = []
        if let sdkPath { allArguments.append("--sdk=\(sdkPath)") }
        allArguments += arguments
        return config.apply(
            to: Command(executablePath)
                .args(allArguments)
                .stdout(stdoutDestination)
                .stderr(stderrDestination)
        )
    }

    // MARK: - Generic

    /// Replaces the subcommand arguments verbatim. Use for commands not modeled by this type.
    public func rawArguments(_ arguments: [String]) -> Self { copy(arguments: arguments) }

    /// `android --version`
    public func version() -> Self { rawArguments(["--version"]) }

    /// `android help [command…]`
    public func help(command: [String] = []) -> Self { rawArguments(["help"] + command) }

    /// `android update [--url=<url>]` — Update AndroidCLI itself. **Mutating.**
    public func update(url: String? = nil) -> Self {
        rawArguments(["update"] + (url.map { ["--url=\($0)"] } ?? []))
    }

    // MARK: - Private

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        arguments: [String]? = nil,
        executablePath: String? = nil,
        sdkPath: String?? = .none
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            arguments: arguments ?? self.arguments,
            executablePath: executablePath ?? self.executablePath,
            sdkPath: sdkPath ?? self.sdkPath
        )
    }
}
