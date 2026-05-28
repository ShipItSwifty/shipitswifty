import Foundation
import Logging

/// Parses `flutter test --machine` newline-delimited JSON output.
public struct FlutterMachineOutputParser: Sendable {
    private let logger: Logger

    public init(logger: Logger = Logger.forType(subsystem: "ShipItSwifty", FlutterMachineOutputParser.self)) {
        self.logger = logger
    }

    public func parse(machineOutput: String) async throws -> ParsedTestRun {
        var testsByID: [Int: ParsedTestCase] = [:]
        var diagnostics: [ParsingDiagnostic] = []

        for rawLine in machineOutput.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            // Skip non-object lines (e.g. array-wrapped VM service events like `[{...}]`)
            guard line.hasPrefix("{") else { continue }
            guard let event = try? JSONDecoder().decode(FlutterMachineEvent.self, from: data) else { continue }

            switch event.type {
            case "testStart":
                guard let id = event.test?.id, let name = event.test?.name else { continue }
                testsByID[id] = ParsedTestCase(
                    stableID: "flutter-case:\(id)",
                    suite: nil,
                    name: name,
                    status: .passed,
                    rerunSelector: .flutter(name: name)
                )
            case "testDone":
                guard let id = event.testID, var testCase = testsByID[id] else { continue }
                // Hidden tests are infrastructure (e.g. file-loading) — exclude from results
                if event.hidden == true {
                    testsByID.removeValue(forKey: id)
                    continue
                }
                if event.result == "success" {
                    testCase = ParsedTestCase(
                        stableID: testCase.stableID,
                        suite: testCase.suite,
                        name: testCase.name,
                        status: .passed,
                        durationSeconds: testCase.durationSeconds,
                        message: testCase.message,
                        file: testCase.file,
                        line: testCase.line,
                        rerunSelector: testCase.rerunSelector
                    )
                } else if event.result == "failure" || event.result == "error" {
                    testCase = ParsedTestCase(
                        stableID: testCase.stableID,
                        suite: testCase.suite,
                        name: testCase.name,
                        status: event.result == "failure" ? .failed : .errored,
                        durationSeconds: testCase.durationSeconds,
                        message: event.message,
                        file: testCase.file,
                        line: testCase.line,
                        rerunSelector: testCase.rerunSelector
                    )
                } else if event.skipped == true {
                    testCase = ParsedTestCase(
                        stableID: testCase.stableID,
                        suite: testCase.suite,
                        name: testCase.name,
                        status: .skipped,
                        durationSeconds: testCase.durationSeconds,
                        message: testCase.message,
                        file: testCase.file,
                        line: testCase.line,
                        rerunSelector: testCase.rerunSelector
                    )
                }
                testsByID[id] = testCase
            case "error":
                diagnostics.append(
                    ParsingDiagnostic(
                        severity: .error,
                        message: event.message ?? "Flutter machine output error"
                    )
                )
            default:
                continue
            }
        }

        let testCases = testsByID.values.sorted { $0.stableID < $1.stableID }
        logger.info("Parsed Flutter machine output with \(testCases.count) test case(s)")

        return ParsedTestRun(
            platform: "flutter",
            runner: "flutter-test",
            source: "machine-output",
            summary: TestSummary(
                passed: testCases.filter { $0.status == .passed }.count,
                failed: testCases.filter { $0.status == .failed }.count,
                skipped: testCases.filter { $0.status == .skipped }.count,
                errored: testCases.filter { $0.status == .errored }.count
            ),
            suites: [],
            testCases: testCases,
            diagnostics: diagnostics
        )
    }
}

extension FlutterMachineOutputParser: TestResultParser {
    public func parse(_ input: String) async throws -> ParsedTestRun {
        try await parse(machineOutput: input)
    }
}

private struct FlutterMachineEvent: Decodable {
    let type: String
    let test: FlutterMachineTest?
    let testID: Int?
    let result: String?
    let skipped: Bool?
    let hidden: Bool?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case test
        case testID = "testID"
        case result
        case skipped
        case hidden
        case message
    }
}

private struct FlutterMachineTest: Decodable {
    let id: Int
    let name: String
}
