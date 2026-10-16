import Foundation
import Logging

/// What one sync did, or in a dry run would do.
public struct IssueSyncAction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case created, updated, reopened, closed, unchanged
    }

    public let kind: Kind
    /// `nil` for an issue a dry run would create.
    public let issueNumber: Int?
    public let title: String
    /// What the issue tracks: a test fingerprint, or `flaky-rollup`.
    public let subject: String
}

public struct IssueSyncConfiguration: Sendable {
    /// Labels every managed issue carries. The first of each pair finds failures and the rollup again on a later run.
    public static let failureLabel = "shipit-test-failure"
    public static let flakyLabel = "shipit-flaky-tests"

    public var extraLabels: [String]
    /// Consecutive clean runs after which an issue closes. `0` never closes automatically.
    public var closeAfterCleanRuns: Int
    /// Rerunning a workflow keeps its run id; counting it again would double a streak or an occurrence.
    public var runID: String?
    public var runURL: String?
    public var artifactURL: String?
    /// Branch the issues are about, for the issue text only.
    public var branch: String?

    public init(
        extraLabels: [String] = [], closeAfterCleanRuns: Int = 3, runID: String? = nil, runURL: String? = nil,
        artifactURL: String? = nil, branch: String? = nil
    ) {
        self.extraLabels = extraLabels
        self.closeAfterCleanRuns = closeAfterCleanRuns
        self.runID = runID
        self.runURL = runURL
        self.artifactURL = artifactURL
        self.branch = branch
    }
}

/// Keeps one issue per consistently failing test, and one rolling issue for flaky tests, in step with test runs.
///
/// - A failing test gets an issue the first time, found again by a hidden fingerprint marker so a rerun never files a
///   second. A closed issue reopens when the test fails again.
/// - A failing test's issue closes after ``IssueSyncConfiguration/closeAfterCleanRuns`` consecutive runs in which the
///   test passed without a retry. A test that did not run in a sharded job says nothing either way.
/// - Flaky tests are listed in a single rolling issue and drop out of it the same way.
/// - Issues carry test ids, plans and links only: no messages, stack traces or logs.
public struct GitHubIssueSync: Sendable {
    let api: any GitHubIssuesAPI
    let configuration: IssueSyncConfiguration
    let dryRun: Bool
    private let logger = Logger.forType(subsystem: "ShipItSwifty", GitHubIssueSync.self)

    public init(api: any GitHubIssuesAPI, configuration: IssueSyncConfiguration = .init(), dryRun: Bool = false) {
        self.api = api
        self.configuration = configuration
        self.dryRun = dryRun
    }

    public func sync(_ digest: TestRunDigest) async throws -> [IssueSyncAction] {
        logger.info("Syncing test issues", metadata: ["failing": "\(digest.consistentFailures.count)", "flaky": "\(digest.flakyTests.count)"])
        var actions = try await syncFailures(digest)
        actions += try await syncFlakyRollup(digest)
        logger.info("Synced test issues", metadata: ["actions": "\(actions.filter { $0.kind != .unchanged }.count)"])
        return actions
    }

    // MARK: Failures

    private func syncFailures(_ digest: TestRunDigest) async throws -> [IssueSyncAction] {
        let known = Dictionary(
            grouping: try await api.issues(withLabel: IssueSyncConfiguration.failureLabel).compactMap { issue in
                IssueMarker.parse(issue.body, kind: "test").map { (marker: $0, issue: issue) }
            }, by: { $0.marker.fingerprint })
        var actions: [IssueSyncAction] = []
        let failing = Set(digest.consistentFailures.map(\.fingerprint))
        let clean = Set(digest.passedFingerprints)
        let recovering = Set(digest.flakyTests.map(\.fingerprint))

        for test in digest.consistentFailures {
            let title = "Test failing: \(test.id.prefix(200))"
            let body = failureBody(test, streak: 0)
            guard let existing = known[test.fingerprint]?.min(by: { $0.issue.number < $1.issue.number }) else {
                actions.append(try await create(title: title, body: body, labels: labels(IssueSyncConfiguration.failureLabel), subject: test.fingerprint))
                continue
            }
            if existing.issue.state == .closed {
                actions.append(try await reopen(existing.issue, body: body, subject: test.fingerprint))
            } else {
                actions.append(try await update(existing.issue, body: body, subject: test.fingerprint))
            }
        }

        // Issues for tests that are not failing in this run: count clean passes toward closing.
        for (fingerprint, entries) in known where !failing.contains(fingerprint) {
            guard let existing = entries.min(by: { $0.issue.number < $1.issue.number }), existing.issue.state == .open else { continue }
            if recovering.contains(fingerprint) {
                // Passed only after a retry: still unreliable, so the streak starts over.
                guard existing.marker.streak != 0 else { continue }
                actions.append(try await update(existing.issue, body: rewriteStreak(existing, to: 0), subject: fingerprint))
            } else if clean.contains(fingerprint), existing.marker.runID == nil || existing.marker.runID != configuration.runID {
                let streak = existing.marker.streak + 1
                if configuration.closeAfterCleanRuns > 0, streak >= configuration.closeAfterCleanRuns {
                    actions.append(
                        try await close(
                            existing.issue, body: rewriteStreak(existing, to: streak),
                            comment: "Closing: this test passed in \(streak) consecutive runs. It reopens if it fails again.",
                            subject: fingerprint))
                } else {
                    actions.append(try await update(existing.issue, body: rewriteStreak(existing, to: streak), subject: fingerprint))
                }
            }
        }
        return actions
    }

