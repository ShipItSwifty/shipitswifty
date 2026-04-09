import Foundation
import ShipItKit

/// Formats output as machine-readable JSON for CI systems.
///
/// Used by CLI commands when `--output json` is selected.
/// All output follows the `ActionResultEnvelope` schema.
public struct JSONFormatter: Sendable {
    private let reporter: JSONReporter

    public init(prettyPrint: Bool = true) {
        self.reporter = JSONReporter(prettyPrint: prettyPrint)
    }

    /// Print an action result as a JSON envelope.
    ///
    /// - Parameters:
    ///   - action: The action name.
    ///   - result: The Codable result value.
    public func printResult<T: Codable & Sendable>(action: String, result: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let payload: JSONValue
        if let data = try? encoder.encode(result),
           let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data) {
            payload = jsonValue
        } else {
            payload = .null
        }

        let envelope = ActionResultEnvelope(action: action, status: "success", payload: payload)
        if let json = try? reporter.encode(envelope) {
            print(json)
        }
    }

    /// Print an error as a JSON envelope.
    ///
    /// - Parameters:
    ///   - action: The action name that failed.
    ///   - error: The error that occurred.
    public func printError(action: String, error: ShipItError, suggestions: [String] = []) {
        let envelope = ActionResultEnvelope(
            action: action,
            status: "failure",
            payload: .object([
                "error": .string(error.errorDescription ?? error.localizedDescription),
                "exitCode": .int(Int(error.exitCode)),
                "suggestions": .array(suggestions.map { .string($0) }),
            ])
        )
        if let json = try? reporter.encode(envelope) {
            print(json)
        }
    }
}
