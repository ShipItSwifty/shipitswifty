import Foundation

/// A concise, human-readable summary parsed from an `xcodebuild` invocation's stdout.
///
/// Unlike Gradle, xcodebuild has no cache-effectiveness line, so this summary is intentionally
/// light: it surfaces the terminal `** … SUCCEEDED **` / `** … FAILED **` marker and the
/// compiler warning/error counts, so they are always visible in CI even without `--verbose`.
///
/// Parsing is best-effort and never fails: `resultLine` is `nil` when no marker is found.
public struct XcodeBuildSummary: Sendable, Equatable {
    /// The terminal xcodebuild marker line, e.g. `"** ARCHIVE SUCCEEDED **"` or
    /// `"** BUILD FAILED **"`. `nil` if no marker is present.
    public var resultLine: String?

    /// Number of lines that look like compiler/linker warnings (`: warning:`).
    public var warningCount: Int

    /// Number of lines that look like compiler/linker errors (`: error:`).
    public var errorCount: Int

    /// Creates a summary.
    public init(resultLine: String? = nil, warningCount: Int = 0, errorCount: Int = 0) {
        self.resultLine = resultLine
        self.warningCount = warningCount
        self.errorCount = errorCount
    }

    /// `true` when no marker was found and there were no warnings or errors.
    public var isEmpty: Bool {
        resultLine == nil && warningCount == 0 && errorCount == 0
    }

    /// Parses a build summary from xcodebuild's stdout.
    ///
    /// Best-effort and order-independent; never throws — summary parsing must never fail a build.
    ///
    /// - Parameter stdout: The captured stdout from an `xcodebuild` invocation.
    /// - Returns: An `XcodeBuildSummary` with whatever was found.
    public static func parse(_ stdout: String) -> XcodeBuildSummary {
        var summary = XcodeBuildSummary()

        for rawLine in stdout.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Terminal markers: "** ARCHIVE SUCCEEDED **", "** BUILD FAILED **", etc.
            if summary.resultLine == nil, line.hasPrefix("**"), line.hasSuffix("**"),
                line.contains("SUCCEEDED") || line.contains("FAILED")
            {
                summary.resultLine = line
            }

            // Compiler/linker diagnostics follow the clang/swift format:
            //   /path/File.swift:12:34: warning: message
            if line.contains(": warning:") {
                summary.warningCount += 1
            }
            if line.contains(": error:") {
                summary.errorCount += 1
            }
        }

        return summary
    }
}
