import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("TestAction — Flutter and React Native")
struct TestActionFlutterTests {

    @Test("Flutter test runs flutter test command")
    func flutterTestRunsFlutterTest() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "00:01 +12: All tests passed!\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        let result = try await TestAction().run(with: TestAction.Options(), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("flutter") && $0.contains("test") })
        #expect(result.passCount == 12)
        #expect(result.failCount == 0)
    }

    @Test("Flutter test failure propagates test counts")
    func flutterTestFailurePropagatesCounts() async throws {
        let (executor, _) = makeCaptureExecutor { _, _ in
            throw ShellError.exitFailure(
                command: "flutter", output: ShellOutput(stdout: "00:02 +11 -2: Some tests failed.\n", stderr: "", exitCode: 1))
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        await #expect {
            _ = try await TestAction().run(with: TestAction.Options(), context: context)
        } throws: { error in
            guard case ShipItError.testFailed(_, let count, _) = error else { return false }
            return count == 2
        }
    }

    @Test("Flutter parser handles elapsed-time prefixes and skips")
    func flutterParserHandlesRealOutputPrefixes() {
        let counts = TestAction.parseFlutterTestCountsForTesting(
            from: "00:01 +10 ~1: some tests skipped\n00:02 +12 ~2: All tests passed!\n"
        )

        #expect(counts.pass == 12)
        #expect(counts.fail == 0)
        #expect(counts.skip == 2)
    }

    @Test("Jest parser handles comma-stripped summary tokens")
    func jestParserHandlesSummaryTokens() {
        let counts = TestAction.parseJSTestCountsForTesting(
            from: "Tests:       1 failed, 2 skipped, 12 passed, 15 total\n"
        )

        #expect(counts.pass == 12)
        #expect(counts.fail == 1)
        #expect(counts.skip == 2)
    }

    @Test("React Native test runs package manager test script")
    func rnTestRunsPackageManagerScript() async throws {
        // Create a temporary package.json with a test script
        let tempDir = try makeTempDirectory(prefix: "RNTestAction")
        let packageJSON = """
            {
              "name": "my-app",
              "scripts": {
                "test": "jest --passWithNoTests",
                "lint": "eslint ."
              }
            }
            """
        try packageJSON.write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(
                stdout: "Tests: 5 passed, 5 total\n",
                stderr: "",
                exitCode: 0
            )
        }
        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        let result = try await TestAction().run(with: TestAction.Options(), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("npm") || $0.contains("yarn") || $0.contains("pnpm") })
        #expect(captured.contains { $0.contains("run") && $0.contains("test") })
        #expect(result.passCount == 5)
    }

    @Test("React Native test throws invalidConfiguration when test script is missing")
    func rnTestThrowsWhenScriptMissing() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNTestNoScript")
        let packageJSON = """
            {
              "name": "my-app",
              "scripts": {}
            }
            """
        try packageJSON.write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        await #expect {
            _ = try await TestAction().run(with: TestAction.Options(), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("test")
        }
    }
}
