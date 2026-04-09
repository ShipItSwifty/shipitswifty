import ArgumentParser
import ShipItKit

/// Execute a named workflow from Shipfile.yml.
///
/// ## Usage
/// ```
/// shipit run beta
/// shipit run release --ci --output json
/// ```
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Execute a named workflow from Shipfile.yml"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Name of the workflow to run")
    var workflow: String

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun)
            )
            let context = try await buildActionContext(config: config)

            guard let workflowConfig = config.workflows[workflow] else {
                throw ShipItError.invalidConfiguration(reason: "Workflow '\(workflow)' not found in Shipfile. Available workflows: \(config.workflows.keys.sorted().joined(separator: ", "))")
            }

            let registry = ActionRegistry()
            try await registerBuiltInActions(into: registry)
            let formatter = makeHumanFormatter(global: global)

            let steps = workflowConfig.map { WorkflowStep(action: $0.action, options: $0.options) }
            let workflowObj = Workflow(workflow, steps: steps)

            if global.dryRun {
                formatter.print("DRY RUN: Would execute workflow '\(workflow)' with \(steps.count) step(s):")
                for (i, step) in steps.enumerated() {
                    formatter.print("  \(i + 1). \(step.action)")
                }
                return
            }

            let result = try await workflowObj.run(context: context, registry: registry)

            switch global.output {
            case .json:
                let reporter = JSONReporter()
                let envelope = ActionResultEnvelope(
                    action: "run",
                    status: result.succeeded ? "success" : "failure",
                    payload: .object([
                        "workflow": .string(workflow),
                        "steps": .int(result.stepResults.count),
                        "duration": .double(result.duration),
                    ])
                )
                print(try reporter.encode(envelope))
            case .human:
                formatter.printSuccess("Workflow '\(workflow)' completed in \(String(format: "%.1f", result.duration))s")
            }
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}

// MARK: - Registry Bootstrap

/// Registers all built-in actions into the given registry.
func registerBuiltInActions(into registry: ActionRegistry) async throws {
    try await registry.register(BuildAction.descriptor(for: BuildAction()))
    try await registry.register(TestAction.descriptor(for: TestAction()))
    try await registry.register(ArchiveAction.descriptor(for: ArchiveAction()))
    try await registry.register(ExportAction.descriptor(for: ExportAction()))
    try await registry.register(SignAction.descriptor(for: SignAction()))
    try await registry.register(UploadAction.descriptor(for: UploadAction()))
    try await registry.register(TestFlightAction.descriptor(for: TestFlightAction()))
    try await registry.register(SnapshotAction.descriptor(for: SnapshotAction()))
    try await registry.register(FrameAction.descriptor(for: FrameAction()))
    try await registry.register(VersionAction.descriptor(for: VersionAction()))
    try await registry.register(MetadataAction.descriptor(for: MetadataAction()))
    try await registry.register(PrecheckAction.descriptor(for: PrecheckAction()))
    try await registry.register(ProvisionAction.descriptor(for: ProvisionAction()))
    try await registry.register(NotifyAction.descriptor(for: NotifyAction()))
    try await registry.register(GitAction.descriptor(for: GitAction()))
    try await registry.register(DsymAction.descriptor(for: DsymAction()))
}
