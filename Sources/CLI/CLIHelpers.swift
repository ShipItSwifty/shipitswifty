import Foundation
import ShipItKit
import SwiftyShell
import OSLog

// MARK: - Shared CLI Helpers

/// Resolve the configured Shipfile path to an absolute filesystem path.
func configuredShipfilePath(from global: GlobalOptions) -> String {
    URL(fileURLWithPath: global.shipfile).path
}

/// Resolve configuration, requiring the configured Shipfile to exist first.
func resolveRequiredConfig(
    global: GlobalOptions,
    cliOptions: CLIOptions = CLIOptions()
) async throws -> ResolvedConfig {
    let shipfilePath = configuredShipfilePath(from: global)
    guard FileManager.default.fileExists(atPath: shipfilePath) else {
        throw ShipItError.invalidConfiguration(reason: "Shipfile not found at \(shipfilePath)")
    }

    return try await ConfigResolver().resolve(cliOptions: cliOptions, shipfilePath: shipfilePath)
}

/// Build a full `ActionContext` from a resolved config.
///
/// Creates the App Store Connect client if credentials are present.
/// If credentials are missing, creates a placeholder client (will fail on API calls).
///
/// - Parameter config: The resolved configuration.
/// - Returns: An `ActionContext` ready for use by actions.
func buildActionContext(config: ResolvedConfig) async throws -> ActionContext {
    let shell = ShellContext()
    let logger = Logger.forType(subsystem: "ShipItSwifty", ActionContext.self)

    // Build ASC client — require credentials for API-touching actions
    let ascClient: AppStoreConnectClient
    if let keyID = config.ascKeyID,
       let issuerID = config.ascIssuerID,
       let keyData = config.ascPrivateKeyData {
        ascClient = AppStoreConnectClient(
            keyID: keyID,
            issuerID: issuerID,
            privateKeyData: keyData
        )
    } else {
        // Placeholder — actions needing ASC will throw when they try to use it
        let placeholderKey = Data("placeholder".utf8)
        ascClient = AppStoreConnectClient(
            keyID: config.ascKeyID ?? "PLACEHOLDER",
            issuerID: config.ascIssuerID ?? "PLACEHOLDER",
            privateKeyData: placeholderKey
        )
    }

    return ActionContext(
        shell: shell,
        logger: logger,
        config: config,
        appStoreConnect: ascClient,
        platform: .ios
    )
}

/// Output a successful action result in the specified format.
func outputResult<T: Codable & Sendable>(action: String, result: T, format: OutputFormat, colorMode: ConsoleColorMode = .auto) {
    switch format {
    case .human:
        HumanFormatter(colorMode: colorMode).printResult(action: action, result: result)
    case .json:
        JSONFormatter().printResult(action: action, result: result)
    }
}

/// Output an error in the specified format.
func outputError(error: ShipItError, format: OutputFormat, colorMode: ConsoleColorMode = .auto) {
    let suggestions = errorSuggestions(for: error)

    switch format {
    case .human:
        let formatter = HumanFormatter(colorMode: colorMode)
        formatter.printError(error.errorDescription ?? error.localizedDescription)
        for suggestion in suggestions {
            formatter.print("  Hint: \(suggestion)")
        }
    case .json:
        JSONFormatter().printError(action: "unknown", error: error, suggestions: suggestions)
    }
}

func makeHumanFormatter(global: GlobalOptions) -> HumanFormatter {
    HumanFormatter(colorMode: global.effectiveColorMode)
}

func schemaFieldJSON(_ field: SchemaField) -> JSONValue {
    var object: [String: JSONValue] = [
        "name": .string(field.name),
        "type": .string(field.type.rawValue),
        "required": .bool(field.required),
        "description": .string(field.description),
        "isSecret": .bool(field.isSecret),
        "allowsAdditionalProperties": .bool(field.allowsAdditionalProperties),
        "notes": .array(field.notes.map(JSONValue.string)),
        "properties": .array(field.propertyValues.map(schemaFieldJSON)),
    ]

    object["default"] = field.defaultValue ?? .null
    object["example"] = field.example ?? .null
    object["envVar"] = field.envVar.map(JSONValue.string) ?? .null
    object["allowedValues"] = .array(field.allowedValues)
    object["items"] = field.itemValue.map(schemaFieldJSON) ?? .null
    object["additionalProperties"] = field.additionalPropertyValue.map(schemaFieldJSON) ?? .null
    return .object(object)
}

