#if os(macOS)
import Foundation
import ShipItKit
import Testing

/// Runs the real `shipit` binary with real `xcodebuild` on an iOS simulator against `Fixtures/ios-sample`, which has two
/// real `.xctestplan`s (English and German configurations) over one test target and scripted test outcomes.
///
/// One run covers it all, because a run takes minutes: the two plans share one build, each plan has a flaky test that is
/// rerun selectively and recovers, and one test fails persistently. Everything is asserted from that single run.
///
/// Opt-in build tier (`SHIPIT_E2E_BUILD=1`): it needs Xcode and a simulator **no other process is using**. Set
/// `SHIPIT_E2E_IOS_DESTINATION` (for example `platform=iOS Simulator,id=<udid>`) to choose one; otherwise ShipIt
/// discovers a destination itself.
@Suite("iOS Fixture Integration", .serialized, .requiresE2EBuild)
struct IOSFixtureIntegrationTests {
    private let fixture = FixturePaths.iosSample

    @Test("Two test plans share one build; flaky tests recover per plan, a failing test persists, and evidence is kept")
    func twoPlansOneBuild() async throws {
        try assertIOSFixtureExists()
        try await withFixtureCopy(of: fixture) { project in
            let reportPath = project.appendingPathComponent("report.json")
            var arguments = [
                "test", "--shipfile", project.appendingPathComponent("Shipfile.yml").path, "--scheme", "ios-sample", "--test-plans", "Unit",
                "Smoke", "--rerun-failed-tests", "--max-rerun-attempts", "2", "--report-path", reportPath.path, "--output", "json",
            ]
            if let destination = ProcessInfo.processInfo.environment["SHIPIT_E2E_IOS_DESTINATION"] {
                arguments += ["--destination", destination]
            }
            // `xcodebuild` forwards `TEST_RUNNER_`-prefixed variables to the tests with the prefix removed.
            let result = try await CLI.run(
                arguments, workingDirectory: project,
                environment: [
                    "TEST_RUNNER_SHIPIT_SAMPLE_FAIL": "1",
                    "TEST_RUNNER_SHIPIT_SAMPLE_FLAKY_DIR": project.appendingPathComponent("flaky-state").path,
                ], timeout: 3000)
            #expect(result.exitCode != 0, "a persistent failure must fail the run:\n\(result.output)")

            let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: reportPath))
            let cases = try #require(report.testCases)
            func test(_ name: String, plan: String) throws -> ParsedTestCase {
                try #require(cases.first { $0.name == name && $0.metadata?["plan"] == plan }, "no \(name) in plan \(plan)")
            }

            // MARK: What ran and where

            #expect(report.runner == .xcodebuild)
            #expect(report.buildSystem == .native)
            #expect(report.destinations.map(\.scope) == ["Unit", "Smoke"], "one destination per plan")
            #expect(report.destinations.allSatisfy { $0.platform == .ios && $0.kind == .simulator })
            let name = try #require(report.destinations.first?.name)
            #expect(name.range(of: #"^[0-9A-Fa-f-]{36}$"#, options: .regularExpression) == nil, "the device's name, not its UDID: \(name)")
            #expect(Set(cases.map(\.stableID)).count == cases.count, "the same test in two plans stays two tests")
            #expect(cases.count == 10, "five tests in each of two plans")

            // MARK: Reruns

            for plan in ["Unit", "Smoke"] {
                let reasons = report.attempts.filter { $0.metadata?["plan"] == plan }.map(\.reason)
                #expect(reasons.first == "initial", "plan \(plan): \(reasons)")
                #expect(reasons.contains("failed_tests"), "plan \(plan) reran its failures: \(reasons)")

                let flaky = try test("testFlaky()", plan: plan)
                #expect(flaky.status == .passed, "plan \(plan)")
                #expect(flaky.attempts == 2)
                #expect(flaky.metadata?["flaky"] == "true")
                #expect(flaky.message == nil)

                let failing = try test("testAlwaysFailsWhenAsked()", plan: plan)
                #expect(failing.status == .failed, "plan \(plan)")
                #expect(failing.attempts == 2, "failed on both attempts")
                #expect(try test("testPasses()", plan: plan).attempts == 1)
            }
            #expect(report.summary.flaky == 2)
            #expect(report.summary.failed == 2)
            #expect(report.persistentFailedTests.count == 2)

