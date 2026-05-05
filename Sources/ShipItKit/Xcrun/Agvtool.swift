#if os(macOS)
import Foundation
import SwiftyShell

/// A typed wrapper for `xcrun agvtool` commands.
public struct Agvtool: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination
    /// Typed `agvtool` arguments for the selected operation.
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates an `agvtool` command family bound to a shell context.
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
    public func updatingConfiguration(_ update: (ToolConfiguration) -> ToolConfiguration) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for the built `xcrun agvtool` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `xcrun agvtool` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Uses `agvtool what-marketing-version -terse`.
    public func whatMarketingVersionTerse() -> Self {
        copy(arguments: ["what-marketing-version", "-terse"])
    }

    /// Uses `agvtool what-version -terse`.
    public func whatVersionTerse() -> Self {
        copy(arguments: ["what-version", "-terse"])
    }

    /// Uses `agvtool new-marketing-version <version>`.
    public func newMarketingVersion(_ version: String) -> Self {
        copy(arguments: ["new-marketing-version", version])
    }

    /// Uses `agvtool new-version -all <build>`.
    public func newVersionAll(_ build: String) -> Self {
        copy(arguments: ["new-version", "-all", build])
    }

    /// Builds the raw `xcrun agvtool` command.
    public func command() -> Command {
        Xcrun(context: context)
            .tool("agvtool")
            .trailingArguments(arguments)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)
            .updatingConfiguration { config in
                var updated = config
                if let executableOverride = self.config.executableOverride {
                    updated = updated.executable(executableOverride)
                }
                if !self.config.environmentOverrides.isEmpty {
                    updated = updated.env(self.config.environmentOverrides)
                }
                if let workingDirectory = self.config.workingDirectoryOverride {
                    updated = updated.workingDirectory(workingDirectory)
                }
                if let timeout = self.config.timeoutOverride {
                    updated = updated.timeout(timeout)
                }
                if let outputLimit = self.config.outputLimitOverride {
                    updated = updated.outputLimit(outputLimit)
                }
                return updated
            }
            .command()
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
