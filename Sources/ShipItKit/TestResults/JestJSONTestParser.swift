import Foundation
import Logging

/// Parses Jest `--json --outputFile` results into a normalized ``ParsedTestRun``.
public struct JestJSONTestParser: Sendable {
    private let logger: Logger

    public init(logger: Logger = Logger.forType(subsystem: "ShipItSwifty", JestJSONTestParser.self)) {
        self.logger = logger
    }

    /// - Parameters:
    ///   - buildSystem: The project's build system when the caller knows it (`.reactNative` for a React Native app).
    ///   - destination: Where Jest ran. Jest always executes in Node on the host, so that is the default.
    public func parse(
        jsonFilePath: String, buildSystem: BuildSystem? = nil,
        destination: TestDestination = TestDestination(platform: .js, kind: .host)
    ) async throws -> ParsedTestRun {
        let url = URL(fileURLWithPath: jsonFilePath)
        let data = try Data(contentsOf: url)
        let root = try JSONDecoder().decode(JestJSONRoot.self, from: data)

        var suites: [ParsedTestSuite] = []
        var testCases: [ParsedTestCase] = []

        for suite in root.testResults {
            let suiteName = suite.name
            let suiteID = "jest-suite:\(suiteName)"
            let cases = suite.assertionResults.map { assertion -> ParsedTestCase in
                let stableID = "jest-case:\(suiteName)::\(assertion.fullName)"
                return ParsedTestCase(
                    stableID: stableID,
                    suite: suiteName,
                    name: assertion.title,
                    status: status(from: assertion.status),
                    durationSeconds: nil,
                    message: assertion.failureMessages.joined(separator: "\n").nilIfEmpty,
                    file: suite.name,
                    line: nil,
                    rerunSelector: .jest(file: suite.name, fullName: assertion.fullName),
                    attempts: 1,
                    destinationID: destination.id
                )
            }

            suites.append(
                ParsedTestSuite(
                    name: suiteName,
                    stableID: suiteID,
                    file: suite.name,
                    testCaseIDs: cases.map(\.stableID)
                )
            )
            testCases.append(contentsOf: cases)
        }

        logger.info("Parsed Jest JSON test results from \(jsonFilePath)")

        return ParsedTestRun(
            runner: .jest,
            buildSystem: buildSystem,
            source: jsonFilePath,
            destinations: [destination],
            summary: TestSummary(
                passed: root.numPassedTests,
                failed: root.numFailedTests,
                skipped: root.numPendingTests,
                errored: root.numRuntimeErrorTestSuites
            ),
            suites: suites,
            testCases: testCases.map { $0.copy(destinationID: destination.id) },
            diagnostics: []
        )
    }

    private func status(from value: String) -> TestCaseStatus {
        switch value.lowercased() {
        case "passed": return .passed
        case "failed": return .failed
        case "pending", "skipped", "todo": return .skipped
        default: return .errored
        }
    }
}

extension JestJSONTestParser: TestResultParser {
    public func parse(_ input: String) async throws -> ParsedTestRun {
        try await parse(jsonFilePath: input)
    }
}

private struct JestJSONRoot: Decodable {
    let numFailedTests: Int
    let numPassedTests: Int
    let numPendingTests: Int
    let numRuntimeErrorTestSuites: Int
    let testResults: [JestJSONSuite]
}

private struct JestJSONSuite: Decodable {
    let name: String
    let assertionResults: [JestJSONAssertion]
}

private struct JestJSONAssertion: Decodable {
    let title: String
    let fullName: String
    let status: String
    let failureMessages: [String]
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
