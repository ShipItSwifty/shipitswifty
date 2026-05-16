import Foundation
import SwiftyShell

/// A typed wrapper for `npx react-native` CLI commands used by ShipItKit.
///
/// React Native CLI commands are invoked via `npx react-native <subcommand>` to ensure
/// the project-local version of the CLI is always used, regardless of global installs.
///
/// ## Usage
/// ```swift
/// let output = try await ReactNativeCLI(context: context.shell)
///     .buildAndroid(mode: "release")
///     .run()
/// ```
public struct ReactNativeCLI: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination
    /// Arguments for the selected `npx react-native` subcommand.
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates a `ReactNativeCLI` bound to a shell context.
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

    /// `npx react-native build-ios --mode Release` — compiles and validates the iOS bundle.
    ///
    /// The RN CLI iOS build is suitable for local validation and CI compile checks.
    /// For App Store-grade archives, ``ArchiveAction`` additionally runs `xcodebuild archive`
    /// on top of the RN-generated Xcode project.
    ///
    /// - Parameters:
    ///   - mode: Build configuration (`"Release"` or `"Debug"`). Default: `"Release"`.
    ///   - scheme: Optional Xcode scheme override.
    public func buildIOS(mode: String = "Release", scheme: String? = nil) -> Self {
        var args = ["react-native", "build-ios", "--mode", mode]
        if let scheme { args.append(contentsOf: ["--scheme", scheme]) }
        return copy(arguments: args)
    }

    /// `npx react-native build-android --mode=release` — wraps Gradle to build Android.
    ///
    /// The RN CLI Android build compiles the JS bundle and invokes Gradle, producing
    /// `android/app/build/outputs/bundle/release/app-release.aab`.
    ///
    /// - Parameters:
    ///   - mode: Build variant (`"release"` or `"debug"`). Default: `"release"`.
    ///   - task: Optional Gradle task to request (for example, `bundleRelease`).
    public func buildAndroid(mode: String = "release", task: String? = nil) -> Self {
        var args = ["react-native", "build-android", "--mode=\(mode)"]
        if let task { args.append(contentsOf: ["--tasks", task]) }
        return copy(arguments: args)
    }

    // MARK: - RunnableCommandFamily

    /// Builds the raw `npx` command with react-native subcommand arguments.
    public func command() -> Command {
        let base = Command("npx")
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
