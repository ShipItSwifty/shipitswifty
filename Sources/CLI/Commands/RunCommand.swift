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
            let context = try await buildActionContext(
                config: config, verbose: global.verbose, jsonOutput: global.output == .json)

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

            let steps = workflowConfig.steps.map {
                WorkflowStep(action: $0.action, options: $0.options, when: $0.when)
            }
            let workflowObj = Workflow(
                workflow,
                steps: steps,
                buildVariant: workflowConfig.buildVariant,
                flavor: workflowConfig.flavor,
                app: workflowConfig.app,
                build: workflowConfig.build,
                archive: workflowConfig.archive,
                export: workflowConfig.export,
                codeSigning: workflowConfig.codeSigning
            )

            if global.dryRun {
                switch global.output {
                case .json:
                    let reporter = JSONReporter()
                    let envelope = ActionResultEnvelope(
                        action: "run",
                        status: "dry_run",
                        payload: .object([
                            "workflow": .string(workflow),
                            "mode": .string("dry_run"),
                            "stepCount": .int(steps.count),
                            "steps": .array(dryRunStepValues(steps)),
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
                        "stepTimings": .array(stepTimingValues(result.stepResults)),
                    ])
                )
                print(try reporter.encode(envelope))
            case .human:
                for (i, stepResult) in result.stepResults.enumerated() {
                    let stepName = steps[i].action
                    let summary = humanStepSummary(action: stepName, payload: stepResult.payload)
                    let timing = stepResult.durationSeconds.map { " (\(formatDurationSeconds($0)))" } ?? ""
                    if let summary {
                        formatter.printSuccess("  \(stepName): \(summary)\(timing)")
                    } else {
                        formatter.printSuccess("  \(stepName)\(timing)")
                    }
                }
                formatter.printSuccess("Workflow '\(workflow)' completed in \(formatDurationSeconds(result.duration))")
            }
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}

/// Projects per-step timing/status from executed workflow steps for `--output json`,
/// so CI can profile which step dominated the workflow runtime.
func stepTimingValues(_ stepResults: [ActionResultEnvelope]) -> [JSONValue] {
    stepResults.enumerated().map { index, step in
        .object([
            "index": .int(index + 1),
            "action": .string(step.action),
            "status": .string(step.status),
            "durationSeconds": step.durationSeconds.map(JSONValue.double) ?? .null,
        ])
    }
}

func dryRunStepValues(_ steps: [WorkflowStep]) -> [JSONValue] {
    steps.enumerated().map { index, step in
        .object([
            "index": .int(index + 1),
            "action": .string(step.action),
            "options": step.options ?? .null,
            "when": step.when.map(JSONValue.string) ?? .null,
        ])
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
        TestResultsAction.descriptor(
            for: TestResultsAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestResultsAction.name)),
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
        // Cross-platform: distributes both IPAs and APKs, and needs only networking,
        // so it stays out of the macOS-only block below.
        FirebaseAppDistributionAction.descriptor(
            for: FirebaseAppDistributionAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: FirebaseAppDistributionAction.name),
            validationRules: FirebaseAppDistributionAction.validationRules),
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
        VersionAction.descriptor(
            for: VersionAction(),
            optionSchema: BuiltInSchemaCatalog.optionSchema(for: VersionAction.name),
            validationRules: VersionAction.validationRules),
        AndroidCreateAction.descriptor(for: AndroidCreateAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidCreateAction.name), platforms: [.android]),
        AndroidDescribeAction.descriptor(for: AndroidDescribeAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidDescribeAction.name), platforms: [.android]),
        AndroidDocsAction.descriptor(for: AndroidDocsAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidDocsAction.name), platforms: [.android]),
        AndroidEmulatorAction.descriptor(for: AndroidEmulatorAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidEmulatorAction.name), platforms: [.android]),
        AndroidHelpAction.descriptor(for: AndroidHelpAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidHelpAction.name), platforms: [.android]),
        AndroidInfoAction.descriptor(for: AndroidInfoAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidInfoAction.name), platforms: [.android]),
        AndroidInitAction.descriptor(for: AndroidInitAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidInitAction.name), platforms: [.android]),
        AndroidInstallAction.descriptor(for: AndroidInstallAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidInstallAction.name), platforms: [.android]),
        AndroidLayoutAction.descriptor(for: AndroidLayoutAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidLayoutAction.name), platforms: [.android]),
        AndroidRunAction.descriptor(for: AndroidRunAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidRunAction.name), platforms: [.android]),
        AndroidScreenAction.descriptor(for: AndroidScreenAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidScreenAction.name), platforms: [.android]),
        AndroidSDKAction.descriptor(for: AndroidSDKAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidSDKAction.name), platforms: [.android]),
        AndroidSkillsAction.descriptor(for: AndroidSkillsAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidSkillsAction.name), platforms: [.android]),
        AndroidStudioAction.descriptor(for: AndroidStudioAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidStudioAction.name), platforms: [.android]),
        AndroidUpdateAction.descriptor(for: AndroidUpdateAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidUpdateAction.name), platforms: [.android]),
        AndroidCLIVersionAction.descriptor(for: AndroidCLIVersionAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: AndroidCLIVersionAction.name), platforms: [.android]),
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
            // Without this the semantic rules declared in ActionValidationRules.swift would
            // only run on the `shipit run` path — `validate yml` builds descriptors from the
            // schema catalog, which carries no action types to read the rules from.
            validationRules: BuiltInValidationRules.rules(for: schema.name),
            runJSON: { _, _ in
                ActionResultEnvelope(action: schema.name, status: "success", payload: nil)
            }
        )
    }
}