func actionSchemaJSON(_ schema: ActionSchema) -> JSONValue {
    .object([
        "name": .string(schema.name),
        "description": .string(schema.description),
        "options": .array(schema.options.map(schemaFieldJSON)),
        "example": schema.example ?? .null,
    ])
}

func schemaSectionsJSON(_ sections: [SchemaSection]) -> JSONValue {
    .array(sections.map { section in
        .object([
            "name": .string(section.name),
            "description": .string(section.description),
            "fields": .array(section.fields.map(schemaFieldJSON)),
        ])
    })
}

func projectInspectionJSON(_ inspection: ProjectInspection) -> JSONValue {
    .object([
        "rootPath": .string(inspection.rootPath),
        "xcodeContainers": .array(inspection.xcodeContainers.map { container in
            .object([
                "kind": .string(container.kind),
                "path": .string(container.path),
            ])
        }),
        "preferredContainer": inspection.preferredContainer.map { preferred in
            .object([
                "kind": .string(preferred.kind),
                "path": .string(preferred.path),
            ])
        } ?? .null,
        "schemes": .array(inspection.schemes.map { scheme in
            .object([
                "name": .string(scheme.name),
                "containerPath": .string(scheme.containerPath),
                "bundleId": scheme.bundleID.map(JSONValue.string) ?? .null,
                "teamId": scheme.teamID.map(JSONValue.string) ?? .null,
                "likelyRunnable": .bool(scheme.likelyRunnable),
            ])
        }),
        "suggestedAppConfig": .object([
            "workspace": inspection.suggestedAppConfig.workspace.map(JSONValue.string) ?? .null,
            "project": inspection.suggestedAppConfig.project.map(JSONValue.string) ?? .null,
            "scheme": inspection.suggestedAppConfig.scheme.map(JSONValue.string) ?? .null,
            "bundleId": inspection.suggestedAppConfig.bundleID.map(JSONValue.string) ?? .null,
            "teamId": inspection.suggestedAppConfig.teamID.map(JSONValue.string) ?? .null,
        ]),
        "existingShipfiles": .array(inspection.existingShipfiles.map(JSONValue.string)),
        "fastlaneFiles": .array(inspection.fastlaneFiles.map(JSONValue.string)),
        "ciFiles": .array(inspection.ciFiles.map(JSONValue.string)),
        "warnings": .array(inspection.warnings.map(JSONValue.string)),
    ])
}

func suggestedShipfileJSON(_ suggestion: SuggestedShipfile) -> JSONValue {
    .object([
        "goal": .string(suggestion.goal.rawValue),
        "inspection": projectInspectionJSON(suggestion.inspection),
        "missingValues": .array(suggestion.missingValues.map { missing in
            .object([
                "keyPath": .string(missing.keyPath),
                "reason": .string(missing.reason),
                "envVar": missing.envVar.map(JSONValue.string) ?? .null,
            ])
        }),
        "warnings": .array(suggestion.warnings.map(JSONValue.string)),
        "yaml": .string(suggestion.yaml),
    ])
}

func inferredConfigEntryJSON(_ entry: InferredConfigEntry) -> JSONValue {
    .object([
        "keyPath": .string(entry.keyPath),
        "value": entry.value ?? .null,
        "source": .string(entry.source.rawValue),
        "confidence": entry.confidence.map { .string($0.rawValue) } ?? .null,
        "why": .string(entry.why),
    ])
}

func secretDescriptorJSON(_ secret: SecretDescriptor) -> JSONValue {
    .object([
        "keyPath": .string(secret.keyPath),
        "envVar": .string(secret.envVar),
        "acceptedFormats": .array(secret.acceptedFormats.map(JSONValue.string)),
        "exampleSource": .string(secret.exampleSource),
        "preferFile": .bool(secret.preferFile),
        "description": .string(secret.description),
    ])
}

func ambiguityFlagJSON(_ flag: AmbiguityFlag) -> JSONValue {
    .object([
        "field": .string(flag.field),
        "options": .array(flag.options),
        "message": .string(flag.message),
    ])
}

