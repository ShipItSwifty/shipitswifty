#if os(macOS)
import Foundation
import Logging
import SwiftyShell

/// Parses iOS test results from an `.xcresult` bundle using `xcresulttool`.
///
/// The parser intentionally walks the compact JSON emitted by the current
/// `xcresulttool get test-results summary/tests` commands rather than relying on
/// one generated schema type. This keeps the parser more resilient across Xcode
/// releases while still extracting the stable data ShipIt needs for reruns and
/// reporting.
public struct IOSXCResultTestParser: Sendable {
    private let shell: ShellContext
    private let logger: Logger

    public init(
        shell: ShellContext,
        logger: Logger = Logger.forType(subsystem: "ShipItSwifty", IOSXCResultTestParser.self)
    ) {
        self.shell = shell
        self.logger = logger
    }

    /// Parses a `.xcresult` bundle into a normalized test run.
    public func parse(xcresultPath: String) async throws -> ParsedTestRun {
        async let summaryOutput = runXCResultTool(arguments: ["get", "test-results", "summary", "--path", xcresultPath, "--compact"])
        async let testsOutput = runXCResultTool(arguments: ["get", "test-results", "tests", "--path", xcresultPath, "--compact"])

        let (summary, tests) = try await (summaryOutput, testsOutput)
        let summaryJSON = try decodeJSON(summary.stdout, source: xcresultPath, command: "summary")
        let testsJSON = try decodeJSON(tests.stdout, source: xcresultPath, command: "tests")

        let extractor = XCResultTestExtractor(logger: logger)
        let extracted = extractor.extract(fromTestsJSON: testsJSON, summaryJSON: summaryJSON)

        return ParsedTestRun(
            platform: "ios",
            runner: "xcodebuild",
            source: xcresultPath,
            summary: extracted.summary,
            suites: extracted.suites,
            testCases: extracted.testCases,
            diagnostics: extracted.diagnostics
        )
    }

    private func runXCResultTool(arguments: [String]) async throws -> ShellOutput {
        do {
            return try await Xcrun(context: shell)
                .tool("xcresulttool")
                .trailingArguments(arguments)
                .command()
                .run(in: shell)
        } catch let ShellError.commandNotFound(name) {
            throw ShipItError.missingTool(name: name)
        } catch let ShellError.exitFailure(_, output) {
            let errorText = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ShipItError.invalidConfiguration(
                reason: "xcresulttool failed (exit \(output.exitCode)): \(errorText)"
            )
        }
    }

    private func decodeJSON(_ text: String, source: String, command: String) throws -> JSONValue {
        guard let data = text.data(using: .utf8) else {
            throw ShipItError.invalidConfiguration(reason: "xcresulttool \(command) output is not valid UTF-8 for \(source)")
        }

        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ShipItError.invalidConfiguration(
                reason: "Failed to decode xcresulttool \(command) JSON for \(source): \(error.localizedDescription)"
            )
        }
    }
}

extension IOSXCResultTestParser: TestResultParser {
    public func parse(_ input: String) async throws -> ParsedTestRun {
        try await parse(xcresultPath: input)
    }
}

private struct XCResultTestExtractor: Sendable {
    let logger: Logger

    func extract(fromTestsJSON testsJSON: JSONValue, summaryJSON: JSONValue) -> ExtractedRun {
        var suitesByID: [String: ParsedTestSuite] = [:]
        var testCasesByID: [String: ParsedTestCase] = [:]
        var diagnostics: [ParsingDiagnostic] = []

        let nodes = collectObjects(from: testsJSON)
        for node in nodes {
            let nodeType = node.string(for: "nodeType") ?? node.string(for: "type") ?? node.string(for: "kind")
            let identifier =
                node.string(for: "identifier")
                ?? node.string(for: "id")
                ?? node.string(for: "testIdentifierURL")
                ?? node.string(for: "name")

            let children =
                node.array(for: "subtests")
                ?? node.array(for: "children")
                ?? node.array(for: "tests")
                ?? []

            if !children.isEmpty {
                let suiteName = node.string(for: "name") ?? identifier ?? "Unnamed Suite"
                let suiteID = "xcresult-suite:\(identifier ?? suiteName)"
                let childIDs = children.compactMap { child -> String? in
                    guard let childObject = child.objectValue else { return nil }
                    let childIdentifier =
                        childObject.string(for: "identifier")
                        ?? childObject.string(for: "id")
                        ?? childObject.string(for: "testIdentifierURL")
                        ?? childObject.string(for: "name")
                    return childIdentifier.map { "xcresult-case:\($0)" }
                }

                suitesByID[suiteID] = ParsedTestSuite(
                    name: suiteName,
                    stableID: suiteID,
                    file: node.string(for: "sourceFileName"),
                    testCaseIDs: childIDs
                )
            }

            let status = status(from: nodeType, node: node)
            guard let status, let identifier else { continue }

            let suiteName = node.string(for: "parentName") ?? inferredSuiteName(from: identifier)
            let selector = onlyTestingSelector(from: identifier)
            let stableID = "xcresult-case:\(identifier)"

            testCasesByID[stableID] = ParsedTestCase(
                stableID: stableID,
                suite: suiteName,
                name: displayName(from: identifier),
                status: status,
                durationSeconds: node.double(for: "duration") ?? node.double(for: "durationSeconds"),
                message: node.string(for: "failureText") ?? node.string(for: "summary") ?? node.string(for: "message"),
                file: node.string(for: "sourceFileName"),
                line: node.int(for: "sourceLineNumber") ?? node.int(for: "lineNumber"),
                rerunSelector: selector.map(TestRerunSelector.xcodeOnlyTesting)
            )
        }

        if testCasesByID.isEmpty {
            diagnostics.append(
                ParsingDiagnostic(
                    severity: .warning,
                    message: "xcresulttool test structure did not expose individual test cases."
                )
            )
        }

        let summary = summarize(testCases: Array(testCasesByID.values), summaryJSON: summaryJSON)
        let suites = suitesByID.values.sorted { $0.name < $1.name }
        let testCases = testCasesByID.values.sorted { $0.stableID < $1.stableID }

        return ExtractedRun(summary: summary, suites: suites, testCases: testCases, diagnostics: diagnostics)
    }