// MARK: - Workflow Step Summary Formatting

/// Returns a human-readable summary for a workflow step result, or `nil` for generic steps.
func humanStepSummary(action: String, payload: JSONValue?) -> String? {
    guard let payload, case .object(let dict) = payload else { return nil }

    switch action {
    case "test":
        let namedTestSummaryLimit = 3
        let pass = dict["passCount"]?.intValue ?? 0
        let fail = dict["failCount"]?.intValue ?? 0
        let skip = dict["skipCount"]?.intValue ?? 0
        let passedTests = dict["passedTests"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let failedTests = dict["failedTests"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if pass == 0 && fail == 0 && skip == 0 { return nil }
        func testCountLabel(_ count: Int, suffix: String) -> String {
            "\(count) \(count == 1 ? "test" : "tests") \(suffix)"
        }

        func namedTestsLabel(_ prefix: String, tests: [String]) -> String {
            let visibleTests = Array(tests.prefix(namedTestSummaryLimit))
            var summary = "\(prefix): \(visibleTests.joined(separator: ", "))"
            let remainingCount = tests.count - visibleTests.count
            if remainingCount > 0 {
                summary += ", +\(remainingCount) more"
            }
            return summary
        }

        var parts: [String] = []
        if !passedTests.isEmpty {
            parts.append(namedTestsLabel("passed", tests: passedTests))
        } else {
            parts.append(testCountLabel(pass, suffix: "passed"))
        }

        if !failedTests.isEmpty {
            parts.append(namedTestsLabel("failed", tests: failedTests))
        } else if fail > 0 {
            parts.append(testCountLabel(fail, suffix: "failed"))
        }

        if skip > 0 { parts.append(testCountLabel(skip, suffix: "skipped")) }
        return parts.joined(separator: ", ")

    case "version":
        if let version = dict["version"]?.stringValue {
            if let buildNumber = dict["buildNumber"]?.stringValue, !buildNumber.isEmpty {
                return "\(version) (\(buildNumber))"
            }
            return version
        }
        return nil

    case "archive":
        if let path = dict["artifactPath"]?.stringValue {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            return filename
        }
        return nil

    case "test-results":
        let parsedRun = dict["parsedRun"]?.objectValue
        let summary = parsedRun?["summary"]?.objectValue
        let passed = summary?["passed"]?.intValue ?? 0
        let failed = summary?["failed"]?.intValue ?? 0
        let skipped = summary?["skipped"]?.intValue ?? 0
        return "\(passed) passed, \(failed) failed, \(skipped) skipped"

    default:
        return nil
    }
}
