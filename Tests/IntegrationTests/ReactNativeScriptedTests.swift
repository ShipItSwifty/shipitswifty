import Foundation
import ShipItKit
import Testing

/// Runs the real `shipit` binary against the real React Native app fixture with real Jest, using
/// `__tests__/scripted.test.js`, whose outcomes (pass, skip, flake, fail) are scripted through the environment.
///
/// Opt-in quick tier (`SHIPIT_E2E=1`): it needs Node and network access for `npm install`.
@Suite("React Native Scripted E2E", .serialized, .requiresE2EQuick)
struct ReactNativeScriptedE2ETests {
    private let fixture = FixturePaths.reactNativeApp

    // MARK: Helpers

    private struct Outcome {
        let result: CLIResult
        let report: TestRunReport?
        let evidence: URL?
    }

    private func runTests(in project: URL, failing: Bool = false, flaky: Bool = true) async throws -> Outcome {
        try await bootstrapReactNativeNode(in: project)
        let shipfile = try makeTempShipfile(
            prefix: "rn-scripted", directory: project, contents: shipfileForExternalReactNativeProject(at: project))
        var environment: [String: String] = [:]
        if flaky { environment["SHIPIT_SAMPLE_FLAKY_DIR"] = project.appendingPathComponent("flaky-state").path }
        if failing { environment["SHIPIT_SAMPLE_FAIL"] = "1" }
        let reportPath = project.appendingPathComponent("report.json")
        try? FileManager.default.removeItem(at: reportPath)
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

    @Test("A flaky test fails, is rerun by name, passes, and reports two attempts; the app's own tests ran once")
    func flakyRecovers() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            let outcome = try await runTests(in: project)
            #expect(outcome.result.exitCode == 0, "\(outcome.result.output)")
            let report = try #require(outcome.report)
            #expect(report.runner == .jest)
            #expect(report.buildSystem == .reactNative)
            #expect(report.destinations == [TestDestination(platform: .js, kind: .host)], "Jest runs in Node")
            #expect(report.attempts.map(\.reason) == ["initial", "failed_tests"])
            #expect(report.summary.failed == 0)
            #expect(report.summary.flaky == 1)
            #expect(report.flakyTests.map(\.name) == ["flaky"])

            let flaky = try test("flaky", in: report)
            #expect(flaky.status == .passed)
            #expect(flaky.attempts == 2)
            #expect(flaky.metadata?["first_failure"]?.contains("Expected: false") == true)
            #expect(flaky.message == nil)
            #expect(try test("skipped on purpose", in: report).status == .skipped)

            let others = (report.testCases ?? []).filter { $0.suite?.hasPrefix("__tests__/scripted") != true && $0.status == .passed }
            #expect(others.count > 1, "the app's own Jest suites ran too")
            #expect(others.allSatisfy { $0.attempts == 1 })
            #expect(
                report.testCases?.allSatisfy { !$0.stableID.hasPrefix("jest-case:/") } == true,
                "identities must not embed this machine's paths")
        }
    }

    @Test("Failing tests are a test failure, not a build failure, and a persistent one reports both attempts")
    func persistentFailure() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            let outcome = try await runTests(in: project, failing: true)
            #expect(outcome.result.exitCode != 0)
            let report = try #require(outcome.report)
            let failure = try test("always fails when asked", in: report)
            #expect(failure.status == .failed)
            #expect(failure.attempts == 2)
            #expect(report.persistentFailedTests.map(\.name) == ["always fails when asked"])
            #expect(report.flakyTests.map(\.name) == ["flaky"], "the flaky one still recovered")
            #expect(report.summary.failed == 1)
            #expect(report.summary.errored == 0, "failing tests are a result, not an execution error")
        }
    }

    // MARK: Results from an earlier run are never reused

    @Test("A Jest run that dies before writing results does not reuse the previous run's results file")
    func staleResultsAreNotReused() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            try await bootstrapReactNativeNode(in: project)
            // A previous run left failing results behind.
            let stale = """
                {"numTotalTests":1,"numPassedTests":0,"numFailedTests":1,"numPendingTests":0,"numRuntimeErrorTestSuites":0,\
                "testResults":[{"name":"\(project.path)/__tests__/ghost.test.js","status":"failed","assertionResults":\
                [{"title":"stale ghost","fullName":"stale ghost","status":"failed","failureMessages":["old"]}]}]}
                """
            try stale.write(to: project.appendingPathComponent(".shipit-jest-results.json"), atomically: true, encoding: .utf8)
            // Jest cannot start, so it writes nothing.
            try "this is not valid javascript".write(
                to: project.appendingPathComponent("jest.config.js"), atomically: true, encoding: .utf8)
            let outcome = try await runTests(in: project, flaky: false)
            #expect(outcome.result.exitCode != 0)
            let names = outcome.report?.testCases?.map(\.name) ?? []
            #expect(!names.contains("stale ghost"), "a stale result must never appear as this run's")
            #expect(outcome.report?.persistentFailedTests.contains { $0.name == "stale ghost" } != true)
        }
    }

    // MARK: Offline inspection agrees with the live run

    @Test("The Jest JSON kept with each attempt reads offline to the same tests and statuses as the live run")
    func offlineMatchesLive() async throws {
        try assertReactNativeAppFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            let outcome = try await runTests(in: project)
            let evidence = try #require(outcome.evidence, "no evidence directory")
            let saved = evidence.appendingPathComponent("attempt-1/jest.json")
            #expect(FileManager.default.fileExists(atPath: saved.path), "each attempt keeps its Jest JSON")
            let live = try JSONDecoder().decode(
                ParsedTestRun.self, from: Data(contentsOf: evidence.appendingPathComponent("attempt-1/results.json")))
            let inspected = try await CLI.run(
                "test-results", "--input", saved.path, "--input-format", "jest", "--output", "json", workingDirectory: project, timeout: 120
            )
            #expect(inspected.exitCode == 0, "\(inspected.output)")
            let object = try #require(JSONSerialization.jsonObject(with: Data(inspected.stdout.utf8)) as? [String: Any])
            let parsed = try #require((object["payload"] as? [String: Any])?["parsedRun"])
            let offline = try JSONDecoder().decode(ParsedTestRun.self, from: JSONSerialization.data(withJSONObject: parsed))

            #expect(
                offline.testCases.map(\.stableID).sorted() == live.testCases.map(\.stableID).sorted(), "same identities offline and live")
            for test in offline.testCases {
                let match = try #require(live.testCases.first { $0.stableID == test.stableID })
                #expect(match.status == test.status, "\(test.name): live \(match.status) vs offline \(test.status)")
            }
        }
    }
}
