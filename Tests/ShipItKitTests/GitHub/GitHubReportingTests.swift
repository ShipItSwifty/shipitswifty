import Foundation
import Testing

@testable import ShipItKit

@Suite("GitHub summary and annotations")
struct GitHubReportingTests {
    private func digest(failing: [String] = [], flaky: [String] = []) -> TestRunDigest {
        TestRunDigest(
            reports: [
                makeReport(
                    failing: failing.map { xcodeCase($0, file: "/work/App/Tests/CartTests.swift", line: 12, attempts: 3) },
                    flaky: flaky.map { xcodeCase($0, attempts: 2) })
            ])
    }

    @Test("The summary carries counts, failing and flaky tests, and the attempt timeline")
    func summarySections() {
        let markdown = GitHubSummary.markdown(
            digest(failing: ["A/B/testBroken()"], flaky: ["A/B/testSometimes()"]), artifactURL: "https://example.com/artifacts")
        #expect(markdown.contains("## ShipIt test results"))
        // A flaky test passed in the end, so it counts as passed and as flaky.
        #expect(markdown.contains("| 1 | 1 | 1 | 0 | 0 |"))
        #expect(markdown.contains("### Consistently failing"))
        #expect(markdown.contains("`A/B/testBroken()`"))
        #expect(markdown.contains("CartTests.swift:12"))
        #expect(markdown.contains("### Flaky (passed on retry)"))
        #expect(markdown.contains("### Attempts"))
        #expect(markdown.contains("failed_tests"))
        #expect(markdown.contains("[artifacts](https://example.com/artifacts)"))
    }

    @Test("A green run has no failure or flaky sections")
    func greenSummary() {
        let markdown = GitHubSummary.markdown(TestRunDigest(reports: [makeReport(passed: [xcodeCase("A/B/t()", status: .passed)])]))
        #expect(!markdown.contains("Consistently failing"))
        #expect(!markdown.contains("### Flaky"))
    }

    @Test("Table cells cannot break out of their row")
    func cellsAreEscaped() {
        let hostile = TestRunDigest(reports: [makeReport(failing: [xcodeCase("A/B/t()", message: "a | b `c`")])])
        let markdown = GitHubSummary.markdown(hostile)
        #expect(markdown.contains("a \\| b `c`"))
    }

    @Test("A broken run is called out as such")
    func runErrorBanner() {
        #expect(GitHubSummary.markdown(TestRunDigest(reports: [makeReport(errored: 1)])).contains("The run itself failed"))
    }

    @Test("Long failure lists are cut and say how many were left out")
    func rowsAreBounded() {
        let many = digest(failing: (0..<130).map { "A/B/test\($0)()" })
        #expect(GitHubSummary.markdown(many).contains("…and 30 more."))
    }

    @Test("Failing tests are errors on their file and line; flaky tests are warnings")
    func annotations() {
        let commands = GitHubAnnotations.commands(
            for: digest(failing: ["A/B/testBroken()"], flaky: ["A/B/testSometimes()"]), workspace: "/work")
        #expect(commands.count == 2)
        #expect(commands[0].hasPrefix("::error title="))
        #expect(commands[0].contains("file=App/Tests/CartTests.swift,line=12"))
        #expect(commands[0].hasSuffix("::XCTAssertEqual failed"))
        #expect(commands[1].hasPrefix("::warning title="))
    }

    @Test("A path outside the checkout is dropped so the annotation still lands on the run")
    func absolutePathOutsideWorkspace() {
        let commands = GitHubAnnotations.commands(for: digest(failing: ["A/B/t()"]), workspace: "/elsewhere")
        #expect(!commands[0].contains("file="))
        #expect(!commands[0].contains("line="))
        #expect(GitHubAnnotations.commands(for: digest(failing: ["A/B/t()"]), workspace: nil)[0].contains("file=") == false)
    }

    @Test("Workflow-command metacharacters in a message cannot start a new command")
    func escaping() {
        let hostile = TestRunDigest(reports: [makeReport(failing: [xcodeCase("A/B/t()", message: "100% bad\n::error::injected")])])
        let line = GitHubAnnotations.commands(for: hostile, workspace: nil)[0]
        #expect(!line.contains("\n"))
        #expect(line.contains("100%25 bad"))
        #expect(GitHubAnnotations.escapeProperty("a:b,c") == "a%3Ab%2Cc")
    }

    @Test("At most ten errors and ten warnings are annotated, and the rest are noted once")
    func annotationLimit() {
        let big = TestRunDigest(
            reports: [
                makeReport(
                    failing: (0..<14).map { xcodeCase("A/B/fail\($0)()") },
                    flaky: (0..<12).map { xcodeCase("A/B/flaky\($0)()", attempts: 2) })
            ])
        let commands = GitHubAnnotations.commands(for: big, workspace: nil)
        #expect(commands.filter { $0.hasPrefix("::error") }.count == 10)
        #expect(commands.filter { $0.hasPrefix("::warning") }.count == 10)
        #expect(commands.filter { $0.hasPrefix("::notice") }.count == 2)
    }

    @Test("A broken run is annotated even with no failing test")
    func runErrorAnnotation() {
        let commands = GitHubAnnotations.commands(for: TestRunDigest(reports: [makeReport(errored: 1)]), workspace: nil)
        #expect(commands.count == 1)
        #expect(commands[0].contains("ShipIt test run failed"))
    }
}
