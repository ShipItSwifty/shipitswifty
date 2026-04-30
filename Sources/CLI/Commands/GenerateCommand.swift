import ArgumentParser
import Foundation
import OSLog
import ShipItKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Generate a Shipfile.yml from project inspection and user confirmation.
///
/// `shipit generate` inspects the current project, detects whether it looks like
/// an iOS, Android, or mixed workspace, asks the user to confirm inferred values,
/// writes `Shipfile.yml`, and offers to run `shipit doctor` afterward.
struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate Shipfile.yml from project inspection and guided prompts"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Goal to optimize for: local, beta, or release")
    var goal: SuggestionGoal = .beta

    @Option(name: .long, help: "Root path to inspect")
    var path: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Overwrite an existing Shipfile without asking")
    var force: Bool = false

    @Flag(name: .long, help: "Skip prompts and write the best-effort generated Shipfile")
    var nonInteractive: Bool = false

    @Flag(name: .long, help: "Do not prompt to run doctor after writing the Shipfile")
    var skipDoctorPrompt: Bool = false

    private static let logger = Logger.forType(subsystem: "ShipItSwifty", GenerateCommand.self)

    func run() async throws {
        Self.logger.info("Starting Shipfile generation for path: \(path)")

        let formatter = makeHumanFormatter(global: global)
        let inspection = try await inspectProject()
        let platform = try resolvePlatform(from: inspection, formatter: formatter)
        let suggestion = ShipfileSuggester().suggest(goal: goal, platform: platform, from: inspection)
        let outputPath = resolvedOutputPath()

        if global.dryRun {
            formatter.printHeader("Shipfile Preview")
            formatter.print(suggestion.yaml)
            return
        }

        if FileManager.default.fileExists(atPath: outputPath), !force {
            guard
                nonInteractive
                    || confirm(
                        "Shipfile.yml already exists at \(outputPath). Overwrite?", defaultAnswer: false)
            else {
                formatter.printWarning("Generation cancelled. Existing Shipfile.yml was not changed.")
                Self.logger.info("Shipfile generation cancelled because output already exists")
                return
            }
        }

        let yaml = try buildYAML(
            suggestion: suggestion,
            platform: platform,
            formatter: formatter
        )

        Self.logger.info("Writing generated Shipfile to: \(outputPath)")
        try FileManager.default.createDirectory(
            atPath: URL(fileURLWithPath: outputPath).deletingLastPathComponent().path,
            withIntermediateDirectories: true
        )
        try yaml.write(toFile: outputPath, atomically: true, encoding: .utf8)

        switch global.output {
        case .json:
            let payload: JSONValue = .object([
                "path": .string(outputPath),
                "goal": .string(goal.rawValue),
                "platform": .string(platform.rawValue),
                "missing": .array(
                    suggestion.missingValues.map { missing in
                        .object([
                            "keyPath": .string(missing.keyPath),
                            "reason": .string(missing.reason),
                            "envVar": missing.envVar.map(JSONValue.string) ?? .null,
                        ])
                    }),
                "warnings": .array(suggestion.warnings.map(JSONValue.string)),
            ])
            print(
                try JSONReporter().encode(
                    ActionResultEnvelope(action: "generate", status: "success", payload: payload)))
        case .human:
            formatter.printSuccess("Created Shipfile.yml at \(outputPath)")
            printGenerationSummary(suggestion: suggestion, platform: platform, formatter: formatter)
        }

        Self.logger.info("Shipfile generation completed")
        try await offerDoctor(outputPath: outputPath, formatter: formatter)
    }

    private func resolvePlatform(
        from inspection: ProjectInspection, formatter: HumanFormatter
    ) throws
        -> Platform
    {
        if let platform = global.platform {
            return platform
        }

        let hasIOS = !inspection.xcodeContainers.isEmpty
        let hasAndroid = !inspection.gradleFiles.isEmpty

        if hasIOS && hasAndroid && !nonInteractive && global.output == .human {
            formatter.printHeader("Detected Platforms")
            formatter.print("This project appears to contain both iOS and Android files.")
            return choosePlatform(defaultPlatform: inspection.detectedPlatform)
        }

        return inspection.detectedPlatform
    }

    private func buildYAML(
        suggestion: SuggestedShipfile,
        platform: Platform,
        formatter: HumanFormatter
    ) throws -> String {
        guard !nonInteractive, global.output == .human else {
            return suggestion.yaml
        }

        if !isInteractiveTerminal {
            return suggestion.yaml
        }

        formatter.printHeader("Project Detection")
        formatter.printKV("Platform", platform.rawValue)
        formatter.printKV("Goal", goal.rawValue)

        for warning in suggestion.warnings {
            formatter.printWarning(warning)
        }

        let overrides = collectOverrides(
            suggestion: suggestion, platform: platform, formatter: formatter)
        let confirmedYAML = apply(overrides: overrides, to: suggestion.yaml)

        formatter.printHeader("Shipfile Preview")
        formatter.print(confirmedYAML)

        guard confirm("Write this Shipfile.yml?", defaultAnswer: true) else {
            Self.logger.info("Shipfile generation cancelled at final confirmation")
            throw ExitCode(1)
        }

        return confirmedYAML
    }

    private func collectOverrides(
        suggestion: SuggestedShipfile,
        platform: Platform,
        formatter: HumanFormatter
    ) -> [String: String] {
        switch platform {
        case .ios:
            return collectIOSOverrides(suggestion: suggestion, formatter: formatter)
        case .android:
            return collectAndroidOverrides(suggestion: suggestion, formatter: formatter)
        }
    }

    private func collectIOSOverrides(
        suggestion: SuggestedShipfile, formatter: HumanFormatter
    )
        -> [String: String]
    {
        let app = suggestion.inspection.suggestedAppConfig
        formatter.printHeader("Confirm iOS Values")

        var overrides: [String: String] = [:]
        addOverride(
            &overrides, placeholder: "${SHIPIT_APP__SCHEME}",
            value: ask("Xcode scheme", defaultValue: app.scheme))
        addOverride(
            &overrides, placeholder: "${SHIPIT_APP__BUNDLE_ID}",
            value: ask("Bundle identifier", defaultValue: app.bundleID))
        addOverride(
            &overrides, placeholder: "${SHIPIT_APP__TEAM_ID}",
            value: ask("Apple Developer Team ID", defaultValue: app.teamID))

        if app.workspace == nil && app.project == nil {
            let container = ask("Workspace or project path", defaultValue: nil)
            if container.hasSuffix(".xcworkspace") {
                overrides["# workspace: MyApp.xcworkspace"] = "workspace: \(container)"
            } else if !container.isEmpty {
                overrides["# project: MyApp.xcodeproj"] = "project: \(container)"
            }
        }

        let uploadsToTestFlight =
            goal == .release
            || confirm(
                "Do you want this Shipfile to include App Store Connect upload settings?",
                defaultAnswer: false)
        if uploadsToTestFlight {
            formatter.printHeader("App Store Connect Environment")
            formatter.print("ShipIt will reference env vars instead of storing secrets in Shipfile.yml.")
            collectEnvironmentVariables(
                [
                    EnvVarSpec(name: "ASC_KEY_ID", isSensitive: false, description: "App Store Connect API key ID"),
                    EnvVarSpec(name: "ASC_ISSUER_ID", isSensitive: false, description: "ASC issuer UUID"),
                    EnvVarSpec(name: "ASC_PRIVATE_KEY_PATH", isSensitive: false, description: "Path to .p8 key file (preferred)"),
                    EnvVarSpec(name: "ASC_PRIVATE_KEY", isSensitive: true, description: "Raw .p8 PEM content (CI fallback)"),
                ],
                formatter: formatter)
            overrides["# app_store_connect:"] = "app_store_connect:"
            overrides["#   key_id: ${ASC_KEY_ID}"] = "  key_id: ${ASC_KEY_ID}"
            overrides["#   issuer_id: ${ASC_ISSUER_ID}"] = "  issuer_id: ${ASC_ISSUER_ID}"
            overrides["#   key_path: ${ASC_PRIVATE_KEY_PATH}"] = "  key_path: ${ASC_PRIVATE_KEY_PATH}"
            overrides["    # - action: testflight"] = "    - action: testflight"
            overrides["    #   options:"] = "      options:"
            overrides["    #     groups: [\"Internal QA\"]"] = "        groups: [\"Internal QA\"]"
        }

        let usesManualSigning = confirm(
            "Are you using manual code signing (.p12 + provisioning profile)?", defaultAnswer: false)
        if usesManualSigning {
            formatter.printHeader("Manual Code Signing Environment")
            formatter.print("ShipIt will reference env vars instead of storing secrets in Shipfile.yml.")
            collectEnvironmentVariables(
                [
                    EnvVarSpec(
                        name: "SHIPIT_CODE_SIGNING__P12_PATH", isSensitive: false, description: "Path to .p12 certificate (preferred)"),
                    EnvVarSpec(name: "P12_BASE64", isSensitive: true, description: "Base64-encoded .p12 content (CI fallback)"),
                    EnvVarSpec(name: "P12_PASSWORD", isSensitive: true, description: "Password for the .p12 file (required)"),
                    EnvVarSpec(
                        name: "SHIPIT_CODE_SIGNING__PROVISIONING_PROFILE_PATH", isSensitive: false,
                        description: "Path to .mobileprovision (preferred)"),
                    EnvVarSpec(
                        name: "PROVISIONING_PROFILE_BASE64", isSensitive: true, description: "Base64-encoded .mobileprovision (CI fallback)"
                    ),
                ],
                formatter: formatter)
        }

        return overrides
    }

    private func collectAndroidOverrides(
        suggestion: SuggestedShipfile, formatter: HumanFormatter
    )
        -> [String: String]
    {
        formatter.printHeader("Confirm Android Values")

        var overrides: [String: String] = [:]
        addOverride(
            &overrides, placeholder: "${SHIPIT_ANDROID__MODULE}",
            value: ask("Gradle module", defaultValue: "app"))
        addOverride(
            &overrides, placeholder: "${SHIPIT_ANDROID__PACKAGE_NAME}",
            value: ask("Android package name", defaultValue: nil))
        addOverride(
            &overrides, placeholder: "${SHIPIT_ANDROID__KEYSTORE_PATH}",
            value: ask("Keystore path", defaultValue: nil))
        addOverride(
            &overrides, placeholder: "${SHIPIT_ANDROID__KEY_ALIAS}",
            value: ask("Keystore key alias", defaultValue: nil))

        let uploadsToPlay =
            goal == .release
            || confirm(
                "Do you want this Shipfile to include Google Play upload settings?", defaultAnswer: false)
        if uploadsToPlay {
            formatter.printHeader("Google Play Environment")
            formatter.print("ShipIt will reference env vars instead of storing secrets in Shipfile.yml.")
            collectEnvironmentVariables(
                [
                    EnvVarSpec(
                        name: "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH", isSensitive: false,
                        description: "Path to service account JSON (preferred)"),
                    EnvVarSpec(
                        name: "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", isSensitive: true,
                        description: "Raw service account JSON content (CI fallback)"),
                    EnvVarSpec(name: "SHIPIT_ANDROID__KEYSTORE_PASSWORD", isSensitive: true, description: "Keystore password"),
                    EnvVarSpec(name: "SHIPIT_ANDROID__KEY_PASSWORD", isSensitive: true, description: "Key alias password"),
                ],
                formatter: formatter)
            overrides["    # - action: play-store"] = "    - action: play-store"
        }

        return overrides
    }

    /// Describes a single environment variable that ShipIt needs.
    struct EnvVarSpec {
        /// The environment variable name, e.g. `ASC_KEY_ID`.
        let name: String
        /// When `true`, the entered value is hidden during typing and shown as `****` in export hints.
        let isSensitive: Bool
        /// Human-readable description shown in the prompt.
        let description: String
    }

    /// Prompts the user to enter or confirm each environment variable in `specs`.
    ///
    /// - Already set vars show `[set]`; the user can press Enter to keep the existing
    ///   value or type a new one to override.
    /// - Missing vars are prompted inline; sensitive ones use hidden input (no echo).
    /// - After all vars are collected, prints `export NAME=value` lines for any values
    ///   the user typed so they can persist them in their shell / `.env`.
    /// - In `--non-interactive` or non-TTY mode the function prints the status table and
    ///   returns without prompting.
    @discardableResult
    private func collectEnvironmentVariables(
        _ specs: [EnvVarSpec], formatter: HumanFormatter
    ) -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var collected: [String: String] = [:]

        for spec in specs {
            let isSet = env[spec.name] != nil
            let statusTag = isSet ? "[set]" : "(not set)"
            formatter.printKV(spec.name, "\(statusTag)  \(spec.description)")
        }

        guard isInteractiveTerminal, !nonInteractive else { return collected }

        formatter.print("")
        for spec in specs {
            let isSet = env[spec.name] != nil
            let entered: String
            if isSet {
                // Already set — offer keep-or-override.
                let override = confirm("Override \(spec.name)?", defaultAnswer: false)
                if override {
                    entered =
                        spec.isSensitive
                        ? askSecret("New value for \(spec.name)")
                        : ask("New value for \(spec.name)", defaultValue: nil)
                } else {
                    entered = ""
                }
            } else {
                // Not set — prompt for value; empty = leave unset for now.
                entered =
                    spec.isSensitive
                    ? askSecret("\(spec.name) (leave blank to skip)")
                    : ask("\(spec.name) (leave blank to skip)", defaultValue: nil)
            }
            if !entered.isEmpty {
                collected[spec.name] = entered
            }
        }

        if !collected.isEmpty {
            formatter.printHeader("Run These Exports in Your Shell")
            formatter.print("Add these to your shell profile or CI secrets:")
            for spec in specs {
                guard let value = collected[spec.name] else { continue }
                let display = spec.isSensitive ? String(repeating: "*", count: min(value.count, 8)) : value
                formatter.print("  export \(spec.name)=\(display)")
            }
            formatter.print("")
            formatter.printWarning(
                "Sensitive values shown as **** above — copy from your input above before continuing.")
        }

        return collected
    }

    /// Reads a line from stdin with terminal echo disabled (for passwords / keys).
    /// Falls back to plain `readLine()` when not running on a TTY.
    private func askSecret(_ prompt: String) -> String {
        print("\(prompt): ", terminator: "")
        fflush(stdout)

        #if canImport(Darwin)
        var old = termios()
        tcgetattr(STDIN_FILENO, &old)
        var noEcho = old
        noEcho.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &noEcho)
        let value = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tcsetattr(STDIN_FILENO, TCSANOW, &old)
        print("")  // newline after hidden input
        return value
        #else
        return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #endif
    }

    private func addOverride(_ overrides: inout [String: String], placeholder: String, value: String) {
        guard !value.isEmpty else { return }
        overrides[placeholder] = value
    }

    private func printGenerationSummary(
        suggestion: SuggestedShipfile, platform: Platform, formatter: HumanFormatter
    ) {
        formatter.printKV("Platform", platform.rawValue)
        formatter.printKV("Goal", suggestion.goal.rawValue)
        if !suggestion.missingValues.isEmpty {
            formatter.printHeader("Values To Review")
            for missing in suggestion.missingValues {
                let envHint = missing.envVar.map { " (or set \($0))" } ?? ""
                formatter.printKV(missing.keyPath, missing.reason + envHint)
            }
        }
    }

    private func offerDoctor(outputPath: String, formatter: HumanFormatter) async throws {
        guard !skipDoctorPrompt, !nonInteractive, global.output == .human, isInteractiveTerminal else {
            return
        }
        guard confirm("Run shipit doctor now to check this configuration?", defaultAnswer: true) else {
            return
        }

        Self.logger.info("Running doctor after Shipfile generation")
        var doctor = DoctorCommand()
        doctor.global = global
        doctor.global.shipfile = outputPath
        try await doctor.run()
    }

    private func resolvedOutputPath() -> String {
        let baseURL = URL(fileURLWithPath: path)
        let shipfileURL = URL(fileURLWithPath: global.shipfile)
        if shipfileURL.path.hasPrefix("/") {
            return shipfileURL.path
        }
        return baseURL.appendingPathComponent(global.shipfile).path
    }

    private func apply(overrides: [String: String], to yaml: String) -> String {
        overrides.reduce(yaml) { result, entry in
            guard !entry.value.isEmpty else { return result }
            return result.replacingOccurrences(of: entry.key, with: entry.value)
        }
    }

    private func choosePlatform(defaultPlatform: Platform) -> Platform {
        let answer = ask(
            "Platform to generate for (ios/android)", defaultValue: defaultPlatform.rawValue
        ).lowercased()
        return Platform(rawValue: answer) ?? defaultPlatform
    }

    private func ask(_ prompt: String, defaultValue: String?) -> String {
        let suffix = defaultValue.map { " [\($0)]" } ?? ""
        let promptLine = "\(prompt)\(suffix): "
        print(promptLine, terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = resolvedPromptValue(answer: answer, defaultValue: defaultValue)
        if answer.isEmpty, let defaultValue {
            print(
                defaultPromptEcho(promptLine: promptLine, value: defaultValue, isStdoutTTY: isatty(STDOUT_FILENO) != 0),
                terminator: ""
            )
        }
        return value
    }

    private func confirm(_ prompt: String, defaultAnswer: Bool) -> Bool {
        let suffix = defaultAnswer ? "Y/n" : "y/N"
        let promptLine = "\(prompt) [\(suffix)]: "
        print(promptLine, terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if answer.isEmpty {
            print(
                defaultPromptEcho(
                    promptLine: promptLine,
                    value: defaultConfirmationEcho(defaultAnswer: defaultAnswer),
                    isStdoutTTY: isatty(STDOUT_FILENO) != 0
                ),
                terminator: ""
            )
            return defaultAnswer
        }
        return ["y", "yes"].contains(answer)
    }

    private func inspectProject() async throws -> ProjectInspection {
        guard
            shouldPrintGenerateInspectionStatus(
                output: global.output,
                isStderrTTY: isatty(STDERR_FILENO) != 0
            )
        else {
            return try await ProjectInspector(rootPath: path).inspect()
        }

        let spinner = TerminalSpinner(message: "Inspecting project and inferring defaults")
        async let animation: Void = spinner.run()

        do {
            let inspection = try await ProjectInspector(rootPath: path).inspect()
            await spinner.finish()
            await animation
            return inspection
        } catch {
            await spinner.finish()
            await animation
            throw error
        }
    }

    private var isInteractiveTerminal: Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    }
}

func shouldPrintGenerateInspectionStatus(output: OutputFormat, isStderrTTY: Bool) -> Bool {
    output == .human && isStderrTTY
}

func resolvedPromptValue(answer: String, defaultValue: String?) -> String {
    answer.isEmpty ? (defaultValue ?? "") : answer
}

func defaultConfirmationEcho(defaultAnswer: Bool) -> String {
    defaultAnswer ? "yes" : "no"
}

func defaultPromptEcho(promptLine: String, value: String, isStdoutTTY: Bool) -> String {
    if isStdoutTTY {
        return "\u{001B}[1A\u{001B}[2K\r\(promptLine)\(value)\n"
    }
    return "\(value)\n"
}

private actor TerminalSpinner {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let message: String
    private var isRunning = true

    init(message: String) {
        self.message = message
    }

    func run() async {
        var index = 0
        while isRunning {
            fputs("\r\(frames[index % frames.count]) \(message)", stderr)
            fflush(stderr)
            index += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func finish() {
        isRunning = false
        fputs("\r\u{001B}[2K", stderr)
        fflush(stderr)
    }
}
