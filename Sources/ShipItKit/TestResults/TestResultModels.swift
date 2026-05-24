import Foundation

/// A normalized test run parsed from an existing tool artifact.
///
/// `ParsedTestRun` is the common cross-platform surface returned by test result
/// parsers in ShipItKit. It preserves enough runner-specific metadata to power
/// reporting, selective reruns, and flaky-test classification without forcing a
/// single universal test identifier format across every toolchain.
public struct ParsedTestRun: Codable, Sendable {
    /// Target platform that produced the result, such as `"ios"` or `"android"`.
    public let platform: String

    /// Runner that produced the result, such as `"xcodebuild"`, `"gradle"`, or `"jest"`.
    public let runner: String

    /// Artifact path or other source identifier used to parse this run.
    public let source: String

    /// Aggregate counts for this parsed run.
    public let summary: TestSummary

    /// Logical suites discovered while parsing.
    public let suites: [ParsedTestSuite]

    /// Individual test cases discovered while parsing.
    public let testCases: [ParsedTestCase]

    /// Recoverable warnings emitted during parsing.
    public let diagnostics: [ParsingDiagnostic]

    public init(
        platform: String,
        runner: String,
        source: String,
        summary: TestSummary,
        suites: [ParsedTestSuite] = [],
        testCases: [ParsedTestCase] = [],
        diagnostics: [ParsingDiagnostic] = []
    ) {
        self.platform = platform
        self.runner = runner
        self.source = source
        self.summary = summary
        self.suites = suites
        self.testCases = testCases
        self.diagnostics = diagnostics
    }
}

/// Aggregate counts for a parsed test run or rerun attempt.
public struct TestSummary: Codable, Sendable, Hashable {
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let flaky: Int
    public let errored: Int

    public init(
        passed: Int = 0,
        failed: Int = 0,
        skipped: Int = 0,
        flaky: Int = 0,
        errored: Int = 0
    ) {
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.flaky = flaky
        self.errored = errored
    }
}

/// Logical grouping for one parsed test suite.
public struct ParsedTestSuite: Codable, Sendable, Hashable {
    public let name: String
    public let stableID: String
    public let file: String?
    public let testCaseIDs: [String]

    public init(name: String, stableID: String, file: String? = nil, testCaseIDs: [String] = []) {
        self.name = name
        self.stableID = stableID
        self.file = file
        self.testCaseIDs = testCaseIDs
    }
}

/// One parsed test case from a tool artifact.
public struct ParsedTestCase: Codable, Sendable, Hashable {
    /// Stable identifier used to correlate the same test across attempts.
    public let stableID: String

    /// Owning suite name when the source format provides one.
    public let suite: String?

    /// Human-readable test name.
    public let name: String

    /// Final status for the parsed test case.
    public let status: TestCaseStatus

    /// Reported duration in seconds when available.
    public let durationSeconds: Double?

    /// Failure or skip message when available.
    public let message: String?

    /// Source file reported by the runner when available.
    public let file: String?

    /// Source line reported by the runner when available.
    public let line: Int?

    /// Runner-specific selector that can be used to target this test for reruns.
    public let rerunSelector: TestRerunSelector?

    public init(
        stableID: String,
        suite: String? = nil,
        name: String,
        status: TestCaseStatus,
        durationSeconds: Double? = nil,
        message: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        rerunSelector: TestRerunSelector? = nil
    ) {
        self.stableID = stableID
        self.suite = suite
        self.name = name
        self.status = status
        self.durationSeconds = durationSeconds
        self.message = message
        self.file = file
        self.line = line
        self.rerunSelector = rerunSelector
    }
}

/// Normalized status for one parsed test case.
public enum TestCaseStatus: String, Codable, Sendable {
    case passed
    case failed
    case skipped
    case flaky
    case errored
}

/// Runner-specific test selector used for targeted reruns.
public enum TestRerunSelector: Codable, Sendable, Hashable {
    case xcodeOnlyTesting(String)
    case gradleTestFilter(String)
    case jest(file: String?, fullName: String)
    case flutter(name: String)
    case unsupported(rawIdentifier: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case file
        case fullName
        case name
        case rawIdentifier
    }

