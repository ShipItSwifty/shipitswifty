import Foundation

/// A typed flag for `gradlew` invocations.
///
/// Flags control Gradle daemon, caching, parallelism, and output verbosity.
///
/// ## Usage
/// ```swift
/// let output = try await Gradle(context: context.shell)
///     .task(.assembleRelease)
///     .flag(.noDaemon)
///     .flag(.buildCache)
///     .run()
/// ```
public struct GradleFlag: Sendable, Equatable, Hashable {

    /// The arguments emitted for this flag.
    public let arguments: [String]

    // MARK: - Daemon

    /// `--no-daemon` — Do not use the Gradle daemon. Recommended for CI environments.
    public static let noDaemon = GradleFlag(arguments: ["--no-daemon"])

    /// `--daemon` — Use the Gradle daemon (default for local development).
    public static let daemon = GradleFlag(arguments: ["--daemon"])

    // MARK: - Caching

    /// `--build-cache` — Enable the Gradle build cache to reuse task outputs.
    public static let buildCache = GradleFlag(arguments: ["--build-cache"])

    /// `--no-build-cache` — Disable the Gradle build cache.
    public static let noBuildCache = GradleFlag(arguments: ["--no-build-cache"])

    /// `--configuration-cache` — Enable the configuration cache (AGP 8+).
    public static let configurationCache = GradleFlag(arguments: ["--configuration-cache"])

    /// `--no-configuration-cache` — Disable the configuration cache for this invocation.
    public static let noConfigurationCache = GradleFlag(arguments: ["--no-configuration-cache"])

    /// `--rerun-tasks` — Ignore up-to-date checks and re-execute every task in the graph.
    public static let rerunTasks = GradleFlag(arguments: ["--rerun-tasks"])

    /// `--refresh-dependencies` — Ignore cached dependency resolution state.
    public static let refreshDependencies = GradleFlag(arguments: ["--refresh-dependencies"])

    // MARK: - Parallelism

    /// `--parallel` — Build projects in parallel.
    public static let parallel = GradleFlag(arguments: ["--parallel"])

    /// `--max-workers=<count>` — Cap the number of concurrent Gradle workers (useful on
    /// memory-constrained CI runners).
    public static func maxWorkers(_ count: Int) -> GradleFlag {
        GradleFlag(arguments: ["--max-workers=\(count)"])
    }

    // MARK: - Execution

    /// `--continue` — Keep executing independent tasks after a failure, so every module's
    /// test report is produced in one invocation.
    public static let continueAfterFailure = GradleFlag(arguments: ["--continue"])

    /// `-x <task>` — Exclude a task (and its exclusive dependencies) from execution.
    public static func excludeTask(_ task: GradleTask) -> GradleFlag {
        GradleFlag(arguments: ["-x", task.name])
    }

    // MARK: - Offline

    /// `--offline` — Run in offline mode using only cached dependencies.
    public static let offline = GradleFlag(arguments: ["--offline"])

    // MARK: - Output / Diagnostics

    /// `--quiet` — Log errors only.
    public static let quiet = GradleFlag(arguments: ["--quiet"])

    /// `--info` — Enable info-level Gradle logging.
    public static let info = GradleFlag(arguments: ["--info"])

    /// `--debug` — Enable debug-level Gradle logging.
    public static let debug = GradleFlag(arguments: ["--debug"])

    /// `--stacktrace` — Print full stacktraces on errors.
    public static let stacktrace = GradleFlag(arguments: ["--stacktrace"])

    /// `--scan` — Publish a build scan to scans.gradle.com.
    public static let scan = GradleFlag(arguments: ["--scan"])

    /// `--warning-mode all` — Show all deprecation warnings.
    public static let warningModeAll = GradleFlag(arguments: ["--warning-mode", "all"])

    // MARK: - Custom

    /// An arbitrary global flag, e.g. `GradleFlag.custom("--dry-run")`.
    ///
    /// Global flags are emitted *before* task names. For task-level options such as `--tests`,
    /// use ``GradleTask/filteringTests(_:)`` or ``GradleTask/appendingOptions(_:)`` instead.
    public static func custom(_ flag: String) -> GradleFlag {
        GradleFlag(arguments: [flag])
    }

    // MARK: - Init

    /// Creates a `GradleFlag` with explicit arguments.
    public init(arguments: [String]) {
        self.arguments = arguments
    }
}