func nextActionJSON(_ action: NextAction) -> JSONValue {
    .object([
        "action": .string(action.action),
        "command": action.command.map(JSONValue.string) ?? .null,
        "reason": .string(action.reason),
    ])
}

func aiReadinessJSON(_ readiness: AIReadiness) -> JSONValue {
    .object([
        "goal": .string(readiness.goal),
        "isReady": .bool(readiness.isReady),
        "blockers": .array(readiness.blockers.map(JSONValue.string)),
        "missingSecrets": .array(readiness.missingSecrets.map(secretDescriptorJSON)),
        "signingRisk": .string(readiness.signingRisk),
        "unblockSteps": .array(readiness.unblockSteps.map(JSONValue.string)),
    ])
}

func aiSessionPayloadJSON(_ payload: AISessionPayload) -> JSONValue {
    .object([
        "version": .string(payload.version),
        "goal": .string(payload.goal),
        "appConfig": .array(payload.appConfig.map(inferredConfigEntryJSON)),
        "missing": .array(payload.missing.map { missing in
            .object([
                "keyPath": .string(missing.keyPath),
                "reason": .string(missing.reason),
                "envVar": missing.envVar.map(JSONValue.string) ?? .null,
            ])
        }),
        "ambiguities": .array(payload.ambiguities.map(ambiguityFlagJSON)),
        "suggestedShipfile": .string(payload.suggestedShipfile),
        "readiness": aiReadinessJSON(payload.readiness),
        "nextAction": nextActionJSON(payload.nextAction),
        "agentPrompt": .string(payload.agentPrompt),
        "nextQuestion": payload.nextQuestion.map(JSONValue.string) ?? .null,
    ])
}

func validationReportJSON(_ report: ValidationReport) -> JSONValue {
    .object([
        "shipfilePath": .string(report.shipfilePath),
        "isValid": .bool(report.isValid),
        "issues": .array(report.issues.map { issue in
            .object([
                "severity": .string(issue.severity.rawValue),
                "path": .string(issue.path),
                "message": .string(issue.message),
            ])
        }),
    ])
}

func errorSuggestions(for error: ShipItError) -> [String] {
    switch error {
    case .invalidConfiguration(let reason):
        invalidConfigurationSuggestions(for: reason)
    case .uploadFailed(_, let reason):
        uploadFailureSuggestions(for: reason)
    case .jwtGenerationFailed:
        [
            "Verify ASC credentials are set: ASC_KEY_ID, ASC_ISSUER_ID, and exactly one of ASC_PRIVATE_KEY or ASC_PRIVATE_KEY_PATH.",
            "If you use ASC_PRIVATE_KEY_PATH, check that the .p8 file exists and the filepath is correct.",
        ]
    case .keychainError(let underlying):
        keychainErrorSuggestions(for: underlying)
    case .missingTool(let name):
        missingToolSuggestions(for: name)
    case .signingResourceNotFound(let description):
        signingResourceSuggestions(for: description)
    case .validateArchiveFailed:
        [
            "Run shipit validate archive to see the full list of issues with severity codes.",
            "Fix all errors before attempting to upload — warnings are advisory.",
        ]
    default:
        []
    }
}

