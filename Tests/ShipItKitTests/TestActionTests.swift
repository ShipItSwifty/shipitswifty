import Foundation
import Testing
import SwiftyShell
@testable import ShipItKit

@Suite("TestAction")
struct TestActionTests {

    @Test("TestAction parses executed test count and forwards result bundle path")
    func parsesSuccessfulOutput() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(
                stdout: "Executed 5 tests, with 0 failures (0 unexpected) in 1.234 (1.567) seconds\n",
                stderr: "",
                exitCode: 0
            )
        }
        let context = ActionContext.mock(executor: executor)

        let result = try await TestAction().run(
            with: .init(scheme: "MockApp", resultBundlePath: "/tmp/Test.xcresult"),
            context: context
        )

        #expect(result.passCount == 5)
        #expect(result.failCount == 0)
        #expect(result.resultBundlePath == "/tmp/Test.xcresult")
    }

    @Test("TestAction parses failure count from failed test output")
    func parsesFailureCount() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(
                stdout: "** TEST FAILED ** (3 failures)\n",
                stderr: "",
                exitCode: 65
            )
        }
        let context = ActionContext.mock(executor: executor)

        do {
            _ = try await TestAction().run(with: .init(scheme: "MockApp"), context: context)
            Issue.record("Expected TestAction to throw")
        } catch let error as ShipItError {
            guard case .testFailed(let exitCode, let failureCount, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(exitCode == 65)
            #expect(failureCount == 3)
        }
    }

    @Test("TestAction includes code coverage and test plan options")
    func emitsCoverageAndTestPlanFlags() async throws {
        nonisolated(unsafe) var capturedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            capturedCommands.append(command.description)
            return ShellOutput(stdout: "Executed 1 test, with 0 failures\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        _ = try await TestAction().run(
            with: .init(
                scheme: "MockApp",
                enableCodeCoverage: true,
                resultBundlePath: "/tmp/Tests.xcresult",
                testPlan: "Smoke"
            ),
            context: context
        )

        let command = capturedCommands.first ?? ""
        #expect(command.contains("-enableCodeCoverage YES"))
        #expect(command.contains("-resultBundlePath /tmp/Tests.xcresult"))
        #expect(command.contains("-testPlan Smoke"))
    }
}
