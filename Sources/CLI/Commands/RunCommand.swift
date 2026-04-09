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
    for descriptor in builtInActionDescriptors() {
        try await registry.register(descriptor)
    }
}

func builtInActionDescriptors() -> [ActionDescriptor] {
    [
        BuildAction.descriptor(for: BuildAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: BuildAction.name)),
        TestAction.descriptor(for: TestAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestAction.name)),
        ArchiveAction.descriptor(for: ArchiveAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: ArchiveAction.name)),
        ExportAction.descriptor(for: ExportAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: ExportAction.name)),
        SignAction.descriptor(for: SignAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: SignAction.name)),
        UploadAction.descriptor(for: UploadAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: UploadAction.name)),
        TestFlightAction.descriptor(for: TestFlightAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestFlightAction.name)),
        SnapshotAction.descriptor(for: SnapshotAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: SnapshotAction.name)),
        FrameAction.descriptor(for: FrameAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: FrameAction.name)),
        VersionAction.descriptor(for: VersionAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: VersionAction.name)),
        MetadataAction.descriptor(for: MetadataAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: MetadataAction.name)),
        PrecheckAction.descriptor(for: PrecheckAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: PrecheckAction.name)),
        ProvisionAction.descriptor(for: ProvisionAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: ProvisionAction.name)),
        NotifyAction.descriptor(for: NotifyAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: NotifyAction.name)),
        GitAction.descriptor(for: GitAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: GitAction.name)),
        DsymAction.descriptor(for: DsymAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: DsymAction.name)),
    ]
}
