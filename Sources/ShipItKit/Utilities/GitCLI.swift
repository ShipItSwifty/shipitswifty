import Foundation
import SwiftyShell

/// A typed wrapper for ad hoc `git` CLI commands used by ShipItKit.
///
/// Use this command family for git invocations that are not covered by the
/// higher-level SwiftyShell `Git` workflows.
public struct GitCLI: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination
    /// Global `git` arguments that must appear before the subcommand.
    public let globalArguments: [String]
    /// Arguments for the selected git subcommand.
    public let arguments: [String]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates a `git` command family bound to a shell context.
    public init(context: ShellContext = .init()) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.globalArguments = []
        self.arguments = []
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        globalArguments: [String],
        arguments: [String]
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.globalArguments = globalArguments
        self.arguments = arguments
    }

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(
        _ update: (ToolConfiguration) -> ToolConfiguration
    ) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for the built `git` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `git` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Adds `-C <path>` before the git subcommand.
    public func repository(at path: String) -> Self {
        copy(globalArguments: globalArguments + ["-C", path])
    }

    /// Uses the `git --version` command.
    public func version() -> Self {
        copy(arguments: ["--version"])
    }

    /// Uses the `git status --porcelain` command.
    public func statusPorcelain() -> Self {
        copy(arguments: ["status", "--porcelain"])
    }

    /// Uses the `git tag -a <name> -m <message>` command.
    public func annotatedTag(name: String, message: String) -> Self {
        copy(arguments: ["tag", "-a", name, "-m", message])
    }

    /// Uses the `git add -A` command.
    public func addAll() -> Self {
        copy(arguments: ["add", "-A"])
    }

    /// Uses the `git commit -m <message>` command.
    public func commit(message: String) -> Self {
        copy(arguments: ["commit", "-m", message])
    }

    /// Uses the `git push <remote>` command.
    public func push(remote: String) -> Self {
        copy(arguments: ["push", remote])
    }

    /// Uses the `git push <remote> --tags` command.
    public func pushTags(remote: String) -> Self {
        copy(arguments: ["push", remote, "--tags"])
    }

    /// Uses the `git push -u <remote> <branch>` command.
    public func pushSetUpstream(remote: String, branch: String) -> Self {
        copy(arguments: ["push", "-u", remote, branch])
    }

    /// Uses the `git log --oneline -<limit>` command.
    public func logOneline(limit: Int) -> Self {
        copy(arguments: ["log", "--oneline", "-\(limit)"])
    }

    /// Uses the `git rev-parse HEAD` command.
    public func currentHEAD() -> Self {
        copy(arguments: ["rev-parse", "HEAD"])
    }

    /// Uses the `git rev-list --count <revision>` command.
    public func revisionCount(_ revision: String = "HEAD") -> Self {
        copy(arguments: ["rev-list", "--count", revision])
    }

    /// Uses the `git clone` command.
    public func clone(url: String, into path: String, depth: Int? = nil) -> Self {
        var values = ["clone"]
        if let depth {
            values.append(contentsOf: ["--depth", String(depth)])
        }
        values.append(contentsOf: [url, path])
        return copy(arguments: values)
    }

    /// Uses the `git init <path>` command.
    public func initializeRepository(at path: String) -> Self {
        copy(arguments: ["init", path])
    }

    /// Builds the raw `git` command.
    public func command() -> Command {
        let base = Command("git")
            .args(globalArguments)
            .args(arguments)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)

        return config.apply(to: base)
    }

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        globalArguments: [String]? = nil,
        arguments: [String]? = nil
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            globalArguments: globalArguments ?? self.globalArguments,
            arguments: arguments ?? self.arguments
        )
    }
}
