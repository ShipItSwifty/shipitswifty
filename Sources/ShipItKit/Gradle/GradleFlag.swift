import Foundation
import SwiftyShell

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

    // MARK: - Parallelism

    /// `--parallel` — Build projects in parallel.
    public static let parallel = GradleFlag(arguments: ["--parallel"])

    // MARK: - Offline

    /// `--offline` — Run in offline mode using only cached dependencies.
    public static let offline = GradleFlag(arguments: ["--offline"])

    // MARK: - Output / Diagnostics

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

    /// Arbitrary flag(s), e.g. `GradleFlag.custom("--rerun-tasks")`.
    public static func custom(_ flag: String) -> GradleFlag {
        GradleFlag(arguments: [flag])
    }

    // MARK: - Init

    /// Creates a `GradleFlag` with explicit arguments.
    public init(arguments: [String]) {
        self.arguments = arguments
    }
}
