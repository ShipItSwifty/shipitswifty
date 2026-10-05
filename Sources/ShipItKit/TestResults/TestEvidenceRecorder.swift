import Foundation
import Logging
import SwiftyShell

/// Serializes attempt allocation and evidence writes; process execution remains structured.
///
/// The recorder writes one directory per attempt plus `attempts.json`. It deliberately does **not** write
/// `report.json` per attempt: an attempt only knows its own tests, so after a selective rerun it would
/// describe the rerun subset as the whole run. The action writes the final, reconciled report; if the
/// action never gets that far (cancellation, a crash, an I/O error), ``writeProvisionalReport(executionError:)``
/// writes the best report the recorded attempts support.
public actor TestEvidenceRecorder {
    public nonisolated let root: URL
    private var number = 0
    private var attempts: [TestAttempt] = []
    private var initial: ParsedTestRun?
    private var remaining: [ParsedTestCase] = []
    private var flaky: [ParsedTestCase] = []
    private var unparsedAttempts = 0
    public init(root: URL) { self.root = root }
    func latestDirectory() -> URL { root.appendingPathComponent("attempt-\(number)") }
    func allocate() throws -> (Int, URL) {
        number += 1
        let directory = root.appendingPathComponent("attempt-\(number)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (number, directory)
    }
    func record(
        _ run: ParsedTestRun?, index: Int, directory: URL, output: ShellOutput, arguments: [String], reason: String,
        parseFailure: String? = nil
    ) throws {
        try output.stdout.write(to: directory.appendingPathComponent("stdout.log"), atomically: true, encoding: .utf8)
        try output.stderr.write(to: directory.appendingPathComponent("stderr.log"), atomically: true, encoding: .utf8)
        try writeJSON(
            ["arguments": arguments, "exit_code": [String(output.exitCode)]], to: directory.appendingPathComponent("command.json"))
        // Missing structured results are an error even when the process exited 0: an unreadable result must
        // never be recorded as a clean zero-test run.
        let effectiveRun =
            run
            ?? ParsedTestRun(
                runner: .unknown, source: directory.path,
                summary: .init(errored: parseFailure != nil || output.exitCode != 0 ? 1 : 0),
                diagnostics: [
                    .init(
                        severity: parseFailure != nil ? .error : .warning,
                        message: parseFailure.map { "Structured result unavailable: \($0). See captured logs." }
                            ?? "Structured result unavailable; see captured logs")
                ])
        if effectiveRun.runner == .flutterTest {
            try output.stdout.write(to: directory.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        }
        try writeJSON(effectiveRun, to: directory.appendingPathComponent("results.json"))
        attempts.append(
            .init(
                attemptNumber: index, reason: reason == "initial" && index > 1 ? "infrastructure" : reason,
                metadata: ["exit_code": String(output.exitCode)], summary: effectiveRun.summary,
                failedTests: run?.testCases.filter { $0.status == .failed || $0.status == .errored } ?? [], source: directory.path))
        reconcile(run, reason: reason)
        try writeJSON(attempts, to: root.appendingPathComponent("attempts.json"))
    }

    /// Same reconciliation the actions apply: a full run replaces what came before, and a selective rerun
    /// resolves only the failures whose tests it saw pass.
    private func reconcile(_ run: ParsedTestRun?, reason: String) {
        guard let run else {
            unparsedAttempts += 1
            return
        }
        let failures = run.testCases.filter { $0.status == .failed || $0.status == .errored }
        if reason == "failed_tests", initial != nil {
            let passed = Set(run.testCases.filter { $0.status == .passed }.map(\.stableID))
            flaky += remaining.filter { passed.contains($0.stableID) }
            remaining = remaining.filter { !passed.contains($0.stableID) }
            for failure in failures where !remaining.contains(where: { $0.stableID == failure.stableID }) { remaining.append(failure) }
        } else {
            initial = run
            remaining = failures
            flaky = []
            unparsedAttempts = 0
        }
    }

    /// Writes `report.json` from the recorded attempts unless the action already wrote the final one.
    ///
    /// - Parameter executionError: `true` when the run stopped for a reason other than test failures
    ///   (cancellation, I/O, configuration), so the report can never read as a clean pass.
    func writeProvisionalReport(executionError: Bool) throws {
        let url = root.appendingPathComponent("report.json")
        guard FileManager.default.fileExists(atPath: root.path), !FileManager.default.fileExists(atPath: url.path) else { return }
        let incomplete = executionError || unparsedAttempts > 0 || initial == nil
        let report: TestRunReport
        if let initial {
            report = TestRunReport(
                runner: initial.runner, buildSystem: initial.buildSystem, source: root.path, destinations: initial.destinations,
                attempts: attempts,
                initialFailedTests: initial.testCases.filter { $0.status == .failed || $0.status == .errored },
                flakyTests: flaky, persistentFailedTests: remaining,
                summary: .init(
                    passed: initial.summary.passed + flaky.count, failed: remaining.filter { $0.status == .failed }.count,
                    skipped: initial.summary.skipped, flaky: flaky.count,
                    errored: remaining.filter { $0.status == .errored }.count + (incomplete ? 1 : 0)),
                testCases: finalTestCases(initial.testCases, remaining: remaining, flaky: flaky))
        } else {
            report = TestRunReport(
                runner: .unknown, source: root.path, attempts: attempts, summary: .init(errored: 1))
        }
        try writeJSON(report, to: url)
    }
}

/// Evidence is secondary to the test outcome: failing to save it is logged and never replaces or hides the
/// result of the run it describes.
func saveEvidence(_ what: String, logger: Logger, _ body: () throws -> Void) {
    do { try body() } catch { logger.warning("Could not save \(what): \(error)") }
}

/// Saves stdout/stderr and native reports before a later attempt can overwrite them.
///
/// - Parameter staleResults: Result locations from earlier runs. They are removed before the command
///   starts so a run that fails before executing any test (for example a compile error) can never be
///   mistaken for the previous run's results.
func executeRecordedTest<C: RunnableCommandFamily>(
    _ command: C, context: ActionContext,
    reason: String = "initial", parse: (@Sendable (ShellOutput) async throws -> ParsedTestRun?)? = nil,
    sources: @Sendable () -> [URL] = { [] },
    staleResults: @Sendable () -> [URL] = { [] }
) async throws -> ShellOutput {
    try removeStaleResults(staleResults())
    guard let recorder = context.testEvidence else { return try await command.run() }
    let index: Int
    let directory: URL
    do { (index, directory) = try await recorder.allocate() } catch {
        // Not being able to record must never stop the tests themselves.
        if error is CancellationError { throw error }
        context.logger.warning("Test evidence unavailable, running without recording: \(error)")
        return try await command.run()
    }
    let output: ShellOutput
    do { output = try await command.run() } catch let ShellError.exitFailure(_, captured) { output = captured } catch {
        try? saveInterruptedTestOutput(error, directory: directory)
        throw error
    }
    var run: ParsedTestRun?
    var parseFailure: String?
    if let parse {
        do { run = try await parse(output) } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            parseFailure = String(describing: error)
        }
        if run == nil && parseFailure == nil { parseFailure = "no structured results were produced" }
    }
    do {
        try await recorder.record(
            run, index: index, directory: directory, output: output, arguments: command.command().arguments, reason: reason,
            parseFailure: parseFailure)
    } catch {
        if error is CancellationError { throw error }
        context.logger.warning("Could not save test evidence for attempt \(index): \(error)")
    }
    // Each attempt keeps a snapshot of native report directories, including partial failures.
    for (sourceIndex, source) in sources().enumerated() where FileManager.default.fileExists(atPath: source.path) {
        saveEvidence("native results snapshot", logger: context.logger) {
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("native-\(sourceIndex + 1)"))
        }
    }
    return output
}

