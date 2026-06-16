import Foundation

/// A concise, human-readable summary parsed from a Gradle build's stdout.
///
/// Used to surface the highest-signal lines of a long Android build — the success/time line,
/// the actionable-task cache-effectiveness line, and a build-scan URL when `--scan` is used —
/// so they are always visible in CI even without `--verbose`.
///
/// Parsing is best-effort and never fails: any field that cannot be located is left `nil`.
public struct GradleBuildSummary: Sendable, Equatable {
    /// The build result line, e.g. `"BUILD SUCCESSFUL in 2m 13s"`. `nil` if not present.
    public var buildResultLine: String?

    /// The actionable-tasks line, e.g.
    /// `"42 actionable tasks: 30 executed, 10 from cache, 2 up-to-date"`. `nil` if not present.
    ///
    /// This is the cache-effectiveness signal: the `from cache` / `up-to-date` counts reveal how
    /// much of the build was avoided.
    public var actionableTasksLine: String?

    /// The Gradle build-scan URL, e.g. `"https://gradle.com/s/abc123"`, when `--scan` was used.
    /// `nil` if no scan was published.
    public var buildScanURL: String?

    /// Creates a summary. All fields default to `nil`.
    public init(
        buildResultLine: String? = nil,
        actionableTasksLine: String? = nil,
        buildScanURL: String? = nil
    ) {
        self.buildResultLine = buildResultLine
        self.actionableTasksLine = actionableTasksLine
        self.buildScanURL = buildScanURL
    }

    /// `true` when no summary line could be parsed from the output.
    public var isEmpty: Bool {
        buildResultLine == nil && actionableTasksLine == nil && buildScanURL == nil
    }

    /// Parses a build summary from Gradle's stdout.
    ///
    /// Best-effort and order-independent: each field is located by scanning lines, and a missing
    /// field is left `nil`. This never throws — summary parsing must never fail a build.
    ///
    /// - Parameter stdout: The captured stdout from a Gradle invocation.
    /// - Returns: A `GradleBuildSummary` with whatever lines were found.
    public static func parse(_ stdout: String) -> GradleBuildSummary {
        var summary = GradleBuildSummary()

        for rawLine in stdout.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if summary.buildResultLine == nil, line.contains("BUILD SUCCESSFUL") {
                summary.buildResultLine = line
            }

            // Matches both "1 actionable task:" and "42 actionable tasks:".
            if summary.actionableTasksLine == nil, line.contains("actionable task") {
                summary.actionableTasksLine = line
            }

            if summary.buildScanURL == nil, let url = scanURL(in: line) {
                summary.buildScanURL = url
            }
        }

        return summary
    }

    /// Extracts a Gradle build-scan URL from a single line, if present.
    ///
    /// Recognizes lines that carry a `gradle.com/s/` (or `develocity.*`) scan link. The
    /// "Publishing build scan..." banner line itself carries no URL, so we key off the URL host.
    private static func scanURL(in line: String) -> String? {
        for token in line.components(separatedBy: .whitespaces) {
            guard token.hasPrefix("https://") || token.hasPrefix("http://") else { continue }
            if token.contains("gradle.com/s/") || token.contains("/s/") {
                return token
            }
        }
        return nil
    }
}
