import ArgumentParser
import Foundation
import ShipItKit

/// What `shipit ci report` found, for the job that called it.
struct CIReportResult: Codable, Sendable {
    let passed: Int
    let failed: Int
    let flaky: Int
    let errored: Int
    let skipped: Int
    let consistentFailureCount: Int
    let hasConsistentFailures: Bool
    let runErrors: Int
    /// Whether the run passes ShipIt's policy (see `--fail-on-flaky`).
    let policyPassed: Bool
    let reports: [String]
    let consistentFailures: [DigestedTest]
    let flakyTests: [DigestedTest]
}

/// Turn test reports into a job summary, pull-request annotations, and a pass/fail verdict.
///
/// ## Usage
/// ```
/// shipit ci report --report build/report.json --summary-path "$GITHUB_STEP_SUMMARY" --annotations
/// shipit ci report --report shard-1/report.json --report shard-2/report.json --fail-on-flaky
/// ```
struct CIReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Summarize test reports for CI: job summary, annotations, and a pass/fail verdict"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .customLong("report"), help: "TestRunReport JSON from `shipit test --report-path` (repeatable; shards are merged)")
    var reports: [String] = []
    @Option(name: .long, help: "Append a Markdown summary to this file (GitHub: $GITHUB_STEP_SUMMARY)")
    var summaryPath: String?
    @Flag(name: .long, help: "Print GitHub workflow-command annotations for failing and flaky tests")
    var annotations: Bool = false
    @Option(name: .long, help: "Checkout root, to turn absolute failure paths into repo-relative ones (default: $GITHUB_WORKSPACE)")
    var workspace: String?
    @Option(name: .long, help: "Link to the run's uploaded evidence, shown in the summary")
    var artifactUrl: String?
    @Option(name: .long, help: "Write the machine-readable result JSON to this file")
    var resultPath: String?
    @Flag(name: .long, help: "Treat a flaky test (one that passed only on a retry) as a failure")
    var failOnFlaky: Bool = false

    func run() async throws {
        do {
            let digest = try TestRunDigest.load(reportPaths: reports)
            if let summaryPath {
                try Self.append(GitHubSummary.markdown(digest, artifactURL: artifactUrl), to: summaryPath)
            }
            if annotations {
                let root = workspace ?? ProcessInfo.processInfo.environment["GITHUB_WORKSPACE"]
                let lines = GitHubAnnotations.commands(for: digest, workspace: root)
                // stdout carries the JSON envelope under --output json, so annotations go to stderr there.
                let handle = global.output == .json ? FileHandle.standardError : FileHandle.standardOutput
                for line in lines { handle.write(Data((line + "\n").utf8)) }
            }
            let passes = digest.passes(failOnFlaky: failOnFlaky)
            let result = CIReportResult(
                passed: digest.passed, failed: digest.failed, flaky: digest.flaky, errored: digest.errored, skipped: digest.skipped,
                consistentFailureCount: digest.consistentFailures.count, hasConsistentFailures: digest.hasConsistentFailures,
                runErrors: digest.runErrors, policyPassed: passes, reports: reports, consistentFailures: digest.consistentFailures,
                flakyTests: digest.flakyTests)
            if let resultPath {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: resultPath).deletingLastPathComponent(), withIntermediateDirectories: true)
                try encoder.encode(result).write(to: URL(fileURLWithPath: resultPath), options: .atomic)
            }
            outputResult(action: "ci-report", result: result, format: global.output, colorMode: global.effectiveColorMode)
            if !passes {
                throw ShipItError.testFailed(
                    exitCode: 1, failureCount: digest.consistentFailures.count + digest.runErrors + (failOnFlaky ? digest.flaky : 0),
                    log:
                        "Test policy failed: \(digest.consistentFailures.count) failing, \(digest.flaky) flaky, \(digest.runErrors) run error(s)"
                )
            }
        } catch let error as ShipItError {
            outputError(action: "ci-report", error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }

    private static func append(_ text: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + text).utf8))
    }
}