private func removeStaleResults(_ urls: [URL]) throws {
    for url in urls where FileManager.default.fileExists(atPath: url.path) {
        do { try FileManager.default.removeItem(at: url) } catch {
            throw ShipItError.invalidConfiguration(reason: "Cannot clear previous test results at \(url.path): \(error)")
        }
    }
}

/// Gradle's result directories for one task.
///
/// A module-qualified task (`:app:testDebugUnitTest`) reads exactly that module. An unqualified task checks
/// every module's `build` directory, without descending into build outputs or dependency trees.
func junitReportDirectories(projectDir: String, task: String) -> [URL] {
    let parts = task.split(separator: ":").map(String.init)
    guard let taskName = parts.last else { return [] }
    let root = URL(fileURLWithPath: projectDir).standardizedFileURL
    let connected = taskName.hasPrefix("connected")
    func results(inBuild build: URL) -> URL? {
        let url =
            connected
            ? build.appendingPathComponent("outputs/androidTest-results/connected", isDirectory: true)
            : build.appendingPathComponent("test-results/\(taskName)", isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : nil
    }
    if parts.count > 1 {
        let module = root.appendingPathComponent(parts.dropLast().joined(separator: "/"), isDirectory: true)
        return results(inBuild: module.appendingPathComponent("build", isDirectory: true)).map { [$0] } ?? []
    }
    var found: [URL] = []
    let dependencyDirectories: Set<String> = ["node_modules", "Pods", "DerivedData", "vendor"]
    guard
        let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else { return [] }
    while let url = walker.nextObject() as? URL {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        if url.lastPathComponent == "build" {
            if let match = results(inBuild: url) { found.append(match) }
            walker.skipDescendants()
        } else if dependencyDirectories.contains(url.lastPathComponent) {
            walker.skipDescendants()
        }
    }
    return found.sorted { $0.path < $1.path }
}

/// Preserve partial logs before propagating cancellation or timeout.
func saveInterruptedTestOutput(_ error: Error, directory: URL) throws {
    let output: ShellOutput
    switch error {
    case ShellError.canceled(_, let captured): output = captured
    case ShellError.timeout(_, _, let captured): output = captured
    default: return
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try output.stdout.write(to: directory.appendingPathComponent("stdout.log"), atomically: true, encoding: .utf8)
    try output.stderr.write(to: directory.appendingPathComponent("stderr.log"), atomically: true, encoding: .utf8)
    try writeJSON(["error": String(describing: error)], to: directory.appendingPathComponent("interruption.json"))
}
