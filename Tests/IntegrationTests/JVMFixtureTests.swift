import Foundation
import ShipItKit
import Testing

/// Runs the real `shipit` binary against `Fixtures/jvm-retry-sample`: a plain JVM project built by real Gradle, with
/// the real `org.gradle.test-retry` plugin, whose tests have scripted outcomes. It checks what ShipIt reports for the
/// XML a retry plugin actually writes, how reruns and the plugin's retries add up, that a build which fails before
/// running tests cannot reuse the previous run's results, and that offline inspection agrees with the live run.
///
/// Opt-in (`SHIPIT_E2E=1`): it needs a JDK and network access for the Gradle distribution and Maven Central.
/// `.serialized` because Gradle runs contend on shared `~/.gradle` locks.
@Suite("JVM Fixture Integration", .serialized, .requiresE2EQuick, .enabled(if: JVMTooling.available, "needs a JDK on PATH or JAVA_HOME"))
struct JVMFixtureIntegrationTests {
    private let fixture = FixturePaths.jvmRetrySample

    // MARK: Helpers

    private struct Outcome {
        let result: CLIResult
        let report: TestRunReport?
    }

    private func runTests(
        in project: URL, failing: Bool = false, flaky: Bool = true, reruns: Bool = true
    ) async throws -> Outcome {
        var environment: [String: String] = [:]
        if flaky { environment["SHIPIT_SAMPLE_FLAKY_DIR"] = project.appendingPathComponent("flaky-state").path }
        if failing { environment["SHIPIT_SAMPLE_FAIL"] = "1" }
        let reportPath = project.appendingPathComponent("report.json")
        try? FileManager.default.removeItem(at: reportPath)
        var arguments = [
            "test", "--platform", "android", "--kind", "unit", "--scope", "root", "--task", "test", "--report-path", reportPath.path,
            "--output", "json", "--shipfile", project.appendingPathComponent("Shipfile.yml").path,
        ]
        if reruns { arguments += ["--rerun-failed-tests", "--max-rerun-attempts", "2"] }
        let result = try await CLI.run(arguments, workingDirectory: project, environment: environment, timeout: 900)
        let report = (try? Data(contentsOf: reportPath)).flatMap { try? JSONDecoder().decode(TestRunReport.self, from: $0) }
        return Outcome(result: result, report: report)
    }

    private func test(_ name: String, in report: TestRunReport) throws -> ParsedTestCase {
        try #require(report.testCases?.first { $0.name == name }, "no test named \(name)")
    }

    // MARK: Retries and reruns add up

    @Test("Flaky tests are counted whether the retry plugin or the workflow's rerun recovered them")
    func flakySourcesAreOneNumber() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let outcome = try await runTests(in: project)
            #expect(outcome.result.exitCode == 0, "\(outcome.result.output)")
            let report = try #require(outcome.report)

            #expect(report.runner == .gradle)
            #expect(report.buildSystem == .native)
            #expect(report.destinations.map(\.id) == ["jvm:host:test"], "the plain `test` task of a JVM project")
            #expect(report.attempts.map(\.reason) == ["initial", "failed_tests"])
            #expect(report.summary.failed == 0)

            let inside = try test("recoversInsideGradle()", in: report)
            #expect(inside.status == .passed)
            #expect(inside.attempts == 2, "the plugin ran it twice inside one Gradle run")
            #expect(inside.metadata?["flaky"] == "true")

            let across = try test("recoversAcrossRuns()", in: report)
            #expect(across.status == .passed)
            #expect(across.attempts == 4, "three plugin attempts failed in the first run, then the workflow's rerun passed it")
            #expect(across.metadata?["flaky"] == "true")

