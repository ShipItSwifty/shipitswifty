import Foundation
import MobileTesting

@testable import ShipItKit

/// An Xcode test case as the native runner reports it, under the positional prefix ShipIt adds.
func xcodeCase(
    _ id: String, status: TestCaseStatus = .failed, plan: String = "default", position: String = "plan-1:destination-1:",
    file: String? = nil, line: Int? = nil, message: String? = "XCTAssertEqual failed", attempts: Int = 1, flaky: Bool = false
) -> ParsedTestCase {
    var metadata = ["plan": plan]
    if flaky { metadata["flaky"] = "true" }
    return ParsedTestCase(
        stableID: position + "xcresult-case:" + id, suite: "Suite", name: id, status: status, message: message, file: file, line: line,
        rerunSelector: .xcodeOnlyTesting(id), metadata: metadata, attempts: attempts)
}

/// A finished multi-attempt report: `failing` failed every attempt, `flaky` recovered, `passed` was clean.
func makeReport(
    failing: [ParsedTestCase] = [], flaky: [ParsedTestCase] = [], passed: [ParsedTestCase] = [], errored: Int = 0
) -> TestRunReport {
    let recovered = flaky.map { $0.copy(status: .passed, metadata: .some(($0.metadata ?? [:]).merging(["flaky": "true"]) { $1 })) }
    let initial = TestSummary(passed: passed.count, failed: failing.count + flaky.count, errored: errored)
    return TestRunReport(
        runner: .xcodebuild,
        source: "build/test-runs",
        attempts: [
            TestAttempt(attemptNumber: 1, reason: "initial", summary: initial, failedTests: failing + flaky, durationSeconds: 12.5),
            TestAttempt(
                attemptNumber: 2, reason: "failed_tests", summary: TestSummary(passed: flaky.count, failed: failing.count),
                failedTests: failing, durationSeconds: 3),
        ],
        initialFailedTests: failing + flaky, flakyTests: recovered, persistentFailedTests: failing,
        summary: TestSummary(
            passed: passed.count + flaky.count, failed: failing.filter { $0.status == .failed }.count, flaky: flaky.count,
            errored: errored + failing.filter { $0.status == .errored }.count),
        testCases: passed + recovered + failing)
}

/// GitHub in memory: the issues endpoint's behavior that ``GitHubIssueSync`` depends on, and nothing more.
actor FakeGitHubIssues: GitHubIssuesAPI {
    private(set) var issues: [GitHubIssue] = []
    private var labelsByNumber: [Int: [String]] = [:]
    private(set) var comments: [(number: Int, body: String)] = []
    private(set) var mutations = 0

    func issues(withLabel label: String) async throws -> [GitHubIssue] {
        issues.filter { labelsByNumber[$0.number]?.contains(label) == true }
    }

    func createIssue(title: String, body: String, labels: [String]) async throws -> GitHubIssue {
        mutations += 1
        let issue = GitHubIssue(number: issues.count + 1, title: title, body: body, state: .open)
        issues.append(issue)
        labelsByNumber[issue.number] = labels
        return issue
    }

    func updateIssue(number: Int, body: String?, state: GitHubIssue.State?) async throws {
        mutations += 1
        guard let index = issues.firstIndex(where: { $0.number == number }) else { return }
        let old = issues[index]
        issues[index] = GitHubIssue(number: number, title: old.title, body: body ?? old.body, state: state ?? old.state)
    }

    func addComment(number: Int, body: String) async throws {
        mutations += 1
        comments.append((number, body))
    }

    func labels(of number: Int) -> [String] { labelsByNumber[number] ?? [] }

    /// An issue that already exists, as an earlier run left it.
    func seed(_ issue: GitHubIssue, labels: [String]) {
        issues.append(issue)
        labelsByNumber[issue.number] = labels
    }
}
