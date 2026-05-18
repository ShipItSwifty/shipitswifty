import ArgumentParser
import Foundation
import ShipItKit

/// Print resolved configuration and environment for debugging.
struct EnvCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "env",
        abstract: "Print resolved config, environment variables, and processed files"
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, inversion: .prefixedNo, help: "Redact sensitive values in output")
    var redact: Bool = true

    func run() async throws {
        do {
            let requestedShipfilePath = configuredShipfilePath(from: global)
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let environment = Environment()
            let formatter = makeHumanFormatter(global: global)

            switch global.output {
            case .human:
                formatter.printHeader("Resolved Configuration")
                formatter.printKV("Shipfile", "\(requestedShipfilePath) [loaded]")
                formatter.printKV(
                    "Processed Files", config.processedFiles.isEmpty ? "(none)" : config.processedFiles.joined(separator: ", "))
                formatter.printKV("App Scheme", config.appScheme ?? "(not set)")
                formatter.printKV(
                    "Bundle ID", resolvedValueDisplay(config.bundleID, fromTargetBuildSettings: config.bundleIDFromTargetBuildSettings))
                formatter.printKV(
                    "Team ID", resolvedValueDisplay(config.teamID, fromTargetBuildSettings: config.teamIDFromTargetBuildSettings))
                formatter.printKV("ASC Key ID", redact ? redactValue(config.ascKeyID) : (config.ascKeyID ?? "(not set)"))
                formatter.printKV("ASC Issuer ID", redact ? redactValue(config.ascIssuerID) : (config.ascIssuerID ?? "(not set)"))
                formatter.printKV(
                    "ASC Private Key",
                    config.ascPrivateKeyData != nil
                        ? (redact ? "[REDACTED]" : "[loaded, \(config.ascPrivateKeyData!.count) bytes]") : "(not set)")
                formatter.printKV("Build Config", config.buildConfiguration)
                formatter.printKV("Archive Method", config.archiveExportMethod)
                formatter.printKV("Code Signing Type", config.codeSigningType)
                formatter.printKV("Code Signing Storage", config.codeSigningStorage)
                formatter.printKV("Code Signing Git URL", config.codeSigningGitUrl ?? "(not set)")
                formatter.printKV(
                    "Slack Webhook", config.slackWebhookUrl != nil ? (redact ? "[REDACTED]" : config.slackWebhookUrl!) : "(not set)")

                if !config.workflows.isEmpty {
                    formatter.printHeader("Workflows")
                    for (name, workflow) in config.workflows.sorted(by: { $0.key < $1.key }) {
                        formatter.printKV(name, "\(workflow.steps.count) step(s): \(workflow.steps.map { $0.action }.joined(separator: " -> "))")
                    }
                }

                formatter.printHeader("Environment")
                for variable in envEntries(from: environment, config: config) {
                    formatter.printKV(variable.key, variable.displayValue(redacted: redact))
                }

            case .json:
                let reporter = JSONReporter()
                let envelope = ActionResultEnvelope(
                    action: "env",
                    status: "success",
                    payload: .object([
                        "shipfile": .object([
                            "path": .string(requestedShipfilePath),
                            "loaded": .bool(true),
                        ]),
                        "environment": .object(
                            envEntries(from: environment, config: config).reduce(into: [String: JSONValue]()) { result, entry in
                                result[entry.key] = .string(entry.displayValue(redacted: redact))
                            }),
                        "processedFiles": .array(config.processedFiles.map { .string($0) }),
                        "scheme": config.appScheme.map { .string($0) } ?? .null,
                        "bundleId": config.bundleID.map { .string($0) } ?? .null,
                        "bundleIdFromTargetBuildSettings": .bool(config.bundleIDFromTargetBuildSettings),
                        "teamId": config.teamID.map { .string($0) } ?? .null,
                        "teamIdFromTargetBuildSettings": .bool(config.teamIDFromTargetBuildSettings),
                        "ascKeyId": .string(redact ? redactValue(config.ascKeyID) : (config.ascKeyID ?? "")),
                        "buildConfiguration": .string(config.buildConfiguration),
                        "workflows": .array(config.workflows.keys.sorted().map { .string($0) }),
                    ])
                )
                print(try reporter.encode(envelope))
            }
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }

    private func redactValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "(not set)" }
        return String(value.prefix(4)) + "****"
    }

    func resolvedValueDisplay(_ value: String?, fromTargetBuildSettings: Bool) -> String {
        guard let value, !value.isEmpty else { return "(not set)" }
        if fromTargetBuildSettings {
            return "\(value) [from Xcode target build settings]"
        }
        return value
    }

    private func envEntries(from environment: Environment, config: ResolvedConfig) -> [EnvEntry] {
        [
            EnvEntry(key: "SHIPIT_APP__WORKSPACE", value: environment.value(for: "SHIPIT_APP__WORKSPACE")),
            EnvEntry(key: "SHIPIT_APP__PROJECT", value: environment.value(for: "SHIPIT_APP__PROJECT")),
            EnvEntry(key: "SHIPIT_APP__SCHEME", value: environment.value(for: "SHIPIT_APP__SCHEME")),
            EnvEntry(
                key: "SHIPIT_APP__BUNDLE_ID",
                value: environment.value(for: "SHIPIT_APP__BUNDLE_ID"),
                fallbackValue: config.bundleIDFromTargetBuildSettings ? config.bundleID : nil,
                fallbackSource: config.bundleIDFromTargetBuildSettings ? "Xcode target build settings" : nil
            ),
            EnvEntry(
                key: "SHIPIT_APP__TEAM_ID",
                value: environment.value(for: "SHIPIT_APP__TEAM_ID"),
                fallbackValue: config.teamIDFromTargetBuildSettings ? config.teamID : nil,
                fallbackSource: config.teamIDFromTargetBuildSettings ? "Xcode target build settings" : nil
            ),
            EnvEntry(
                key: "SHIPIT_APP_STORE_CONNECT__KEY_ID", value: environment.value(for: "SHIPIT_APP_STORE_CONNECT__KEY_ID"),
                isSensitive: true),
            EnvEntry(key: "ASC_KEY_ID", value: environment.value(for: "ASC_KEY_ID"), isSensitive: true),
            EnvEntry(
                key: "SHIPIT_APP_STORE_CONNECT__ISSUER_ID", value: environment.value(for: "SHIPIT_APP_STORE_CONNECT__ISSUER_ID"),
                isSensitive: true),
            EnvEntry(key: "ASC_ISSUER_ID", value: environment.value(for: "ASC_ISSUER_ID"), isSensitive: true),
            EnvEntry(key: "SHIPIT_APP_STORE_CONNECT__KEY_PATH", value: environment.value(for: "SHIPIT_APP_STORE_CONNECT__KEY_PATH")),
            EnvEntry(key: "ASC_PRIVATE_KEY_PATH", value: environment.value(for: "ASC_PRIVATE_KEY_PATH")),
            EnvEntry(key: "ASC_PRIVATE_KEY", value: environment.value(for: "ASC_PRIVATE_KEY"), isSensitive: true),
            EnvEntry(key: "SHIPIT_BUILD__CONFIGURATION", value: environment.value(for: "SHIPIT_BUILD__CONFIGURATION")),
            EnvEntry(key: "SHIPIT_BUILD__DERIVED_DATA_PATH", value: environment.value(for: "SHIPIT_BUILD__DERIVED_DATA_PATH")),
            EnvEntry(key: "SHIPIT_ARCHIVE__EXPORT_METHOD", value: environment.value(for: "SHIPIT_ARCHIVE__EXPORT_METHOD")),
            EnvEntry(key: "SHIPIT_ARCHIVE__OUTPUT_PATH", value: environment.value(for: "SHIPIT_ARCHIVE__OUTPUT_PATH")),
            EnvEntry(key: "SHIPIT_CODE_SIGNING__GIT_URL", value: environment.value(for: "SHIPIT_CODE_SIGNING__GIT_URL")),
            EnvEntry(key: "VAULT_PASSWORD", value: environment.value(for: "VAULT_PASSWORD"), isSensitive: true),
            EnvEntry(key: "SLACK_WEBHOOK_URL", value: environment.value(for: "SLACK_WEBHOOK_URL"), isSensitive: true),
        ]
    }
}

private struct EnvEntry: Sendable {
    let key: String
    let value: String?
    let fallbackValue: String?
    let fallbackSource: String?
    let isSensitive: Bool

    init(key: String, value: String?, fallbackValue: String? = nil, fallbackSource: String? = nil, isSensitive: Bool = false) {
        self.key = key
        self.value = value
        self.fallbackValue = fallbackValue
        self.fallbackSource = fallbackSource
        self.isSensitive = isSensitive
    }

    func displayValue(redacted: Bool) -> String {
        if let value, !value.isEmpty {
            if isSensitive && redacted {
                return "[REDACTED]"
            }
            return value
        }

        if let fallbackValue, !fallbackValue.isEmpty {
            if isSensitive && redacted {
                return "[REDACTED] [from \(fallbackSource ?? "resolved config")]"
            }
            if let fallbackSource {
                return "\(fallbackValue) [from \(fallbackSource)]"
            }
            return fallbackValue
        }

        if isSensitive && redacted {
            return "[REDACTED]"
        }
        return "(not set)"
    }
}
