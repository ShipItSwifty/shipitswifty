import ArgumentParser
import Foundation
import MobileTesting
import TestCommons
import Testing

@testable import ShipItCLI
@testable import ShipItKit

@Suite("CLI ci report and ci issues")
struct CIReportCommandTests {
    private func makeCase(_ id: String, status: TestCaseStatus, attempts: Int = 1, flaky: Bool = false) -> ParsedTestCase {
        ParsedTestCase(
            stableID: "plan-1:destination-1:xcresult-case:\(id)", name: id, status: status, message: "assertion failed",
            file: "/work/Tests/CartTests.swift", line: 9, rerunSelector: .xcodeOnlyTesting(id),
            metadata: flaky ? ["plan": "default", "flaky": "true"] : ["plan": "default"], attempts: attempts)
    }

    private func write(failing: Bool = false, flaky: Bool = false, into directory: TemporaryDirectory) throws -> String {
        let failed = failing ? [makeCase("App/Cart/testBroken()", status: .failed, attempts: 3)] : []
        let recovered = flaky ? [makeCase("App/Cart/testSometimes()", status: .passed, attempts: 2, flaky: true)] : []
        let report = TestRunReport(
            runner: .xcodebuild, source: "build/test-runs", flakyTests: recovered, persistentFailedTests: failed,
            summary: TestSummary(passed: 1 + recovered.count, failed: failed.count, flaky: recovered.count),
            testCases: [makeCase("App/Cart/testFine()", status: .passed)] + recovered + failed)
        let url = directory.url.appendingPathComponent("report.json")
        try JSONEncoder().encode(report).write(to: url)
        return url.path
    }

    @Test("ci report parses its options, repeating --report for shards")
    func parsesReport() throws {
        let command =
            try CIReportCommand.parseAsRoot([
                "--report", "a.json", "--report", "b.json", "--summary-path", "s.md", "--annotations", "--fail-on-flaky",
                "--result-path", "r.json", "--artifact-url", "https://example.com/a",
            ]) as! CIReportCommand
        #expect(command.reports == ["a.json", "b.json"])
        #expect(command.summaryPath == "s.md")
        #expect(command.annotations)
        #expect(command.failOnFlaky)
        #expect(command.resultPath == "r.json")
    }

    @Test("ci issues parses its options and takes no token argument")
    func parsesIssues() throws {
        let command =
            try CIIssuesCommand.parseAsRoot([
                "--report", "a.json", "--repository", "octo/app", "--label", "ci", "--label", "ios", "--close-after-clean-runs", "5",
                "--only-ref", "main",
            ]) as! CIIssuesCommand
        #expect(command.labels == ["ci", "ios"])
        #expect(command.closeAfterCleanRuns == 5)
        #expect(command.onlyRef == "main")
        #expect(throws: Error.self) { try CIIssuesCommand.parseAsRoot(["--report", "a.json", "--token", "secret"]) }
    }

    @Test("ci is registered with export, report and issues")
    func registered() {
        let names = CICommand.configuration.subcommands.map { $0.configuration.commandName }
        #expect(names == ["export", "report", "issues"])
    }

    @Test("A consistently failing test fails the policy, writes the summary and the result file")
    func failingReport() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let report = try write(failing: true, flaky: true, into: scratch)
        let summary = scratch.url.appendingPathComponent("summary.md").path
        let result = scratch.url.appendingPathComponent("out/result.json").path
        var command =
            try CIReportCommand.parseAsRoot(["--report", report, "--summary-path", summary, "--result-path", result]) as! CIReportCommand
        do {
            try await command.run()
            Issue.record("A failing test must fail the command")
        } catch let error as ExitCode {
            #expect(error.rawValue == 11)
        }
        let markdown = try String(contentsOfFile: summary, encoding: .utf8)
        #expect(markdown.contains("Consistently failing"))
        #expect(markdown.contains("App/Cart/testBroken()"))
        let decoded = try JSONDecoder().decode(CIReportResult.self, from: Data(contentsOf: URL(fileURLWithPath: result)))
        #expect(decoded.hasConsistentFailures)
        #expect(!decoded.policyPassed)
        #expect(decoded.flaky == 1)
        #expect(decoded.consistentFailureCount == 1)
    }

    @Test("A flaky-but-recovered run passes unless --fail-on-flaky is set")
    func flakyPolicy() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let report = try write(flaky: true, into: scratch)

        var lenient = try CIReportCommand.parseAsRoot(["--report", report]) as! CIReportCommand
        try await lenient.run()

        var strict = try CIReportCommand.parseAsRoot(["--report", report, "--fail-on-flaky"]) as! CIReportCommand
        do {
            try await strict.run()
            Issue.record("--fail-on-flaky must fail a flaky run")
        } catch let error as ExitCode {
            #expect(error.rawValue == 11)
        }
    }

    @Test("A summary is appended, so earlier steps' summaries survive")
    func summaryAppends() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let report = try write(into: scratch)
        let summary = scratch.url.appendingPathComponent("summary.md")
        try "earlier step\n".write(to: summary, atomically: true, encoding: .utf8)
        var command = try CIReportCommand.parseAsRoot(["--report", report, "--summary-path", summary.path]) as! CIReportCommand
        try await command.run()
        let text = try String(contentsOf: summary, encoding: .utf8)
        #expect(text.hasPrefix("earlier step"))
        #expect(text.contains("ShipIt test results"))
    }

    @Test("A missing report is a configuration error, never a green run")
    func missingReport() async throws {
        var command = try CIReportCommand.parseAsRoot(["--report", "/no/such/report.json"]) as! CIReportCommand
        do {
            try await command.run()
            Issue.record("A missing report must fail")
        } catch let error as ExitCode {
            #expect(error.rawValue == 2)
        }
    }

    @Test("ci issues skips, without a token, when the branch is not the one issues are filed from")
    func issuesSkipOutOfScope() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let report = try write(failing: true, into: scratch)
        var command =
            try CIIssuesCommand.parseAsRoot(["--report", report, "--only-ref", "no-such-branch-for-shipit-tests"]) as! CIIssuesCommand
        try await command.run()
    }
}
