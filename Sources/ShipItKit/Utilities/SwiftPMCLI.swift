import Foundation
import SwiftyShell

/// Typed `swift` commands used by package test lanes.
///
/// ## Usage
/// ```swift
/// try await SwiftPMCLI(context: shell).test(package: ".", events: "events.jsonl").run()
/// ```
public struct SwiftPMCLI: RunnableCommandFamily {
    public let config: ToolConfiguration
    public let arguments: [String]
    public let stdoutDestination: OutputDestination
    public let stderrDestination: OutputDestination
    public var context: ShellContext { config.context }
    public init(context: ShellContext = .init()) {
        config = ToolConfiguration(context: context)
        arguments = []
        stdoutDestination = .capture
        stderrDestination = .capture
    }
    private init(config: ToolConfiguration, arguments: [String], stdout: OutputDestination, stderr: OutputDestination) {
        self.config = config
        self.arguments = arguments
        stdoutDestination = stdout
        stderrDestination = stderr
    }
    public func updatingConfiguration(_ update: (ToolConfiguration) -> ToolConfiguration) -> Self { copy(config: update(config)) }
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self { copy(stdout: destination) }
    public func settingStderrDestination(_ destination: OutputDestination) -> Self { copy(stderr: destination) }
    /// `swift test --event-stream-output-path …` — **Mutating**: build and run package tests.
    public func test(
        package: String, scratch: String? = nil, events: String, attachments: String? = nil,
        coverage: Bool = false, skipBuild: Bool = false, filter: String? = nil, skip: String? = nil, junit: String? = nil
    ) -> Self {
        var args = ["test", "--package-path", package, "--parallel", "--event-stream-output-path", events]
        if let junit { args += ["--xunit-output", junit] }
        if let scratch { args += ["--scratch-path", scratch] }
        if let attachments { args += ["--attachments-path", attachments] }
        if coverage { args.append("--enable-code-coverage") }
        if skipBuild { args.append("--skip-build") }
        if let filter { args += ["--filter", filter] }
        if let skip { args += ["--skip", skip] }
        return copy(arguments: args)
    }
    /// `swift test --show-codecov-path` — locate generated coverage without running tests.
    public func coveragePath(package: String, scratch: String? = nil) -> Self {
        var args = ["test", "--package-path", package, "--show-codecov-path"]
        if let scratch { args += ["--scratch-path", scratch] }
        return copy(arguments: args)
    }
    /// `swift format lint --recursive --strict …` — checks formatting without modifying sources.
    public func formatLint(paths: [String], configuration: String? = nil) -> Self {
        var args = ["format", "lint", "--recursive", "--strict"]
        if let configuration { args += ["--configuration", configuration] }
        return copy(arguments: args + paths)
    }
    public func command() -> Command {
        config.apply(to: Command("swift").args(arguments).stdout(stdoutDestination).stderr(stderrDestination))
    }
    private func copy(
        config: ToolConfiguration? = nil, arguments: [String]? = nil, stdout: OutputDestination? = nil, stderr: OutputDestination? = nil
    ) -> Self {
        .init(
            config: config ?? self.config, arguments: arguments ?? self.arguments, stdout: stdout ?? stdoutDestination,
            stderr: stderr ?? stderrDestination)
    }
}
