import ArgumentParser
import Foundation
import Logging
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

        if hasIOS && hasAndroid && !nonInteractive {
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
        guard !nonInteractive else {
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
            overrides[
                "# App Store Connect credentials are only needed when you want to upload to TestFlight.\n# Uncomment this section and add a `testflight` step to the beta workflow when ready.\n# app_store_connect:"
            ] = "app_store_connect:"
            overrides["#   key_id: ${ASC_KEY_ID}"] = "  key_id: ${ASC_KEY_ID}"
            overrides["#   issuer_id: ${ASC_ISSUER_ID}"] = "  issuer_id: ${ASC_ISSUER_ID}"
            overrides["#   key_path: ${ASC_PRIVATE_KEY_PATH}"] = "  key_path: ${ASC_PRIVATE_KEY_PATH}"
            overrides[
                "    # To upload to TestFlight, uncomment the app_store_connect section above and add:\n    # - action: testflight\n    #   options:\n    #     groups: [\"Internal QA\"]"
            ] = "    - action: testflight\n      options:\n        groups: [\"Internal QA\"]"
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

        // --- Keystore setup ---
        let (keystorePath, keystoreAlias, keystorePassword, keyPassword) = collectAndroidKeystore(
            formatter: formatter)
        addOverride(&overrides, placeholder: "${SHIPIT_ANDROID__KEYSTORE_PATH}", value: keystorePath)
        addOverride(&overrides, placeholder: "${SHIPIT_ANDROID__KEY_ALIAS}", value: keystoreAlias)

        // --- Signing env vars (always shown) ---
        // Gradle needs these env vars to apply the signing config at build time.
        // The keystore path and alias are in the Shipfile, but Gradle also reads
        // them from env vars — so we must inform the user to export all four.
        var signingEnvOverrides: [String: String] = [:]
        if !keystorePath.isEmpty { signingEnvOverrides["SHIPIT_ANDROID__KEYSTORE_PATH"] = keystorePath }
        if !keystoreAlias.isEmpty { signingEnvOverrides["SHIPIT_ANDROID__KEY_ALIAS"] = keystoreAlias }
        if !keystorePassword.isEmpty { signingEnvOverrides["SHIPIT_ANDROID__KEYSTORE_PASSWORD"] = keystorePassword }
        if !keyPassword.isEmpty { signingEnvOverrides["SHIPIT_ANDROID__KEY_PASSWORD"] = keyPassword }

        let signingEnvSpecs: [EnvVarSpec] = [
            EnvVarSpec(
                name: "SHIPIT_ANDROID__KEYSTORE_PATH", isSensitive: false,
                description: "Path to .keystore / .jks file (read by Gradle signingConfig)"),
            EnvVarSpec(
                name: "SHIPIT_ANDROID__KEY_ALIAS", isSensitive: false,
                description: "Keystore key alias (read by Gradle signingConfig)"),
            EnvVarSpec(
                name: "SHIPIT_ANDROID__KEYSTORE_PASSWORD", isSensitive: true,
                description: "Keystore password (read by Gradle signingConfig)"),
            EnvVarSpec(
                name: "SHIPIT_ANDROID__KEY_PASSWORD", isSensitive: true,
                description: "Key alias password (read by Gradle signingConfig)"),
        ]

        if !signingEnvOverrides.isEmpty {
            formatter.printHeader("Android Signing — Required Environment Variables")
            formatter.print("Your build.gradle.kts reads these env vars to sign the release AAB.")
            formatter.print("Add them to your shell profile (~/.zshrc) or CI secrets:\n")
            for spec in signingEnvSpecs {
                guard let value = signingEnvOverrides[spec.name] else { continue }
                let display =
                    spec.isSensitive ? String(repeating: "*", count: min(value.count, 8)) : value
                formatter.print("  export \(spec.name)=\"\(display)\"")
            }
            formatter.print("")
            formatter.printWarning(
                "Without these exports, Gradle will produce an unsigned AAB that Google Play rejects.")
            formatter.printWarning(
                "Sensitive values shown as **** above — copy from your earlier input.")
            formatter.print("")
        }

        let uploadsToPlay =
            goal == .release
            || confirm(
                "Do you want this Shipfile to include Google Play upload settings?", defaultAnswer: false)
        if uploadsToPlay {
            formatter.printHeader("Google Play Environment")
            formatter.print("ShipIt will reference env vars instead of storing secrets in Shipfile.yml.")

            // Values already collected during keystore setup — treat as [collected].
            var envOverrides: [String: String] = [:]
            if !keystorePassword.isEmpty { envOverrides["SHIPIT_ANDROID__KEYSTORE_PASSWORD"] = keystorePassword }
            if !keyPassword.isEmpty { envOverrides["SHIPIT_ANDROID__KEY_PASSWORD"] = keyPassword }

            let processEnv = ProcessInfo.processInfo.environment
            let envSpecs: [EnvVarSpec] = [
                EnvVarSpec(
                    name: "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH", isSensitive: false,
                    description: "Path to service account JSON (preferred)"),
                EnvVarSpec(
                    name: "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", isSensitive: true,
                    description: "Raw service account JSON content (CI fallback)"),
                EnvVarSpec(
                    name: "SHIPIT_ANDROID__KEYSTORE_PASSWORD", isSensitive: true,
                    description: "Keystore password"),
                EnvVarSpec(
                    name: "SHIPIT_ANDROID__KEY_PASSWORD", isSensitive: true,
                    description: "Key alias password"),
            ]

            // Show status for all specs so the user can see what's already handled.
            for spec in envSpecs {
                if envOverrides[spec.name] != nil {
                    formatter.printKV(spec.name, "[collected]  \(spec.description)")
                } else if processEnv[spec.name] != nil {
                    formatter.printKV(spec.name, "[set]  \(spec.description)")
                } else {
                    formatter.printKV(spec.name, "(not set)  \(spec.description)")
                }
            }

            // Only prompt for specs not yet answered in-memory or in the process env.
            let filteredSpecs = envSpecs.filter {
                envOverrides[$0.name] == nil && processEnv[$0.name] == nil
            }
            if !filteredSpecs.isEmpty {
                formatter.print("")
                let collected = collectEnvironmentVariables(filteredSpecs, formatter: formatter, showStatusTable: false)
                envOverrides.merge(collected) { _, new in new }
            }

            if !envOverrides.isEmpty {
                formatter.printHeader("Run These Exports in Your Shell")
                formatter.print("Add these to your shell profile or CI secrets:")
                for spec in envSpecs {
                    guard let value = envOverrides[spec.name] else { continue }
                    let display =
                        spec.isSensitive ? String(repeating: "*", count: min(value.count, 8)) : value
                    formatter.print("  export \(spec.name)=\(display)")
                }
                formatter.print("")
                formatter.printWarning(
                    "Sensitive values shown as **** above — copy from your input above before continuing.")
            }

            overrides["    # - action: play-store"] = "    - action: play-store"
        }

        return overrides
    }

    /// Guides the user through keystore setup: either creating a new one via `keytool`
    /// or reading alias information from an existing one.
    ///
    /// Returns `(keystorePath, keystoreAlias, keystorePassword, keyPassword)`.
    private func collectAndroidKeystore(formatter: HumanFormatter)
        -> (path: String, alias: String, keystorePassword: String, keyPassword: String)
    {
        formatter.printHeader("Android Keystore")

        let hasKeystore = confirm("Do you already have an Android keystore (.jks / .keystore)?", defaultAnswer: true)

        if hasKeystore {
            return collectExistingKeystore(formatter: formatter)
        } else {
            return createNewKeystore(formatter: formatter)
        }
    }

    /// Prompts for an existing keystore path and password, then tries to read aliases
    /// via `keytool -list -v`.  Falls back to manual alias entry on any failure.
    private func collectExistingKeystore(formatter: HumanFormatter)
        -> (path: String, alias: String, keystorePassword: String, keyPassword: String)
    {
        let keystorePath = ask("Keystore path (.jks or .keystore)", defaultValue: nil)
        guard !keystorePath.isEmpty else {
            formatter.printWarning("No keystore path entered; you can set it manually in Shipfile.yml later.")
            return ("", "", "", "")
        }

        formatter.print("Enter the keystore password to inspect aliases (leave blank to enter alias manually).")
        let keystorePassword = askSecret("Keystore password")

        var resolvedAlias = ""
        if !keystorePassword.isEmpty {
            resolvedAlias = readAliasFromKeystore(
                path: keystorePath, password: keystorePassword, formatter: formatter)
        }

        if resolvedAlias.isEmpty {
            resolvedAlias = ask("Keystore key alias", defaultValue: nil)
        }

        // Key password may differ from keystore password.
        formatter.print(
            "Key password (press Enter to use the same password as the keystore).")
        let rawKeyPassword = askSecret("Key password")
        let keyPassword = rawKeyPassword.isEmpty ? keystorePassword : rawKeyPassword

        return (keystorePath, resolvedAlias, keystorePassword, keyPassword)
    }

    /// Runs `keytool -list -v` to extract aliases from an existing keystore.
    /// Returns the selected alias, or an empty string on failure.
    private func readAliasFromKeystore(
        path: String, password: String, formatter: HumanFormatter
    ) -> String {
        let keytoolPath = resolveKeytoolPath()
        guard let keytoolPath else {
            formatter.printWarning("keytool not found on PATH — alias must be entered manually.")
            return ""
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: keytoolPath)
        proc.arguments = [
            "-list", "-v",
            "-keystore", path,
            "-storepass", password,
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()  // suppress keytool warnings

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            formatter.printWarning("Could not run keytool: \(error.localizedDescription)")
            return ""
        }

        guard proc.terminationStatus == 0 else {
            formatter.printWarning("keytool exited with error — check keystore path and password.")
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let aliases = parseAliases(from: output)

        switch aliases.count {
        case 0:
            formatter.printWarning("No aliases found in keystore.")
            return ""
        case 1:
            formatter.print("Found alias: \(aliases[0])")
            return aliases[0]
        default:
            formatter.print("Multiple aliases found:")
            for (i, alias) in aliases.enumerated() {
                formatter.print("  \(i + 1). \(alias)")
            }
            let input = ask(
                "Enter alias number or type the alias directly",
                defaultValue: "1")
            if let idx = Int(input), idx >= 1, idx <= aliases.count {
                return aliases[idx - 1]
            }
            return input
        }
    }

    /// Parses `Alias name: <value>` lines from `keytool -list -v` output.
    private func parseAliases(from output: String) -> [String] {
        output.components(separatedBy: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.lowercased().hasPrefix("alias name:") else { return nil }
                let value = trimmed.dropFirst("alias name:".count)
                    .trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
    }

    /// Guides the user through creating a brand-new keystore by collecting distinguished
    /// name fields and invoking `keytool -genkeypair`.
    private func createNewKeystore(formatter: HumanFormatter)
        -> (path: String, alias: String, keystorePassword: String, keyPassword: String)
    {
        formatter.printHeader("Create New Keystore")
        formatter.print("ShipIt will run keytool to generate a new keystore for you.")
        formatter.print("")

        guard let keytoolPath = resolveKeytoolPath() else {
            formatter.printWarning(
                "keytool not found on PATH. Install a JDK (e.g. via `brew install openjdk`) and re-run.")
            formatter.print("Then run: keytool -genkeypair -v -keystore ./keystore.jks -alias <alias> \\")
            formatter.print("  -keyalg RSA -keysize 2048 -validity 10000 -storepass <pw> -keypass <pw>")
            return ("", "", "", "")
        }

        // Output path
        let outputPath = ask("Keystore output path", defaultValue: "./keystore.jks")

        // Alias
        let alias = ask("Key alias (e.g. my-app-key)", defaultValue: "release")

        // Passwords
        formatter.print("Choose a keystore password (min 6 characters).")
        let keystorePassword = askSecret("Keystore password")
        let confirm1 = askSecret("Confirm keystore password")
        guard keystorePassword == confirm1, !keystorePassword.isEmpty else {
            formatter.printWarning("Passwords did not match or were empty — keystore not created.")
            return (outputPath, alias, "", "")
        }

        formatter.print("Key password (press Enter to use the same as keystore password).")
        let rawKeyPassword = askSecret("Key password")
        let keyPassword = rawKeyPassword.isEmpty ? keystorePassword : rawKeyPassword

        // Distinguished name fields
        formatter.print("")
        formatter.print("These fields are embedded in the signing certificate (press Enter to skip any).")
        let cn = ask("Your name or organisation (CN)", defaultValue: nil)
        let ou = ask("Organisational unit (OU)", defaultValue: nil)
        let o  = ask("Organisation (O)", defaultValue: nil)
        let l  = ask("City / Locality (L)", defaultValue: nil)
        let st = ask("State / Province (ST)", defaultValue: nil)
        let c  = ask("Two-letter country code (C)", defaultValue: nil)
        let validityDays = ask("Validity in days", defaultValue: "10000")

        var dnParts: [String] = []
        if !cn.isEmpty { dnParts.append("CN=\(cn)") }
        if !ou.isEmpty { dnParts.append("OU=\(ou)") }
        if !o.isEmpty  { dnParts.append("O=\(o)") }
        if !l.isEmpty  { dnParts.append("L=\(l)") }
        if !st.isEmpty { dnParts.append("ST=\(st)") }
        if !c.isEmpty  { dnParts.append("C=\(c)") }
        let dname = dnParts.isEmpty ? "CN=Unknown" : dnParts.joined(separator: ", ")

        // Run keytool
        formatter.print("")
        formatter.print("Generating keystore…")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: keytoolPath)
        proc.arguments = [
            "-genkeypair", "-v",
            "-keystore", outputPath,
            "-alias", alias,
            "-keyalg", "RSA",
            "-keysize", "2048",
            "-validity", validityDays,
            "-storepass", keystorePassword,
            "-keypass", keyPassword,
            "-dname", dname,
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            formatter.printWarning("Failed to run keytool: \(error.localizedDescription)")
            return (outputPath, alias, keystorePassword, keyPassword)
        }

        if proc.terminationStatus == 0 {
            formatter.print("Keystore created at: \(outputPath)")
        } else {
            formatter.printWarning(
                "keytool exited with status \(proc.terminationStatus) — check output above.")
        }

        return (outputPath, alias, keystorePassword, keyPassword)
    }

    /// Returns the path to `keytool`, preferring `JAVA_HOME/bin/keytool` then PATH lookup.
    private func resolveKeytoolPath() -> String? {
        if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            let candidate = "\(javaHome)/bin/keytool"
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        // Fall back to PATH lookup via `which keytool`.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["keytool"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
        } catch {
            return nil
        }
        guard which.terminationStatus == 0 else { return nil }
        let found = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return found.isEmpty ? nil : found
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
    /// - Pass `showStatusTable: false` when the caller already printed a full status
    ///   table and you only want the prompting loop.
    @discardableResult
    private func collectEnvironmentVariables(
        _ specs: [EnvVarSpec], formatter: HumanFormatter, showStatusTable: Bool = true
    ) -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var collected: [String: String] = [:]

        if showStatusTable {
            for spec in specs {
                let isSet = env[spec.name] != nil
                let statusTag = isSet ? "[set]" : "(not set)"
                formatter.printKV(spec.name, "\(statusTag)  \(spec.description)")
            }
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
        fflush(nil)

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

    private func offerDoctor(outputPath: String, formatter: HumanFormatter) async throws {
        #if os(macOS)
        guard !skipDoctorPrompt, !nonInteractive, isInteractiveTerminal else {
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
        #endif
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
    isStderrTTY
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
            FileHandle.standardError.write(Data("\r\(frames[index % frames.count]) \(message)".utf8))
            index += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func finish() {
        isRunning = false
        FileHandle.standardError.write(Data("\r\u{001B}[2K".utf8))
    }
}
