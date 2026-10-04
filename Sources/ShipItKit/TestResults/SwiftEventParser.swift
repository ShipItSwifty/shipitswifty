import Foundation

/// Reads Swift Testing's saved event stream without interpreting human console output.
public struct SwiftEventParser: Sendable {
    public init() {}
    public func parse(path: String) throws -> ParsedTestRun {
        struct State {
            var id: String
            var name: String
            var file: String?
            var line: Int?
            var started: Double?
            var ended: Double?
            var failed = false
            var skipped = false
            var messages: [String] = []
        }
        var states: [String: State] = [:]
        var recognized = false
        for line in try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines) where !line.isEmpty {
            guard let data = line.data(using: .utf8), let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = record["payload"] as? [String: Any]
            else { continue }
            recognized = true
            if record["kind"] as? String == "test", payload["kind"] as? String == "function", let id = payload["id"] as? String {
                let location = payload["sourceLocation"] as? [String: Any]
                states[id] = State(
                    id: id, name: payload["displayName"] as? String ?? payload["name"] as? String ?? id,
                    file: location?["filePath"] as? String, line: location?["line"] as? Int)
            }
            if record["kind"] as? String == "event", let id = payload["testID"] as? String, var state = states[id] {
                let instant = (payload["instant"] as? [String: Any])?["absolute"] as? Double
                switch payload["kind"] as? String {
                case "testStarted": state.started = instant
                case "testEnded": state.ended = instant
                case "testSkipped": state.skipped = true
                case "issueRecorded":
                    let issue = payload["issue"] as? [String: Any]
                    if issue?["isKnown"] as? Bool != true {
                        state.failed = true
                        state.messages += (payload["messages"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
                        if let comment = issue?["comment"] as? String { state.messages.append(comment) }
                    }
                default: break
                }
                states[id] = state
            }
        }
        guard recognized else { throw ShipItError.invalidConfiguration(reason: "No Swift Testing event records in \(path)") }
        let cases = states.values.filter { $0.started != nil || $0.skipped }.map { state in
            let selector = state.id.split(separator: "/").prefix(2).joined(separator: "/")
            return ParsedTestCase(
                stableID: "swift-case:" + selector, name: state.name,
                status: state.skipped ? .skipped : state.failed ? .failed : state.ended == nil ? .errored : .passed,
                durationSeconds: state.ended.flatMap { end in state.started.map { max(0, end - $0) } },
                message: state.messages.isEmpty
                    ? (state.ended == nil && !state.skipped ? "Test did not finish" : nil) : state.messages.joined(separator: "\n"),
                file: state.file, line: state.line, rerunSelector: .swiftTestFilter(selector))
        }.sorted { $0.stableID < $1.stableID }
        return ParsedTestRun(
            platform: "swift", runner: "swift-test", source: path,
            summary: .init(
                passed: cases.filter { $0.status == .passed }.count, failed: cases.filter { $0.status == .failed }.count,
                skipped: cases.filter { $0.status == .skipped }.count, errored: cases.filter { $0.status == .errored }.count),
            testCases: cases)
    }
}
