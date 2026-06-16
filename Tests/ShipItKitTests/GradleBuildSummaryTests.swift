import Testing

@testable import ShipItKit

@Suite("GradleBuildSummary.parse")
struct GradleBuildSummaryTests {

    @Test("parses a full Gradle tail: result, actionable tasks, and scan URL")
    func parsesFullSummary() {
        let stdout = """
            > Task :app:bundleRelease

            Deprecated Gradle features were used in this build.

            Publishing build scan...
            https://gradle.com/s/abc123xyz

            BUILD SUCCESSFUL in 2m 13s
            42 actionable tasks: 30 executed, 10 from cache, 2 up-to-date
            """

        let summary = GradleBuildSummary.parse(stdout)

        #expect(summary.buildResultLine == "BUILD SUCCESSFUL in 2m 13s")
        #expect(summary.actionableTasksLine == "42 actionable tasks: 30 executed, 10 from cache, 2 up-to-date")
        #expect(summary.buildScanURL == "https://gradle.com/s/abc123xyz")
        #expect(!summary.isEmpty)
    }

    @Test("returns empty summary when no recognizable lines are present")
    func parsesAbsentSummary() {
        let stdout = """
            > Configure project :app
            > Task :app:preBuild UP-TO-DATE
            Some unrelated log output
            """

        let summary = GradleBuildSummary.parse(stdout)

        #expect(summary.buildResultLine == nil)
        #expect(summary.actionableTasksLine == nil)
        #expect(summary.buildScanURL == nil)
        #expect(summary.isEmpty)
    }

    @Test("parses result + tasks without a scan URL")
    func parsesWithoutScanURL() {
        let stdout = """
            BUILD SUCCESSFUL in 47s
            5 actionable tasks: 5 executed
            """

        let summary = GradleBuildSummary.parse(stdout)

        #expect(summary.buildResultLine == "BUILD SUCCESSFUL in 47s")
        #expect(summary.actionableTasksLine == "5 actionable tasks: 5 executed")
        #expect(summary.buildScanURL == nil)
    }

    @Test("matches the singular 'actionable task' phrasing")
    func parsesSingularActionableTask() {
        let stdout = """
            BUILD SUCCESSFUL in 1s
            1 actionable task: 1 up-to-date
            """

        let summary = GradleBuildSummary.parse(stdout)

        #expect(summary.actionableTasksLine == "1 actionable task: 1 up-to-date")
    }

    @Test("trims surrounding whitespace from parsed lines")
    func trimsWhitespace() {
        let stdout = "   BUILD SUCCESSFUL in 10s   \n   8 actionable tasks: 8 from cache   "

        let summary = GradleBuildSummary.parse(stdout)

        #expect(summary.buildResultLine == "BUILD SUCCESSFUL in 10s")
        #expect(summary.actionableTasksLine == "8 actionable tasks: 8 from cache")
    }

    @Test("empty stdout yields an empty summary, never throws")
    func parsesEmptyStdout() {
        let summary = GradleBuildSummary.parse("")
        #expect(summary.isEmpty)
    }
}
