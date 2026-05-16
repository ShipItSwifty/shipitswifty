import Foundation
import SwiftyShell

/// A typed wrapper for `flutter` CLI commands used by ShipItKit.
///
/// `FlutterCLI` follows the same `RunnableCommandFamily` pattern used by `GitCLI`,
/// `XcodeBuildKit`, and `GradleKit`. Every method returns a new value — the family
/// is immutable and value-typed.
///
/// ## Usage
/// ```swift
/// let output = try await FlutterCLI(context: context.shell)
///     .buildIPA(flavor: nil)
///     .run()
/// ```
public struct FlutterCLI: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination
    /// Arguments for the selected flutter subcommand.
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates a `FlutterCLI` bound to a shell context.
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

    public func updatingConfiguration(
        _ update: (ToolConfiguration) -> ToolConfiguration
    ) -> Self {
        copy(config: update(config))
    }

    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    // MARK: - Build commands

    /// `flutter build ipa` — produces `build/ios/ipa/*.ipa` directly.
    ///
    /// Flutter's IPA build does not require a separate export step; the IPA is ready for
    /// upload after this command. Pass `flavor` for multi-flavor projects.
    ///
    /// - Parameters:
    ///   - flavor: Optional product flavor (e.g. `"free"`, `"paid"`).
    ///   - dartDefines: Optional `--dart-define=KEY=VALUE` arguments.
    ///   - target: Optional Dart entry point (e.g. `"lib/main_prod.dart"`).
    public func buildIPA(
        flavor: String? = nil,
        dartDefines: [String: String] = [:],
        target: String? = nil
    ) -> Self {
        var args = ["build", "ipa", "--release"]
        if let flavor { args.append(contentsOf: ["--flavor", flavor]) }
        for (key, value) in dartDefines { args.append("--dart-define=\(key)=\(value)") }
        if let target { args.append(contentsOf: ["--target", target]) }
        return copy(arguments: args)
    }

    /// `flutter build appbundle` — produces `build/app/outputs/bundle/release/app-release.aab`.
    ///
    /// - Parameters:
    ///   - flavor: Optional product flavor.
    ///   - dartDefines: Optional `--dart-define=KEY=VALUE` arguments.
    ///   - target: Optional Dart entry point.
    public func buildAppBundle(
        flavor: String? = nil,
        dartDefines: [String: String] = [:],
        target: String? = nil
    ) -> Self {
        var args = ["build", "appbundle", "--release"]
        if let flavor { args.append(contentsOf: ["--flavor", flavor]) }
        for (key, value) in dartDefines { args.append("--dart-define=\(key)=\(value)") }
        if let target { args.append(contentsOf: ["--target", target]) }
        return copy(arguments: args)
    }

    /// `flutter build apk` — produces `build/app/outputs/flutter-apk/app-release.apk`.
    ///
    /// - Parameters:
    ///   - flavor: Optional product flavor.
    ///   - dartDefines: Optional `--dart-define=KEY=VALUE` arguments.
    ///   - target: Optional Dart entry point.
    public func buildAPK(
        flavor: String? = nil,
        dartDefines: [String: String] = [:],
        target: String? = nil
    ) -> Self {
        var args = ["build", "apk", "--release"]
        if let flavor { args.append(contentsOf: ["--flavor", flavor]) }
        for (key, value) in dartDefines { args.append("--dart-define=\(key)=\(value)") }
        if let target { args.append(contentsOf: ["--target", target]) }
        return copy(arguments: args)
    }

    // MARK: - Test / Analyze commands

    /// `flutter test` — runs Dart unit tests.
    ///
    /// - Parameter coverage: When `true`, appends `--coverage`.
    public func test(coverage: Bool = false) -> Self {
        var args = ["test"]
        if coverage { args.append("--coverage") }
        return copy(arguments: args)
    }

    /// `flutter analyze` — runs the Dart analyzer (static analysis).
    public func analyze() -> Self {
        copy(arguments: ["analyze"])
    }

    // MARK: - Other

    /// `flutter --version` — prints Flutter SDK version.
    public func version() -> Self {
        copy(arguments: ["--version"])
    }

    // MARK: - RunnableCommandFamily

    /// Builds the raw `flutter` command.
    public func command() -> Command {
        let base = Command("flutter")
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
