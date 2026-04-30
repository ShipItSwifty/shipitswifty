import Foundation
import OSLog
import SwiftyShell

/// Generates an Xcode project from a project spec file (e.g. XcodeGen's `project.yml`).
///
/// This action supports spec-driven iOS project workflows where the `.xcodeproj` is a
/// generated artifact rather than a checked-in source of truth. When configured in
/// `Shipfile.yml`, it runs before any action that requires an Xcode container.
///
/// ## Usage
/// ```swift
/// let result = try await GenerateProjectAction().run(
///     with: .init(),
///     context: context
/// )
/// print("Generated project: \(result.outputProject)")
/// ```
public struct GenerateProjectAction: Action {
    public static let name = "generate_project"
    public static let description = "Generate Xcode project from a spec file (e.g. XcodeGen project.yml)"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", GenerateProjectAction.self)

    /// Creates a `GenerateProjectAction`.
    public init() {}

    /// Configuration for the generate project action.
    public struct Options: Codable, Sendable {
        /// Override the generation command (e.g. `xcodegen generate --spec alt.yml`).
        public var command: String?

        /// Path to the project spec file. Falls back to config `project_generation.spec_path`.
        public var specPath: String?

        /// Path to the expected output project. Falls back to config.
        public var outputProject: String?

        /// Force regeneration even if the output project already exists.
        public var force: Bool?

        /// Creates `Options` for the generate project action.
        public init(
            command: String? = nil,
            specPath: String? = nil,
            outputProject: String? = nil,
            force: Bool? = nil
        ) {
            self.command = command
            self.specPath = specPath
            self.outputProject = outputProject
            self.force = force
        }
    }

    /// Result of project generation.
    public struct Result: Codable, Sendable {
        /// The path to the generated project.
        public let outputProject: String

        /// Whether the project was generated in this run (vs. already existed).
        public let generated: Bool

        /// The command that was executed, if any.
        public let commandExecuted: String?

        /// Creates a `Result`.
        public init(outputProject: String, generated: Bool, commandExecuted: String?) {
            self.outputProject = outputProject
            self.generated = generated
            self.commandExecuted = commandExecuted
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let config = context.config

        // Resolve the generation command
        let command = options.command ?? config.projectGenerationCommand
        guard let command, !command.isEmpty else {
            throw ShipItError.invalidConfiguration(
                reason: """
                    No project generation command configured. \
                    Set project_generation.command in Shipfile.yml (e.g. "xcodegen generate") \
                    or pass it as an option to the generate_project action.
                    """
            )
        }

        // Resolve spec path for validation
        let specPath = options.specPath ?? config.projectGenerationSpecPath
        if let specPath {
            guard FileManager.default.fileExists(atPath: specPath) else {
                throw ShipItError.invalidConfiguration(
                    reason: """
                        Project spec file not found at '\(specPath)'. \
                        Ensure the spec_path in project_generation config points to an existing file \
                        (e.g. project.yml for XcodeGen).
                        """
                )
            }
        }

        // Resolve output project path
        let outputProject = options.outputProject ?? config.projectGenerationOutputProject

        // Check if generation is needed
        let force = options.force ?? false
        if !force, let outputProject, FileManager.default.fileExists(atPath: outputProject) {
            logger.info("Output project '\(outputProject)' already exists, skipping generation")
            return Result(outputProject: outputProject, generated: false, commandExecuted: nil)
        }

        // Execute the generation command
        logger.info("Generating project with command: \(command)")

        let parts = command.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let executable = parts.first else {
            throw ShipItError.invalidConfiguration(
                reason: "Project generation command is empty after parsing: '\(command)'"
            )
        }
        let args = Array(parts.dropFirst())

        let output: ShellOutput
        do {
            output = try await Command(executable).args(args).run(in: context.shell)
        } catch let ShellError.exitFailure(cmd, shellOutput) {
            let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            logger.error("Project generation failed: \(combinedLog)")
            throw ShipItError.buildFailed(
                exitCode: Int(shellOutput.exitCode),
                log: "Project generation command '\(cmd)' failed:\n\(combinedLog)"
            )
        }

        // Verify the output was created
        if let outputProject {
            guard FileManager.default.fileExists(atPath: outputProject) else {
                throw ShipItError.invalidConfiguration(
                    reason: """
                        Project generation command succeeded but the expected output \
                        '\(outputProject)' was not found. Check that the command produces \
                        output at the configured output_project path.
                        """
                )
            }
            logger.info("Project generated successfully at '\(outputProject)'")
            return Result(outputProject: outputProject, generated: true, commandExecuted: command)
        }

        // No output project configured — trust the command succeeded
        logger.info("Project generation command completed successfully")
        return Result(
            outputProject: output.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            generated: true,
            commandExecuted: command
        )
    }
}

// MARK: - Project Generation Helper

extension ActionContext {
    /// Actions that require an Xcode container (`.xcodeproj` / `.xcworkspace`) call this
    /// method to ensure the project exists. If project generation is configured and the
    /// output project is missing, this runs the generation command automatically.
    ///
    /// - Throws: `ShipItError` when generation fails or is needed but not configured.
    public func ensureProjectGenerated() async throws {
        let config = self.config
        guard config.projectGenerationTool != nil || config.projectGenerationCommand != nil else {
            // No project generation configured — nothing to do
            return
        }

        guard config.projectGenerationAutoGenerate else {
            // Auto-generation disabled
            return
        }

        // Check if the output project already exists
        if let outputProject = config.projectGenerationOutputProject,
            FileManager.default.fileExists(atPath: outputProject)
        {
            return
        }

        // Need to generate — run the action
        let action = GenerateProjectAction()
        _ = try await action.run(
            with: .init(force: false),
            context: self
        )
    }
}
