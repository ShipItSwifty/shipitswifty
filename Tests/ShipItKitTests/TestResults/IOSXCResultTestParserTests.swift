#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("IOSXCResultTestParser")
struct IOSXCResultTestParserTests {

    @Test("Parses xcresulttool summary and tests JSON into normalized test cases")
    func parsesXCResultToolJSON() async throws {
        let summaryJSON = """
            {
              "metrics": {
                "testsCount": 3,
                "testsFailedCount": 1,
                "testsSkippedCount": 1
              }
            }
            """

        let testsJSON = """
            {
              "name": "Root",
              "subtests": [
                {
                  "name": "MyAppTests/LoginTests",
                  "subtests": [
                    {
                      "identifier": "MyAppTests/LoginTests/testSuccessfulLogin()",
                      "name": "testSuccessfulLogin()",
                      "testStatus": "Success",
                      "duration": 0.5
                    },
                    {
                      "identifier": "MyAppTests/LoginTests/testFailedLogin()",
                      "name": "testFailedLogin()",
                      "testStatus": "Failure",
                      "duration": 0.7,
                      "failureText": "XCTAssertEqual failed"
                    },
                    {
                      "identifier": "MyAppTests/LoginTests/testLegacyLogin()",
                      "name": "testLegacyLogin()",
                      "testStatus": "Skipped"
                    }
                  ]
                }
              ]
            }
            """

        let executor = MockExecutor { command, _ in
            let description = command.description
            if description.contains("xcresulttool get test-results summary") {
                return ShellOutput(stdout: summaryJSON, stderr: "", exitCode: 0)
            }
            if description.contains("xcresulttool get test-results tests") {
                return ShellOutput(stdout: testsJSON, stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "unexpected command", exitCode: 1)
        }
        let shell = ShellContext(executor: executor)
        let parser = IOSXCResultTestParser(shell: shell)

        let run = try await parser.parse(xcresultPath: "/tmp/MyApp-tests.xcresult")

        #expect(run.platform == "ios")
        #expect(run.runner == "xcodebuild")
        #expect(run.summary.passed == 1)
        #expect(run.summary.failed == 1)
        #expect(run.summary.skipped == 1)
        #expect(run.testCases.count == 3)
        #expect(run.testCases.first(where: { $0.name == "testFailedLogin()" })?.rerunSelector == .xcodeOnlyTesting("MyAppTests/LoginTests/testFailedLogin()"))
    }

    @Test("Surfaces xcresulttool failures as invalid configuration")
    func surfacesXCResultToolFailures() async throws {
        let executor = MockExecutor { _, _ in
            throw ShellError.exitFailure(
                command: "xcrun xcresulttool",
                output: ShellOutput(stdout: "", stderr: "bundle not found", exitCode: 64)
            )
        }
        let parser = IOSXCResultTestParser(shell: ShellContext(executor: executor))

        do {
            _ = try await parser.parse(xcresultPath: "/tmp/missing.xcresult")
            Issue.record("Expected IOSXCResultTestParser to throw")
        } catch let error as ShipItError {
            guard case .invalidConfiguration = error else {
                Issue.record("Expected invalidConfiguration, got \(error)")
                return
            }
        }
    }
}
#endif
