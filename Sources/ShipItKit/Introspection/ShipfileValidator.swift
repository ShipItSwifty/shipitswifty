import Foundation
import Yams

public struct ShipfileValidator: Sendable {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func validate(shipfilePath: String, actionDescriptors: [ActionDescriptor]) async -> ValidationReport {
        let absolutePath = URL(fileURLWithPath: shipfilePath).path

        guard FileManager.default.fileExists(atPath: absolutePath) else {
            return ValidationReport(
                shipfilePath: absolutePath,
                issues: [.init(severity: .error, path: "$", message: "Shipfile not found at \(absolutePath)")]
            )
        }

        let contents: String
        do {
            contents = try String(contentsOfFile: absolutePath, encoding: .utf8)
        } catch {
            return ValidationReport(
                shipfilePath: absolutePath,
                issues: [.init(severity: .error, path: "$", message: "Failed to read Shipfile: \(error.localizedDescription)")]
            )
        }

        return await validate(shipfileContents: contents, shipfilePath: absolutePath, actionDescriptors: actionDescriptors)
    }

    public func validate(
        shipfileContents: String, shipfilePath: String = "<generated>", actionDescriptors: [ActionDescriptor]
    ) async -> ValidationReport {
        var issues: [ValidationIssue] = []
        let normalizedPath = shipfilePath

        let rawJSON: JSONValue
        do {
            rawJSON = try SchemaValidator.jsonValue(fromYAML: shipfileContents, environment: environment)
            issues.append(contentsOf: SchemaValidator.validate(value: rawJSON, against: BuiltInSchemaCatalog.shipfileFields()))
        } catch {
            return ValidationReport(
                shipfilePath: normalizedPath,
                issues: [.init(severity: .error, path: "$", message: "Failed to parse Shipfile: \(error.localizedDescription)")]
            )
        }

        let resolvedConfig = await resolvedConfig(from: shipfileContents)
        switch resolvedConfig {
        case .failure(let error):
            issues.append(.init(severity: .error, path: "$", message: "Failed to resolve config: \(error.localizedDescription)"))
            return ValidationReport(shipfilePath: normalizedPath, issues: issues)
        case .success(let config):
            issues.append(contentsOf: validationIssues(for: config, actionDescriptors: actionDescriptors))
            return ValidationReport(shipfilePath: normalizedPath, issues: issues)
        }
    }

