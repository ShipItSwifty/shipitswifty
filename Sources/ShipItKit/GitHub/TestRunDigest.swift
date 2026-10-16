import Foundation
import MobileTesting

/// One test as a CI report talks about it.
public struct DigestedTest: Codable, Sendable, Hashable {
    /// Stable across shards and reruns; see ``TestFingerprint``.
    public let fingerprint: String
    /// The runner's name for the test (for Xcode: `Target/Class/method`).
    public let id: String
    public let name: String
    public let plan: String?
    /// The simulator, emulator or device it ran on, when the runner said.
    public let destination: String?
    /// Source location of the failure, when the runner reported one.
    public let file: String?
    public let line: Int?
    /// First line of the failure message, truncated. Never the stack trace.
    public let message: String?
    /// Executions it took to reach this result, retries included.
    public let attempts: Int
}

/// One execution attempt, flattened for a table.
public struct DigestedAttempt: Codable, Sendable, Hashable {
    public let number: Int
    public let reason: String
    public let passed: Int
    public let failed: Int
    public let errored: Int
    public let durationSeconds: Double?
}

/// What a CI job needs to know about one or more `TestRunReport`s: counts, which tests failed for good, and which
/// only passed on a retry. Built from reports alone so it can be produced, and checked, anywhere.
public struct TestRunDigest: Codable, Sendable {
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let errored: Int
    public let flaky: Int
    /// Failed or errored in every attempt.
    public let consistentFailures: [DigestedTest]
    /// Failed at first and passed on a retry.
    public let flakyTests: [DigestedTest]
    /// Passed cleanly, with no retry. Only these count toward closing an issue.
    public let passedFingerprints: [String]
    public let attempts: [DigestedAttempt]
    /// Errored outcomes that are not a failing test: a build failure, a crashed runner, no results.
    public let runErrors: Int
    public let reportCount: Int

    public var hasConsistentFailures: Bool { !consistentFailures.isEmpty }

    /// Whether the run passes ShipIt's policy: no test failed for good and the run itself did not break. Flaky tests
    /// pass unless the caller opts into failing on them.
    public func passes(failOnFlaky: Bool = false) -> Bool {
        consistentFailures.isEmpty && runErrors == 0 && !(failOnFlaky && flaky > 0)
    }

    public init(reports: [TestRunReport]) {
        var failures: [String: DigestedTest] = [:]
        var failureOrder: [String] = []
        var flakies: [String: DigestedTest] = [:]
        var flakyOrder: [String] = []
        var clean = Set<String>()
        var rows: [DigestedAttempt] = []
        var totals = (passed: 0, failed: 0, skipped: 0, errored: 0)
        var failingErrors = 0

        for report in reports {
            // `persistentFailedTests` holds each test as its first failure saw it; the reconciled `testCases` entry
            // carries the executions across every attempt, so a test that failed twice says 2, not 1.
            let reconciled = Dictionary((report.testCases ?? []).map { ($0.stableID, $0) }, uniquingKeysWith: { first, _ in first })
            totals.passed += report.summary.passed
            totals.failed += report.summary.failed
            totals.skipped += report.summary.skipped
            totals.errored += report.summary.errored
            for attempt in report.attempts {
                rows.append(
                    DigestedAttempt(
                        number: attempt.attemptNumber, reason: attempt.reason ?? "initial", passed: attempt.summary.passed,
                        failed: attempt.summary.failed, errored: attempt.summary.errored, durationSeconds: attempt.durationSeconds))
            }
            for test in report.persistentFailedTests {
                let item = Self.digest(reconciled[test.stableID].flatMap { $0.attempts == nil ? nil : test.copy(attempts: .some($0.attempts)) } ?? test, report: report)
                if failures[item.fingerprint] == nil { failureOrder.append(item.fingerprint) }
                failures[item.fingerprint] = failures[item.fingerprint].map { $0.attempts >= item.attempts ? $0 : item } ?? item
                if test.status == .errored { failingErrors += 1 }
            }
            var reportFlaky = report.flakyTests
            for test in report.testCases ?? [] {
                let recovered = test.status == .flaky || (test.status == .passed && test.metadata?["flaky"] == "true")
                if recovered, !reportFlaky.contains(where: { $0.stableID == test.stableID }) { reportFlaky.append(test) }
                if test.status == .passed, !recovered { clean.insert(TestFingerprint.make(for: test, runner: report.runner)) }
            }
            for test in reportFlaky {
                let item = Self.digest(test, report: report)
                if flakies[item.fingerprint] == nil { flakyOrder.append(item.fingerprint) }
                flakies[item.fingerprint] = item
            }
        }

        let failing = Set(failures.keys)
        let recovering = Set(flakies.keys)
        passed = totals.passed
        failed = totals.failed
        skipped = totals.skipped
        errored = totals.errored
        flaky = flakyOrder.count
        consistentFailures = failureOrder.compactMap { failures[$0] }
        flakyTests = flakyOrder.compactMap { flakies[$0] }
        passedFingerprints = clean.subtracting(failing).subtracting(recovering).sorted()
        attempts = rows
        runErrors = max(0, totals.errored - failingErrors)
        reportCount = reports.count
    }

    private static func digest(_ test: ParsedTestCase, report: TestRunReport) -> DigestedTest {
        let destination = test.destinationID.flatMap { id in report.destinations.first { $0.id == id }?.name }
        let reason = test.message ?? test.metadata?["first_failure"]
        return DigestedTest(
            fingerprint: TestFingerprint.make(for: test, runner: report.runner), id: TestFingerprint.identity(of: test), name: test.name,
            plan: test.metadata?["plan"], destination: destination, file: test.file, line: test.line,
            message: reason.flatMap(Self.firstLine), attempts: test.attempts ?? 1)
    }

    /// The first non-empty line, bounded: assertion text is useful in an annotation, a stack trace is not.
    private static func firstLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return line.map { $0.count > 300 ? String($0.prefix(300)) + "…" : $0 }
    }
}

extension TestRunDigest {
    /// Reads `TestRunReport` JSON files (as `shipit test --report-path` writes them) and digests them together.
    ///
    /// - Throws: ``ShipItError/invalidConfiguration(reason:)`` for a file that is missing, is not a report, or has a
    ///   schema version this ShipIt does not read. A report is never silently skipped: a missing shard report would
    ///   otherwise look like a green run.
    public static func load(reportPaths: [String]) throws -> TestRunDigest {
        guard !reportPaths.isEmpty else { throw ShipItError.invalidConfiguration(reason: "At least one --report is required") }
        let reports = try reportPaths.map { path -> TestRunReport in
            guard let data = FileManager.default.contents(atPath: path) else {
                throw ShipItError.invalidConfiguration(reason: "Test report not found: \(path)")
            }
            do {
                let report = try JSONDecoder().decode(TestRunReport.self, from: data)
                guard report.schemaVersion == TestRunReport.currentSchemaVersion else {
                    throw ShipItError.invalidConfiguration(
                        reason: "Unsupported test report schema \(report.schemaVersion) in \(path); expected \(TestRunReport.currentSchemaVersion)")
                }
                return report
            } catch let error as ShipItError {
                throw error
            } catch {
                throw ShipItError.invalidConfiguration(reason: "Not a ShipIt test report: \(path) (\(error.localizedDescription))")
            }
        }
        return TestRunDigest(reports: reports)
    }
}
