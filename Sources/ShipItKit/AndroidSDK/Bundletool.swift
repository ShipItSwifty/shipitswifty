import Foundation
import SwiftyShell

/// A fluent wrapper for `bundletool` — the tool for manipulating Android App Bundles.
///
/// `bundletool` is a command-line tool from Google for working with Android App Bundles (AABs).
/// It is distributed as a JAR and invoked via `java -jar bundletool.jar`.
///
/// ## Usage
/// ```swift
/// // Build APK set from AAB for a connected device
/// let output = try await Bundletool(context: context.shell)
///     .buildApks(
///         bundle: "./build/app-release.aab",
///         output: "./build/app.apks",
///         connectedDevice: true
///     )
///     .run()
/// ```
///
/// - Note: Set `BUNDLETOOL_JAR` or pass `jarPath` to specify the JAR location.
///   The default fallback is `bundletool` on PATH (if installed as a native binary on macOS via Homebrew).
public struct Bundletool: RunnableCommandFamily {

    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration

    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination

    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination

    /// All positional and named arguments for the bundletool subcommand.
    public let arguments: [String]

    /// Path to the `bundletool.jar` file. When nil, falls back to `bundletool` on PATH.
    public let jarPath: String?

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    // MARK: - Init

    /// Creates a `Bundletool` command family bound to a shell context.
    ///
    /// - Parameters:
    ///   - context: Shell execution context.
    ///   - jarPath: Explicit path to `bundletool.jar`. Defaults to `BUNDLETOOL_JAR` env var,
    ///     then falls back to `bundletool` command on PATH.
    public init(context: ShellContext = .init(), jarPath: String? = nil) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.arguments = []
        self.jarPath = jarPath ?? ProcessInfo.processInfo.environment["BUNDLETOOL_JAR"]
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        arguments: [String],
        jarPath: String?
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.arguments = arguments
        self.jarPath = jarPath
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

    /// Builds the raw command.
    public func command() -> Command {
        let base: Command
        if let jar = jarPath {
            base = Command("java")
                .args(["-jar", jar])
                .args(arguments)
                .stdout(stdoutDestination)
                .stderr(stderrDestination)
        } else {
            base = Command("bundletool")
                .args(arguments)
                .stdout(stdoutDestination)
                .stderr(stderrDestination)
        }
        return config.apply(to: base)
    }

    // MARK: - Subcommands

    /// `bundletool build-apks` — Build an APK set from an AAB.
    ///
    /// - Parameters:
    ///   - bundle: Path to the `.aab` file.
    ///   - output: Path for the output `.apks` archive.
    ///   - keystorePath: Keystore for signing the APKs (optional if the bundle is already signed).
    ///   - keystorePassword: Keystore password.
    ///   - keyAlias: Key alias in the keystore.
    ///   - keyPassword: Key password.
    ///   - connectedDevice: Generate APKs optimized for the currently connected device.
    public func buildApks(
        bundle: String,
        output: String,
        keystorePath: String? = nil,
        keystorePassword: String? = nil,
        keyAlias: String? = nil,
        keyPassword: String? = nil,
        connectedDevice: Bool = false
    ) -> Self {
        var args = [
            "build-apks",
            "--bundle=\(bundle)",
            "--output=\(output)",
        ]
        if let ks = keystorePath { args.append("--ks=\(ks)") }
        if let ksPw = keystorePassword { args.append("--ks-pass=pass:\(ksPw)") }
        if let alias = keyAlias { args.append("--ks-key-alias=\(alias)") }
        if let keyPw = keyPassword { args.append("--key-pass=pass:\(keyPw)") }
        if connectedDevice { args.append("--connected-device") }
        return copy(arguments: args)
    }

    /// `bundletool install-apks` — Install APK set on connected device.
    public func installApks(apks: String) -> Self {
        copy(arguments: ["install-apks", "--apks=\(apks)"])
    }

    /// `bundletool validate --bundle=<path>` — Validate an AAB file.
    public func validate(bundle: String) -> Self {
        copy(arguments: ["validate", "--bundle=\(bundle)"])
    }

    /// `bundletool get-device-spec --output=<path>` — Write the connected device spec to a JSON file.
    public func getDeviceSpec(output: String) -> Self {
        copy(arguments: ["get-device-spec", "--output=\(output)"])
    }

    /// `bundletool get-size total --apks=<path>` — Estimate download size for an APK set.
    public func getSize(apks: String) -> Self {
        copy(arguments: ["get-size", "total", "--apks=\(apks)"])
    }

    // MARK: - Private

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        arguments: [String],
        jarPath: String?? = .none
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            arguments: arguments,
            jarPath: jarPath != .none ? jarPath! : self.jarPath
        )
    }
}
