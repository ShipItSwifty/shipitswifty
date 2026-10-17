import Foundation
import Testing

@testable import ShipItKit

@Suite("GitHub issue sync")
struct GitHubIssueSyncTests {
    private let broken = "AppTests/CartTests/testBroken()"
    private let sometimes = "AppTests/CartTests/testSometimes()"

    private func failing(_ message: String? = "XCTAssertEqual failed") -> TestRunDigest {
        TestRunDigest(reports: [makeReport(failing: [xcodeCase(broken, message: message, attempts: 3)])])
    }

    private func clean() -> TestRunDigest {
        TestRunDigest(reports: [makeReport(passed: [xcodeCase(broken, status: .passed)])])
    }

    private func flaky() -> TestRunDigest {
        TestRunDigest(reports: [makeReport(flaky: [xcodeCase(sometimes, attempts: 2)])])
    }

    private func sync(
        _ digest: TestRunDigest, on api: FakeGitHubIssues, run: String, closeAfter: Int = 3, dryRun: Bool = false
    ) async throws -> [IssueSyncAction] {
        try await GitHubIssueSync(
            api: api,
            configuration: IssueSyncConfiguration(
                extraLabels: ["ci"], closeAfterCleanRuns: closeAfter, runID: run, runURL: "https://github.com/o/r/actions/runs/\(run)",
                artifactURL: "https://github.com/o/r/actions/runs/\(run)/artifacts/1", branch: "main"),
            dryRun: dryRun
        ).sync(digest)
    }

    @Test("The first failure files one issue with the managed and extra labels")
    func filesIssue() async throws {
        let api = FakeGitHubIssues()
        let actions = try await sync(failing(), on: api, run: "100")
        #expect(actions.map(\.kind) == [.created])
        let issue = try #require(await api.issues.first)
        #expect(issue.title == "Test failing: \(broken)")
        #expect(await api.labels(of: issue.number) == [IssueSyncConfiguration.failureLabel, "ci"])
        #expect(issue.body.contains("fingerprint="))
        #expect(issue.body.contains("https://github.com/o/r/actions/runs/100"))
        #expect(issue.body.contains("[artifacts]"))
    }

