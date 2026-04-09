import Foundation

/// Encodes `ActionResultEnvelope` values to JSON strings for CLI output.
///
/// Used by CLI commands when `--output json` is specified to produce
/// machine-readable output suitable for CI systems.
///
/// ## Usage
/// ```swift
/// let reporter = JSONReporter()
/// let envelope = ActionResultEnvelope(action: "build", status: "success", payload: nil)
/// let json = try reporter.encode(envelope)
/// print(json)
/// ```
public struct JSONReporter: Sendable {
    private let encoder: JSONEncoder

    /// Creates a `JSONReporter` with pretty-printed output by default.
    ///
    /// - Parameter prettyPrint: When `true` (default), output is indented for readability.
    public init(prettyPrint: Bool = true) {
        let enc = JSONEncoder()
        if prettyPrint {
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        self.encoder = enc
    }

    /// Encodes an `ActionResultEnvelope` to a JSON string.
    ///
    /// - Parameter envelope: The result envelope to encode.
    /// - Returns: A JSON string representation.
    /// - Throws: An encoding error if serialization fails.
    public func encode(_ envelope: ActionResultEnvelope) throws -> String {
        let data = try encoder.encode(envelope)
        return String(decoding: data, as: UTF8.self)
    }

    /// Encodes any `Encodable` value to a JSON string.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: A JSON string representation.
    /// - Throws: An encoding error if serialization fails.
    public func encodeAny<T: Encodable & Sendable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