            // MARK: Test plan configurations carry through

            #expect(try test("testPasses()", plan: "Unit").metadata?["configuration"] == "English")
            #expect(try test("testPasses()", plan: "Unit").metadata?["language"] == "en")
            #expect(try test("testPasses()", plan: "Smoke").metadata?["configuration"] == "German")
            #expect(try test("testPasses()", plan: "Smoke").metadata?["language"] == "de")

            // MARK: One build, and evidence for every attempt

            let runs = try FileManager.default.contentsOfDirectory(
                at: project.appendingPathComponent("build/test-runs"), includingPropertiesForKeys: nil)
            let evidence = try #require(runs.first { $0.lastPathComponent.hasPrefix("xcode-") })
            func command(_ directory: URL) throws -> [String] {
                let object = try #require(
                    JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("command.json"))) as? [String: Any]
                )
                return try #require(object["arguments"] as? [String])
            }
            let build = try command(evidence.appendingPathComponent("build"))
            #expect(build.contains("build-for-testing"), "built once")
            let products = try #require(build.firstIndex(of: "-testProductsPath").map { build[$0 + 1] })
            var attemptDirectories: [URL] = []
            for plan in ["plan-1", "plan-2"] {
                let attempts = try FileManager.default.contentsOfDirectory(
                    at: evidence.appendingPathComponent("\(plan)/destination-1"), includingPropertiesForKeys: nil
                ).filter { $0.lastPathComponent.hasPrefix("attempt-") }
                #expect(attempts.count >= 2, "\(plan) kept each attempt")
                attemptDirectories += attempts
            }
            for directory in attemptDirectories {
                let arguments = try command(directory)
                #expect(arguments.contains("test-without-building"), "\(directory.lastPathComponent) runs without rebuilding")
                #expect(!arguments.contains("build-for-testing"))
                #expect(
                    arguments.firstIndex(of: "-testProductsPath").map { arguments[$0 + 1] } == products, "every attempt reuses the build")
                for file in ["results.xcresult", "stdout.log", "stderr.log", "results.json"] {
                    #expect(
                        FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path),
                        "\(directory.lastPathComponent)/\(file)")
                }
            }

            // MARK: Offline inspection of a real result bundle agrees with the live run

            let first = evidence.appendingPathComponent("plan-1/destination-1/attempt-1")
            let live = try JSONDecoder().decode(ParsedTestRun.self, from: Data(contentsOf: first.appendingPathComponent("results.json")))
            let inspected = try await CLI.run(
                "test-results", "--input", first.appendingPathComponent("results.xcresult").path, "--output", "json",
                workingDirectory: project, timeout: 300)
            #expect(inspected.exitCode == 0, "\(inspected.output)")
            let object = try #require(JSONSerialization.jsonObject(with: Data(inspected.stdout.utf8)) as? [String: Any])
            let parsed = try #require((object["payload"] as? [String: Any])?["parsedRun"])
            let offline = try JSONDecoder().decode(ParsedTestRun.self, from: JSONSerialization.data(withJSONObject: parsed))
            #expect(offline.runner == .xcodebuild)
            #expect(offline.destinations.map(\.platform) == [.ios])
            #expect(offline.destinations.first?.kind == .simulator)
            #expect(offline.destinations.first?.name == name, "the same device name offline as in the live report")
            #expect(offline.testCases.map(\.stableID).sorted() == live.testCases.map(\.stableID).sorted())
            for test in offline.testCases {
                let match = try #require(live.testCases.first { $0.stableID == test.stableID })
                #expect(match.status == test.status, "\(test.name): live \(match.status) vs offline \(test.status)")
            }
        }
    }
}
#endif
