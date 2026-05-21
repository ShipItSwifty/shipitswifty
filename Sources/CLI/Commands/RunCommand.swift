import ArgumentParser
import Foundation
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
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config, verbose: global.verbose)

            guard let workflowConfig = config.workflows[workflow] else {
                throw ShipItError.invalidConfiguration(
                    reason:
                        "Workflow '\(workflow)' not found in Shipfile. Available workflows: \(config.workflows.keys.sorted().joined(separator: ", "))"
                )
            }

            let registry = ActionRegistry()
            try await registerBuiltInActions(into: registry)
            try await registry.registerCustomActions(config.customActions)
            let formatter = makeHumanFormatter(global: global)

            let steps = workflowConfig.steps.map { WorkflowStep(action: $0.action, options: $0.options) }
            let workflowObj = Workflow(
                workflow,
                steps: steps,
                buildVariant: workflowConfig.buildVariant,
                flavor: workflowConfig.flavor
            )

            if global.dryRun {
                switch global.output {
                case .json:
                    let stepValues: [JSONValue] = steps.enumerated().map { index, step in
                        .object([
                            "index": .int(index + 1),
                            "action": .string(step.action),
                            "options": step.options ?? .null,
                        ])
                    }
                    let reporter = JSONReporter()
                    let envelope = ActionResultEnvelope(
                        action: "run",
                        status: "dry_run",
                        payload: .object([
                            "workflow": .string(workflow),
                            "mode": .string("dry_run"),
                            "stepCount": .int(steps.count),
                            "steps": .array(stepValues),
                        ])
                    )
                    print(try reporter.encode(envelope))
                case .human:
                    formatter.print("DRY RUN: Would execute workflow '\(workflow)' with \(steps.count) step(s):")
                    for (i, step) in steps.enumerated() {
                        formatter.print("  \(i + 1). \(step.action)")
                    }
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
                for (i, stepResult) in result.stepResults.enumerated() {
                    let stepName = steps[i].action
                    let summary = humanStepSummary(action: stepName, payload: stepResult.payload)
                    if let summary {
                        formatter.printSuccess("  \(stepName): \(summary)")
                    } else {
                        formatter.printSuccess("  \(stepName): ✓")
                    }
                }
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
    var descriptors: [ActionDescriptor] = [
        BuildAction.descriptor(
            for: BuildAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: BuildAction.name),
            validationRules: BuildAction.validationRules),
        TestAction.descriptor(
            for: TestAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestAction.name),
            validationRules: TestAction.validationRules),
        CoverageAction.descriptor(
            for: CoverageAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: CoverageAction.name)),
        ArchiveAction.descriptor(
            for: ArchiveAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: ArchiveAction.name),
            validationRules: ArchiveAction.validationRules),
        LintAction.descriptor(
            for: LintAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: LintAction.name)),
        PlayStoreAction.descriptor(
            for: PlayStoreAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: PlayStoreAction.name)),
        ValidateBundleAction.descriptor(
            for: ValidateBundleAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: ValidateBundleAction.name)),
        NotifyAction.descriptor(
            for: NotifyAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: NotifyAction.name),
            validationRules: NotifyAction.validationRules),
        GitAction.descriptor(
            for: GitAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: GitAction.name),
            validationRules: GitAction.validationRules),
    ]
    #if os(macOS)
    descriptors.append(contentsOf: [
        ExportAction.descriptor(
            for: ExportAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: ExportAction.name),
            validationRules: ExportAction.validationRules),
        SignAction.descriptor(
            for: SignAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: SignAction.name),
            validationRules: SignAction.validationRules),
        UploadAction.descriptor(
            for: UploadAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: UploadAction.name),
            validationRules: UploadAction.validationRules),
        TestFlightAction.descriptor(
            for: TestFlightAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestFlightAction.name),
            validationRules: TestFlightAction.validationRules),
        SnapshotAction.descriptor(
            for: SnapshotAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: SnapshotAction.name),
            validationRules: SnapshotAction.validationRules),
        FrameAction.descriptor(
            for: FrameAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: FrameAction.name)),
        VersionAction.descriptor(
            for: VersionAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: VersionAction.name),
            validationRules: VersionAction.validationRules),
        MetadataAction.descriptor(
            for: MetadataAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: MetadataAction.name),
            validationRules: MetadataAction.validationRules),
        PrecheckAction.descriptor(
            for: PrecheckAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: PrecheckAction.name)),
        ValidateArchiveAction.descriptor(
            for: ValidateArchiveAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: ValidateArchiveAction.name)),
        ProvisionAction.descriptor(
            for: ProvisionAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: ProvisionAction.name),
            validationRules: ProvisionAction.validationRules),
        DsymAction.descriptor(
            for: DsymAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: DsymAction.name),
            validationRules: DsymAction.validationRules),
        GenerateProjectAction.descriptor(
            for: GenerateProjectAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: GenerateProjectAction.name)),
    ])
    #endif
    return descriptors
}

func validationActionDescriptors() -> [ActionDescriptor] {
    BuiltInSchemaCatalog.validationActionSchemas().map { schema in
        ActionDescriptor(
            name: schema.name,
            description: schema.description,
            optionSchema: schema.options,
            runJSON: { _, _ in
                ActionResultEnvelope(action: schema.name, status: "success", payload: nil)
            }
        )
    }
}

// MARK: - Workflow Step Summary Formatting

/// Returns a human-readable summary for a workflow step result, or `nil` for generic steps.
private func humanStepSummary(action: String, payload: JSONValue?) -> String? {
    guard let payload, case let .object(dict) = payload else { return nil }

    switch action {
    case "test":
        let pass = dict["passCount"]?.intValue ?? 0
        let fail = dict["failCount"]?.intValue ?? 0
        let skip = dict["skipCount"]?.intValue ?? 0
        if pass == 0 && fail == 0 && skip == 0 { return nil }
        var parts = ["\(pass) passed"]
        if fail > 0 { parts.append("\(fail) failed") }
        if skip > 0 { parts.append("\(skip) skipped") }
        return parts.joined(separator: ", ")

    case "version":
        if let version = dict["version"]?.stringValue {
            return version
        }
        return nil

    case "archive":
        if let path = dict["artifactPath"]?.stringValue {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            return filename
        }
        return nil

    default:
        return nil
    }
}
