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

        for (workflowName, steps) in resolvedConfig.workflows.sorted(by: { $0.key < $1.key }) {
            for (index, step) in steps.enumerated() {
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
                        allSteps: steps,
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
        allSteps: WorkflowConfig,
        config: ResolvedConfig
    ) -> [ValidationIssue] {
        let options = step.options?.objectValue ?? [:]
        var issues: [ValidationIssue] = []
        let action = step.action.lowercased()

        if ["build", "test", "archive"].contains(action), stringOption("scheme", in: options) == nil, config.appScheme == nil {
            issues.append(
                .init(severity: .error, path: ".options.scheme", message: "This action requires a scheme or app.scheme in config."))
        }

        if action == "snapshot" {
            if stringOption("scheme", in: options) == nil, config.screenshotScheme == nil, config.appScheme == nil {
                issues.append(
                    .init(
                        severity: .error, path: ".options.scheme",
                        message: "Snapshot requires screenshots.scheme, app.scheme, or a step-level scheme."))
            }
            if arrayOption("devices", in: options).isEmpty && config.screenshotDevices.isEmpty {
                issues.append(.init(severity: .error, path: ".options.devices", message: "Snapshot requires at least one device."))
            }
        }

        if action == "export",
            stringOption("archive_path", in: options) == nil,
            config.exportArchivePath == nil,
            config.archiveOutputPath == nil
        {
            issues.append(
                .init(severity: .error, path: ".options.archive_path", message: "Export requires an archive path or archive.output_path."))
        }

        if ["upload", "testflight", "metadata"].contains(action), config.bundleID == nil {
            issues.append(.init(severity: .error, path: "$", message: "This action requires app.bundle_id or SHIPIT_APP__BUNDLE_ID."))
        }

        if action == "upload" {
            let hasExplicitIPA = stringOption("ipa_path", in: options) != nil
            if !hasExplicitIPA && !hasExportContext(before: stepIndex, in: allSteps, config: config) {
                issues.append(
                    .init(
                        severity: .error, path: ".options.ipa_path",
                        message:
                            "Upload needs `ipa_path`, a previous export step, or an IPA already present in the export output directory."))
            }
        }

        if action == "testflight" {
            let hasExplicitIPA = stringOption("ipa", in: options) != nil
            if !hasExplicitIPA && !hasExportContext(before: stepIndex, in: allSteps, config: config) {
                issues.append(
                    .init(
                        severity: .error, path: ".options.ipa",
                        message: "TestFlight needs `ipa`, a previous export step, or an IPA already present in the export output directory."
                    ))
            }
        }

        if action == "sign" {
            let operation = stringOption("operation", in: options) ?? ""
            if ["sync", "import", "init"].contains(operation), stringOption("git_url", in: options) == nil, config.codeSigningGitUrl == nil
            {
                issues.append(
                    .init(
                        severity: .error, path: ".options.git_url", message: "This sign operation requires git_url or code_signing.git_url."
                    ))
            }
            if operation == "import" {
                if stringOption("p12_path", in: options) == nil {
                    issues.append(.init(severity: .error, path: ".options.p12_path", message: "sign import requires p12_path."))
                }
                if stringOption("provisioning_profile_path", in: options) == nil {
                    issues.append(
                        .init(
                            severity: .error, path: ".options.provisioning_profile_path",
                            message: "sign import requires provisioning_profile_path."))
                }
            }
        }

        if action == "git" {
            let operation = stringOption("operation", in: options) ?? ""
            if operation == "tag", stringOption("tag_name", in: options) == nil {
                issues.append(.init(severity: .error, path: ".options.tag_name", message: "git tag requires tag_name."))
            }
            if operation == "commit", stringOption("commit_message", in: options) == nil {
                issues.append(.init(severity: .error, path: ".options.commit_message", message: "git commit requires commit_message."))
            }
        }

        if action == "version", stringOption("bump", in: options) == "set", stringOption("version", in: options) == nil {
            issues.append(
                .init(severity: .error, path: ".options.version", message: "version bump `set` requires an explicit version value."))
        }

        if action == "provision" {
            let operation = stringOption("operation", in: options) ?? ""
            if operation == "createAppId", stringOption("bundle_id", in: options) == nil, config.bundleID == nil {
                issues.append(
                    .init(severity: .error, path: ".options.bundle_id", message: "createAppId requires bundle_id or app.bundle_id."))
            }
            if operation == "registerDevices", arrayOption("device_udids", in: options).isEmpty {
                issues.append(
                    .init(severity: .error, path: ".options.device_udids", message: "registerDevices requires at least one device UDID."))
            }
        }

        if action == "dsym", stringOption("operation", in: options) == "upload" {
            if stringOption("dsym_path", in: options) == nil {
                issues.append(.init(severity: .error, path: ".options.dsym_path", message: "dSYM upload requires dsym_path."))
            }
            if stringOption("upload_url", in: options) == nil {
                issues.append(.init(severity: .error, path: ".options.upload_url", message: "dSYM upload requires upload_url."))
            }
        }

        if action == "notify", options["slack"] == nil, stringOption("webhook_url", in: options) == nil {
            issues.append(.init(severity: .warning, path: ".options", message: "notify has no configured destination and will be a no-op."))
        }

        if workflowName.isEmpty {
            issues.append(.init(severity: .warning, path: "$", message: "Workflow names should not be empty."))
        }

        return issues
    }

    private func ascWarningsIfNeeded(config: ResolvedConfig) -> [ValidationIssue] {
        let ascActions: Set<String> = ["upload", "testflight", "metadata", "provision", "dsym"]
        let usesASC = config.workflows.values.flatMap { $0 }.contains { ascActions.contains($0.action.lowercased()) }
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

    private func hasExportContext(before stepIndex: Int, in steps: WorkflowConfig, config: ResolvedConfig) -> Bool {
        if steps[..<stepIndex].contains(where: { $0.action.lowercased() == "export" }) {
            return true
        }

        let outputDirectory = config.exportOutputDirectory ?? "./build/export"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: outputDirectory) else {
            return false
        }
        return contents.contains(where: { $0.hasSuffix(".ipa") })
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

    private func stringOption(_ key: String, in object: [String: JSONValue]) -> String? {
        object[key]?.stringValue
    }

    private func arrayOption(_ key: String, in object: [String: JSONValue]) -> [JSONValue] {
        object[key]?.arrayValue ?? []
    }
}
