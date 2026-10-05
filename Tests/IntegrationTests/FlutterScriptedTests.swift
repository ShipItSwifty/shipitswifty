import Foundation
import ShipItKit
import Testing

/// Runs the real `shipit` binary against the real Flutter app fixture with real `flutter test --machine`, using
/// `test/scripted_test.dart`, whose outcomes (pass, skip, flake, fail) are scripted through the environment.
///
/// Opt-in quick tier (`SHIPIT_E2E=1`): it needs the Flutter SDK and network access for `flutter pub get`.
@Suite("Flutter Scripted E2E", .serialized, .requiresFlutterToolchain, .requiresE2EQuick)
struct FlutterScriptedE2ETests {
    private let fixture = FixturePaths.flutterApp

    // MARK: Helpers

    private struct Outcome {
        let result: CLIResult
        let report: TestRunReport?
        let evidence: URL?
    }

    private func runTests(
        in project: URL, failing: Bool = false, flaky: Bool = true
    ) async throws -> Outcome {
        try await bootstrapFlutter(in: project)
        let shipfile = try makeTempShipfile(
            prefix: "flutter-scripted", directory: project, contents: shipfileForExternalFlutterProject(at: project))
        var environment: [String: String] = [:]
        if flaky { environment["SHIPIT_SAMPLE_FLAKY_DIR"] = project.appendingPathComponent("flaky-state").path }
        if failing { environment["SHIPIT_SAMPLE_FAIL"] = "1" }
        let reportPath = project.appendingPathComponent("report.json")
        let result = try await CLI.run(
            "test", "--rerun-failed-tests", "--max-rerun-attempts", "2", "--report-path", reportPath.path, "--output", "json", "--shipfile",
            shipfile.path, workingDirectory: project, environment: environment, timeout: 900)
        let report = (try? Data(contentsOf: reportPath)).flatMap { try? JSONDecoder().decode(TestRunReport.self, from: $0) }
        let runs =
            (try? FileManager.default.contentsOfDirectory(
                at: project.appendingPathComponent("build/test-runs"), includingPropertiesForKeys: nil)) ?? []
        return Outcome(result: result, report: report, evidence: runs.first)
    }

    private func test(_ name: String, in report: TestRunReport) throws -> ParsedTestCase {
        try #require(report.testCases?.first { $0.name == name }, "no test named \(name)")
    }

    // MARK: Reruns

    @Test("A flaky test fails, is rerun by name, passes, and reports two attempts; the rest ran once")
    func flakyRecovers() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            let outcome = try await runTests(in: project)
            #expect(outcome.result.exitCode == 0, "\(outcome.result.output)")
            let report = try #require(outcome.report)
            #expect(report.runner == .flutterTest)
            #expect(report.buildSystem == .flutter)
            #expect(report.destinations == [TestDestination.host()], "`flutter test` runs in the Dart VM on this machine")
            #expect(report.attempts.map(\.reason) == ["initial", "failed_tests"])
            #expect(report.summary.failed == 0)
            #expect(report.summary.flaky == 1)
            #expect(report.flakyTests.map(\.name) == ["Scripted flaky"])

            let flaky = try test("Scripted flaky", in: report)
            #expect(flaky.status == .passed)
            #expect(flaky.attempts == 2)
            #expect(flaky.metadata?["flaky"] == "true")
            #expect(flaky.metadata?["first_failure"]?.contains("fails on the first attempt only") == true)
            #expect(flaky.message == nil, "a recovered test carries no failure")

            #expect(try test("Scripted passes", in: report).attempts == 1)
            #expect(try test("Scripted skipped on purpose", in: report).status == .skipped)
            let others = (report.testCases ?? []).filter { !$0.name.hasPrefix("Scripted flaky") && $0.status == .passed }
            #expect(others.count > 1, "the app's own tests ran too")
            #expect(others.allSatisfy { $0.attempts == 1 })
        }
    }

    @Test("A test that keeps failing fails the run and reports both attempts")
    func persistentFailure() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            let outcome = try await runTests(in: project, failing: true)
            #expect(outcome.result.exitCode != 0)
            let report = try #require(outcome.report)
            let failure = try test("Scripted always fails when asked", in: report)
            #expect(failure.status == .failed)
            #expect(failure.attempts == 2)
            #expect(failure.message?.contains("asked to fail") == true)
            #expect(report.persistentFailedTests.map(\.name) == ["Scripted always fails when asked"])
            #expect(report.flakyTests.map(\.name) == ["Scripted flaky"], "the flaky one still recovered")
            #expect(report.summary.failed == 1)
        }
    }

    // MARK: Evidence and offline inspection

    @Test("Every attempt keeps its machine events and logs, and reading them offline matches the live run")
    func offlineMatchesLive() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            let outcome = try await runTests(in: project)
            let evidence = try #require(outcome.evidence, "no evidence directory")
            for attempt in 1...2 {
                for file in ["events.jsonl", "stdout.log", "stderr.log", "command.json", "results.json"] {
                    #expect(
                        FileManager.default.fileExists(atPath: evidence.appendingPathComponent("attempt-\(attempt)/\(file)").path),
                        "attempt-\(attempt)/\(file)")
                }
            }
            let live = try JSONDecoder().decode(
                ParsedTestRun.self, from: Data(contentsOf: evidence.appendingPathComponent("attempt-1/results.json")))
            let inspected = try await CLI.run(
                "test-results", "--input", evidence.appendingPathComponent("attempt-1/events.jsonl").path, "--input-format", "flutter",
                "--output", "json", workingDirectory: project, timeout: 120)
            #expect(inspected.exitCode == 0, "\(inspected.output)")
            let object = try #require(JSONSerialization.jsonObject(with: Data(inspected.stdout.utf8)) as? [String: Any])
            let parsed = try #require((object["payload"] as? [String: Any])?["parsedRun"])
            let offline = try JSONDecoder().decode(ParsedTestRun.self, from: JSONSerialization.data(withJSONObject: parsed))

            #expect(offline.runner == live.runner)
            #expect(offline.destinations.isEmpty, "saved events do not say where the tests ran; the live run does")
            #expect(live.destinations == [TestDestination.host()])
            #expect(offline.testCases.map(\.stableID).sorted() == live.testCases.map(\.stableID).sorted())
            for test in offline.testCases {
                let match = try #require(live.testCases.first { $0.stableID == test.stableID })
                #expect(match.status == test.status, "\(test.name): live \(match.status) vs offline \(test.status)")
            }
        }
    }

    // MARK: A run that reports nothing

    @Test("A Flutter project with no tests fails instead of reporting a passing zero-test run")
    func noTestsFails() async throws {
        try assertFlutterAppFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            try FileManager.default.removeItem(at: project.appendingPathComponent("test"))
            let outcome = try await runTests(in: project, flaky: false)
            #expect(outcome.result.exitCode != 0, "no results must never read as a pass:\n\(outcome.result.output)")
            #expect((outcome.report?.summary.passed ?? 0) == 0)
        }
    }
}
