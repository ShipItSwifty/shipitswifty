#if os(macOS)
import Foundation
import SwiftyShell

/// A format accepted by `plutil -convert`.
public enum PlutilConversionFormat: String, Sendable {
    /// XML property list format, version 1.
    case xml = "xml1"
    /// Binary property list format, version 1.
    case binary = "binary1"
    /// JSON format.
    case json
    /// Swift literal syntax.
    case swift
    /// Objective-C literal syntax.
    case objectiveC = "objc"
}

/// A format accepted by `plutil -extract`.
public enum PlutilExtractionFormat: String, Sendable {
    /// XML property list format, version 1.
    case xml = "xml1"
    /// Binary property list format, version 1.
    case binary = "binary1"
    /// JSON format.
    case json
}

/// A property list type that `plutil` can verify while extracting a value.
public enum PlutilValueType: String, Sendable {
    /// A Boolean value.
    case bool
    /// A signed 64-bit integer.
    case integer
    /// A 64-bit floating-point value.
    case float
    /// A UTF-8 string.
    case string
    /// A property list date.
    case date
    /// Binary data.
    case data
    /// A dictionary.
    case dictionary
    /// An array.
    case array
}

/// A typed value accepted by `plutil -insert` and `plutil -replace`.
public enum PlutilValue: Sendable {
    /// A Boolean value.
    case bool(Bool)
    /// A signed 64-bit integer.
    case integer(Int64)
    /// A 64-bit floating-point value.
    case float(Double)
    /// A UTF-8 string.
    case string(String)
    /// A date encoded in the XML property list date format.
    case date(Date)
    /// Binary data, encoded as Base64 when passed to `plutil`.
    case data(Data)
    /// An XML property list fragment for a compound value.
    case xml(String)
    /// A JSON fragment for a compound value.
    case json(String)

    fileprivate var arguments: [String] {
        switch self {
        case .bool(let value):
            ["-bool", value ? "YES" : "NO"]
        case .integer(let value):
            ["-integer", String(value)]
        case .float(let value):
            ["-float", String(value)]
        case .string(let value):
            ["-string", value]
        case .date(let value):
            ["-date", value.formatted(.iso8601)]
        case .data(let value):
            ["-data", value.base64EncodedString()]
        case .xml(let value):
            ["-xml", value]
        case .json(let value):
            ["-json", value]
        }
    }
}

/// An empty property list collection accepted by `plutil -insert`.
public enum PlutilEmptyCollection: String, Sendable {
    /// An empty array.
    case array
    /// An empty dictionary.
    case dictionary
}

/// The destination for a converted property list.
public enum PlutilConversionOutput: Sendable {
    /// Replaces the input file with its converted representation.
    case replaceInput
    /// Writes the converted property list to a file.
    case file(String)
    /// Writes the converted property list to standard output.
    case standardOutput

    fileprivate var arguments: [String] {
        switch self {
        case .replaceInput:
            []
        case .file(let path):
            ["-o", path]
        case .standardOutput:
            ["-o", "-"]
        }
    }
}

