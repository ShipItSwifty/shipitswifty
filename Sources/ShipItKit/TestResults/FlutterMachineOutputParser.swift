import Foundation
import Logging

/// Parses saved `flutter test --machine` events; incomplete tests are errors.
public struct FlutterMachineOutputParser: Sendable {
    private let logger: Logger
    public init(logger: Logger = Logger.forType(subsystem: "ShipItSwifty", FlutterMachineOutputParser.self)) { self.logger = logger }
    public func parse(machineOutput: String) async throws -> ParsedTestRun {
        struct Pending {
            var name: String
            var file: String?
            var started: Double?
            var status: TestCaseStatus = .errored
            var message: String? = "Test did not finish"
            var duration: Double?
        }
        var tests: [Int: Pending] = [:]
        var suiteFiles: [Int: String] = [:]
        var diagnostics: [ParsingDiagnostic] = []
        var recognized = false
        for line in machineOutput.components(separatedBy: .newlines) {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = event["type"] as? String
            else { continue }
            recognized = true
            switch type {
            case "suite":
                if let suite = event["suite"] as? [String: Any], let id = suite["id"] as? Int, let path = suite["path"] as? String {
                    suiteFiles[id] = path
                }
            case "testStart":
                if let test = event["test"] as? [String: Any], let id = test["id"] as? Int, let name = test["name"] as? String {
                    tests[id] = Pending(
                        name: name, file: (test["suiteID"] as? Int).flatMap { suiteFiles[$0] }, started: event["time"] as? Double)
                }
            case "error":
                let message = [event["error"] as? String ?? event["message"] as? String, event["stackTrace"] as? String].compactMap { $0 }
                    .joined(separator: "\n")
                if let id = event["testID"] as? Int, tests[id] != nil {
                    tests[id]?.message = message
                } else {
                    diagnostics.append(.init(severity: .error, message: message))
                }
            case "testDone":
                guard let id = event["testID"] as? Int, var test = tests[id] else { continue }
                if event["hidden"] as? Bool == true {
                    tests.removeValue(forKey: id)
                    continue
                }
                let result = event["result"] as? String
                test.status =
                    event["skipped"] as? Bool == true ? .skipped : result == "success" ? .passed : result == "failure" ? .failed : .errored
                if test.status == .passed || test.status == .skipped {
                    test.message = nil
                } else if let message = event["message"] as? String {
                    test.message = message
                }
                if let end = event["time"] as? Double, let start = test.started { test.duration = max(0, end - start) / 1000 }
                tests[id] = test
            default: break
            }
        }
        guard recognized else { throw ShipItError.invalidConfiguration(reason: "No Flutter machine events found.") }
        let cases = tests.values.map { test in
            ParsedTestCase(
                stableID: "flutter-case:\(test.file ?? "unknown"):\(test.name)", name: test.name,
                status: test.status, durationSeconds: test.duration, message: test.message, file: test.file,
                rerunSelector: .flutter(name: test.name))
        }.sorted { $0.stableID < $1.stableID }
        return ParsedTestRun(
            platform: "flutter", runner: "flutter-test", source: "machine-output",
            summary: TestSummary(
                passed: cases.filter { $0.status == .passed }.count, failed: cases.filter { $0.status == .failed }.count,
                skipped: cases.filter { $0.status == .skipped }.count, errored: cases.filter { $0.status == .errored }.count),
            testCases: cases, diagnostics: diagnostics)
    }
}
extension FlutterMachineOutputParser: TestResultParser {
    public func parse(_ input: String) async throws -> ParsedTestRun { try await parse(machineOutput: input) }
}