private func invalidConfigurationSuggestions(for reason: String) -> [String] {
    let normalizedReason = reason.lowercased()

    if let shipfilePath = suffix(after: "Shipfile not found at ", in: reason) {
        return [
            "Check that the filepath is correct: \(shipfilePath).",
            "If your config lives elsewhere, rerun with --shipfile /path/to/Shipfile.yml.",
        ]
    }

    if normalizedReason.contains("failed to parse shipfile") {
        return [
            "Check Shipfile.yml for YAML syntax or indentation issues.",
            "If you are using a custom config location, rerun with --shipfile /path/to/Shipfile.yml.",
        ]
    }

    if normalizedReason.contains("requires a scheme") {
        return [
            "Pass --scheme <YourScheme> on the command line.",
            "Or set app.scheme in Shipfile.yml so the command can resolve it automatically.",
        ]
    }

    if normalizedReason.contains("requires app.bundle_id") || normalizedReason.contains("requires a bundle id") {
        return [
            "Set app.bundle_id in Shipfile.yml.",
            "Or export SHIPIT_APP__BUNDLE_ID=com.example.app before rerunning.",
        ]
    }

    if normalizedReason.contains("metadata directory not found") {
        return [
            "Check that the metadata directory exists and the filepath is correct.",
            "If it lives elsewhere, rerun with --directory /path/to/metadata.",
        ]
    }

    if normalizedReason.contains("export requires an archive path") {
        return [
            "Pass --archive /path/to/App.xcarchive when running shipit export.",
            "Or set export.archive_path or archive.output_path in Shipfile.yml.",
        ]
    }

    if normalizedReason.contains("upload requires an ipa path") || normalizedReason.contains("testflight requires an ipa path") {
        return [
            "Pass --ipa /path/to/App.ipa when running the command.",
            "Check that the .ipa exists at that path before rerunning.",
        ]
    }

    if normalizedReason.contains("workflow '") && normalizedReason.contains("not found in shipfile") {
        return [
            "Check the workflow name in Shipfile.yml.",
            "If you are using a non-default config file, rerun with --shipfile /path/to/Shipfile.yml.",
        ]
    }

    if normalizedReason.contains("snapshot requires at least one device") {
        return [
            "Pass one or more --devices values, for example --devices 'iPhone 16'.",
            "Or configure screenshots.devices in Shipfile.yml.",
        ]
    }

    if normalizedReason.contains("sign sync requires code_signing.git_url") || normalizedReason.contains("sign import requires code_signing.git_url") {
        return [
            "Set code_signing.git_url in Shipfile.yml.",
            "Or export SHIPIT_CODE_SIGNING__GIT_URL before rerunning.",
        ]
    }

    if normalizedReason.contains("sign init requires a --git-url") {
        return [
            "Rerun the command with --git-url <repository-url>.",
        ]
    }

    if normalizedReason.contains("sign import requires --p12-path") {
        return [
            "Rerun the command with --p12-path /path/to/certificate.p12.",
            "Check that the .p12 filepath exists and is correct.",
        ]
    }

    if normalizedReason.contains("sign import requires --provisioning-profile-path") {
        return [
            "Rerun the command with --provisioning-profile-path /path/to/profile.mobileprovision.",
            "Check that the provisioning profile filepath exists and is correct.",
        ]
    }

    if normalizedReason.contains("invalid bump type") {
        return [
            "Use --bump build, patch, minor, major, or set.",
        ]
    }

    if normalizedReason.contains("invalid operation") {
        return [
            "Use --operation create-app-id, register-devices, list-devices, or list-bundle-ids.",
        ]
    }

    if normalizedReason.contains("could not find info.plist") {
        return [
            "Check that the selected scheme, workspace, or project points at the expected target.",
            "If needed, pass --scheme or update app.project/app.workspace in Shipfile.yml.",
        ]
    }

    if normalizedReason.contains("invalid slack webhook url") || normalizedReason.contains("invalid webhook url") {
        return [
            "Check that SLACK_WEBHOOK_URL or notifications.slack.webhook_url is a valid HTTPS URL.",
        ]
    }

    if normalizedReason.contains("createappid requires a bundle id") {
        return [
            "Rerun the command with --bundle-id com.example.app.",
        ]
    }

    if normalizedReason.contains("registerdevices requires at least one udid") {
        return [
            "Pass one or more --device-udids values when registering devices.",
        ]
    }

    if normalizedReason.contains("dsym upload requires a dsym path") {
        return [
            "Set dsym_path in the workflow step options before rerunning.",
            "Check that the dSYM filepath exists and is correct.",
        ]
    }

    if normalizedReason.contains("dsym upload requires an upload url") {
        return [
            "Set upload_url in the workflow step options before rerunning.",
            "Check that the upload URL is a valid HTTPS endpoint.",
        ]
    }

    if normalizedReason.contains("working tree is not clean") {
        return [
            "Commit or stash your local changes before rerunning the workflow.",
            "If those changes are intentional, inspect git status and commit what you need first.",
        ]
    }

    if normalizedReason.contains("git tag requires a tag name") {
        return [
            "Set tag_name in the workflow step options before rerunning.",
        ]
    }

    if normalizedReason.contains("git commit requires a commit message") {
        return [
            "Set commit_message in the workflow step options before rerunning.",
        ]
    }

    if normalizedReason.contains("git tag failed") {
        return [
            "Check whether the tag already exists locally or on the remote.",
            "Inspect the git error output above for conflicts or repository state issues.",
        ]
    }

    if normalizedReason.contains("git add failed") || normalizedReason.contains("git commit failed") {
        return [
            "Inspect the git error output above for repository state, hook failures, or missing identity configuration.",
            "Run git status locally to confirm what will be committed.",
        ]
    }

    if normalizedReason.contains("git push failed") || normalizedReason.contains("git push --tags failed") {
        return [
            "Check that the remote exists and that you have permission to push to it.",
            "If the branch has no upstream yet, push it manually first and then rerun the workflow.",
        ]
    }

    if normalizedReason.contains("invalid url for path") {
        return [
            "Check any custom App Store Connect server/base URL configuration if you are overriding it.",
            "If you are not overriding the server URL, this likely indicates an internal bug rather than a user config issue.",
        ]
    }

    if normalizedReason.contains("key '") && normalizedReason.contains("not found in info.plist") {
        return [
            "Check that the target Info.plist contains the expected version keys.",
            "If ShipIt is resolving the wrong app target, pass --scheme or update app.project/app.workspace in Shipfile.yml.",
        ]
    }

    if normalizedReason.contains("plutil failed to write") {
        return [
            "Check that the Info.plist file is writable and not locked by permissions or source control.",
            "Inspect the plutil error output above for the specific write failure.",
        ]
    }

    return []
}

