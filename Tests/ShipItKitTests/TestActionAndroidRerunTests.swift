import Foundation
import SwiftyShell
import Synchronization
import Testing

@testable import ShipItKit

/// Android unit-test reruns, exercised with realistic Gradle behaviour: a run with failing tests
/// exits non-zero. (The macOS-only suite in `TestActionTests` mocks exit code 0, which masked the
/// fact that a real failure threw before the rerun could start.)
@Suite("TestAction — Android failed-test reruns")
struct TestActionAndroidRerunTests {

    private static let failingOutput = """
        com.example.FeatureTests > testHappyPath PASSED
        com.example.FeatureTests > testOfflineMode FAILED
        2 tests completed, 1 failed, 0 skipped
        FAILURE: Build failed with an exception.
        """

    private func makeContext(executor: MockExecutor, projectDir: String) -> ActionContext {
        let config = ResolvedConfig(
            platform: .android,
            androidModule: "app",
            androidBuildVariant: "debug",
            gradleProjectDir: projectDir
        )
        return makeTestActionContext(executor: executor, config: config, platform: .android)
    }

    private func rerunOptions(reportPath: String? = nil, enabled: Bool = true) -> TestAction.Options {
        .init(
            rerunFailedTests: .init(enabled: enabled, maxAttempts: 2),
            reportPath: reportPath,
            kind: .unit
        )
    }

    @Test("A failed Gradle run is re-run with --tests after the task, and flaky tests pass the action")
    func flakyFailureIsRerunAndPasses() async throws {
        let tempDirectory = try makeTempDirectory(prefix: "AndroidRerunFlaky")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let reportPath = tempDirectory.appendingPathComponent("report.json").path

        let (executor, commands) = makeCaptureExecutor { command, _ in
            if command.description.contains("--tests") {
                return ShellOutput(stdout: "1 tests completed, 0 failed, 0 skipped\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: Self.failingOutput, stderr: "", exitCode: 1)
        }

        let result = try await TestAction().run(
            with: rerunOptions(reportPath: reportPath),
            context: makeContext(executor: executor, projectDir: tempDirectory.path)
        )

        #expect(result.failCount == 0)
        #expect(result.report?.flakyTests.count == 1)
        #expect(result.report?.attempts.count == 2)
        #expect(FileManager.default.fileExists(atPath: reportPath))

        let rerun = try #require(commands().first { $0.contains("--tests") })
        // `--tests` is a task option and must follow the task, with `Class > method` normalized.
        #expect(rerun.contains(":app:testDebugUnitTest --tests com.example.FeatureTests.testOfflineMode"))
    }

    @Test("Failures that persist after the rerun still fail the action and write the report")
    func persistentFailureThrows() async throws {
        let tempDirectory = try makeTempDirectory(prefix: "AndroidRerunPersistent")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let reportPath = tempDirectory.appendingPathComponent("report.json").path

        let (executor, commands) = makeCaptureExecutor { command, _ in
            if command.description.contains("--tests") {
                return ShellOutput(
                    stdout: "com.example.FeatureTests > testOfflineMode FAILED\n1 tests completed, 1 failed, 0 skipped\n",
                    stderr: "",
                    exitCode: 1
                )
            }
            return ShellOutput(stdout: Self.failingOutput, stderr: "", exitCode: 1)
        }

        await #expect {
            try await TestAction().run(
                with: rerunOptions(reportPath: reportPath),
                context: makeContext(executor: executor, projectDir: tempDirectory.path)
            )
        } throws: { error in
            guard case ShipItError.testFailed(_, let failureCount, _) = error else { return false }
            return failureCount == 1
        }

        #expect(commands().filter { $0.contains("testDebugUnitTest") }.count == 2)
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
        #expect(report.persistentFailedTests.count == 1)
        #expect(report.flakyTests.isEmpty)
    }

    @Test("Without reruns a failed Gradle run throws immediately")
    func rerunDisabledThrows() async throws {
        let tempDirectory = try makeTempDirectory(prefix: "AndroidRerunDisabled")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: Self.failingOutput, stderr: "", exitCode: 1)
        }

