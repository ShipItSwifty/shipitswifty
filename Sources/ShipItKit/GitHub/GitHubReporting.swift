import Foundation

/// Markdown for a GitHub job summary (`$GITHUB_STEP_SUMMARY`).
public enum GitHubSummary {
    /// GitHub truncates a step summary at 1 MiB, so long lists are cut rather than the whole table lost.
    static let rowLimit = 100

    public static func markdown(_ digest: TestRunDigest, title: String = "ShipIt test results", artifactURL: String? = nil) -> String {
        var lines = ["## \(title)", ""]
        lines += ["| Passed | Failed | Flaky | Errored | Skipped |", "|---:|---:|---:|---:|---:|"]
        lines.append("| \(digest.passed) | \(digest.failed) | \(digest.flaky) | \(digest.errored) | \(digest.skipped) |")
        if digest.runErrors > 0 {
            lines += ["", "> **The run itself failed** (\(digest.runErrors) errored outcome(s) that are not a failing test, such as a build failure or a crashed runner)."]
        }
        if !digest.consistentFailures.isEmpty {
            lines += ["", "### Consistently failing", "", "| Test | Plan | Attempts | Location | Message |", "|---|---|---:|---|---|"]
            for test in digest.consistentFailures.prefix(rowLimit) {
                lines.append(
                    "| \(code(test.id)) | \(cell(test.plan)) | \(test.attempts) | \(location(test)) | \(cell(test.message)) |")
            }
            lines += more(digest.consistentFailures.count)
        }
        if !digest.flakyTests.isEmpty {
            lines += ["", "### Flaky (passed on retry)", "", "| Test | Plan | Attempts | First failure |", "|---|---|---:|---|"]
            for test in digest.flakyTests.prefix(rowLimit) {
                lines.append("| \(code(test.id)) | \(cell(test.plan)) | \(test.attempts) | \(cell(test.message)) |")
            }
            lines += more(digest.flakyTests.count)
        }
        if digest.attempts.count > 1 {
            lines += ["", "### Attempts", "", "| # | Reason | Passed | Failed | Errored | Seconds |", "|---:|---|---:|---:|---:|---:|"]
            for attempt in digest.attempts.prefix(rowLimit) {
                let seconds = attempt.durationSeconds.map { String(format: "%.1f", $0) } ?? "–"
                lines.append(
                    "| \(attempt.number) | \(cell(attempt.reason)) | \(attempt.passed) | \(attempt.failed) | \(attempt.errored) | \(seconds) |")
            }
        }
        if let artifactURL { lines += ["", "Evidence (logs, result bundles): [artifacts](\(artifactURL))"] }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func more(_ count: Int) -> [String] {
        count > rowLimit ? ["", "…and \(count - rowLimit) more."] : []
    }

    private static func location(_ test: DigestedTest) -> String {
        guard let file = test.file else { return "–" }
        return code(test.line.map { "\((file as NSString).lastPathComponent):\($0)" } ?? (file as NSString).lastPathComponent)
    }

    static func code(_ text: String) -> String { "`" + text.replacingOccurrences(of: "`", with: "'").replacingOccurrences(of: "|", with: "\\|") + "`" }

    static func cell(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "–" }
        return text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}

/// GitHub Actions workflow commands that annotate a pull request's files.
public enum GitHubAnnotations {
    /// GitHub shows at most 10 error and 10 warning annotations per step; the rest are summarized in one notice.
    public static let limit = 10

    /// - Parameter workspace: The checkout root. Annotations need repo-relative paths, so an absolute path outside it
    ///   is dropped and the annotation attaches to the run instead of a file.
    public static func commands(for digest: TestRunDigest, workspace: String?) -> [String] {
        var commands: [String] = []
        for test in digest.consistentFailures.prefix(limit) {
            commands.append(
                command(
                    "error", title: "Test failed after \(test.attempts) attempt(s): \(test.id)", message: test.message ?? "See the job summary.",
                    test: test, workspace: workspace))
        }
        if digest.consistentFailures.count > limit {
            commands.append(command("notice", title: "More failing tests", message: "\(digest.consistentFailures.count - limit) more failing test(s); see the job summary."))
        }
        for test in digest.flakyTests.prefix(limit) {
            commands.append(
                command(
                    "warning", title: "Flaky test (passed on retry): \(test.id)", message: test.message ?? "Passed after \(test.attempts) attempts.",
                    test: test, workspace: workspace))
        }
        if digest.flakyTests.count > limit {
            commands.append(command("notice", title: "More flaky tests", message: "\(digest.flakyTests.count - limit) more flaky test(s); see the job summary."))
        }
        if digest.runErrors > 0 {
            commands.append(command("error", title: "ShipIt test run failed", message: "The run errored without a failing test, such as a build failure or a crashed runner."))
        }
        return commands
    }

    static func command(_ kind: String, title: String, message: String, test: DigestedTest? = nil, workspace: String? = nil) -> String {
        var properties = ["title=\(escapeProperty(title))"]
        if let path = test?.file.flatMap({ relativePath($0, workspace: workspace) }) {
            properties.append("file=\(escapeProperty(path))")
            if let line = test?.line { properties.append("line=\(line)") }
        }
        return "::\(kind) \(properties.joined(separator: ","))::\(escapeData(message))"
    }

    static func relativePath(_ path: String, workspace: String?) -> String? {
        guard path.hasPrefix("/") else { return path }
        guard let workspace else { return nil }
        let root = workspace.hasSuffix("/") ? workspace : workspace + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : nil
    }

    static func escapeData(_ text: String) -> String {
        text.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "\r", with: "%0D").replacingOccurrences(of: "\n", with: "%0A")
    }

    static func escapeProperty(_ text: String) -> String {
        escapeData(text).replacingOccurrences(of: ":", with: "%3A").replacingOccurrences(of: ",", with: "%2C")
    }
}