    private enum SelectorType: String, Codable {
        case xcodeOnlyTesting
        case gradleTestFilter
        case jest
        case flutter
        case unsupported
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(SelectorType.self, forKey: .type) {
        case .xcodeOnlyTesting:
            self = .xcodeOnlyTesting(try container.decode(String.self, forKey: .value))
        case .gradleTestFilter:
            self = .gradleTestFilter(try container.decode(String.self, forKey: .value))
        case .jest:
            self = .jest(
                file: try container.decodeIfPresent(String.self, forKey: .file),
                fullName: try container.decode(String.self, forKey: .fullName)
            )
        case .flutter:
            self = .flutter(name: try container.decode(String.self, forKey: .name))
        case .unsupported:
            self = .unsupported(rawIdentifier: try container.decode(String.self, forKey: .rawIdentifier))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .xcodeOnlyTesting(let value):
            try container.encode(SelectorType.xcodeOnlyTesting, forKey: .type)
            try container.encode(value, forKey: .value)
        case .gradleTestFilter(let value):
            try container.encode(SelectorType.gradleTestFilter, forKey: .type)
            try container.encode(value, forKey: .value)
        case .jest(let file, let fullName):
            try container.encode(SelectorType.jest, forKey: .type)
            try container.encodeIfPresent(file, forKey: .file)
            try container.encode(fullName, forKey: .fullName)
        case .flutter(let name):
            try container.encode(SelectorType.flutter, forKey: .type)
            try container.encode(name, forKey: .name)
        case .unsupported(let rawIdentifier):
            try container.encode(SelectorType.unsupported, forKey: .type)
            try container.encode(rawIdentifier, forKey: .rawIdentifier)
        }
    }
}

/// Recoverable warning emitted while parsing an artifact.
public struct ParsingDiagnostic: Codable, Sendable, Hashable {
    public let severity: ParsingDiagnosticSeverity
    public let message: String
    public let source: String?

    public init(severity: ParsingDiagnosticSeverity, message: String, source: String? = nil) {
        self.severity = severity
        self.message = message
        self.source = source
    }
}

/// Severity level for a parsing diagnostic.
public enum ParsingDiagnosticSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

/// Aggregate report spanning one or more rerun attempts.
public struct TestRunReport: Codable, Sendable {
    /// Increment this when the JSON contract changes incompatibly.
    public let schemaVersion: Int

    public let platform: String
    public let runner: String
    public let source: String
    public let attempts: [TestAttempt]
    public let initialFailedTests: [ParsedTestCase]
    public let flakyTests: [ParsedTestCase]
    public let persistentFailedTests: [ParsedTestCase]
    public let summary: TestSummary
    public let generatedAt: Date

    public init(
        schemaVersion: Int = 1,
        platform: String,
        runner: String,
        source: String,
        attempts: [TestAttempt] = [],
        initialFailedTests: [ParsedTestCase] = [],
        flakyTests: [ParsedTestCase] = [],
        persistentFailedTests: [ParsedTestCase] = [],
        summary: TestSummary,
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.platform = platform
        self.runner = runner
        self.source = source
        self.attempts = attempts
        self.initialFailedTests = initialFailedTests
        self.flakyTests = flakyTests
        self.persistentFailedTests = persistentFailedTests
        self.summary = summary
        self.generatedAt = generatedAt
    }
}

/// One execution attempt within a multi-attempt test run.
public struct TestAttempt: Codable, Sendable, Hashable {
    public let attemptNumber: Int
    public let summary: TestSummary
    public let failedTests: [ParsedTestCase]
    public let durationSeconds: Double?
    public let source: String?

    public init(
        attemptNumber: Int,
        summary: TestSummary,
        failedTests: [ParsedTestCase] = [],
        durationSeconds: Double? = nil,
        source: String? = nil
    ) {
        self.attemptNumber = attemptNumber
        self.summary = summary
        self.failedTests = failedTests
        self.durationSeconds = durationSeconds
        self.source = source
    }
}