    private func resolvedConfig(from shipfileContents: String) async -> Result<ResolvedConfig, Error> {
        let temporaryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShipItValidation_\(UUID().uuidString).yml")

        do {
            try shipfileContents.write(to: temporaryPath, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: temporaryPath) }

            let env = Environment(env: environment)
            let resolver = ConfigResolver(environment: env)
            return .success(try await resolver.resolve(shipfilePath: temporaryPath.path))
        } catch {
            try? FileManager.default.removeItem(at: temporaryPath)
            return .failure(error)
        }
    }

    private func validationIssues(for resolvedConfig: ResolvedConfig, actionDescriptors: [ActionDescriptor]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        let builtInNames = Set(actionDescriptors.map(\.name))
        var descriptorsByName = Dictionary(uniqueKeysWithValues: actionDescriptors.map { ($0.name, $0) })

        // Validate custom actions themselves, then inject pseudo-descriptors so
        // workflow steps referencing them aren't flagged as unknown.
        issues.append(
            contentsOf: customActionIssues(
                customActions: resolvedConfig.customActions,
                builtInNames: builtInNames
            ))

        for (compositeName, config) in resolvedConfig.customActions {
            let compositeSchema = CompositeAction.parameterSchema(for: config)
            descriptorsByName[compositeName] = ActionDescriptor(
                name: compositeName,
                description: config.description ?? "Custom composite action.",
                optionSchema: compositeSchema,
                runJSON: { _, _ in
                    ActionResultEnvelope(action: compositeName, status: "success", payload: nil)
                }
            )
        }

        for (workflowName, workflowConfig) in resolvedConfig.workflows.sorted(by: { $0.key < $1.key }) {
            for (index, step) in workflowConfig.steps.enumerated() {
                let stepPath = "$.workflows.\(workflowName)[\(index)]"

                guard let descriptor = descriptorsByName[step.action] else {
                    issues.append(.init(severity: .error, path: stepPath + ".action", message: "Unknown action '\(step.action)'."))
                    continue
                }

                let optionValue = step.options ?? .object([:])
                if !descriptor.optionSchema.isEmpty {
                    if optionValue.objectValue == nil {
                        issues.append(
                            .init(severity: .error, path: stepPath + ".options", message: "Expected an object of workflow options."))
                    } else {
                        issues.append(
                            contentsOf: SchemaValidator.validate(
                                value: .object(["options": optionValue]),
                                against: [
                                    .object("options", description: "Action options.", properties: descriptor.optionSchema)
                                ]
                            ).map {
                                ValidationIssue(
                                    severity: $0.severity, path: $0.path.replacingOccurrences(of: "$.options", with: stepPath + ".options"),
                                    message: $0.message)
                            })
                    }
                }

                issues.append(
                    contentsOf: semanticIssues(
                        workflowName: workflowName,
                        stepIndex: index,
                        step: step,
                        allSteps: workflowConfig.steps,
                        descriptor: descriptor,
                        config: resolvedConfig
                    ).map {
                        ValidationIssue(severity: $0.severity, path: stepPath + ($0.path == "$" ? "" : $0.path), message: $0.message)
                    })
            }
        }

        issues.append(contentsOf: ascWarningsIfNeeded(config: resolvedConfig))
        return issues
    }

    private func semanticIssues(
        workflowName: String,
        stepIndex: Int,
        step: WorkflowStepConfig,
        allSteps: [WorkflowStepConfig],
        descriptor: ActionDescriptor,
        config: ResolvedConfig
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if workflowName.isEmpty {
            issues.append(.init(severity: .warning, path: "$", message: "Workflow names should not be empty."))
        }

        let ctx = ActionValidationContext(
            options: step.options?.objectValue ?? [:],
            stepIndex: stepIndex,
            allSteps: allSteps,
            config: config
        )

        for rule in descriptor.validationRules {
            if let issue = rule.evaluate(context: ctx) {
                issues.append(issue)
            }
        }

        return issues
    }

    private func ascWarningsIfNeeded(config: ResolvedConfig) -> [ValidationIssue] {
        let ascActions: Set<String> = ["upload", "testflight", "metadata", "provision", "dsym"]
        let usesASC = config.workflows.values.flatMap { $0.steps }.contains { ascActions.contains($0.action.lowercased()) }
        guard usesASC else { return [] }

        let credentialsPresent = config.ascKeyID != nil && config.ascIssuerID != nil && config.ascPrivateKeyData != nil
        guard !credentialsPresent else { return [] }

        return [
            .init(
                severity: .warning,
                path: "$",
                message:
                    "ASC-backed workflows are configured, but ASC credentials are not fully resolved in the current environment. Validation assumes they may be supplied by CI environment variables."
            )
        ]
    }

    private func customActionIssues(
        customActions: [String: CustomActionConfig],
        builtInNames: Set<String>
    ) -> [ValidationIssue] {
        guard !customActions.isEmpty else { return [] }
        var issues: [ValidationIssue] = []

        // Collision with built-ins.
        for name in customActions.keys.sorted() where builtInNames.contains(name) {
            issues.append(
                .init(
                    severity: .error,
                    path: "$.custom_actions.\(name)",
                    message: "Custom action '\(name)' collides with a built-in action. Rename the custom action."
                ))
        }

        // Cycle detection.
        if let cycle = ActionRegistry.detectCycle(in: customActions) {
            issues.append(
                .init(
                    severity: .error,
                    path: "$.custom_actions",
                    message: "Custom action cycle detected: \(cycle.joined(separator: " -> "))."
                ))
        }

        let compositeNames = Set(customActions.keys)
        for (compositeName, config) in customActions.sorted(by: { $0.key < $1.key }) {
            let declared = Set((config.parameters ?? [:]).keys)
            let pathPrefix = "$.custom_actions.\(compositeName)"

            if config.steps.isEmpty {
                issues.append(
                    .init(
                        severity: .error,
                        path: pathPrefix + ".steps",
                        message: "Custom action '\(compositeName)' must declare at least one step."
                    ))
            }

            for (index, step) in config.steps.enumerated() {
                let stepPath = pathPrefix + ".steps[\(index)]"

                // Referenced action must be a built-in or another composite.
                if !builtInNames.contains(step.action), !compositeNames.contains(step.action) {
                    issues.append(
                        .init(
                            severity: .error,
                            path: stepPath + ".action",
                            message: "Unknown action '\(step.action)' referenced in custom action '\(compositeName)'."
                        ))
                }

                // `{{param.X}}` references must match a declared parameter.
                for ref in parameterReferences(in: step.options) where !declared.contains(ref) {
                    issues.append(
                        .init(
                            severity: .error,
                            path: stepPath + ".options",
                            message:
                                "Custom action '\(compositeName)' references undeclared parameter '\(ref)'. Add it under custom_actions.\(compositeName).parameters."
                        ))
                }
            }
        }

        return issues
    }

    private func parameterReferences(in value: JSONValue?) -> Set<String> {
        guard let value else { return [] }
        var out: Set<String> = []
        collectParameterReferences(in: value, into: &out)
        return out
    }

    private func collectParameterReferences(in value: JSONValue, into out: inout Set<String>) {
        switch value {
        case .string(let s):
            var cursor = s.startIndex
            while let open = s.range(of: "{{param.", range: cursor..<s.endIndex) {
                guard let close = s.range(of: "}}", range: open.upperBound..<s.endIndex) else { break }
                let key = String(s[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, !key.contains("{{"), !key.contains("}}") {
                    out.insert(key)
                }
                cursor = close.upperBound
            }
        case .array(let arr):
            for item in arr { collectParameterReferences(in: item, into: &out) }
        case .object(let obj):
            for v in obj.values { collectParameterReferences(in: v, into: &out) }
        default:
            break
        }
    }
}
