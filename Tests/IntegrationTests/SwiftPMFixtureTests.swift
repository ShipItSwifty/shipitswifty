import Foundation
import ShipItKit
import Testing

/// Runs the real `shipit` binary against `Fixtures/swiftpm-sample`, a package whose tests have scripted outcomes
/// (see its `SampleTests.swift`), and asserts exactly what ShipIt reports: the typed report, the attempts, the
/// evidence it keeps, and that offline inspection of the saved artifacts agrees with the live run.
///
/// No network and no credentials: only a Swift toolchain, so this runs on macOS and Linux.
@Suite("SwiftPM Fixture Integration", .serialized)
struct SwiftPMFixtureIntegrationTests {
    private let fixture = FixturePaths.swiftPMSample

    // MARK: Helpers

    private struct Run {
        let result: CLIResult
        let directory: URL
        let report: TestRunReport

        func attempt(_ number: Int) throws -> ParsedTestRun {
            try JSONDecoder().decode(
                ParsedTestRun.self, from: Data(contentsOf: directory.appendingPathComponent("attempt-\(number)/results.json")))
        }
    }

    /// Runs the sample's `tests` workflow in a fresh copy and loads what it left behind.
    private func runTests(
        in project: URL, failing: Bool = false, flaky: Bool = true
    ) async throws -> Run {
        var environment: [String: String] = [:]
        if flaky { environment["SHIPIT_SAMPLE_FLAKY_DIR"] = project.appendingPathComponent("flaky-state").path }
        if failing { environment["SHIPIT_SAMPLE_FAIL"] = "1" }
        let result = try await CLI.run(
            "test", "--workflow", "tests", "--shipfile", project.appendingPathComponent("Shipfile.yml").path, "--output", "json", "--ci",
            workingDirectory: project, environment: environment, timeout: 600)
        let runs = try FileManager.default.contentsOfDirectory(
            at: project.appendingPathComponent("build/workflow-artifacts"), includingPropertiesForKeys: nil
        ).compactMap {
            try? FileManager.default.contentsOfDirectory(at: $0.appendingPathComponent("test-runs"), includingPropertiesForKeys: nil)
        }
        .flatMap { $0 }.filter { $0.lastPathComponent.hasPrefix("swift-") }
        let directory = try #require(runs.first, "no test run evidence was kept.\n\(result.output)")
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: directory.appendingPathComponent("report.json")))
        return Run(result: result, directory: directory, report: report)
    }

    private func names(_ tests: [ParsedTestCase]?) -> [String] { (tests ?? []).map(\.name).sorted() }

    // MARK: A clean run

    @Test("A package with no failures passes in one attempt and says where it ran")
    func cleanRun() async throws {
        try await withFixtureCopy(of: fixture) { project in
            // No flaky directory: the flaky tests pass the first time.
            let run = try await runTests(in: project, flaky: false)
            #expect(run.result.exitCode == 0, "\(run.result.output)")
            #expect(run.report.schemaVersion == TestRunReport.currentSchemaVersion)
            #expect(run.report.runner == .swiftTest)
            #expect(run.report.buildSystem == .native)
            #expect(run.report.destinations == [TestDestination.host()])
            #expect(run.report.attempts.map(\.reason) == ["initial"])
            #expect(run.report.summary.failed == 0)
            #expect(run.report.summary.flaky == 0)
            #expect(run.report.summary.skipped == 1)
            #expect(run.report.summary.passed == 7)
            #expect(run.report.testCases?.allSatisfy { $0.attempts == 1 && $0.destinationID == TestDestination.host().id } == true)
        }
    }

    // MARK: Flaky tests

    @Test("Flaky tests are rerun selectively, pass, and report how many attempts they needed")
    func flakyTestsRecover() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let run = try await runTests(in: project)
            #expect(run.result.exitCode == 0, "recovered flakiness must not fail the workflow:\n\(run.result.output)")
            let report = run.report
            #expect(report.attempts.map(\.reason) == ["initial", "failed_tests"])
            #expect(names(report.flakyTests) == ["flaky()", "testFlakyXCTest"])
            #expect(report.persistentFailedTests.isEmpty)
            #expect(report.summary.failed == 0)
            #expect(report.summary.flaky == 2)
            #expect(report.summary.passed == 7)

            // The first attempt saw both fail; the rerun ran only those two, not the whole suite.
            #expect(names(report.attempts[0].failedTests) == ["flaky()", "testFlakyXCTest"])
            #expect(report.attempts[1].summary.passed == 2)
            #expect(report.attempts[1].summary.failed == 0)

            let cases = try #require(report.testCases)
            for name in ["flaky()", "testFlakyXCTest"] {
                let test = try #require(cases.first { $0.name == name })
                #expect(test.status == .passed, "\(name) recovered")
                #expect(test.attempts == 2, "\(name) failed once, then passed")
                #expect(test.metadata?["flaky"] == "true")
                #expect(test.metadata?["first_failure"] != nil, "why it first failed is kept")
                #expect(test.message == nil, "a recovered test carries no failure")
            }
            for test in cases where !["flaky()", "testFlakyXCTest"].contains(test.name) {
                #expect(test.attempts == 1, "\(test.name) ran once")
            }
        }
    }

    @Test("Every attempt keeps its own logs and machine-readable results")
    func attemptsKeepEvidence() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let run = try await runTests(in: project)
            for attempt in 1...2 {
                let directory = run.directory.appendingPathComponent("attempt-\(attempt)")
                for file in ["stdout.log", "stderr.log", "events.jsonl", "xctest.xml", "results.json"] {
                    #expect(
                        FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path), "attempt-\(attempt)/\(file)")
                }
            }
            // The first attempt's events still record the failure after the rerun succeeded.
            let first = try String(contentsOf: run.directory.appendingPathComponent("attempt-1/events.jsonl"), encoding: .utf8)
            #expect(first.contains("issueRecorded"))
            #expect(run.directory.appendingPathComponent("report.json").path.hasSuffix("report.json"))
            // The workflow also stages the evidence for CI upload, even though nothing failed.
            let staged = project.appendingPathComponent("build/workflow-artifacts")
            let workflow = try FileManager.default.contentsOfDirectory(atPath: staged.path).first
            #expect(workflow != nil)
            #expect(
                FileManager.default.fileExists(
                    atPath: staged.appendingPathComponent("\(workflow ?? "")/workflow.json").path))
        }
    }

    // MARK: Persistent failures

    @Test("A failure that survives the rerun fails the workflow and is reported with every attempt")
    func persistentFailure() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let run = try await runTests(in: project, failing: true)
            #expect(run.result.exitCode != 0, "a persistent failure must fail the workflow")
            let report = run.report
            #expect(names(report.persistentFailedTests) == ["alwaysFailsWhenAsked()", "testAlwaysFailsWhenAsked"])
            #expect(names(report.flakyTests) == ["flaky()", "testFlakyXCTest"], "recoveries are still reported alongside")
            #expect(report.summary.failed == 2)
            #expect(report.summary.flaky == 2)
            #expect(report.attempts.map(\.reason) == ["initial", "failed_tests"])
            #expect(report.attempts.first?.failedTests.count == 4, "all four failed on the first attempt")

            let cases = try #require(report.testCases)
            for name in ["alwaysFailsWhenAsked()", "testAlwaysFailsWhenAsked"] {
                let test = try #require(cases.first { $0.name == name })
                #expect(test.status == .failed)
                #expect(test.attempts == 2, "\(name) failed on both attempts")
                #expect(test.message != nil, "a persistent failure keeps its message")
            }
            // Evidence survives the failure, including the staged copy for CI.
            #expect(FileManager.default.fileExists(atPath: run.directory.appendingPathComponent("attempt-1/events.jsonl").path))
            #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("build/workflow-artifacts").path))
        }
    }

    // MARK: Offline inspection agrees with the live run

    @Test("Inspecting the saved artifacts offline gives the same tests, IDs and statuses as the live run")
    func offlineMatchesLive() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let run = try await runTests(in: project)
            let live = try run.attempt(1)

            func inspect(_ arguments: [String]) async throws -> ParsedTestRun {
                let result = try await CLI.run(
                    ["test-results"] + arguments + ["--output", "json"], workingDirectory: project, timeout: 120)
                #expect(result.exitCode == 0, "\(result.output)")
                let object = try #require(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
                let parsed = try #require((object["payload"] as? [String: Any])?["parsedRun"])
                return try JSONDecoder().decode(ParsedTestRun.self, from: JSONSerialization.data(withJSONObject: parsed))
            }

            let events = try await inspect([
                "--input", run.directory.appendingPathComponent("attempt-1/events.jsonl").path, "--input-format", "swift",
            ])
            let xunit = try await inspect([
                "--input", run.directory.appendingPathComponent("attempt-1/xctest.xml").path, "--input-format", "junit", "--runner",
                "swift-test",
            ])
            for offline in [events, xunit] {
                #expect(offline.runner == .swiftTest)
                for test in offline.testCases {
                    let match = try #require(
                        live.testCases.first { $0.stableID == test.stableID }, "\(test.stableID) is not in the live run")
                    #expect(match.status == test.status, "\(test.name): live \(match.status) vs offline \(test.status)")
                }
            }
            #expect(events.testCases.count + xunit.testCases.count == live.testCases.count, "together they cover every live test")
            #expect(events.summary.failed + xunit.summary.failed == live.summary.failed)
        }
    }

    @Test("An export can be moved and read back with the same results")
    func exportSurvivesRelocation() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let run = try await runTests(in: project)
            let export = project.appendingPathComponent("export")
            let exported = try await CLI.run(
                "test-results", "--input", run.directory.appendingPathComponent("attempt-1/events.jsonl").path, "--input-format", "swift",
                "--export-directory", export.path, "--output", "json", workingDirectory: project, timeout: 120)
            #expect(exported.exitCode == 0, "\(exported.output)")
            for file in ["results.json", "manifest.json", "index.md"] {
                #expect(FileManager.default.fileExists(atPath: export.appendingPathComponent(file).path), "\(file)")
            }
            let moved = project.deletingLastPathComponent().appendingPathComponent("moved-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: moved) }
            try FileManager.default.moveItem(at: export, to: moved)
            let reread = try await CLI.run(
                "test-results", "--input", moved.path, "--output", "json", workingDirectory: project, timeout: 120)
            #expect(reread.exitCode == 0, "\(reread.output)")
            let object = try #require(JSONSerialization.jsonObject(with: Data(reread.stdout.utf8)) as? [String: Any])
            let parsed = try #require((object["payload"] as? [String: Any])?["parsedRun"] as? [String: Any])
            let summary = try #require(parsed["summary"] as? [String: Int])
            // Attempt 1's Swift Testing events: three pass, `flaky` fails, one is skipped (the XCTest cases are in xctest.xml).
            #expect(summary["failed"] == 1)
            #expect(summary["passed"] == 3)
            #expect(summary["skipped"] == 1)
        }
    }

    // MARK: Coverage and CI

    @Test("Coverage is saved from the first full run and read back with its runner")
    func coverage() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let run = try await runTests(in: project)
            let coverage = run.directory.appendingPathComponent("coverage.json")
            #expect(FileManager.default.fileExists(atPath: coverage.path), "coverage.json is kept next to the report")
            let result = try await CLI.run(
                "coverage", "--input-format", "swift", "--report", coverage.path, "--source-root", "Sources/Sample", "--format", "json",
                workingDirectory: project, timeout: 120)
            #expect(result.exitCode == 0, "\(result.output)")
            let object = try #require(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
            let payload = try #require(object["payload"] as? [String: Any])
            #expect(payload["runner"] as? String == "swift-test")
            #expect(payload["platform"] as? String == "unknown", "a SwiftPM coverage file does not say where tests ran")
            let percent = try #require(payload["overallLineCoverage"] as? Double)
            #expect(percent > 0 && percent < 100, "the sample leaves one branch uncovered, got \(percent)")
        }
    }

    @Test("The workflow exports as a CI job that publishes evidence even when tests fail")
    func ciExport() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let result = try await CLI.run(
                "ci", "export", "--provider", "github-actions", "--workflow", "tests", "--runner", "ubuntu-latest", "--setup-command",
                "swift --version", "--shipfile", project.appendingPathComponent("Shipfile.yml").path, workingDirectory: project,
                timeout: 120)
            #expect(result.exitCode == 0, "\(result.output)")
            #expect(result.stdout.contains("runs-on: ubuntu-latest"))
            #expect(result.stdout.contains("swift --version"), "setup is explicit")
            #expect(result.stdout.contains("actions/upload-artifact"))
            #expect(result.stdout.contains("if: always()"), "evidence is published after a failure too")
            #expect(result.stdout.contains("'tests'"))
        }
    }
}