/// A typed wrapper for macOS property list validation, conversion, extraction, and mutation.
///
/// Build one operation and execute it through SwiftyShell with ``run()``.
public struct Plutil: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination

    private let operation: Operation?

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates a `plutil` command family bound to a shell context.
    public init(context: ShellContext = .init()) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.operation = nil
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        operation: Operation?
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.operation = operation
    }

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(_ update: (ToolConfiguration) -> ToolConfiguration) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for the built `plutil` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `plutil` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Checks one or more property list files for syntax errors.
    /// - Parameters:
    ///   - plistPath: The first property list to check.
    ///   - additionalPlistPaths: Any additional property lists to check in the same invocation.
    public func lint(_ plistPath: String, additionalPlistPaths: [String] = []) -> Self {
        copy(operation: .lint([plistPath] + additionalPlistPaths))
    }

    /// Converts a property list to another representation.
    public func convert(
        _ plistPath: String,
        to format: PlutilConversionFormat,
        output: PlutilConversionOutput = .replaceInput,
        prettyPrinted: Bool = false
    ) -> Self {
        copy(operation: .convert(path: plistPath, format: format, output: output, prettyPrinted: prettyPrinted))
    }

    /// Extracts a value as a standalone property list, optionally asserting its type.
    public func extract(
        _ keyPath: String,
        as format: PlutilExtractionFormat,
        expectedType: PlutilValueType? = nil,
        from plistPath: String
    ) -> Self {
        copy(operation: .extract(keyPath: keyPath, format: format.rawValue, expectedType: expectedType, path: plistPath))
    }

    /// Extracts the unencapsulated representation of a property list value.
    public func extractRaw(
        _ keyPath: String,
        expectedType: PlutilValueType? = nil,
        from plistPath: String,
        omitTrailingNewline: Bool = false
    ) -> Self {
        copy(
            operation: .extractRaw(
                keyPath: keyPath,
                expectedType: expectedType,
                path: plistPath,
                omitTrailingNewline: omitTrailingNewline
            ))
    }

    /// Inserts a typed value at a key path that does not already exist.
    public func insert(_ value: PlutilValue, at keyPath: String, in plistPath: String) -> Self {
        copy(operation: .insert(keyPath: keyPath, value: value, path: plistPath, append: false))
    }

    /// Appends a typed value to the array at a key path.
    public func append(_ value: PlutilValue, toArrayAt keyPath: String, in plistPath: String) -> Self {
        copy(operation: .insert(keyPath: keyPath, value: value, path: plistPath, append: true))
    }

    /// Inserts an empty array or dictionary at a key path that does not already exist.
    public func insertEmpty(_ collection: PlutilEmptyCollection, at keyPath: String, in plistPath: String) -> Self {
        copy(operation: .insertEmpty(keyPath: keyPath, collection: collection, path: plistPath))
    }

    /// Replaces an existing value at a key path.
    public func replace(_ value: PlutilValue, at keyPath: String, in plistPath: String) -> Self {
        copy(operation: .replace(keyPath: keyPath, value: value, path: plistPath))
    }

    /// Removes the value at a key path.
    public func remove(_ keyPath: String, from plistPath: String) -> Self {
        copy(operation: .remove(keyPath: keyPath, path: plistPath))
    }

    /// Builds the selected `plutil` command.
    public func command() -> Command {
        let base = Command("plutil")
            .args(operation?.arguments ?? [])
            .stdout(stdoutDestination)
            .stderr(stderrDestination)

        return config.apply(to: base)
    }

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        operation: Operation? = nil
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            operation: operation ?? self.operation
        )
    }
}

extension Plutil {
    private enum Operation: Sendable {
        case lint([String])
        case convert(
            path: String,
            format: PlutilConversionFormat,
            output: PlutilConversionOutput,
            prettyPrinted: Bool
        )
        case extract(keyPath: String, format: String, expectedType: PlutilValueType?, path: String)
        case extractRaw(keyPath: String, expectedType: PlutilValueType?, path: String, omitTrailingNewline: Bool)
        case insert(keyPath: String, value: PlutilValue, path: String, append: Bool)
        case insertEmpty(keyPath: String, collection: PlutilEmptyCollection, path: String)
        case replace(keyPath: String, value: PlutilValue, path: String)
        case remove(keyPath: String, path: String)

        var arguments: [String] {
            switch self {
            case .lint(let paths):
                ["-lint", "--"] + paths
            case .convert(let path, let format, let output, let prettyPrinted):
                ["-convert", format.rawValue] + output.arguments + (prettyPrinted ? ["-r"] : []) + ["--", path]
            case .extract(let keyPath, let format, let expectedType, let path):
                extractArguments(keyPath: keyPath, format: format, expectedType: expectedType, path: path)
            case .extractRaw(let keyPath, let expectedType, let path, let omitTrailingNewline):
                extractArguments(
                    keyPath: keyPath,
                    format: "raw",
                    expectedType: expectedType,
                    options: omitTrailingNewline ? ["-n"] : [],
                    path: path
                )
            case .insert(let keyPath, let value, let path, let append):
                ["-insert", keyPath] + value.arguments + (append ? ["-append"] : []) + ["--", path]
            case .insertEmpty(let keyPath, let collection, let path):
                ["-insert", keyPath, "-\(collection.rawValue)", "--", path]
            case .replace(let keyPath, let value, let path):
                ["-replace", keyPath] + value.arguments + ["--", path]
            case .remove(let keyPath, let path):
                ["-remove", keyPath, "--", path]
            }
        }

        private func extractArguments(
            keyPath: String,
            format: String,
            expectedType: PlutilValueType?,
            options: [String] = [],
            path: String
        ) -> [String] {
            ["-extract", keyPath, format]
                + (expectedType.map { ["-expect", $0.rawValue] } ?? [])
                + options
                + ["--", path]
        }
    }
}
#endif