    private func failureBody(_ test: DigestedTest, streak: Int) -> String {
        var rows = ["| Test | `\(test.id.replacingOccurrences(of: "`", with: "'"))` |", "|---|---|"]
        if let plan = test.plan { rows.append("| Plan | \(plan) |") }
        if let destination = test.destination { rows.append("| Device | \(destination) |") }
        rows.append("| Attempts | \(test.attempts) |")
        if let branch = configuration.branch { rows.append("| Branch | `\(branch)` |") }
        if let url = configuration.runURL { rows.append("| Last failed in | \(url) |") }
        if let url = configuration.artifactURL { rows.append("| Evidence | [artifacts](\(url)) |") }
        let marker = IssueMarker(kind: "test", fingerprint: test.fingerprint, streak: streak, runID: configuration.runID)
        return ([marker.render(), "", "**Consistently failing test.** It failed in every attempt."] + [""] + rows + [
            "", "Managed by ShipIt: the issue reopens if the test fails again and closes after \(configuration.closeAfterCleanRuns) consecutive passing runs. "
                + "It holds test ids and links only; read logs and result bundles from the run's artifacts.",
        ]).joined(separator: "\n")
    }

    private func rewriteStreak(_ entry: (marker: IssueMarker, issue: GitHubIssue), to streak: Int) -> String {
        var marker = entry.marker
        marker.streak = streak
        marker.runID = configuration.runID
        return marker.replacing(in: entry.issue.body)
    }

    // MARK: Flaky rollup

    private struct FlakyEntry: Codable, Equatable {
        var fingerprint: String
        var id: String
        var plan: String?
        var occurrences: Int
        var cleanRuns: Int
        var lastRunID: String?
    }

    private func syncFlakyRollup(_ digest: TestRunDigest) async throws -> [IssueSyncAction] {
        let rollup = try await api.issues(withLabel: IssueSyncConfiguration.flakyLabel)
            .filter { IssueMarker.parse($0.body, kind: "flaky-rollup") != nil }
            .min { $0.number < $1.number }
        var entries: [String: FlakyEntry] = [:]
        if let rollup, let data = IssueMarker.payload(in: rollup.body), let decoded = try? JSONDecoder().decode([FlakyEntry].self, from: data) {
            entries = Dictionary(decoded.map { ($0.fingerprint, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let before = entries
        let rerun = { (entry: FlakyEntry) in configuration.runID != nil && entry.lastRunID == configuration.runID }
        for test in digest.flakyTests {
            var entry = entries[test.fingerprint] ?? FlakyEntry(fingerprint: test.fingerprint, id: test.id, plan: test.plan, occurrences: 0, cleanRuns: 0)
            if !rerun(entry) { entry.occurrences += 1 }
            entry.cleanRuns = 0
            entry.lastRunID = configuration.runID
            entries[test.fingerprint] = entry
        }
        for fingerprint in digest.passedFingerprints {
            guard var entry = entries[fingerprint], !rerun(entry) else { continue }
            entry.cleanRuns += 1
            entry.lastRunID = configuration.runID
            entries[fingerprint] = entry
        }
        if configuration.closeAfterCleanRuns > 0 {
            entries = entries.filter { $0.value.cleanRuns < configuration.closeAfterCleanRuns }
        }

        let subject = "flaky-rollup"
        let title = "Flaky tests"
        if entries.isEmpty {
            guard let rollup, rollup.state == .open else { return [] }
            return [try await close(rollup, body: nil, comment: "Closing: no test is flaky any more.", subject: subject)]
        }
        guard entries != before || rollup?.state == .closed else {
            return [IssueSyncAction(kind: .unchanged, issueNumber: rollup?.number, title: title, subject: subject)]
        }
        let body = try rollupBody(Array(entries.values).sorted { $0.id < $1.id })
        guard let rollup else {
            return [try await create(title: title, body: body, labels: labels(IssueSyncConfiguration.flakyLabel), subject: subject)]
        }
        return [
            rollup.state == .closed
                ? try await reopen(rollup, body: body, subject: subject) : try await update(rollup, body: body, subject: subject)
        ]
    }

    private func rollupBody(_ entries: [FlakyEntry]) throws -> String {
        var lines = [
            IssueMarker(kind: "flaky-rollup").render(), "", "**Flaky tests.** Each passed only after a retry. A test leaves this list after "
                + "\(configuration.closeAfterCleanRuns) consecutive runs that pass without a retry.",
            "", "| Test | Plan | Flaky runs |", "|---|---|---:|",
        ]
        for entry in entries.prefix(200) {
            lines.append("| `\(entry.id.replacingOccurrences(of: "`", with: "'").replacingOccurrences(of: "|", with: "\\|"))` | \(entry.plan ?? "–") | \(entry.occurrences) |")
        }
        if let url = configuration.runURL { lines += ["", "Last updated by \(url)"] }
        lines += ["", IssueMarker.payloadComment(try JSONEncoder().encode(entries))]
        return lines.joined(separator: "\n")
    }

    // MARK: Operations

    private func labels(_ managed: String) -> [String] { [managed] + configuration.extraLabels }

    private func create(title: String, body: String, labels: [String], subject: String) async throws -> IssueSyncAction {
        if dryRun { return .init(kind: .created, issueNumber: nil, title: title, subject: subject) }
        let issue = try await api.createIssue(title: title, body: body, labels: labels)
        logger.info("Created issue", metadata: ["number": "\(issue.number)", "subject": "\(subject)"])
        return .init(kind: .created, issueNumber: issue.number, title: title, subject: subject)
    }

    private func update(_ issue: GitHubIssue, body: String, subject: String) async throws -> IssueSyncAction {
        if !dryRun, body != issue.body { try await api.updateIssue(number: issue.number, body: body, state: nil) }
        return .init(kind: body == issue.body ? .unchanged : .updated, issueNumber: issue.number, title: issue.title, subject: subject)
    }

    private func reopen(_ issue: GitHubIssue, body: String, subject: String) async throws -> IssueSyncAction {
        if !dryRun {
            try await api.updateIssue(number: issue.number, body: body, state: .open)
            try await api.addComment(number: issue.number, body: "Failing again" + (configuration.runURL.map { " in \($0)." } ?? "."))
            logger.info("Reopened issue", metadata: ["number": "\(issue.number)", "subject": "\(subject)"])
        }
        return .init(kind: .reopened, issueNumber: issue.number, title: issue.title, subject: subject)
    }

    private func close(_ issue: GitHubIssue, body: String?, comment: String, subject: String) async throws -> IssueSyncAction {
        if !dryRun {
            try await api.addComment(number: issue.number, body: comment)
            try await api.updateIssue(number: issue.number, body: body, state: .closed)
            logger.info("Closed issue", metadata: ["number": "\(issue.number)", "subject": "\(subject)"])
        }
        return .init(kind: .closed, issueNumber: issue.number, title: issue.title, subject: subject)
    }
}

/// The hidden HTML comment that ties an issue to a test, so a later run finds it without searching text.
struct IssueMarker: Equatable {
    var kind: String
    var fingerprint: String = ""
    var streak: Int = 0
    var runID: String?

    private static let pattern = #"<!-- shipit:(test|flaky-rollup)((?: [a-z]+=[^\s>]+)*) -->"#

    func render() -> String {
        var fields = ["shipit:\(kind)"]
        if kind == "test" { fields += ["fingerprint=\(fingerprint)", "streak=\(streak)"] }
        if let runID { fields.append("run=\(runID)") }
        return "<!-- " + fields.joined(separator: " ") + " -->"
    }

    /// `body` with its marker replaced by this one.
    func replacing(in body: String) -> String {
        guard let range = body.range(of: Self.pattern, options: .regularExpression) else { return render() + "\n" + body }
        return body.replacingCharacters(in: range, with: render())
    }

    static func parse(_ body: String, kind: String) -> IssueMarker? {
        guard let range = body.range(of: pattern, options: .regularExpression) else { return nil }
        let text = String(body[range])
        guard text.contains("shipit:\(kind)") else { return nil }
        func field(_ name: String) -> String? {
            text.range(of: "\(name)=[^\\s>]+", options: .regularExpression).map { String(text[$0]).dropFirst(name.count + 1).description }
        }
        if kind == "test", field("fingerprint") == nil { return nil }
        return IssueMarker(kind: kind, fingerprint: field("fingerprint") ?? "", streak: field("streak").flatMap(Int.init) ?? 0, runID: field("run"))
    }

    /// Base64, so test ids containing `--` cannot end the comment early.
    static func payloadComment(_ data: Data) -> String { "<!-- shipit:data \(data.base64EncodedString()) -->" }

    static func payload(in body: String) -> Data? {
        guard let range = body.range(of: #"<!-- shipit:data [A-Za-z0-9+/=]+ -->"#, options: .regularExpression) else { return nil }
        let encoded = body[range].dropFirst("<!-- shipit:data ".count).dropLast(" -->".count)
        return Data(base64Encoded: String(encoded))
    }
}
