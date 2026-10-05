import Foundation
import Yams

/// Explicit setup for an exported provider job; setup does not run during export.
public struct CIJobConfiguration: Sendable {
    public let runner: String
    public let setupCommands: [String]
    public let executable: String
    public let shipfile: String
    public init(runner: String, setupCommands: [String], executable: String = "shipit", shipfile: String = "Shipfile.yml") {
        self.runner = runner
        self.setupCommands = setupCommands
        self.executable = executable
        self.shipfile = shipfile
    }
}

/// Statically registered provider plugins translate lane and artifact contracts to native CI configuration.
public protocol CIProvider: Sendable {
    var name: String { get }
    func export(workflow: String, config: WorkflowConfig, job: CIJobConfiguration) throws -> String
}

/// The built-in GitHub Actions provider. No credentials or runtime upload are required by ShipIt.
public struct GitHubActionsProvider: CIProvider {
    public let name = "github-actions"
    public init() {}
    public func export(workflow: String, config: WorkflowConfig, job: CIJobConfiguration) throws -> String {
        guard !job.runner.isEmpty else { throw ShipItError.invalidConfiguration(reason: "CI export requires an explicit runner") }
        var steps: [[String: Any]] = [["name": "Checkout", "uses": "actions/checkout@v7", "with": ["persist-credentials": false]]]
        for (index, command) in job.setupCommands.enumerated() { steps.append(["name": "Setup \(index + 1)", "run": command]) }
        steps.append([
            "name": "Run \(workflow)", "run": "\(quote(job.executable)) run \(quote(workflow)) --shipfile \(quote(job.shipfile)) --ci",
        ])
        for (index, step) in config.steps.enumerated() {
            for artifact in step.artifacts ?? [] {
                guard artifact.name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
                    throw ShipItError.invalidConfiguration(reason: "Invalid artifact name: \(artifact.name)")
                }
                var settings: [String: Any] = [
                    "name": "\(safe(workflow))-step-\(index + 1)-\(artifact.name)",
                    "path": "build/workflow-artifacts/*/step-\(index + 1)/\(artifact.name)/", "if-no-files-found": "warn",
                ]
                if let days = artifact.retentionDays {
                    guard (1...90).contains(days) else {
                        throw ShipItError.invalidConfiguration(reason: "Artifact retention_days must be 1...90")
                    }
                    settings["retention-days"] = days
                }
                steps.append(["name": "Publish \(artifact.name)", "if": "always()", "uses": "actions/upload-artifact@v7", "with": settings])
            }
        }
        // Includes automatically discovered outputs, composite outputs, and failure manifests.
        steps.append([
            "name": "Publish lane evidence", "if": "always()", "uses": "actions/upload-artifact@v7",
            "with": [
                "name": "\(safe(workflow))-evidence", "path": "build/workflow-artifacts/", "if-no-files-found": "warn",
                "retention-days": config.steps.flatMap { $0.artifacts ?? [] }.compactMap(\.retentionDays).min() ?? 14,
            ],
        ])
        return try Yams.dump(object: [
            "name": workflow, "on": ["push", "pull_request"], "permissions": ["contents": "read"],
            "jobs": [safe(workflow): ["runs-on": job.runner, "steps": steps]],
        ])
    }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func safe(_ value: String) -> String {
        value.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
    }
}

/// Provider registration is explicit and statically linked, like action plugins.
public struct CIProviderRegistry: Sendable {
    private let providers: [any CIProvider]
    public init(providers: [any CIProvider] = [GitHubActionsProvider()]) { self.providers = providers }
    public func provider(named name: String) throws -> any CIProvider {
        guard let provider = providers.first(where: { $0.name == name }) else {
            throw ShipItError.invalidConfiguration(
                reason: "Unknown CI provider '\(name)'; available: \(providers.map(\.name).joined(separator: ", "))")
        }
        return provider
    }
}
