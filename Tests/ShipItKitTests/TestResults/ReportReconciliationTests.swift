import Foundation
import SwiftyShell
import Synchronization
import TestCommons
import Testing

@testable import ShipItKit

/// A report must tell the truth when a run does not finish cleanly, and saving evidence must never change or
/// hide the outcome of the tests it describes.
@Suite("Report reconciliation")
struct ReportReconciliationTests {
    private func run(_ cases: [ParsedTestCase]) -> ParsedTestRun {
        func count(_ status: TestCaseStatus) -> Int { cases.filter { $0.status == status }.count }
        return ParsedTestRun(
            platform: "android", runner: "gradle", source: "gradle",
            summary: .init(passed: count(.passed), failed: count(.failed), skipped: count(.skipped), errored: count(.errored)),
            testCases: cases)
    }

    private func test(_ name: String, _ status: TestCaseStatus) -> ParsedTestCase {
        .init(stableID: name, name: name, status: status)
    }

    private func record(
        _ recorder: TestEvidenceRecorder, _ run: ParsedTestRun?, reason: String, exitCode: Int32 = 1, parseFailure: String? = nil
    ) async throws {
        let (index, directory) = try await recorder.allocate()
        try await recorder.record(
            run, index: index, directory: directory, output: .init(stdout: "", stderr: "", exitCode: exitCode), arguments: [],
            reason: reason, parseFailure: parseFailure)
    }

