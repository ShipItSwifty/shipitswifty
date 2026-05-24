import Foundation
import Testing

@testable import ShipItKit

@Suite("TestResults models")
struct TestResultModelsTests {

    @Test("ParsedTestRun round-trips through JSON")
    func parsedTestRunRoundTrips() throws {
        let run = ParsedTestRun(
            platform: "ios",
            runner: "xcodebuild",
            source: "/tmp/Tests.xcresult",
            summary: TestSummary(passed: 8, failed: 1, skipped: 1),
            suites: [
                ParsedTestSuite(
                    name: "MyAppTests/LoginTests",
                    stableID: "suite:login",
                    file: "LoginTests.swift",
                    testCaseIDs: ["case:login-success"]
                )
            ],
            testCases: [
                ParsedTestCase(
                    stableID: "case:login-success",
                    suite: "MyAppTests/LoginTests",
                    name: "testLoginSuccess",
                    status: .failed,
                    durationSeconds: 1.25,
                    message: "Expected status 200",
                    file: "LoginTests.swift",
                    line: 42,
                    rerunSelector: .xcodeOnlyTesting("MyAppTests/LoginTests/testLoginSuccess")
                )
            ],
            diagnostics: [
                ParsingDiagnostic(
                    severity: .warning,
                    message: "Attachment payload skipped",
                    source: "actionTestSummary"
                )
            ]
        )

        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(ParsedTestRun.self, from: data)

        #expect(decoded.platform == "ios")
        #expect(decoded.runner == "xcodebuild")
        #expect(decoded.summary.failed == 1)
        #expect(decoded.suites.first?.testCaseIDs == ["case:login-success"])
        #expect(decoded.testCases.first?.rerunSelector == .xcodeOnlyTesting("MyAppTests/LoginTests/testLoginSuccess"))
        #expect(decoded.diagnostics.first?.severity == .warning)
    }

    @Test("TestRunReport captures attempts and classifications")
    func testRunReportEncodesAttempts() throws {
        let failedTest = ParsedTestCase(
            stableID: "case:checkout-failure",
            suite: "CheckoutTests",
            name: "testCheckoutFailure",
            status: .failed,
            rerunSelector: .gradleTestFilter("com.example.CheckoutTests.testCheckoutFailure")
        )

        let report = TestRunReport(
            platform: "android",
            runner: "gradle",
            source: "app/build/test-results/testDebugUnitTest",
            attempts: [
                TestAttempt(
                    attemptNumber: 1,
                    summary: TestSummary(passed: 12, failed: 1),
                    failedTests: [failedTest],
                    durationSeconds: 8.4,
                    source: "attempt-1"
                ),
                TestAttempt(
                    attemptNumber: 2,
                    summary: TestSummary(passed: 13, failed: 0, flaky: 1),
                    failedTests: [],
                    durationSeconds: 2.1,
                    source: "attempt-2"
                ),
            ],
            initialFailedTests: [failedTest],
            flakyTests: [failedTest],
            persistentFailedTests: [],
            summary: TestSummary(passed: 13, failed: 0, flaky: 1),
            generatedAt: Date(timeIntervalSince1970: 1_735_000_000)
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(TestRunReport.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.attempts.count == 2)
        #expect(decoded.flakyTests == [failedTest])
        #expect(decoded.persistentFailedTests.isEmpty)
        #expect(decoded.summary.flaky == 1)
    }

    @Test("TestParseContext and TestArtifact round-trip through JSON")
    func locatorTypesRoundTrip() throws {
        let context = TestParseContext(platform: "ios", runner: "xcodebuild", preferredSources: ["./build"])
        let artifact = TestArtifact(kind: .xcresult, path: "./build/MyApp-tests.xcresult", platform: "ios", runner: "xcodebuild")

        let encodedContext = try JSONEncoder().encode(context)
        let encodedArtifact = try JSONEncoder().encode(artifact)

        #expect(try JSONDecoder().decode(TestParseContext.self, from: encodedContext) == context)
        #expect(try JSONDecoder().decode(TestArtifact.self, from: encodedArtifact) == artifact)
    }
}
