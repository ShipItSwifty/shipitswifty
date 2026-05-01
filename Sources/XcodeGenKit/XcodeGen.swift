import Foundation
import SwiftyShell

/// A fluent wrapper for the `xcodegen` command.
///
/// XcodeGen generates Xcode project files from a YAML or JSON project spec.
/// This wrapper provides a typed, fluent API on top of the CLI.
///
/// ## Usage
/// ```swift
/// // Generate a project from the default project.yml
/// let output = try await XcodeGen(context: shell)
///     .generate()
///     .run()
///
/// // Generate from a custom spec with a specific project path
/// let output = try await XcodeGen(context: shell)
///     .generate()
///     .spec("custom-project.yml")
///     .projectDirectory("./MyApp")
///     .run()
///
/// // Dump the resolved spec (useful for debugging)
/// let output = try await XcodeGen(context: shell)
///     .dump()
///     .spec("project.yml")
///     .run()
/// ```
public struct XcodeGen: RunnableCommandFamily {

    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration

    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination

    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination

    /// The subcommand to run (e.g. `generate`, `dump`, `cache`).
    public let subcommand: String?

    /// Typed options for the xcodegen invocation.
    public let options: [XcodeGenOption]

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    // MARK: - Init

    /// Creates an `XcodeGen` command family bound to a shell context.
    public init(context: ShellContext = .init()) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.subcommand = nil
        self.options = []
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        subcommand: String?,
        options: [XcodeGenOption]
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.subcommand = subcommand
        self.options = options
    }

    // MARK: - RunnableCommandFamily

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(
        _ update: (ToolConfiguration) -> ToolConfiguration
    ) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for the built `xcodegen` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `xcodegen` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    // MARK: - Subcommands

    /// `xcodegen generate` — Generate an Xcode project from a spec file.
    public func generate() -> Self {
        copy(subcommand: "generate")
    }

    /// `xcodegen dump` — Dump the resolved project spec to stdout.
    public func dump() -> Self {
        copy(subcommand: "dump")
    }

    /// `xcodegen cache` — Write or check the cache.
    public func cache() -> Self {
        copy(subcommand: "cache")
    }

    // MARK: - Options

    /// Appends a typed `xcodegen` option.
    public func option(_ option: XcodeGenOption) -> Self {
        copy(options: options + [option])
    }

    /// Sets the project spec file path (`--spec <path>`).
    public func spec(_ path: String) -> Self {
        option(.spec(path))
    }

    /// Sets the project directory for the generated `.xcodeproj` (`--project <path>`).
    public func projectDirectory(_ path: String) -> Self {
        option(.project(path))
    }

    /// Disables the project generation cache (`--no-cache`).
    public func noCache() -> Self {
        option(.noCache)
    }

    /// Enables quiet mode — suppress non-error output (`--quiet`).
    public func quiet() -> Self {
        option(.quiet)
    }

    // MARK: - Command Builder

    /// Builds the raw `xcodegen` command.
    public func command() -> Command {
        var args: [String] = []

        if let subcommand {
            args.append(subcommand)
        }

        args += options.flatMap(\.arguments)

        let base = Command("xcodegen")
            .args(args)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)

        return config.apply(to: base)
    }

    // MARK: - Private

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        subcommand: String?? = .none,
        options: [XcodeGenOption]? = nil
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            subcommand: subcommand != .none ? subcommand! : self.subcommand,
            options: options ?? self.options
        )
    }
}