            // One number for flaky tests, whoever retried them.
            #expect(report.summary.flaky == 2)
            #expect(report.flakyTests.map(\.name).sorted() == ["recoversAcrossRuns()", "recoversInsideGradle()"])
            #expect(try test("passes()", in: report).attempts == 1)
            #expect(try test("skipped()", in: report).status == .skipped)
        }
    }

    @Test("A test that fails every attempt counts every execution, including the plugin's retries in each")
    func persistentFailureCountsEveryExecution() async throws {
        try await withFixtureCopy(of: fixture) { project in
            let outcome = try await runTests(in: project, failing: true)
            #expect(outcome.result.exitCode != 0, "a persistent failure fails the run")
            let report = try #require(outcome.report)
            let failure = try test("alwaysFailsWhenAsked()", in: report)
            #expect(failure.status == .failed)
            #expect(failure.attempts == 6, "three plugin executions in the first run and three more in the rerun")
            #expect(failure.message?.contains("asked to fail") == true)
            #expect(report.persistentFailedTests.map(\.name) == ["alwaysFailsWhenAsked()"])
            #expect(report.summary.failed == 1)
        }
    }

    // MARK: Results from an earlier run are never reused

    @Test("A build that fails before running tests does not reuse the previous run's failing results")
    func staleResultsAreNotReused() async throws {
        try await withFixtureCopy(of: fixture) { project in
            // First, a real run that leaves failing XML behind.
            let first = try await runTests(in: project, failing: true, reruns: false)
            #expect(first.result.exitCode != 0)
            let results = project.appendingPathComponent("build/test-results/test")
            #expect(FileManager.default.fileExists(atPath: results.path), "the failing run wrote its XML")

            // Now break compilation, so Gradle fails without executing any test.
            let source = project.appendingPathComponent("src/test/java/sample/SampleTest.java")
            try (String(contentsOf: source, encoding: .utf8) + "\nthis is not valid java\n").write(
                to: source, atomically: true, encoding: .utf8)
            let second = try await runTests(in: project, flaky: false, reruns: false)

            #expect(second.result.exitCode != 0, "a compile failure fails the run")
            // The old failing XML must not be presented as this run's results.
            let leftover = (try? FileManager.default.contentsOfDirectory(atPath: results.path)) ?? []
            #expect(leftover.filter { $0.hasSuffix(".xml") }.isEmpty, "stale XML was cleared before the run, found \(leftover)")
            let names = second.report?.testCases?.map(\.name) ?? []
            #expect(!names.contains("alwaysFailsWhenAsked()"), "no stale test may appear as this run's result")
            // A build that never ran a test is an execution error, not "a failed test named after a Gradle task".
            #expect(second.report?.summary.errored == 1)
            #expect(second.report?.summary.failed == 0)
            #expect(second.report?.persistentFailedTests.isEmpty == true, "got \(second.report?.persistentFailedTests.map(\.name) ?? [])")
        }
    }

    @Test("A test task with nothing to run is a legitimate empty run, not a missing-results failure")
    func noSourceIsNotAFailure() async throws {
        try await withFixtureCopy(of: fixture) { project in
            try FileManager.default.removeItem(at: project.appendingPathComponent("src/test"))
            let outcome = try await runTests(in: project, flaky: false, reruns: false)
            #expect(outcome.result.exitCode == 0, "Gradle reports `:test NO-SOURCE`:\n\(outcome.result.output)")
            #expect(!outcome.result.output.contains("produced no JUnit XML"))
        }
    }

    // MARK: Offline inspection agrees with the live run

    @Test("Inspecting the retry plugin's XML offline gives the same tests, statuses and attempts as the live run")
    func offlineMatchesLive() async throws {
        try await withFixtureCopy(of: fixture) { project in
            // No workflow reruns, so build/test-results holds exactly the run the live report describes.
            let outcome = try await runTests(in: project, reruns: false)
            #expect(outcome.result.exitCode != 0, "recoversAcrossRuns fails all three plugin attempts without a rerun")
            let live = try #require(outcome.report)

            let inspected = try await CLI.run(
                "test-results", "--input", project.appendingPathComponent("build/test-results/test").path, "--runner", "gradle",
                "--output", "json", workingDirectory: project, timeout: 120)
            #expect(inspected.exitCode == 0, "\(inspected.output)")
            let object = try #require(JSONSerialization.jsonObject(with: Data(inspected.stdout.utf8)) as? [String: Any])
            let parsed = try #require((object["payload"] as? [String: Any])?["parsedRun"])
            let offline = try JSONDecoder().decode(ParsedTestRun.self, from: JSONSerialization.data(withJSONObject: parsed))

            #expect(offline.runner == live.runner)
            #expect(offline.destinations == live.destinations)
            let liveCases = try #require(live.testCases)
            #expect(offline.testCases.count == liveCases.count)
            for test in offline.testCases {
                let match = try #require(liveCases.first { $0.stableID == test.stableID }, "\(test.stableID) is not in the live run")
                #expect(match.status == test.status, "\(test.name): live \(match.status) vs offline \(test.status)")
                #expect(
                    match.attempts == test.attempts,
                    "\(test.name): live \(String(describing: match.attempts)) attempts vs offline \(String(describing: test.attempts))")
                #expect(match.destinationID == test.destinationID)
            }
            #expect(offline.summary.flaky == live.summary.flaky)
            #expect(offline.summary.failed == live.summary.failed)
        }
    }
}

/// Whether a JDK is available, so the suite is skipped (not failed) on a machine without one.
enum JVMTooling {
    static let available: Bool = {
        if ProcessInfo.processInfo.environment["JAVA_HOME"] != nil { return true }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").contains { FileManager.default.isExecutableFile(atPath: "\($0)/java") }
    }()
}