        await #expect(throws: ShipItError.self) {
            try await TestAction().run(
                with: rerunOptions(enabled: false),
                context: makeContext(executor: executor, projectDir: tempDirectory.path)
            )
        }
        #expect(!commands().contains { $0.contains("--tests") })
    }

    @Test("A failure that names no tests (e.g. compilation) is not re-run")
    func nonTestFailureIsNotRerun() async throws {
        let tempDirectory = try makeTempDirectory(prefix: "AndroidRerunCompile")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "e: Unresolved reference: foo\nFAILURE: Build failed", exitCode: 1)
        }

        await #expect(throws: ShipItError.self) {
            try await TestAction().run(
                with: rerunOptions(),
                context: makeContext(executor: executor, projectDir: tempDirectory.path)
            )
        }
        #expect(!commands().contains { $0.contains("--tests") })
    }

    @Test("JUnit XML reports supply fully-qualified rerun filters")
    func junitReportsDriveRerunFilters() async throws {
        let tempDirectory = try makeTempDirectory(prefix: "AndroidRerunJUnit")
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let reportDirectory = tempDirectory.appendingPathComponent("app/build/test-results/testDebugUnitTest")
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuite name="com.example.FeatureTests" tests="2" skipped="0" failures="1" errors="0">
          <testcase name="testHappyPath()" classname="com.example.FeatureTests" time="0.01"/>
          <testcase name="testOfflineMode()" classname="com.example.FeatureTests" time="0.02">
            <failure message="boom">java.lang.AssertionError</failure>
          </testcase>
        </testsuite>
        """.write(to: reportDirectory.appendingPathComponent("TEST-com.example.FeatureTests.xml"), atomically: true, encoding: .utf8)

        let (executor, commands) = makeCaptureExecutor { command, _ in
            if command.description.contains("--tests") {
                try """
                <testsuite tests="1" failures="0" errors="0" skipped="0"><testcase name="testOfflineMode()" classname="com.example.FeatureTests"/></testsuite>
                """.write(
                    to: reportDirectory.appendingPathComponent("TEST-com.example.FeatureTests.xml"), atomically: true, encoding: .utf8)

                return ShellOutput(stdout: "1 tests completed, 0 failed, 0 skipped\n", stderr: "", exitCode: 0)
            }
            // Console output without per-test lines: only the XML names the failed test.
            return ShellOutput(stdout: "2 tests completed, 1 failed\n", stderr: "", exitCode: 1)
        }

        let result = try await TestAction().run(
            with: rerunOptions(),
            context: makeContext(executor: executor, projectDir: tempDirectory.path)
        )

        #expect(result.failCount == 0)
        #expect(commands().contains { $0.contains("--tests com.example.FeatureTests.testOfflineMode") && !$0.contains("()") })
    }
    @Test("A new failure on rerun cannot turn two nonzero exits into success")
    func changedFailureStillThrows() async throws {
        let directory = try makeTempDirectory(prefix: "AndroidChangedFailure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let reportPath = directory.appendingPathComponent("report.json").path
        let (executor, _) = makeCaptureExecutor { command, _ in
            let name = command.description.contains("--tests") ? "initializationError" : "testOfflineMode"
            return ShellOutput(
                stdout: "com.example.FeatureTests > \(name) FAILED\n1 tests completed, 1 failed, 0 skipped\n", stderr: "", exitCode: 1)
        }
        await #expect(throws: ShipItError.self) {
            try await TestAction().run(
                with: rerunOptions(reportPath: reportPath), context: makeContext(executor: executor, projectDir: directory.path))
        }
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
        #expect(report.flakyTests.isEmpty)
        #expect(report.persistentFailedTests.contains { $0.name.contains("initializationError") })
    }

    @Test("A skipped rerun does not resolve an initial failure")
    func skippedRerunStillThrows() async throws {
        let directory = try makeTempDirectory(prefix: "AndroidSkippedRerun")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (executor, _) = makeCaptureExecutor { command, _ in
            if command.description.contains("--tests") {
                return ShellOutput(stdout: "1 tests completed, 0 failed, 1 skipped\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: Self.failingOutput, stderr: "", exitCode: 1)
        }
        await #expect(throws: ShipItError.self) {
            try await TestAction().run(with: rerunOptions(), context: makeContext(executor: executor, projectDir: directory.path))
        }
    }

    @Test(
        "Root reruns include failures from every module; module reruns exclude unrelated reports",
        arguments: [GradleTaskScope.root, .module])
    func reportDiscoveryRespectsScope(scope: GradleTaskScope) async throws {
        let directory = try makeTempDirectory(prefix: "AndroidReportScope")
        defer { try? FileManager.default.removeItem(at: directory) }
        for module in ["app", "feature"] {
            let reports = directory.appendingPathComponent("\(module)/build/test-results/testDebugUnitTest")
            try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
            try """
            <testsuite name="\(module).Tests" tests="1" failures="1" errors="0" skipped="0"><testcase classname="\(module).Tests" name="testFailure"><failure message="failure"/></testcase></testsuite>
            """.write(to: reports.appendingPathComponent("TEST-example.xml"), atomically: true, encoding: .utf8)
        }
        let (executor, commands) = makeCaptureExecutor { command, _ in
            if command.description.contains("--tests") {
                for module in ["app", "feature"] {
                    try """
                    <testsuite tests="1" failures="0" errors="0" skipped="0"><testcase classname="\(module).Tests" name="testFailure"/></testsuite>
                    """.write(
                        to: directory.appendingPathComponent("\(module)/build/test-results/testDebugUnitTest/TEST-example.xml"),
                        atomically: true, encoding: .utf8)
                }

                return ShellOutput(stdout: "2 tests completed, 0 failed, 0 skipped\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "2 tests completed, 2 failed, 0 skipped\n", stderr: "", exitCode: 1)
        }
        var options = rerunOptions()
        options.scope = scope
        let result = try await TestAction().run(with: options, context: makeContext(executor: executor, projectDir: directory.path))
        let rerun = try #require(commands().first { $0.contains("--tests") })
        #expect(rerun.contains("--tests app.Tests.testFailure"))
        #expect(rerun.contains("--tests feature.Tests.testFailure") == (scope == .root))
        #expect(result.report?.initialFailedTests.count == (scope == .root ? 2 : 1))
        #expect(result.failCount == 0)
        if scope == .root { #expect(rerun.contains("--continue")) }
    }

    @Test("Gradle summaries parse totals, optional fields, and multiple modules")
    func parsesGradleSummaries() {
        let action = TestAction()
        let counts = action.parseGradleCounts(from: "12 tests completed, 2 failed, 1 skipped\n3 tests completed, 1 failed\n")
        #expect(counts.pass == 11)
        #expect(counts.fail == 3)
        #expect(counts.skip == 1)
        let passed = action.parseGradleCounts(from: "1 test completed\n")
        #expect(passed.pass == 1)
        #expect(passed.fail == 0)
        let skipped = action.parseGradleCounts(from: "2 tests completed, 1 skipped\n")
        #expect(skipped.pass == 1)
        #expect(skipped.skip == 1)
        #expect(action.parseGradleCounts(from: "BUILD SUCCESSFUL").pass == 0)
    }

    @Test("Android honors the attempt limit and stops after recovery", arguments: [1, 2, 3, 4])
    func respectsAttemptLimit(maxAttempts: Int) async throws {
        let directory = try makeTempDirectory(prefix: "AndroidAttemptLimit")
        defer { try? FileManager.default.removeItem(at: directory) }
        let attempt = Mutex(0)
        let (executor, commands) = makeCaptureExecutor { _, _ in
            let current = attempt.withLock {
                $0 += 1
                return $0
            }
            if current >= 3 {
                return ShellOutput(stdout: "1 tests completed, 0 failed, 0 skipped\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: Self.failingOutput, stderr: "", exitCode: 1)
        }
        var options = rerunOptions()
        options.rerunFailedTests = .init(enabled: true, maxAttempts: maxAttempts)
        let context = makeContext(executor: executor, projectDir: directory.path)
        if maxAttempts < 3 {
            await #expect(throws: ShipItError.self) { try await TestAction().run(with: options, context: context) }
        } else {
            let result = try await TestAction().run(with: options, context: context)
            #expect(result.passCount == 2)
            #expect(result.failCount == 0)
            #expect(result.report?.attempts.map(\.attemptNumber) == [1, 2, 3])
            #expect(result.report?.flakyTests.count == 1)
        }
        #expect(commands().filter { $0.contains("testDebugUnitTest") }.count == min(maxAttempts, 3))
    }

    @Test("Android persistent failures exhaust all configured attempts")
    func persistentFailureExhaustsAttempts() async throws {
        let directory = try makeTempDirectory(prefix: "AndroidExhaustAttempts")
        defer { try? FileManager.default.removeItem(at: directory) }
        let reportPath = directory.appendingPathComponent("report.json").path
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: Self.failingOutput, stderr: "", exitCode: 1)
        }
        var options = rerunOptions(reportPath: reportPath)
        options.rerunFailedTests = .init(enabled: true, maxAttempts: 4)
        await #expect(throws: ShipItError.self) {
            try await TestAction().run(with: options, context: makeContext(executor: executor, projectDir: directory.path))
        }
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
        #expect(report.attempts.map(\.attemptNumber) == [1, 2, 3, 4])
        #expect(report.flakyTests.isEmpty)
        #expect(commands().filter { $0.contains("testDebugUnitTest") }.count == 4)
    }

}
