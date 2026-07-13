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

    enum PlatformFocus: String, Sendable {
        case ios
        case android
        case both

        var platform: Platform? {
            switch self {
            case .ios:
                return .ios
            case .android:
                return .android
            case .both:
                return nil
            }
        }
    }

    func run() async throws {
        Self.logger.info("Starting Shipfile generation for path: \(path)")

        let formatter = makeHumanFormatter(global: global)
        let inspection = try await inspectProject()
        let outputPath = resolvedOutputPath()
        if global.dryRun, global.output == .json {
            let focus = resolvedNonInteractivePlatformFocus(from: inspection)
            let platform = focus.platform ?? inspection.detectedPlatform
            let suggestion = ShipfileSuggester().suggest(goal: goal, platform: platform, from: inspection)
            try outputDryRun(
                action: "generate",
                message: "Would generate Shipfile at '\(outputPath)'",
                payload: [
                    "path": .string(outputPath),
                    "goal": .string(goal.rawValue),
                    "platform": .string(platform.rawValue),
                    "yaml": .string(suggestion.yaml),
                ],
                global: global
            )
            return
        }

        let focus = try resolvePlatformFocus(from: inspection, formatter: formatter)
        let platform = focus.platform ?? inspection.detectedPlatform
        let suggestion = ShipfileSuggester().suggest(goal: goal, platform: platform, from: inspection)

        if global.dryRun {
            try outputDryRun(
                action: "generate",
                message: "Would generate Shipfile at '\(outputPath)'",
                payload: [
                    "path": .string(outputPath),
                    "goal": .string(goal.rawValue),
                    "platform": .string(platform.rawValue),
                    "yaml": .string(suggestion.yaml),
                ],
                global: global
            )
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
            focus: focus,
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
        switch global.output {
        case .json:
            print(
                try JSONReporter().encode(
                    ActionResultEnvelope(action: "generate", status: "success", payload: payload)))
        case .human:
            formatter.printSuccess("Generated Shipfile at \(outputPath)")
        }

        Self.logger.info("Shipfile generation completed")
        if global.output == .human {
            printReleaseSetupGuidance(formatter: formatter)
            try await offerDoctor(outputPath: outputPath, formatter: formatter)
        }
    }

    private func resolvedNonInteractivePlatformFocus(from inspection: ProjectInspection) -> PlatformFocus {
        if let platform = global.platform {
            return platform == .ios ? .ios : .android
        }
        if inspection.detectedBuildSystem == .reactNative || inspection.detectedBuildSystem == .flutter {
            return .both
        }
        return inspection.detectedPlatform == .ios ? .ios : .android
    }

    private func resolvePlatformFocus(
        from inspection: ProjectInspection, formatter: HumanFormatter
    ) throws
        -> PlatformFocus
    {
        if let platform = global.platform {
            return platform == .ios ? .ios : .android
        }

        if inspection.detectedBuildSystem == .reactNative || inspection.detectedBuildSystem == .flutter {
            guard !nonInteractive else { return .both }

            formatter.printHeader("Detected Platforms")
            formatter.print("This project supports both iOS and Android workflows.")
            return choosePlatformFocus(defaultFocus: .both)
        }

        let hasIOS = !inspection.xcodeContainers.isEmpty
        let hasAndroid = !inspection.gradleFiles.isEmpty

        if hasIOS && hasAndroid && !nonInteractive {
            formatter.printHeader("Detected Platforms")
            formatter.print("This project appears to contain both iOS and Android files.")
            return choosePlatform(defaultFocus: .both, fallbackPlatform: inspection.detectedPlatform)
        }

        return inspection.detectedPlatform == .ios ? .ios : .android
    }

    private func buildYAML(
        suggestion: SuggestedShipfile,
        focus: PlatformFocus,
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
        formatter.printKV("Platform Focus", focus.rawValue)
        formatter.printKV("Goal", goal.rawValue)

        for warning in suggestion.warnings {
            formatter.printWarning(warning)
        }

        let overrides = collectOverrides(
            suggestion: suggestion, platform: platform, formatter: formatter)
        var confirmedYAML = apply(overrides: overrides, to: suggestion.yaml)
        confirmedYAML = applyTestRetryQuestionnaire(to: confirmedYAML, formatter: formatter)
        confirmedYAML = applyReleaseTaggingQuestionnaire(to: confirmedYAML, formatter: formatter)

        formatter.printHeader("Shipfile Preview")
        formatter.print(confirmedYAML)

        guard confirm("Write this Shipfile.yml?", defaultAnswer: true) else {
            Self.logger.info("Shipfile generation cancelled at final confirmation")
            throw ExitCode(1)
        }

        return confirmedYAML
    }

    /// For a `release` goal, explains the commit/tag/push tail and offers to drive the
    /// version bump component from CI via the `RELEASE_BUMP` env var. Interactive only —
    /// non-interactive generation keeps the default `bump: patch` scaffold.
    private func applyReleaseTaggingQuestionnaire(to yaml: String, formatter: HumanFormatter) -> String {
        guard goal == .release, yaml.contains("operation: tag") else { return yaml }

        formatter.printHeader("Release Tagging")
        formatter.print("The release workflow commits the version bump, tags the released marketing")
        formatter.print("version (v{{version}}), and pushes — the tag step is skipped on build-only")
        formatter.print("bumps. It all runs as one `shipit run release`, no external scripting.")
        let ciDriven = confirm(
            "Drive the version bump component from CI via the RELEASE_BUMP env var?",
            defaultAnswer: false)
        return releaseBumpFromCI(yaml: yaml, enabled: ciDriven)
    }

    /// Prints the CI prerequisites for the release workflow's commit/tag/push tail.
    /// Interactive `release` generations only.
    private func printReleaseSetupGuidance(formatter: HumanFormatter) {
        guard goal == .release, !nonInteractive, isInteractiveTerminal else { return }

        formatter.printHeader("Release Setup — CI Prerequisites")
        formatter.print("Your `release` workflow commits, tags, and pushes. The CI job that runs")
        formatter.print("`shipit run release` needs:")
        formatter.print("  • Full-history checkout so tags resolve (GitHub Actions: actions/checkout with fetch-depth: 0)")
        formatter.print("  • Write permission to push the commit and tag (e.g. permissions: contents: write, or a PAT)")
        formatter.print("  • A git identity (git config user.name / user.email)")
        formatter.print("  • Optional: set RELEASE_BUMP=major|minor|patch|build at dispatch to choose the bump")
        formatter.print("")
        formatter.print("Run locally with:  shipit run release")
        formatter.print("More: docs/ci-setup.md and the “Workflow tokens” section of docs/configuration-reference.md.")
    }

    private func applyTestRetryQuestionnaire(to yaml: String, formatter: HumanFormatter) -> String {
        guard yaml.contains("infrastructure_retry"), yaml.contains("# options: { infrastructure_retry") else {
            return yaml
        }

        formatter.printHeader("Test Retry Policy")
        formatter.print("ShipIt can retry the entire test invocation for transient infrastructure failures.")
        formatter.print(
            "Examples: iOS simulator launch crashes, Android emulator disconnects, Flutter tool crashes, and JS worker failures.")
        let enableRetries = confirm("Enable infrastructure retries for generated test steps?", defaultAnswer: true)
        guard enableRetries else { return yaml }

        let attempts = ask("Maximum attempts including the first run", defaultValue: "3")
        let initialDelay = ask("Initial retry delay in seconds", defaultValue: "2")
        let maxDelay = ask("Maximum retry delay in seconds", defaultValue: "30")
        let optionLine =
            "      options: { infrastructure_retry: { max_attempts: \(attempts), initial_delay_seconds: \(initialDelay), max_delay_seconds: \(maxDelay) } }"
        let nestedLine =
            "        infrastructure_retry: { max_attempts: \(attempts), initial_delay_seconds: \(initialDelay), max_delay_seconds: \(maxDelay) }"

        return
            yaml
            .replacingOccurrences(
                of: "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                with: optionLine
            )
            .replacingOccurrences(
                of: "        # infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }",
                with: nestedLine
            )
    }

    private func collectOverrides(
        suggestion: SuggestedShipfile,
        platform: Platform,
        formatter: HumanFormatter
    ) -> [String: String] {
        if suggestion.inspection.detectedBuildSystem == .reactNative {
            var overrides = collectIOSOverrides(suggestion: suggestion, formatter: formatter)
            for (key, value) in collectAndroidOverrides(suggestion: suggestion, formatter: formatter) {
                overrides[key] = value
            }
            return overrides
        }

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
        formatter.printHeader("iOS Configuration")
        formatter.print("Tip: For any value, you can enter ${MY_ENV_VAR} to reference an environment variable at runtime.\n")

        var overrides: [String: String] = [:]
        addOverride(
            &overrides, placeholder: "${SHIPIT_APP__SCHEME}",
            value: ask(iosPrompt("Xcode scheme"), defaultValue: app.scheme))
        addOverride(
            &overrides, placeholder: "${SHIPIT_APP__BUNDLE_ID}",
            value: ask(iosPrompt("Bundle identifier"), defaultValue: app.bundleID))
        addOverride(
            &overrides, placeholder: "${SHIPIT_APP__TEAM_ID}",
            value: ask(iosPrompt("Apple Developer Team ID"), defaultValue: app.teamID))

        if app.workspace == nil && app.project == nil {
            let container = ask(iosPrompt("Workspace or project path"), defaultValue: nil)
            if container.hasSuffix(".xcworkspace") {
                overrides["# workspace: MyApp.xcworkspace"] = "workspace: \(container)"
            } else if !container.isEmpty {
                overrides["# project: MyApp.xcodeproj"] = "project: \(container)"
            }
        }

        let uploadsToTestFlight =
            goal == .release
            || confirm(
                iosPrompt("Include App Store Connect upload settings?"),
                defaultAnswer: false)
        if uploadsToTestFlight {
            formatter.printHeader("iOS App Store Connect")
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
            iosPrompt("Use manual code signing (.p12 + provisioning profile)?"), defaultAnswer: false)
        if usesManualSigning {
            formatter.printHeader("iOS Code Signing")
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
        formatter.printHeader("Android Configuration")
        formatter.print("Tip: For any value, you can enter ${MY_ENV_VAR} to reference an environment variable at runtime.\n")

        var overrides: [String: String] = [:]
        addOverride(
            &overrides, placeholder: "${SHIPIT_ANDROID__MODULE}",
            value: ask(androidPrompt("Gradle module"), defaultValue: "app"))
        addOverride(
            &overrides, placeholder: "${SHIPIT_ANDROID__PACKAGE_NAME}",
            value: ask(androidPrompt("Package name"), defaultValue: suggestion.inspection.suggestedAndroidPackageName))

        // --- Build variant ---
        formatter.print("")
        formatter.print("Build variant determines the AAB output path and Gradle task.")
        formatter.print("Common values: release, prodRelease, stagingRelease, debug")
        formatter.print("If you use product flavors (e.g. prod + release), use the combined name (e.g. prodRelease).")
        let buildVariant = ask(androidPrompt("Build variant"), defaultValue: "release")
        addOverride(&overrides, placeholder: "build_variant: release", value: "build_variant: \(buildVariant)")

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
            formatter.print("Without them, Gradle produces an unsigned bundle that Google Play rejects.\n")

            let envFilePath = (path as NSString).appendingPathComponent(".env")
            let envFileExists = FileManager.default.fileExists(atPath: envFilePath)
            let envOption =
                envFileExists
                ? "Update existing .env file (auto-loaded by shipit)"
                : "Create a .env file (recommended for local dev, auto-loaded by shipit)"

            let setupChoice = choose(
                "How would you like to configure signing environment variables?",
                options: [
                    envOption,
                    "Append to shell profile (~/.zshrc or ~/.bashrc)",
                    "I'll set them up manually — just show me the names",
                ],
                defaultIndex: 0
            )

            switch setupChoice {
            case 0:
                writeSigningEnvFile(
                    signingEnvOverrides, specs: signingEnvSpecs, formatter: formatter)
            case 1:
                appendSigningToShellProfile(
                    signingEnvOverrides, specs: signingEnvSpecs, formatter: formatter)
            default:
                formatter.print("\nRequired exports:")
                for spec in signingEnvSpecs {
                    guard signingEnvOverrides[spec.name] != nil else { continue }
                    let display =
                        spec.isSensitive ? "<your-value>" : (signingEnvOverrides[spec.name] ?? "")
                    formatter.print("  export \(spec.name)=\"\(display)\"")
                }
                formatter.print("")
                formatter.printWarning(
                    "You must set these before running `shipit archive` or `shipit run`.")
            }
            formatter.print("")
        }

        let uploadsToPlay =
            goal == .release
            || confirm(
                androidPrompt("Include Google Play upload settings?"), defaultAnswer: false)
        if uploadsToPlay {
            formatter.printHeader("Android Google Play")
            formatter.print("ShipIt needs these env vars for signing and uploading to Google Play.")
            formatter.print("Press Enter to accept detected values, or type your own.\n")

            // Values already collected during keystore setup
            var envOverrides: [String: String] = [:]
            if !keystorePassword.isEmpty { envOverrides["SHIPIT_ANDROID__KEYSTORE_PASSWORD"] = keystorePassword }
            if !keyPassword.isEmpty { envOverrides["SHIPIT_ANDROID__KEY_PASSWORD"] = keyPassword }

            let processEnv = ProcessInfo.processInfo.environment
            let dotEnvValues = readDotEnvValues(directory: path)
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

            // Show clear status for each var
            for spec in envSpecs {
                let status: String
                if envOverrides[spec.name] != nil {
                    status = "ready (collected above)"
                } else if let envVal = processEnv[spec.name] {
                    status = spec.isSensitive ? "ready (set in environment)" : "ready (\(envVal))"
                } else if let dotVal = dotEnvValues[spec.name] {
                    status = spec.isSensitive ? "ready (set in .env)" : "ready (\(dotVal))"
                } else {
                    status = "missing"
                }
                formatter.print("  \(spec.name): \(status)")
                formatter.print("    \(spec.description)")
            }

            // Only prompt for vars that are truly missing (not collected, not in env, not in .env)
            let filteredSpecs = envSpecs.filter {
                envOverrides[$0.name] == nil
                    && processEnv[$0.name] == nil
                    && dotEnvValues[$0.name] == nil
            }
            if !filteredSpecs.isEmpty {
                formatter.print("\nThe following are not yet configured:")
                let collected = collectEnvironmentVariables(filteredSpecs, formatter: formatter, showStatusTable: false)
                envOverrides.merge(collected) { _, new in new }
            } else {
                formatter.print("\nAll required env vars are already configured.")
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

            // Ask which track to upload to
            formatter.printHeader("Android Google Play Track")
            formatter.print("Which Google Play track should this workflow upload to?")
            formatter.print("  1) internal  — small internal testing group (recommended for beta)")
            formatter.print("  2) alpha     — closed testing")
            formatter.print("  3) beta      — open testing")
            formatter.print("  4) production")
            let trackChoices = ["internal", "alpha", "beta", "production"]
            let defaultTrack = goal == .release ? "production" : "internal"
            let defaultIndex = trackChoices.firstIndex(of: defaultTrack)! + 1
            let trackInput = ask(androidPrompt("Google Play track"), defaultValue: "\(defaultIndex)")
            let selectedTrack: String
            if let idx = Int(trackInput), (1...4).contains(idx) {
                selectedTrack = trackChoices[idx - 1]
            } else if trackChoices.contains(trackInput.lowercased()) {
                selectedTrack = trackInput.lowercased()
            } else {
                selectedTrack = defaultTrack
            }

            overrides[
                "    # Add this when you are ready to upload to Google Play:\n    # - action: play-store\n    #   options: { track: internal }"
            ] = "    - action: play-store\n      options: { track: \(selectedTrack) }"
        }

        return overrides
    }

    /// Guides the user through keystore setup: either creating a new one via `keytool`
    /// or reading alias information from an existing one.
    ///
    /// Returns `(keystorePath, keystoreAlias, keystorePassword, keyPassword)`.
    private func collectAndroidKeystore(
        formatter: HumanFormatter
    )
        -> (path: String, alias: String, keystorePassword: String, keyPassword: String)
    {
        formatter.printHeader("Android Keystore")

        // If we can detect an existing keystore path from env or .env, skip the "do you have one?" question
        let env = ProcessInfo.processInfo.environment
        let dotEnvValues = readDotEnvValues(directory: path)
        let detectedPath = env["SHIPIT_ANDROID__KEYSTORE_PATH"] ?? dotEnvValues["SHIPIT_ANDROID__KEYSTORE_PATH"]

        let hasKeystore: Bool
        if detectedPath != nil {
            hasKeystore = true
        } else {
            hasKeystore = confirm(androidPrompt("Do you already have a keystore (.jks / .keystore)?"), defaultAnswer: true)
        }

        if hasKeystore {
            return collectExistingKeystore(formatter: formatter)
        } else {
            return createNewKeystore(formatter: formatter)
        }
    }

    /// Prompts for an existing keystore path and password, then tries to read aliases
    /// via `keytool -list -v`.  Falls back to manual alias entry on any failure.
    private func collectExistingKeystore(
        formatter: HumanFormatter
    )
        -> (path: String, alias: String, keystorePassword: String, keyPassword: String)
    {
        let env = ProcessInfo.processInfo.environment

        // Check for existing env vars that could prefill values
        let existingPath = env["SHIPIT_ANDROID__KEYSTORE_PATH"]
        let existingAlias = env["SHIPIT_ANDROID__KEY_ALIAS"]
        let existingKeystorePassword = env["SHIPIT_ANDROID__KEYSTORE_PASSWORD"]
        let existingKeyPassword = env["SHIPIT_ANDROID__KEY_PASSWORD"]

        // Also check .env file in project directory
        let dotEnvValues = readDotEnvValues(directory: path)
        let prefillPath = existingPath ?? dotEnvValues["SHIPIT_ANDROID__KEYSTORE_PATH"]
        let prefillAlias = existingAlias ?? dotEnvValues["SHIPIT_ANDROID__KEY_ALIAS"]
        let prefillKeystorePassword = existingKeystorePassword ?? dotEnvValues["SHIPIT_ANDROID__KEYSTORE_PASSWORD"]
        let prefillKeyPassword = existingKeyPassword ?? dotEnvValues["SHIPIT_ANDROID__KEY_PASSWORD"]

        let hasExisting = prefillPath != nil || prefillAlias != nil
        if hasExisting {
            formatter.print("Detected existing signing configuration:")
            if let p = prefillPath {
                let source = existingPath != nil ? "env" : ".env"
                formatter.print("  Keystore path: \(p) (from \(source))")
            }
            if let a = prefillAlias {
                let source = existingAlias != nil ? "env" : ".env"
                formatter.print("  Key alias: \(a) (from \(source))")
            }
            if prefillKeystorePassword != nil { formatter.print("  Keystore password: ******** (detected)") }
            if prefillKeyPassword != nil { formatter.print("  Key password: ******** (detected)") }
            formatter.print("")
        }

        let keystorePath: String
        if prefillPath != nil {
            // Show the env var reference as default so Shipfile uses ${ENV_VAR} syntax
            let envVarDefault =
                existingPath != nil
                ? "${SHIPIT_ANDROID__KEYSTORE_PATH}"
                : (dotEnvValues["SHIPIT_ANDROID__KEYSTORE_PATH"].map { _ in "${SHIPIT_ANDROID__KEYSTORE_PATH}" } ?? prefillPath!)
            let answer = ask(androidPrompt("Keystore path (.jks or .keystore)"), defaultValue: envVarDefault)
            keystorePath = answer
        } else {
            keystorePath = ask(androidPrompt("Keystore path (.jks or .keystore)"), defaultValue: nil)
        }

        guard !keystorePath.isEmpty else {
            formatter.printWarning("No keystore path entered; you can set it manually in Shipfile.yml later.")
            return ("", "", "", "")
        }

        let keystorePassword: String
        if let prefill = prefillKeystorePassword {
            formatter.print("Keystore password detected. Press Enter to keep it, or type a new one.")
            let raw = askSecret(androidPrompt("Keystore password"))
            keystorePassword = raw.isEmpty ? prefill : raw
        } else {
            formatter.print("Enter the keystore password to inspect aliases (leave blank to enter alias manually).")
            keystorePassword = askSecret(androidPrompt("Keystore password"))
        }

        var resolvedAlias = ""
        if !keystorePassword.isEmpty {
            // Use the actual filesystem path for keytool, not the ${ENV_VAR} reference
            let actualKeystorePath = prefillPath ?? keystorePath
            resolvedAlias = readAliasFromKeystore(
                path: actualKeystorePath, password: keystorePassword, formatter: formatter)
        }

        if resolvedAlias.isEmpty {
            let aliasDefault: String? = prefillAlias != nil ? "${SHIPIT_ANDROID__KEY_ALIAS}" : nil
            resolvedAlias = ask(androidPrompt("Keystore key alias"), defaultValue: aliasDefault)
        }

        // Key password may differ from keystore password.
        let keyPassword: String
        if let prefill = prefillKeyPassword {
            formatter.print("Key password detected. Press Enter to keep it, or type a new one.")
            let raw = askSecret(androidPrompt("Key password"))
            keyPassword = raw.isEmpty ? prefill : raw
        } else {
            formatter.print(
                "Key password (press Enter to use the same password as the keystore).")
            let rawKeyPassword = askSecret(androidPrompt("Key password"))
            keyPassword = rawKeyPassword.isEmpty ? keystorePassword : rawKeyPassword
        }

        return (keystorePath, resolvedAlias, keystorePassword, keyPassword)
    }

    /// Reads KEY=VALUE pairs from a .env file without loading them into the process.
    private func readDotEnvValues(directory: String) -> [String: String] {
        let envPath = (directory as NSString).appendingPathComponent(".env")
        guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            var keyValue = trimmed
            if keyValue.hasPrefix("export ") { keyValue = String(keyValue.dropFirst("export ".count)) }
            guard let eq = keyValue.firstIndex(of: "=") else { continue }
            let key = String(keyValue[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(keyValue[keyValue.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
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
                androidPrompt("Enter alias number or type the alias directly"),
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
    private func createNewKeystore(
        formatter: HumanFormatter
    )
        -> (path: String, alias: String, keystorePassword: String, keyPassword: String)
    {
        formatter.printHeader("Android Create Keystore")
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
        let outputPath = ask(androidPrompt("Keystore output path"), defaultValue: "./keystore.jks")

        // Alias
        let alias = ask(androidPrompt("Key alias (e.g. my-app-key)"), defaultValue: "release")

        // Passwords
        formatter.print("Choose a keystore password (min 6 characters).")
        let keystorePassword = askSecret(androidPrompt("Keystore password"))
        let confirm1 = askSecret(androidPrompt("Confirm keystore password"))
        guard keystorePassword == confirm1, !keystorePassword.isEmpty else {
            formatter.printWarning("Passwords did not match or were empty — keystore not created.")
            return (outputPath, alias, "", "")
        }

        formatter.print("Key password (press Enter to use the same as keystore password).")
        let rawKeyPassword = askSecret(androidPrompt("Key password"))
        let keyPassword = rawKeyPassword.isEmpty ? keystorePassword : rawKeyPassword

        // Distinguished name fields
        formatter.print("")
        formatter.print("These fields are embedded in the signing certificate (press Enter to skip any).")
        let cn = ask(androidPrompt("Your name or organisation (CN)"), defaultValue: nil)
        let ou = ask(androidPrompt("Organisational unit (OU)"), defaultValue: nil)
        let o = ask(androidPrompt("Organisation (O)"), defaultValue: nil)
        let l = ask(androidPrompt("City / Locality (L)"), defaultValue: nil)
        let st = ask(androidPrompt("State / Province (ST)"), defaultValue: nil)
        let c = ask(androidPrompt("Two-letter country code (C)"), defaultValue: nil)
        let validityDays = ask(androidPrompt("Validity in days"), defaultValue: "10000")

        var dnParts: [String] = []
        if !cn.isEmpty { dnParts.append("CN=\(cn)") }
        if !ou.isEmpty { dnParts.append("OU=\(ou)") }
        if !o.isEmpty { dnParts.append("O=\(o)") }
        if !l.isEmpty { dnParts.append("L=\(l)") }
        if !st.isEmpty { dnParts.append("ST=\(st)") }
        if !c.isEmpty { dnParts.append("C=\(c)") }
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

    private func choosePlatformFocus(defaultFocus: PlatformFocus) -> PlatformFocus {
        resolvedPlatformFocus(
            answer: ask(
                "Which platform do you want to focus on first? (ios/android/both)", defaultValue: defaultFocus.rawValue
            ),
            defaultFocus: defaultFocus
        )
    }

    private func choosePlatform(defaultFocus: PlatformFocus, fallbackPlatform: Platform) -> PlatformFocus {
        let answer = ask(
            "Which platform do you want to focus on first? (ios/android/both)", defaultValue: defaultFocus.rawValue
        )
        let focus = resolvedPlatformFocus(answer: answer, defaultFocus: defaultFocus)
        if focus == .both {
            formatterPrintBothFallbackWarning(for: fallbackPlatform)
            return fallbackPlatform == .ios ? .ios : .android
        }
        return focus
    }

    private func formatterPrintBothFallbackWarning(for platform: Platform) {
        let formatter = makeHumanFormatter(global: global)
        formatter.printWarning(
            "Generating a combined Shipfile is not supported for this project type yet; using \(platform.rawValue)."
        )
    }

    private func iosPrompt(_ prompt: String) -> String {
        "[iOS] \(prompt)"
    }

    private func androidPrompt(_ prompt: String) -> String {
        "[Android] \(prompt)"
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

    /// Presents a numbered list of options and returns the 0-based index of the user's choice.
    private func choose(_ prompt: String, options: [String], defaultIndex: Int) -> Int {
        guard isInteractiveTerminal else {
            print("\n\(prompt)")
            for (index, option) in options.enumerated() {
                let marker = index == defaultIndex ? "*" : " "
                print("  \(marker) \(index + 1). \(option)")
            }
            let answer = ask("Choice", defaultValue: "\(defaultIndex + 1)")
            if let choice = Int(answer), choice >= 1, choice <= options.count {
                return choice - 1
            }
            return defaultIndex
        }

        #if canImport(Darwin)
        return interactiveChoose(prompt, options: options, defaultIndex: defaultIndex)
        #else
        print("\n\(prompt)")
        for (index, option) in options.enumerated() {
            let marker = index == defaultIndex ? "*" : " "
            print("  \(marker) \(index + 1). \(option)")
        }
        let answer = ask("Choice", defaultValue: "\(defaultIndex + 1)")
        if let choice = Int(answer), choice >= 1, choice <= options.count {
            return choice - 1
        }
        return defaultIndex
        #endif
    }

    #if canImport(Darwin)
    private func interactiveChoose(_ prompt: String, options: [String], defaultIndex: Int) -> Int {
        var selectedIndex = min(max(defaultIndex, 0), max(options.count - 1, 0))
        var old = termios()
        tcgetattr(STDIN_FILENO, &old)
        var raw = old
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &old)
            print("")
        }

        renderInteractiveChoices(prompt: prompt, options: options, selectedIndex: selectedIndex)

        while true {
            var input = [UInt8](repeating: 0, count: 3)
            let count = read(STDIN_FILENO, &input, input.count)
            guard count > 0 else { continue }

            switch input[0] {
            case 13, 10:
                clearInteractiveChoices(prompt: prompt, optionsCount: options.count)
                renderSelectedChoice(prompt: prompt, option: options[selectedIndex])
                return selectedIndex
            case 65, 107:
                selectedIndex = max(selectedIndex - 1, 0)
            case 66, 106:
                selectedIndex = min(selectedIndex + 1, options.count - 1)
            case 27:
                if count >= 3, input[1] == 91 {
                    if input[2] == 65 {
                        selectedIndex = max(selectedIndex - 1, 0)
                    } else if input[2] == 66 {
                        selectedIndex = min(selectedIndex + 1, options.count - 1)
                    }
                }
            default:
                if let digit = Int(String(UnicodeScalar(input[0]))), digit >= 1, digit <= options.count {
                    selectedIndex = digit - 1
                }
            }

            clearInteractiveChoices(prompt: prompt, optionsCount: options.count)
            renderInteractiveChoices(prompt: prompt, options: options, selectedIndex: selectedIndex)
        }
    }

    private func renderInteractiveChoices(prompt: String, options: [String], selectedIndex: Int) {
        print("\n\(prompt)")
        for (index, option) in options.enumerated() {
            let prefix = index == selectedIndex ? ">" : " "
            print("  \(prefix) \(index + 1). \(option)")
        }
        print("  Use arrow keys, j/k, or 1-\(options.count). Press Enter to confirm.")
    }

    private func clearInteractiveChoices(prompt: String, optionsCount: Int) {
        let totalLines = optionsCount + 3
        for _ in 0..<totalLines {
            print("\u{001B}[1A\u{001B}[2K\r", terminator: "")
        }
    }

    private func renderSelectedChoice(prompt: String, option: String) {
        print(interactiveSelectedChoiceEcho(prompt: prompt, option: option))
    }
    #endif

    /// Writes a `.env` file in the project directory containing signing env vars.
    /// Also ensures `.env` is in `.gitignore`.
    ///
    /// When a value matches an existing environment variable, writes a `${VAR_NAME}`
    /// reference instead of the literal value. This avoids duplicating secrets and
    /// keeps `.env` portable across machines that already export the same vars.
    private func writeSigningEnvFile(
        _ vars: [String: String],
        specs: [EnvVarSpec],
        formatter: HumanFormatter
    ) {
        let envFilePath = (path as NSString).appendingPathComponent(".env")
        let processEnv = ProcessInfo.processInfo.environment
        var lines: [String] = ["# ShipIt Android signing configuration", "# Generated by `shipit generate`", ""]
        for spec in specs {
            guard let value = vars[spec.name] else { continue }
            lines.append("# \(spec.description)")
            // If the value came from an existing env var (same value currently exported),
            // reference the env var instead of inlining the secret.
            if let envValue = processEnv[spec.name], envValue == value {
                lines.append("\(spec.name)=\"${\(spec.name)}\"")
            } else {
                lines.append("\(spec.name)=\"\(value)\"")
            }
            lines.append("")
        }

        let newContent = lines.joined(separator: "\n")

        do {
            if FileManager.default.fileExists(atPath: envFilePath) {
                let existing = try String(contentsOfFile: envFilePath, encoding: .utf8)

                // Check which vars are already present
                let missingVars = specs.filter { vars[$0.name] != nil && !existing.contains($0.name) }
                let existingVars = specs.filter { vars[$0.name] != nil && existing.contains($0.name) }

                if missingVars.isEmpty && !existingVars.isEmpty {
                    // All vars already present — ask if user wants to overwrite their values
                    formatter.print("All signing vars already exist in .env:")
                    for spec in existingVars {
                        formatter.print("  \(spec.name)")
                    }
                    guard confirm("Overwrite existing values?", defaultAnswer: false) else {
                        formatter.print("Kept existing .env unchanged.")
                        return
                    }
                    // Overwrite: replace lines for existing keys
                    var updatedLines = existing.components(separatedBy: "\n")
                    for spec in existingVars {
                        guard let value = vars[spec.name] else { continue }
                        let writeValue: String
                        if let envValue = processEnv[spec.name], envValue == value {
                            writeValue = "${\(spec.name)}"
                        } else {
                            writeValue = value
                        }
                        if let idx = updatedLines.firstIndex(where: { $0.hasPrefix("\(spec.name)=") }) {
                            updatedLines[idx] = "\(spec.name)=\"\(writeValue)\""
                        }
                    }
                    try updatedLines.joined(separator: "\n")
                        .write(toFile: envFilePath, atomically: true, encoding: .utf8)
                    formatter.printSuccess("Updated signing vars in \(envFilePath)")
                } else if !missingVars.isEmpty {
                    // Some vars missing — offer append or overwrite
                    let choice = choose(
                        ".env already exists. How should signing vars be added?",
                        options: [
                            "Append only missing vars (keep existing values intact)",
                            "Overwrite entire signing block (replace all signing vars)",
                            "Skip — don't modify .env",
                        ],
                        defaultIndex: 0
                    )
                    switch choice {
                    case 0:
                        var toAppend = "\n"
                        for spec in missingVars {
                            guard let value = vars[spec.name] else { continue }
                            let writeValue: String
                            if let envValue = processEnv[spec.name], envValue == value {
                                writeValue = "${\(spec.name)}"
                            } else {
                                writeValue = value
                            }
                            toAppend += "# \(spec.description)\n\(spec.name)=\"\(writeValue)\"\n\n"
                        }
                        try (existing + toAppend)
                            .write(toFile: envFilePath, atomically: true, encoding: .utf8)
                        formatter.printSuccess(
                            "Appended \(missingVars.count) missing var(s) to \(envFilePath)")
                    case 1:
                        // Replace all signing vars with new values
                        var updatedLines = existing.components(separatedBy: "\n")
                        // Remove existing signing lines
                        for spec in specs where vars[spec.name] != nil {
                            updatedLines.removeAll { $0.hasPrefix("\(spec.name)=") }
                            updatedLines.removeAll { $0 == "# \(spec.description)" }
                        }
                        // Remove trailing empty lines from cleanup
                        while updatedLines.last?.isEmpty == true { updatedLines.removeLast() }
                        let base = updatedLines.joined(separator: "\n")
                        try (base + "\n\n" + newContent)
                            .write(toFile: envFilePath, atomically: true, encoding: .utf8)
                        formatter.printSuccess("Replaced signing vars in \(envFilePath)")
                    default:
                        formatter.print("Skipped — .env not modified.")
                        return
                    }
                }
            } else {
                try newContent.write(toFile: envFilePath, atomically: true, encoding: .utf8)
                formatter.printSuccess("Created \(envFilePath)")
            }

            // Ensure .env is in .gitignore
            ensureGitignoreContains(".env", projectPath: path, formatter: formatter)

            formatter.print("  ShipIt will auto-load .env before running actions.")
        } catch {
            formatter.printWarning("Could not write .env file: \(error.localizedDescription)")
            formatter.print("  You'll need to export these env vars manually.")
        }
    }

    /// Appends signing env vars to the user's shell profile.
    private func appendSigningToShellProfile(
        _ vars: [String: String],
        specs: [EnvVarSpec],
        formatter: HumanFormatter
    ) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let zshrc = (homeDir as NSString).appendingPathComponent(".zshrc")
        let bashrc = (homeDir as NSString).appendingPathComponent(".bashrc")

        // Detect which shell profile to use
        let profilePath: String
        if FileManager.default.fileExists(atPath: zshrc) {
            profilePath = zshrc
        } else if FileManager.default.fileExists(atPath: bashrc) {
            profilePath = bashrc
        } else {
            profilePath = zshrc  // default to .zshrc on macOS
        }

        let shortPath = profilePath.replacingOccurrences(of: homeDir, with: "~")
        guard confirm("Append signing exports to \(shortPath)?", defaultAnswer: true) else {
            formatter.print("Skipped. Set these manually before running shipit.")
            return
        }

        var exportLines = ["\n# ShipIt Android signing (added by `shipit generate`)"]
        for spec in specs {
            guard let value = vars[spec.name] else { continue }
            exportLines.append("export \(spec.name)=\"\(value)\"")
        }
        exportLines.append("")

        let block = exportLines.joined(separator: "\n")

        do {
            let existing = (try? String(contentsOfFile: profilePath, encoding: .utf8)) ?? ""
            // Don't duplicate if already present
            if existing.contains("SHIPIT_ANDROID__KEYSTORE_PATH") {
                formatter.print("Signing exports already present in \(shortPath).")
                guard confirm("Overwrite existing signing exports?", defaultAnswer: false) else {
                    formatter.print("Kept \(shortPath) unchanged.")
                    return
                }
                // Remove old block and re-append
                var lines = existing.components(separatedBy: "\n")
                lines.removeAll { line in
                    specs.contains { line.contains($0.name) }
                        || line.contains("# ShipIt Android signing")
                }
                while lines.last?.isEmpty == true { lines.removeLast() }
                try (lines.joined(separator: "\n") + block)
                    .write(toFile: profilePath, atomically: true, encoding: .utf8)
                formatter.printSuccess("Updated signing exports in \(shortPath)")
                formatter.print("  Run `source \(shortPath)` or open a new terminal to activate.")
            } else {
                try (existing + block).write(toFile: profilePath, atomically: true, encoding: .utf8)
                formatter.printSuccess("Added signing exports to \(shortPath)")
                formatter.print("  Run `source \(shortPath)` or open a new terminal to activate.")
            }
        } catch {
            formatter.printWarning("Could not write to \(shortPath): \(error.localizedDescription)")
            formatter.print("  Add these manually:")
            for line in exportLines where line.hasPrefix("export") {
                formatter.print("  \(line)")
            }
        }
    }

    /// Ensures a given entry exists in the project's .gitignore.
    private func ensureGitignoreContains(_ entry: String, projectPath: String, formatter: HumanFormatter) {
        let gitignorePath = (projectPath as NSString).appendingPathComponent(".gitignore")
        do {
            var content = (try? String(contentsOfFile: gitignorePath, encoding: .utf8)) ?? ""
            let lines = content.components(separatedBy: "\n")
            if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == entry }) {
                if !content.isEmpty && !content.hasSuffix("\n") {
                    content += "\n"
                }
                content += "\(entry)\n"
                try content.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
                formatter.print("  Added '\(entry)' to .gitignore")
            }
        } catch {
            formatter.printWarning("Could not update .gitignore: \(error.localizedDescription)")
            formatter.print("  Make sure '\(entry)' is in your .gitignore to avoid committing secrets.")
        }
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

/// Switches the generated release workflow's version step to read the bump component from
/// the `RELEASE_BUMP` env var (CI-driven) instead of the default `patch`. No-op when
/// `enabled` is false or the scaffold line is absent.
func releaseBumpFromCI(yaml: String, enabled: Bool) -> String {
    guard enabled else { return yaml }
    return yaml.replacingOccurrences(
        of: "bump: patch }   # or: { bump: ${RELEASE_BUMP} }",
        with: "bump: ${RELEASE_BUMP} }   # major|minor|patch|build, set at CI dispatch")
}

func resolvedPlatformFocus(
    answer: String,
    defaultFocus: GenerateCommand.PlatformFocus
) -> GenerateCommand.PlatformFocus {
    GenerateCommand.PlatformFocus(rawValue: answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        ?? defaultFocus
}

func interactiveSelectedChoiceEcho(prompt: String, option: String) -> String {
    "\(prompt): \(option)"
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
