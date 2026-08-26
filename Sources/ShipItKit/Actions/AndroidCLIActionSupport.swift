import AndroidCLIKit
import Foundation
import SwiftyShell

public struct AndroidCLIWorkflowOptions: Codable, Sendable {
    public var operation: String?
    public var arguments: [String]?
    public var allowMutation: Bool?

    public init(operation: String? = nil, arguments: [String]? = nil, allowMutation: Bool? = nil) {
        self.operation = operation
        self.arguments = arguments
        self.allowMutation = allowMutation
    }
}

public struct AndroidCLIWorkflowResult: Codable, Sendable {
    public let command: [String]
    public let stdout: String
    public let stderr: String
    public let exitCode: Int
}

protocol AndroidCLIFamilyAction: Action
where Options == AndroidCLIWorkflowOptions, Result == AndroidCLIWorkflowResult {
    static var family: [String] { get }
    static var operations: Set<String> { get }
    static var mutationOperations: Set<String> { get }
    static var operationRequired: Bool { get }
    static func commandArguments(operation: String?, arguments: [String]) -> [String]
}

extension AndroidCLIFamilyAction {
    static var mutationOperations: Set<String> { [] }
    static var operationRequired: Bool { !operations.isEmpty }
    static func commandArguments(operation: String?, arguments: [String]) -> [String] {
        family + (operation.map { [$0] } ?? []) + arguments
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .android else {
            throw ShipItError.invalidConfiguration(reason: "\(Self.name) requires the Android platform.")
        }
        guard context.config.androidCLI.enabled == true else {
            throw ShipItError.invalidConfiguration(
                reason: "\(Self.name) requires `android.cli.enabled: true` in Shipfile.yml."
            )
        }

        let operation = options.operation?.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.operationRequired, operation == nil || operation?.isEmpty == true {
            throw ShipItError.invalidConfiguration(
                reason: "\(Self.name) requires an `operation`. Supported values: \(Self.operations.sorted().joined(separator: ", "))."
            )
        }
        if let operation, !Self.operations.isEmpty, !Self.operations.contains(operation) {
            throw ShipItError.invalidConfiguration(
                reason: "Unsupported \(Self.name) operation '\(operation)'. Supported values: \(Self.operations.sorted().joined(separator: ", "))."
            )
        }
        let mutates = operation.map(Self.mutationOperations.contains) ?? Self.mutationOperations.contains("*")
        if mutates, options.allowMutation != true {
            throw ShipItError.invalidConfiguration(
                reason: "\(Self.name) operation '\(operation ?? Self.family.last ?? Self.name)' requires `allow_mutation: true`."
            )
        }

        let executable = context.config.androidCLI.executablePath ?? "android"
        let cli = AndroidCLI(
            context: context.shell,
            executablePath: executable,
            sdkPath: context.config.androidCLI.sdkPath
        )

        do {
            try await AndroidCLIVersionGate.ensureSupported(cli)
            let commandArguments = Self.commandArguments(
                operation: operation,
                arguments: options.arguments ?? []
            )
            let output = try await cli.rawArguments(commandArguments).run()
            return Result(
                command: commandArguments,
                stdout: output.stdout,
                stderr: output.stderr,
                exitCode: Int(output.exitCode)
            )
        } catch let error as ShipItError {
            throw error
        } catch {
            throw ShipItError.invalidConfiguration(
                reason: "AndroidCLI command failed using '\(executable)': \(error.localizedDescription)"
            )
        }
    }
}

/// Shared minimum-version enforcement for every `android` CLI invocation, so the version
/// requirement and its error wrapping stay consistent between workflow actions and any
/// action (like `TestAction`) that needs to shell out to AndroidCLI directly.
enum AndroidCLIVersionGate {
    static func ensureSupported(_ cli: AndroidCLI) async throws {
        let versionOutput: ShellOutput
        do {
            versionOutput = try await cli.version().run()
        } catch let error as ShipItError {
            throw error
        } catch {
            throw ShipItError.invalidConfiguration(
                reason: "AndroidCLI version check failed: \(error.localizedDescription)"
            )
        }
        guard supports(versionOutput.stdout) else {
            throw ShipItError.invalidConfiguration(
                reason: "AndroidCLI 1.0 or newer is required; found '\(versionOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines))'."
            )
        }
    }

    /// Extracts the first `X.Y[.Z]`-shaped version number anywhere in `output` (rather than
    /// assuming the string starts with a bare version) and checks its major component.
    static func supports(_ output: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\.\d+(?:\.\d+)?"#) else {
            return false
        }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range),
            let majorRange = Range(match.range(at: 1), in: output),
            let major = Int(output[majorRange])
        else {
            return false
        }
        return major >= 1
    }
}