    @Test("An issue holds ids and links only: no failure message, no stack trace")
    func issueLeaksNothing() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing("token=SECRET-123 account=jane@example.com"), on: api, run: "100")
        let body = try #require(await api.issues.first?.body)
        #expect(!body.contains("SECRET-123"))
        #expect(!body.contains("jane@example.com"))
        #expect(!body.contains("XCTAssert"))
    }

    @Test("Rerunning does not file a second issue")
    func noDuplicates() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing(), on: api, run: "100")
        let again = try await sync(failing(), on: api, run: "101")
        #expect(await api.issues.count == 1)
        #expect(again.map(\.kind) == [.updated])
        #expect(await api.comments.isEmpty, "a recurring failure must not comment on every run")
    }

    @Test("A closed issue reopens, with one comment, when the test fails again")
    func reopens() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing(), on: api, run: "100")
        let number = try #require(await api.issues.first?.number)
        try await api.updateIssue(number: number, body: nil, state: .closed)
        let actions = try await sync(failing(), on: api, run: "101")
        #expect(actions.map(\.kind) == [.reopened])
        #expect(await api.issues.first?.state == .open)
        #expect(await api.comments.count == 1)
    }

    @Test("The issue closes after the configured number of consecutive clean runs")
    func closesAfterCleanRuns() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing(), on: api, run: "100", closeAfter: 2)
        let first = try await sync(clean(), on: api, run: "101", closeAfter: 2)
        #expect(first.map(\.kind) == [.updated])
        #expect(await api.issues.first?.state == .open)
        let second = try await sync(clean(), on: api, run: "102", closeAfter: 2)
        #expect(second.map(\.kind) == [.closed])
        #expect(await api.issues.first?.state == .closed)
        #expect(await api.comments.last?.body.contains("2 consecutive runs") == true)
    }

    @Test("Rerunning the same workflow run does not advance the clean streak")
    func rerunDoesNotCountTwice() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing(), on: api, run: "100", closeAfter: 2)
        _ = try await sync(clean(), on: api, run: "101", closeAfter: 2)
        _ = try await sync(clean(), on: api, run: "101", closeAfter: 2)
        #expect(await api.issues.first?.state == .open)
    }

    @Test("A failure resets the clean streak")
    func failureResetsStreak() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing(), on: api, run: "100", closeAfter: 2)
        _ = try await sync(clean(), on: api, run: "101", closeAfter: 2)
        _ = try await sync(failing(), on: api, run: "102", closeAfter: 2)
        _ = try await sync(clean(), on: api, run: "103", closeAfter: 2)
        #expect(await api.issues.first?.state == .open)
    }

    @Test("Passing only after a retry is not a clean run")
    func flakyIsNotClean() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing(), on: api, run: "100", closeAfter: 1)
        let recovered = TestRunDigest(reports: [makeReport(flaky: [xcodeCase(broken, attempts: 2)])])
        _ = try await sync(recovered, on: api, run: "101", closeAfter: 1)
        #expect(await api.issues.first(where: { $0.title.hasPrefix("Test failing") })?.state == .open)
    }

    @Test("A shard that did not run the test says nothing about it")
    func absentTestIsIgnored() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing(), on: api, run: "100", closeAfter: 1)
        let otherShard = TestRunDigest(reports: [makeReport(passed: [xcodeCase("AppTests/Other/testOther()", status: .passed)])])
        let actions = try await sync(otherShard, on: api, run: "101", closeAfter: 1)
        #expect(actions.isEmpty)
        #expect(await api.issues.first?.state == .open)
    }

    @Test("closeAfterCleanRuns of zero never closes")
    func neverCloses() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(failing(), on: api, run: "100", closeAfter: 0)
        for run in 101...106 { _ = try await sync(clean(), on: api, run: "\(run)", closeAfter: 0) }
        #expect(await api.issues.first?.state == .open)
    }

    @Test("Flaky tests share one rolling issue")
    func flakyRollup() async throws {
        let api = FakeGitHubIssues()
        let created = try await sync(flaky(), on: api, run: "100")
        #expect(created.map(\.kind) == [.created])
        let rollup = try #require(await api.issues.first)
        #expect(rollup.title == "Flaky tests")
        #expect(await api.labels(of: rollup.number).first == IssueSyncConfiguration.flakyLabel)
        #expect(rollup.body.contains(sometimes))

        let second = try await sync(flaky(), on: api, run: "101")
        #expect(second.map(\.kind) == [.updated])
        #expect(await api.issues.count == 1)
        #expect(await api.issues.first?.body.contains("| 2 |") == true)
    }

    @Test("A flaky occurrence is not counted twice when the same run is rerun")
    func flakyRerun() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(flaky(), on: api, run: "100")
        let again = try await sync(flaky(), on: api, run: "100")
        #expect(again.map(\.kind) == [.unchanged])
        #expect(await api.issues.first?.body.contains("| 1 |") == true)
    }

    @Test("A test leaves the flaky issue after clean runs, and the issue closes when none are left")
    func flakyRollupCloses() async throws {
        let api = FakeGitHubIssues()
        _ = try await sync(flaky(), on: api, run: "100", closeAfter: 2)
        let stable = TestRunDigest(reports: [makeReport(passed: [xcodeCase(sometimes, status: .passed)])])
        _ = try await sync(stable, on: api, run: "101", closeAfter: 2)
        #expect(await api.issues.first?.state == .open)
        let last = try await sync(stable, on: api, run: "102", closeAfter: 2)
        #expect(last.map(\.kind) == [.closed])
        #expect(await api.issues.first?.state == .closed)
    }

    @Test("A flaky rollup and a failure issue coexist without confusing each other")
    func bothKinds() async throws {
        let api = FakeGitHubIssues()
        let both = TestRunDigest(
            reports: [makeReport(failing: [xcodeCase(broken, attempts: 3)], flaky: [xcodeCase(sometimes, attempts: 2)])])
        let actions = try await sync(both, on: api, run: "100")
        #expect(actions.map(\.kind) == [.created, .created])
        #expect(await api.issues.count == 2)
        _ = try await sync(both, on: api, run: "101")
        #expect(await api.issues.count == 2)
    }

    @Test("A dry run reports the plan and writes nothing")
    func dryRun() async throws {
        let api = FakeGitHubIssues()
        let actions = try await sync(failing(), on: api, run: "100", dryRun: true)
        #expect(actions.map(\.kind) == [.created])
        #expect(actions.first?.issueNumber == nil)
        #expect(await api.mutations == 0)
    }

    @Test("Marker round trip survives an edit to the rest of the body")
    func markerRoundTrip() throws {
        let marker = IssueMarker(kind: "test", fingerprint: "abcdef0123456789", streak: 2, runID: "99")
        let body = marker.render() + "\n\nhand-written notes"
        #expect(IssueMarker.parse(body, kind: "test") == marker)
        var next = marker
        next.streak = 3
        #expect(IssueMarker.parse(next.replacing(in: body), kind: "test")?.streak == 3)
        #expect(next.replacing(in: body).hasSuffix("hand-written notes"))
        #expect(IssueMarker.parse("no marker here", kind: "test") == nil)
    }
}
