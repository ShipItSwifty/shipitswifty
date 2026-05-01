import Foundation
import SwiftyShell

/// A fluent wrapper for `./gradlew` (Gradle Wrapper) invocations.
///
/// Follows the same `RunnableCommandFamily` pattern as `XcodeBuild` and `Xcrun`.
/// All shell execution goes through the injected `ShellContext`.
///
/// ## Resolution Order for the gradlew executable
/// 1. `gradlewPath` set explicitly via `settingGradlewPath(_:)`
/// 2. `./gradlew` relative to `projectDir` (or current directory)
/// 3. `gradle` on `PATH` as a fallback
///
/// ## Usage
/// ```swift
/// // Build a release AAB
/// let output = try await Gradle(context: context.shell)
///     .projectDir("./android")
///     .task(.bundleRelease)
///     .flag(.noDaemon)
///     .flag(.buildCache)
///     .run()
///
/// // Run unit tests
/// let result = try await Gradle(context: context.shell)
///     .task(.testDebugUnitTest)
///     .flag(.noDaemon)
///     .run()
/// ```
public struct Gradle: RunnableCommandFamily {

    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration

    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination

    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination

    /// Ordered list of Gradle tasks to execute.
    public let tasks: [GradleTask]

    /// `-P` properties passed to every invocation.
    public let properties: [GradleProperty]

    /// Flags (e.g. `--no-daemon`, `--build-cache`).
    public let flags: [GradleFlag]

    /// Explicit path to the `gradlew` script. Auto-detected when `nil`.
    public let gradlewPath: String?

    /// Project directory containing the root `build.gradle(.kts)`.
    public let projectDir: String?

    /// JVM arguments passed via `-Dorg.gradle.jvmargs`.
    public let jvmArgs: String?

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    // MARK: - Init

    /// Creates a `Gradle` command family bound to a shell context.
    public init(context: ShellContext = .init()) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.tasks = []
        self.properties = []
        self.flags = []
        self.gradlewPath = nil
        self.projectDir = nil
        self.jvmArgs = nil
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        tasks: [GradleTask],
        properties: [GradleProperty],
        flags: [GradleFlag],
        gradlewPath: String?,
        projectDir: String?,
        jvmArgs: String?
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.tasks = tasks
        self.properties = properties
        self.flags = flags
        self.gradlewPath = gradlewPath
        self.projectDir = projectDir
        self.jvmArgs = jvmArgs
    }

    // MARK: - Fluent API

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(
        _ update: (ToolConfiguration) -> ToolConfiguration
    ) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for the built `gradlew` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `gradlew` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Appends a Gradle task (e.g. `.assembleRelease`, `.bundleRelease`).
    public func task(_ task: GradleTask) -> Self {
        copy(tasks: tasks + [task])
    }

    /// Appends multiple Gradle tasks.
    public func tasks(_ values: [GradleTask]) -> Self {
        copy(tasks: tasks + values)
    }

    /// Appends a `-P` project property.
    public func property(_ property: GradleProperty) -> Self {
        copy(properties: properties + [property])
    }

    /// Appends multiple `-P` project properties.
    public func properties(_ values: [GradleProperty]) -> Self {
        copy(properties: properties + values)
    }

    /// Appends a Gradle flag (e.g. `.noDaemon`, `.buildCache`).
    public func flag(_ flag: GradleFlag) -> Self {
        copy(flags: flags + [flag])
    }

    /// Appends multiple Gradle flags.
    public func flags(_ values: [GradleFlag]) -> Self {
        copy(flags: flags + values)
    }

    /// Sets an explicit path to the `gradlew` script.
    /// When nil (default), the wrapper is auto-detected.
    public func settingGradlewPath(_ path: String?) -> Self {
        copy(gradlewPath: path)
    }

    /// Sets the Gradle project directory.
    /// Defaults to the current working directory when nil.
    public func projectDir(_ dir: String) -> Self {
        copy(projectDir: dir)
    }

    /// Sets JVM arguments via `-Dorg.gradle.jvmargs`.
    public func jvmArgs(_ args: String) -> Self {
        copy(jvmArgs: args)
    }

    // MARK: - RunnableCommandFamily

    /// Builds the raw `gradlew` (or `gradle`) command.
    public func command() -> Command {
        let executable = resolveGradlew()
        var args: [String] = []

        // Flags come first (e.g. --no-daemon)
        args += flags.flatMap(\.arguments)

        // JVM args as system property
        if let jvmArgs {
            args += ["-Dorg.gradle.jvmargs=\(jvmArgs)"]
        }

        // -P properties
        args += properties.map(\.argument)

        // Task names
        args += tasks.map(\.name)

        let base = Command(executable)
            .args(args)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)

        return config.apply(to: base)
    }

    // MARK: - Private

    private func resolveGradlew() -> String {
        // 1. Explicitly set path
        if let path = gradlewPath { return path }

        // 2. ./gradlew relative to projectDir or cwd
        let dir = projectDir ?? "."
        let candidate = "\(dir)/gradlew"
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        // 3. Fall back to `gradle` on PATH
        return "gradle"
    }

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        tasks: [GradleTask]? = nil,
        properties: [GradleProperty]? = nil,
        flags: [GradleFlag]? = nil,
        gradlewPath: String?? = .none,
        projectDir: String?? = .none,
        jvmArgs: String?? = .none
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            tasks: tasks ?? self.tasks,
            properties: properties ?? self.properties,
            flags: flags ?? self.flags,
            gradlewPath: gradlewPath != .none ? gradlewPath! : self.gradlewPath,
            projectDir: projectDir != .none ? projectDir! : self.projectDir,
            jvmArgs: jvmArgs != .none ? jvmArgs! : self.jvmArgs
        )
    }
}
