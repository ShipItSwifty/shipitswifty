import Testing

@testable import ShipItCLI
@testable import ShipItKit

@Suite("CLI TestResults")
struct TestResultsCommandTests {

    @Test("Test-results command parses iOS options")
    func parsesIOSOptions() throws {
        let command =
            try TestResultsCommand.parseAsRoot([
                "--xcresult", "./build/MyApp-tests.xcresult",
                "--report-path", "./artifacts/report.json",
                "--format", "markdown",
            ]) as! TestResultsCommand

        #expect(command.xcresultPath == "./build/MyApp-tests.xcresult")
        #expect(command.reportPath == "./artifacts/report.json")
        #expect(command.format == "markdown")
    }

    @Test("Test-results command parses Android options")
    func parsesAndroidOptions() throws {
        let command =
            try TestResultsCommand.parseAsRoot([
                "--platform", "android",
                "--report", "./app/build/test-results/testDebugUnitTest",
                "--failed-only",
                "--exclude-passed",
            ]) as! TestResultsCommand

        #expect(command.global.platform == .android)
        #expect(command.report == "./app/build/test-results/testDebugUnitTest")
        #expect(command.failedOnly)
        #expect(command.excludePassed)
    }

    @Test("Test-results rejects conflicting artifact options")
    func rejectsConflictingArtifacts() {
        #expect(throws: Error.self) {
            try TestResultsCommand.parseAsRoot([
                "--xcresult", "./Tests.xcresult",
                "--report", "./build/test-results",
            ])
        }
    }

    @Test("Test-results rejects artifact and platform conflicts")
    func rejectsArtifactPlatformConflict() {
        #expect(throws: Error.self) {
            try TestResultsCommand.parseAsRoot([
                "--platform", "android",
                "--xcresult", "./Tests.xcresult",
            ])
        }
    }

    @Test("Test-results rejects unknown formats")
    func rejectsUnknownFormat() {
        #expect(throws: Error.self) {
            try TestResultsCommand.parseAsRoot(["--format", "xml"])
        }
    }

    @Test("Test-results rejects non-JSON format with global JSON output")
    func rejectsConflictingOutputFormats() {
        #expect(throws: Error.self) {
            try TestResultsCommand.parseAsRoot([
                "--output", "json",
                "--format", "markdown",
            ])
        }
    }
}
