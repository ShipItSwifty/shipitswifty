import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("LintAction — Flutter and React Native")
struct LintActionFlutterTests {

    @Test("Flutter lint runs flutter analyze")
    func flutterLintRunsAnalyze() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "No issues found!\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        let result = try await LintAction().run(with: LintAction.Options(), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("flutter") && $0.contains("analyze") })
        #expect(result.issueCount == 0)
        #expect(result.exitCode == 0)
    }

    @Test("Flutter lint returns issue count from flutter analyze output")
    func flutterLintCountsIssues() async throws {
        let analyzeOutput = """
        Analyzing my_app...
          • Avoid using print. Try using a Logger instead.
          • Prefer single quotes.
        2 issues found.
        """
        let (executor, _) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: analyzeOutput, stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        let result = try await LintAction().run(with: LintAction.Options(), context: context)
        #expect(result.issueCount == 2)
    }

    @Test("React Native lint runs package manager lint script")
    func rnLintRunsPackageManagerScript() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNLintAction")
        let packageJSON = """
        {
          "name": "my-app",
          "scripts": {
            "lint": "eslint src/"
          }
        }
        """
        try packageJSON.write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        _ = try await LintAction().run(with: LintAction.Options(), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("run") && $0.contains("lint") })
    }

    @Test("React Native lint throws when lint script missing and failOnError is true")
    func rnLintThrowsWhenScriptMissing() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNLintNoScript")
        let packageJSON = """
        {"name": "my-app", "scripts": {}}
        """
        try packageJSON.write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        await #expect {
            _ = try await LintAction().run(with: LintAction.Options(failOnError: true), context: context)
        } throws: { error in
            if case ShipItError.invalidConfiguration = error { return true }
            if case ShipItError.buildFailed = error { return true }
            return false
        }
    }

    @Test("React Native lint still throws unexpected errors when failOnError is false")
    func rnLintDoesNotSwallowUnexpectedErrors() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNLintUnexpectedError")
        let packageJSON = """
        {"name": "my-app", "scripts": {"lint": "eslint src/"}}
        """
        try packageJSON.write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        struct UnexpectedError: Error {}

        let executor = MockExecutor { _, _ in throw UnexpectedError() }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        await #expect {
            _ = try await LintAction().run(with: LintAction.Options(failOnError: false), context: context)
        } throws: { error in
            error is UnexpectedError
        }
    }
}
