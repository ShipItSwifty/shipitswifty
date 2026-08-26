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
            let versionOutput = try await cli.version().run()
            guard Self.supports(versionOutput.stdout) else {
                throw ShipItError.invalidConfiguration(
                    reason: "AndroidCLI 1.0 or newer is required; found '\(versionOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines))'."
                )
            }
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

    private static func supports(_ output: String) -> Bool {
        guard let major = output.split(separator: ".").first.flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else {
            return false
        }
        return major >= 1
    }
}