    private func report(_ recorder: TestEvidenceRecorder) throws -> TestRunReport {
        try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: recorder.root.appendingPathComponent("report.json")))
    }

    // MARK: Provisional reports

    @Test("An interrupted run keeps unresolved failures instead of reporting the last rerun as the whole run")
    func interruptedRunKeepsUnresolvedFailures() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let recorder = TestEvidenceRecorder(root: scratch.url.appendingPathComponent("evidence"))
        try await record(
            recorder, run([test("a", .failed), test("b", .failed), test("c", .passed), test("d", .passed), test("e", .passed)]),
            reason: "initial")
        // The rerun saw only `a`, and it passed. `b` was never resolved.
        try await record(recorder, run([test("a", .passed)]), reason: "failed_tests", exitCode: 0)
        try await recorder.writeProvisionalReport(executionError: true)
        let report = try report(recorder)
        #expect(report.persistentFailedTests.map(\.stableID) == ["b"])
        #expect(report.flakyTests.map(\.stableID) == ["a"])
        #expect(report.summary.passed == 4)
        #expect(report.summary.failed == 1)
        #expect(report.summary.flaky == 1)
        #expect(report.summary.errored == 1, "an interrupted run must never read as clean")
        #expect(report.testCases?.count == 5, "the full run's identities survive, not just the rerun subset")
    }

    @Test("Failing tests are an outcome, not an execution error")
    func testFailureIsNotAnExecutionError() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let recorder = TestEvidenceRecorder(root: scratch.url.appendingPathComponent("evidence"))
        try await record(recorder, run([test("a", .failed), test("b", .passed)]), reason: "initial")
        try await recorder.writeProvisionalReport(executionError: false)
        let report = try report(recorder)
        #expect(report.summary.failed == 1)
        #expect(report.summary.errored == 0)
    }

    @Test("An unreadable rerun leaves the run incomplete")
    func unreadableRerunIsIncomplete() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let recorder = TestEvidenceRecorder(root: scratch.url.appendingPathComponent("evidence"))
        try await record(recorder, run([test("a", .failed)]), reason: "initial")
        try await record(recorder, nil, reason: "failed_tests", exitCode: 0, parseFailure: "garbled")
        try await recorder.writeProvisionalReport(executionError: false)
        let report = try report(recorder)
        #expect(report.persistentFailedTests.map(\.stableID) == ["a"])
        #expect(report.summary.errored == 1)
    }

    @Test("A final report written by the action is never overwritten")
    func provisionalNeverOverwritesFinal() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let recorder = TestEvidenceRecorder(root: scratch.url.appendingPathComponent("evidence"))
        try await record(recorder, run([test("a", .failed)]), reason: "initial")
        let final = TestRunReport(platform: "android", runner: "gradle", source: "final", summary: .init(passed: 9))
        try writeJSON(final, to: recorder.root.appendingPathComponent("report.json"))
        try await recorder.writeProvisionalReport(executionError: true)
        #expect(try report(recorder).source == "final")
    }

    @Test("Failing tests through the action leave a report that lists them, even though the action threw")
    func actionFailureLeavesReconciledReport() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let reports = scratch.url.appendingPathComponent("app/build/test-results/testDebugUnitTest")
        let (executor, _) = makeCaptureExecutor { _, _ in
            try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
            try """
            <testsuite name="S" tests="2" failures="1"><testcase classname="C" name="good"/><testcase classname="C" name="bad"><failure message="boom"/></testcase></testsuite>
            """.write(to: reports.appendingPathComponent("TEST-C.xml"), atomically: true, encoding: .utf8)
            return ShellOutput(stdout: "2 tests completed, 1 failed\n", stderr: "", exitCode: 1)
        }
        var context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(
                platform: .android, androidModule: "app", androidBuildVariant: "debug", gradleProjectDir: scratch.url.path),
            platform: .android)
        context.evidenceRoot = scratch.url.appendingPathComponent("evidence").path
        await #expect(throws: ShipItError.self) {
            _ = try await TestAction().run(with: .init(legacyCombinedTest: true, kind: .unit), context: context)
        }
        let directories = try FileManager.default.contentsOfDirectory(atPath: scratch.url.appendingPathComponent("evidence/test-runs").path)
        let root = scratch.url.appendingPathComponent("evidence/test-runs/\(try #require(directories.first))")
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: root.appendingPathComponent("report.json")))
        #expect(report.persistentFailedTests.map(\.name) == ["bad"])
        #expect(report.summary.failed == 1)
        #expect(report.summary.errored == 0)
    }

    // MARK: Saving evidence never changes the outcome

    @Test("Tests still run and report their exit code when the evidence directory cannot be created")
    func unwritableEvidenceDoesNotStopTests() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let blocker = scratch.url.appendingPathComponent("blocker")
        try "a file, not a directory".write(to: blocker, atomically: true, encoding: .utf8)
        var context = ActionContext.mock(executor: MockExecutor { _, _ in .init(stdout: "ran", stderr: "", exitCode: 3) })
        context.testEvidence = TestEvidenceRecorder(root: blocker.appendingPathComponent("evidence"))
        // Unrecorded, the shell's non-zero exit surfaces exactly as it does for any other command.
        do {
            _ = try await executeRecordedTest(
                SwiftPMCLI(context: context.shell).formatLint(paths: []), context: context, parse: { _ in nil })
            Issue.record("the command's failing exit must propagate")
        } catch let ShellError.exitFailure(_, captured) {
            #expect(captured.stdout == "ran")
            #expect(captured.exitCode == 3)
        }
    }

    @Test("A failure while saving an attempt's evidence does not replace the result")
    func evidenceWriteFailureKeepsOutcome() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let root = scratch.url.appendingPathComponent("evidence")
        // `attempts.json` is written last; a directory in its place makes that write fail after the tests ran.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("attempts.json"), withIntermediateDirectories: true)
        var context = ActionContext.mock(executor: MockExecutor { _, _ in .init(stdout: "ran", stderr: "", exitCode: 3) })
        context.testEvidence = TestEvidenceRecorder(root: root)
        let output = try await executeRecordedTest(
            SwiftPMCLI(context: context.shell).formatLint(paths: []), context: context, parse: { _ in nil })
        #expect(output.exitCode == 3)
    }

    // MARK: SwiftPM reruns

    @Test("An unreadable SwiftPM rerun keeps the original failure as persistent")
    func unreadableSwiftRerun() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let executor = MockExecutor { command, _ in
            let args = command.arguments
            guard let flag = args.firstIndex(of: "--event-stream-output-path") else { return .init(stdout: "", stderr: "", exitCode: 0) }
            if args.contains("--skip-build") {
                return .init(stdout: "", stderr: "crashed", exitCode: 1)  // writes no events at all
            }
            try """
            {"kind":"test","payload":{"kind":"function","id":"Tests.Suite/test()","name":"test"}}
            {"kind":"event","payload":{"kind":"testStarted","testID":"Tests.Suite/test()","instant":{"absolute":1}}}
            {"kind":"event","payload":{"kind":"issueRecorded","testID":"Tests.Suite/test()","messages":[{"text":"boom"}]}}
            {"kind":"event","payload":{"kind":"testEnded","testID":"Tests.Suite/test()","instant":{"absolute":2}}}
            """.write(toFile: args[flag + 1], atomically: true, encoding: .utf8)
            return .init(stdout: "", stderr: "failed", exitCode: 1)
        }
        let output = scratch.url.appendingPathComponent("run")
        await #expect(throws: ShipItError.self) {
            _ = try await SwiftTestAction().run(
                with: .init(outputDirectory: output.path, rerunFailedTests: .init(enabled: true, maxAttempts: 2)),
                context: .mock(executor: executor))
        }
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: output.appendingPathComponent("report.json")))
        #expect(report.persistentFailedTests.count == 1, "the original failure must survive an unreadable rerun")
        #expect(report.initialFailedTests.count == 1)
        #expect(report.attempts.last?.metadata?["results"] == "unavailable")
        #expect(report.summary.failed == 1)
    }

    // MARK: Android zero-result policy

    private func androidContext(
        _ scratch: TemporaryDirectory, stdout: String, exitCode: Int32 = 0
    ) -> ActionContext {
        let (executor, _) = makeCaptureExecutor { _, _ in .init(stdout: stdout, stderr: "", exitCode: exitCode) }
        return makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(
                platform: .android, androidModule: "app", androidBuildVariant: "debug", gradleProjectDir: scratch.url.path),
            platform: .android)
    }

    @Test("An Android run that exits 0 without any result is an execution failure")
    func androidSilentSuccessFails() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let context = androidContext(scratch, stdout: "BUILD SUCCESSFUL\n> Task :app:compileDebugAidl NO-SOURCE\n")
        await #expect(throws: ShipItError.self) {
            _ = try await TestAction().run(with: .init(legacyCombinedTest: true, kind: .unit), context: context)
        }
    }

    @Test("An Android test task that Gradle reports as having nothing to run is a legitimate empty run")
    func androidNoSourceIsLegitimate() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        for status in ["NO-SOURCE", "SKIPPED"] {
            let context = androidContext(scratch, stdout: "> Task :app:testDebugUnitTest \(status)\nBUILD SUCCESSFUL\n")
            let result = try await TestAction().run(with: .init(legacyCombinedTest: true, kind: .unit), context: context)
            #expect(result.succeeded)
            #expect(result.passCount == 0)
        }
    }

    @Test("NO-SOURCE on some other task says nothing about whether the tests ran")
    func gradleNoSourceIsTaskSpecific() {
        let action = TestAction()
        let log = "> Task :app:compileDebugAidl NO-SOURCE\n> Task :feature:testDebugUnitTest NO-SOURCE\n"
        #expect(action.gradleTaskHadNothingToRun(log, task: ":feature:testDebugUnitTest"))
        #expect(action.gradleTaskHadNothingToRun(log, task: "testDebugUnitTest"))
        #expect(!action.gradleTaskHadNothingToRun(log, task: ":app:testDebugUnitTest"))
        #expect(!action.gradleTaskHadNothingToRun("> Task :app:testDebugUnitTest FAILED\n", task: ":app:testDebugUnitTest"))
    }
}
