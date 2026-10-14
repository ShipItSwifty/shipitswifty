import Foundation
import MobileCore
import MobileTesting

/// Aggregate report spanning one or more rerun attempts.
public struct TestRunReport: Codable, Sendable {
    /// Increment this when the JSON contract changes incompatibly.
    public let schemaVersion: Int

    public let runner: TestRunner
    public let buildSystem: AppFramework?
    public let source: String
    /// Where the tests ran; `ParsedTestCase.destinationID` refers to these.
    public let destinations: [TestDestination]
    /// How long the shared build took, for runners that build once and test many times (native iOS). `nil` when the
    /// build is part of each test command (SwiftPM, Gradle). Attempts carry their own `durationSeconds`.
    public let buildSeconds: Double?
    public let attempts: [TestAttempt]
    public let initialFailedTests: [ParsedTestCase]
    public let flakyTests: [ParsedTestCase]
    public let persistentFailedTests: [ParsedTestCase]
    public let summary: TestSummary
    public let testCases: [ParsedTestCase]?
    public let generatedAt: Date

    /// The current contract. Version 2 replaced the string `platform` with typed `destinations`, and the string
    /// `runner` with `TestRunner`.
    public static let currentSchemaVersion = 2

    public init(
        schemaVersion: Int = TestRunReport.currentSchemaVersion,
        runner: TestRunner,
        buildSystem: AppFramework? = nil,
        source: String,
        destinations: [TestDestination] = [],
        buildSeconds: Double? = nil,
        attempts: [TestAttempt] = [],
        initialFailedTests: [ParsedTestCase] = [],
        flakyTests: [ParsedTestCase] = [],
        persistentFailedTests: [ParsedTestCase] = [],
        summary: TestSummary,
        generatedAt: Date = Date(),
        testCases: [ParsedTestCase]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runner = runner
        self.buildSystem = buildSystem
        self.source = source
        self.destinations = destinations
        self.buildSeconds = buildSeconds
        self.attempts = attempts
        self.initialFailedTests = initialFailedTests
        self.flakyTests = flakyTests
        self.persistentFailedTests = persistentFailedTests
        self.summary = summary
        self.generatedAt = generatedAt
        self.testCases = testCases
    }
}

extension TestRunReport {
    /// The report with `flakyTests` and `summary.flaky` taken from every test that passed only after a retry, whoever
    /// retried it: the workflow's own reruns, or the runner inside one execution (a retry plugin). Counting only the
    /// first would hide flakiness the runner already absorbed.
    func unifyingFlaky() -> TestRunReport {
        guard let testCases else { return self }
        let recovered = testCases.filter { $0.status == .passed && $0.metadata?["flaky"] == "true" }
        return TestRunReport(
            schemaVersion: schemaVersion, runner: runner, buildSystem: buildSystem, source: source, destinations: destinations,
            buildSeconds: buildSeconds, attempts: attempts, initialFailedTests: initialFailedTests, flakyTests: recovered,
            persistentFailedTests: persistentFailedTests,
            summary: .init(
                passed: summary.passed, failed: summary.failed, skipped: summary.skipped, flaky: recovered.count,
                errored: summary.errored),
            generatedAt: generatedAt, testCases: testCases)
    }
}

/// One execution attempt within a multi-attempt test run.
public struct TestAttempt: Codable, Sendable, Hashable {
    public let reason: String?
    public let metadata: [String: String]?
    public let attemptNumber: Int
    public let summary: TestSummary
    public let failedTests: [ParsedTestCase]
    public let durationSeconds: Double?
    public let source: String?

    public init(
        attemptNumber: Int,
        reason: String? = nil,
        metadata: [String: String]? = nil,
        summary: TestSummary,
        failedTests: [ParsedTestCase] = [],
        durationSeconds: Double? = nil,
        source: String? = nil
    ) {
        self.reason = reason
        self.metadata = metadata
        self.attemptNumber = attemptNumber
        self.summary = summary
        self.failedTests = failedTests
        self.durationSeconds = durationSeconds
        self.source = source
    }
}

/// Preserve all case identities in final reports while replacing outcomes resolved by reruns.
///
/// - Parameter attempts: Every attempt the workflow made. A test's executions are the executions of each attempt
///   it failed in (each failed instance already counts the retries a runner made inside that attempt, such as a
///   retry plugin's) plus the one that passed, so a test recovered by a rerun reports 2 or more instead of the 1 its
///   first execution recorded.
func finalTestCases(
    _ initial: [ParsedTestCase], remaining: [ParsedTestCase], flaky: [ParsedTestCase], attempts: [TestAttempt] = []
) -> [ParsedTestCase] {
    let recovered = Set(flaky.map(\.stableID))
    var failedExecutions: [String: Int] = [:]
    for attempt in attempts {
        for failed in attempt.failedTests { failedExecutions[failed.stableID, default: 0] += failed.attempts ?? 1 }
    }
    func executions(of test: ParsedTestCase, passed: Bool) -> Int? {
        guard let failed = failedExecutions[test.stableID] else { return nil }
        let total = failed + (passed ? 1 : 0)
        return total > (test.attempts ?? 1) ? total : nil
    }
    var cases = initial.map { test in
        if let persistent = remaining.first(where: { $0.stableID == test.stableID }) {
            guard let count = executions(of: test, passed: false) else { return persistent }
            return persistent.copy(attempts: .some(count))
        }
        guard recovered.contains(test.stableID) else { return test }
        var metadata = test.metadata ?? [:]
        metadata["flaky"] = "true"
        // A recovered test carries no failure; why it first failed is kept as context, as when a retry plugin folds attempts.
        if metadata["first_failure"] == nil, let why = test.message ?? test.stackTrace {
            metadata["first_failure"] = String(why.prefix(500))
        }
        var final = test.copy(status: .passed, metadata: metadata, message: .some(nil), stackTrace: .some(nil))
        if let count = executions(of: test, passed: true) { final = final.copy(attempts: .some(count)) }
        return final
    }
    for test in remaining where !cases.contains(where: { $0.stableID == test.stableID }) { cases.append(test) }
    return cases
}
