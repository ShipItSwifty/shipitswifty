import Foundation
import SwiftyShell

/// A typed wrapper for the `frameit` command.
public struct Frameit: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination
    /// Typed `frameit` arguments for the selected operation.
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates a `frameit` command family bound to a shell context.
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

    /// Redirects stdout for the built `frameit` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `frameit` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Uses `frameit --path <screenshotsDirectory> --output <outputDirectory>`.
    public func render(screenshotsDirectory: String, outputDirectory: String) -> Self {
        copy(arguments: ["--path", screenshotsDirectory, "--output", outputDirectory])
    }

    /// Builds the raw `frameit` command.
    public func command() -> Command {
        let base = Command("frameit")
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
