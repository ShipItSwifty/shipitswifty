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
        // xcresulttool may initialize its result database on first read; serialize these reads.
        let summary = try await runXCResultTool(arguments: ["get", "test-results", "summary", "--path", xcresultPath, "--compact"])
        let tests = try await runXCResultTool(arguments: ["get", "test-results", "tests", "--path", xcresultPath, "--compact"])
        let summaryJSON = try decodeJSON(summary.stdout, source: xcresultPath, command: "summary")
        var testsJSON = try decodeJSON(tests.stdout, source: xcresultPath, command: "tests")

        // Aggregate test nodes collapse configurations. Read each test's runs when dimensions vary.
        if let object = testsJSON.objectValue,
            (object.array(for: "testPlanConfigurations")?.count ?? 0) > 1 || (object.array(for: "devices")?.count ?? 0) > 1
        {
            testsJSON = try await enrichRuns(testsJSON, path: xcresultPath)
        }
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

    private func enrichRuns(_ value: JSONValue, path: String) async throws -> JSONValue {
        switch value {
        case .object(var object):
            if object.string(for: "nodeType") == "Test Case", let id = object.string(for: "nodeIdentifier") {
                let output = try await runXCResultTool(arguments: [
                    "get", "test-results", "test-details", "--path", path, "--test-id", id, "--compact",
                ])
                let details = try decodeJSON(output.stdout, source: path, command: "test-details")
                if let runs = details.objectValue?.array(for: "testRuns"), !runs.isEmpty { object["children"] = .array(runs) }
            } else {
                for key in object.keys.sorted() { if let child = object[key] { object[key] = try await enrichRuns(child, path: path) } }
            }
            return .object(object)
        case .array(let values):
            var enriched: [JSONValue] = []
            for value in values { enriched.append(try await enrichRuns(value, path: path)) }
            return .array(enriched)
        default: return value
        }
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

        var dimensions: [String: JSONValue] = [:]
        if let devices = testsJSON.objectValue?.array(for: "devices"), devices.count == 1, let device = devices.first?.objectValue {
            dimensions["_device"] = device["deviceName"]
            dimensions["_deviceID"] = device["deviceId"]
            dimensions["_runtime"] = device["osVersion"]
        }
        if let configurations = testsJSON.objectValue?.array(for: "testPlanConfigurations"), configurations.count == 1 {
            dimensions["_configuration"] = configurations.first?.objectValue?["configurationName"]
        }
        let nodes = collectObjects(from: testsJSON, context: dimensions)
        for node in nodes {
            let nodeType = node.string(for: "nodeType") ?? node.string(for: "type") ?? node.string(for: "kind")
            let identifier =
                node.string(for: "_testIdentifier")
                ?? node.string(for: "nodeIdentifier")
                ?? node.string(for: "identifier")
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

            if let nodeType,
                ["Test Plan", "Test Suite", "Unit test bundle", "UI test bundle", "Failure Message"].contains(nodeType)
                    || (["Device", "Test Plan Configuration"].contains(nodeType)
                        && children.contains(where: { child in
                            ["Test Case Run", "Device", "Test Plan Configuration"].contains(
                                child.objectValue?.string(for: "nodeType") ?? "")
                        }))
            {
                continue
            }
            let status = status(from: nodeType, node: node)
            guard let status, let identifier else { continue }

            let suiteName = node.string(for: "parentName") ?? inferredSuiteName(from: identifier)
            let selector = onlyTestingSelector(from: identifier).map { value in
                if identifier.split(separator: "/").count < 3, let target = node.string(for: "_testTarget") { return target + "/" + value }
                return value
            }
            let dimensions = [node.string(for: "_configuration"), node.string(for: "_device")].compactMap { $0 }
            let stableID = "xcresult-case:\(identifier)" + (dimensions.isEmpty ? "" : ":" + dimensions.joined(separator: ":"))

            testCasesByID[stableID] = ParsedTestCase(
                stableID: stableID,
                suite: suiteName,
                name: displayName(from: identifier),
                status: status,
                durationSeconds: node.double(for: "durationInSeconds") ?? node.double(for: "duration")
                    ?? node.double(for: "durationSeconds"),
                message: node.string(for: "failureText") ?? node.string(for: "summary") ?? node.string(for: "message")
                    ?? children.compactMap { child in
                        child.objectValue?.string(for: "nodeType") == "Failure Message" ? child.objectValue?.string(for: "name") : nil
                    }.first,
                file: node.string(for: "sourceFileName") ?? node.object(for: "sourceLocation")?.string(for: "filePath"),
                line: node.int(for: "sourceLineNumber") ?? node.int(for: "lineNumber")
                    ?? node.object(for: "sourceLocation")?.int(for: "lineNumber"),
                rerunSelector: selector.map(TestRerunSelector.xcodeOnlyTesting),
                metadata: [
                    "configuration": node.string(for: "_configuration"), "device": node.string(for: "_device"),
                    "device_id": node.string(for: "_deviceID"), "runtime": node.string(for: "_runtime"),
                ].compactMapValues { $0 }
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
        if testCases.contains(where: { $0.metadata?["configuration"] != nil || $0.metadata?["device"] != nil }) {
            return .init(
                passed: testCases.filter { $0.status == .passed }.count, failed: testCases.filter { $0.status == .failed }.count,
                skipped: testCases.filter { $0.status == .skipped }.count, errored: testCases.filter { $0.status == .errored }.count)
        }
        if let object = summaryJSON.objectValue {
            let metrics = object.object(for: "metrics") ?? object.object(for: "summary") ?? object
            let passed =
                metrics.int(for: "passedTests")
                ?? metrics.int(for: "testsCount")
                .flatMap { total in
                    let skipped = metrics.int(for: "skippedTests") ?? metrics.int(for: "testsSkippedCount") ?? 0
                    let failed = metrics.int(for: "failedTests") ?? metrics.int(for: "testsFailedCount") ?? 0
                    return max(total - skipped - failed, 0)
                }
            let failed =
                metrics.int(for: "failedTests") ?? metrics.int(for: "testsFailedCount") ?? testCases.filter { $0.status == .failed }.count
            let skipped =
                metrics.int(for: "skippedTests") ?? metrics.int(for: "testsSkippedCount")
                ?? testCases.filter { $0.status == .skipped }.count
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

        return nil
    }

    private func collectObjects(from value: JSONValue, context: [String: JSONValue] = [:]) -> [[String: JSONValue]] {
        switch value {
        case .object(let raw):
            var inherited = context
            let type = raw.string(for: "nodeType")
            if type == "Test Plan Configuration" { inherited["_configuration"] = raw["name"] }
            if let configuration = raw["configurationName"] { inherited["_configuration"] = configuration }
            if let device = raw["deviceName"] { inherited["_device"] = device }
            if type == "Device" { inherited["_device"] = raw["name"] }
            if type == "UI test bundle" || type == "Unit test bundle" { inherited["_testTarget"] = raw["name"] }
            if type == "Test Case" { inherited["_testIdentifier"] = raw["nodeIdentifier"] ?? raw["identifier"] }
            var object = raw
            for (key, value) in inherited { object[key] = value }
            let children = raw.values.flatMap { collectObjects(from: $0, context: inherited) }
            if type == "Test Case",
                children.contains(where: {
                    ["Test Case Run", "Test Plan Configuration", "Device"].contains($0.string(for: "nodeType") ?? "")
                        && $0.string(for: "result") != nil
                })
            {
                return children
            }
            return [object] + children
        case .array(let array): return array.flatMap { collectObjects(from: $0, context: context) }
        default: return []
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