    private func summarize(testCases: [ParsedTestCase], summaryJSON: JSONValue) -> TestSummary {
        if let object = summaryJSON.objectValue {
            let metrics = object.object(for: "metrics") ?? object.object(for: "summary") ?? object
            let passed = metrics.int(for: "testsCount")
                .flatMap { total in
                    let skipped = metrics.int(for: "testsSkippedCount") ?? 0
                    let failed = metrics.int(for: "testsFailedCount") ?? 0
                    return max(total - skipped - failed, 0)
                }
            let failed = metrics.int(for: "testsFailedCount") ?? testCases.filter { $0.status == .failed || $0.status == .errored }.count
            let skipped = metrics.int(for: "testsSkippedCount") ?? testCases.filter { $0.status == .skipped }.count
            let errored = metrics.int(for: "testsErroredCount") ?? testCases.filter { $0.status == .errored }.count
            return TestSummary(
                passed: passed ?? testCases.filter { $0.status == .passed }.count,
                failed: failed,
                skipped: skipped,
                errored: errored
            )
        }

        return TestSummary(
            passed: testCases.filter { $0.status == .passed }.count,
            failed: testCases.filter { $0.status == .failed }.count,
            skipped: testCases.filter { $0.status == .skipped }.count,
            errored: testCases.filter { $0.status == .errored }.count
        )
    }

    private func status(from nodeType: String?, node: [String: JSONValue]) -> TestCaseStatus? {
        let statusText =
            node.string(for: "testStatus")
            ?? node.string(for: "status")
            ?? node.string(for: "result")
            ?? node.string(for: "outcome")

        switch statusText?.lowercased() {
        case "success", "passed": return .passed
        case "failure", "failed": return .failed
        case "skipped": return .skipped
        case "error", "errored": return .errored
        default: break
        }

        let loweredNodeType = nodeType?.lowercased() ?? ""
        if loweredNodeType.contains("test") && node.array(for: "subtests") == nil && node.array(for: "children") == nil {
            return .passed
        }

        return nil
    }

    private func collectObjects(from value: JSONValue) -> [[String: JSONValue]] {
        switch value {
        case .object(let object):
            return [object] + object.values.flatMap(collectObjects(from:))
        case .array(let array):
            return array.flatMap(collectObjects(from:))
        default:
            return []
        }
    }

    private func displayName(from identifier: String) -> String {
        if let last = identifier.split(separator: "/").last {
            return String(last)
        }
        return identifier
    }

    private func inferredSuiteName(from identifier: String) -> String? {
        let parts = identifier.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return parts.dropLast().joined(separator: "/")
    }

    private func onlyTestingSelector(from identifier: String) -> String? {
        let parts = identifier.split(separator: "/")
        guard parts.count >= 3 else { return identifier }
        return "\(parts[0])/\(parts[1])/\(parts[2])"
    }
}

private struct ExtractedRun: Sendable {
    let summary: TestSummary
    let suites: [ParsedTestSuite]
    let testCases: [ParsedTestCase]
    let diagnostics: [ParsingDiagnostic]
}

extension Dictionary where Key == String, Value == JSONValue {
    fileprivate func string(for key: String) -> String? {
        self[key]?.stringValue
    }

    fileprivate func int(for key: String) -> Int? {
        self[key]?.intValue
    }

    fileprivate func double(for key: String) -> Double? {
        if let double = self[key]?.doubleValue {
            return double
        }
        if let int = self[key]?.intValue {
            return Double(int)
        }
        return nil
    }

    fileprivate func object(for key: String) -> [String: JSONValue]? {
        self[key]?.objectValue
    }

    fileprivate func array(for key: String) -> [JSONValue]? {
        self[key]?.arrayValue
    }
}
#endif