private func uploadFailureSuggestions(for reason: String) -> [String] {
    let normalizedReason = reason.lowercased()

    if normalizedReason.contains("not found") {
        return [
            "Check that the filepath exists and is correct.",
            "If the file is not in the current directory, rerun with the correct absolute path.",
        ]
    }

    if normalizedReason.contains("invalid upload url") {
        return [
            "Check that the upload URL is a valid HTTPS endpoint.",
            "If this comes from workflow config, verify the upload_url value is correct.",
        ]
    }

    if normalizedReason.contains("webhook returned non-2xx response") || normalizedReason.contains("slack webhook returned non-2xx response") {
        return [
            "Check that the webhook URL is valid and still active.",
            "Inspect the receiving service configuration and credentials before rerunning.",
        ]
    }

    return []
}

private func keychainErrorSuggestions(for underlying: any Error) -> [String] {
    if let shipItError = underlying as? ShipItError {
        let suggestions = errorSuggestions(for: shipItError)
        if !suggestions.isEmpty {
            return suggestions
        }
    }

    let message = underlying.localizedDescription.lowercased()

    if message.contains("failed to create keychain") {
        return [
            "Check that the macOS security tool is available and the process has permission to create keychains.",
            "If a keychain with the same name already exists, remove it or rerun in a clean environment.",
        ]
    }

    if message.contains("certificate import failed") {
        return [
            "Check that the .p12 filepath and password are correct.",
            "Verify the certificate file is valid and readable before rerunning.",
        ]
    }

    if message.contains("failed to unlock keychain") {
        return [
            "Check that the keychain password is correct and the keychain exists.",
            "If this is CI, rerun after recreating the temporary keychain.",
        ]
    }

    return []
}

private func missingToolSuggestions(for name: String) -> [String] {
    if name == "xcodebuild" || name == "xcrun" {
        return [
            "Install Xcode and make sure the active developer directory is set correctly with xcode-select.",
            "Then rerun the command after confirming \(name) is available on PATH.",
        ]
    }

    return [
        "Install \(name) and make sure it is available on PATH before rerunning.",
    ]
}

private func signingResourceSuggestions(for description: String) -> [String] {
    if description.lowercased().contains("not found") || description.contains("/") {
        return [
            "Check that the referenced signing file exists and the filepath is correct.",
        ]
    }

    return []
}

private func suffix(after prefix: String, in text: String) -> String? {
    guard text.hasPrefix(prefix) else { return nil }
    return String(text.dropFirst(prefix.count))
}
