import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("TestResultsAction")
struct TestResultsActionTests {

    @Test("Parses iOS xcresult artifacts through the action and writes a report")
    func parsesIOSArtifactsAndWritesReport() async throws {
        let summaryJSON = """
            { "metrics": { "testsCount": 2, "testsFailedCount": 1, "testsSkippedCount": 0 } }
            """
        let testsJSON = """
            {
              "subtests": [
                {
                  "name": "MyAppTests/LoginTests",
                  "subtests": [
                    { "identifier": "MyAppTests/LoginTests/testHappyPath()", "name": "testHappyPath()", "testStatus": "Success" },
                    { "identifier": "MyAppTests/LoginTests/testFailure()", "name": "testFailure()", "testStatus": "Failure" }
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

        let temp = try makeTempDirectory(prefix: "TestResultsAction")
        defer { try? FileManager.default.removeItem(at: temp) }

        let reportPath = temp.appendingPathComponent("report.json").path
        let context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(platform: .ios),
            platform: .ios
        )

        let result = try await TestResultsAction().run(
            with: .init(xcresultPath: "/tmp/MyApp-tests.xcresult", reportOutputPath: reportPath),
            context: context
        )

        #expect(result.parsedRun.summary.failed == 1)
        #expect(result.report.persistentFailedTests.count == 1)
        #expect(FileManager.default.fileExists(atPath: reportPath))
    }

    @Test("Filters down to failed tests only")
    func filtersFailedOnly() async throws {
        let root = try makeTempDirectory(prefix: "TestResultsActionAndroid")
        defer { try? FileManager.default.removeItem(at: root) }

        let reportDirectory = root.appendingPathComponent("app/build/test-results/testReleaseUnitTest", isDirectory: true)
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <testsuite name="com.example.CheckoutTests" tests="2" skipped="0" failures="1" errors="0">
              <testcase name="testHappyPath" classname="com.example.CheckoutTests"/>
              <testcase name="testFailure" classname="com.example.CheckoutTests"><failure message="boom"/></testcase>
            </testsuite>
            """
        try xml.write(to: reportDirectory.appendingPathComponent("TEST-com.example.CheckoutTests.xml"), atomically: true, encoding: .utf8)

        let context = makeTestActionContext(
            executor: MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
            config: ResolvedConfig(platform: .android),
            platform: .android
        )

        let result = try await TestResultsAction().run(
            with: .init(platform: "android", reportPath: reportDirectory.path, failedOnly: true),
            context: context
        )

        #expect(result.parsedRun.testCases.count == 1)
        #expect(result.parsedRun.testCases.first?.name == "testFailure")
        #expect(result.report.initialFailedTests.count == 1)
    }
}
