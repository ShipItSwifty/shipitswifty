import ArgumentParser
import ShipItKit
import Foundation

/// Interactive project setup — generates a Shipfile.yml.
///
/// In interactive mode, detects the Xcode workspace/scheme, bundle ID, and team,
/// then writes a comprehensive starter Shipfile.yml.
///
/// In `--non-interactive` mode (intended for agents and CI), uses `ProjectInspector`
/// to detect all values and writes the file without any prompts. Pass `--goal` to
/// control which workflow template is generated.
///
/// ## Usage
/// ```
/// shipit init
/// shipit init --goal beta --non-interactive
/// shipit init --goal release --non-interactive --output json
/// ```
struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Interactive project setup — generates Shipfile.yml"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Xcode scheme name")
    var scheme: String?

    @Option(name: .long, help: "App bundle identifier")
    var bundleId: String?

    @Option(name: .long, help: "Apple Developer Team ID")
    var teamId: String?

    @Option(name: .long, help: "Goal to optimize for: local, beta, or release. Used in --non-interactive mode.")
    var goal: SuggestionGoal = .beta

    @Option(name: .long, help: "Root path to inspect. Used in --non-interactive mode.")
    var path: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Skip prompts and use provided/detected values. Integrates with ProjectInspector for accurate detection.")
    var nonInteractive: Bool = false

    func run() async throws {
        if nonInteractive {
            try await runNonInteractive()
        } else {
            try runInteractive()
        }
    }

    // MARK: - Non-interactive (agent/CI path)

    private func runNonInteractive() async throws {
        let inspection = try await ProjectInspector(rootPath: path).inspect()
        let suggestion = ShipfileSuggester().suggest(goal: goal, from: inspection)

        let outputPath = URL(fileURLWithPath: path)
            .appendingPathComponent("Shipfile.yml").path

        // CLI overrides take priority over detected values
        let yaml = applyOverrides(to: suggestion.yaml)

        try yaml.write(toFile: outputPath, atomically: true, encoding: .utf8)

        switch global.output {
        case .json:
            let reporter = JSONReporter()
            let payload: JSONValue = .object([
                "path": .string(outputPath),
                "goal": .string(goal.rawValue),
                "missing": .array(suggestion.missingValues.map { mv in
                    .object([
                        "keyPath": .string(mv.keyPath),
                        "reason": .string(mv.reason),
                        "envVar": mv.envVar.map(JSONValue.string) ?? .null,
                    ])
                }),
                "warnings": .array(suggestion.warnings.map(JSONValue.string)),
            ])
            let envelope = ActionResultEnvelope(action: "init", status: "success", payload: payload)
            print(try reporter.encode(envelope))
        case .human:
            let formatter = makeHumanFormatter(global: global)
            formatter.printSuccess("Created Shipfile.yml at \(outputPath)")
            if !suggestion.missingValues.isEmpty {
                formatter.printWarning("Unresolved fields — edit Shipfile.yml before running:")
                for mv in suggestion.missingValues {
                    let envHint = mv.envVar.map { " (or set \($0))" } ?? ""
                    formatter.print("  \(mv.keyPath): \(mv.reason)\(envHint)")
                }
            }
            printNextSteps(formatter: formatter)
        }
    }

    /// Apply CLI flag overrides to generated YAML by injecting them as comments/substitutions.
    /// This is a lightweight string pass; a full YAML round-trip is not needed here.
    private func applyOverrides(to yaml: String) -> String {
        var result = yaml
        if let scheme {
            // Replace env-placeholder or detected scheme with CLI-supplied value
            result = result.replacingOccurrences(of: "scheme: ${SHIPIT_APP__SCHEME}", with: "scheme: \(scheme)")
        }
        if let bundleId {
            result = result.replacingOccurrences(of: "bundle_id: ${SHIPIT_APP__BUNDLE_ID}", with: "bundle_id: \(bundleId)")
        }
        if let teamId {
            result = result.replacingOccurrences(of: "team_id: ${SHIPIT_APP__TEAM_ID}", with: "team_id: \(teamId)")
        }
        return result
    }

    // MARK: - Interactive path

    private func runInteractive() throws {
        let formatter = makeHumanFormatter(global: global)
        formatter.printHeader("ShipItSwifty Init")

        // Auto-detect Xcode workspace/project
        let detectedWorkspace = detectWorkspace()
        let detectedScheme = scheme ?? detectScheme()
        let resolvedBundleId = bundleId
        let resolvedTeamId = teamId ?? ""

        let shipfileContent = """
        # Shipfile.yml — ShipItSwifty configuration
        # Generated by `shipit init` on \(ISO8601DateFormatter().string(from: Date()))
        # All values can be overridden via CLI flags or environment variables.

        app:
          \(detectedWorkspace.map { "workspace: \($0)" } ?? "# workspace: MyApp.xcworkspace")
          scheme: \(detectedScheme ?? "MyApp")
          \(resolvedBundleId.map { "bundle_id: \($0)" } ?? "# bundle_id: com.example.myapp  # Optional; auto-detected from Xcode if omitted")
          \(resolvedTeamId.isEmpty ? "# team_id: ABCDE12345" : "team_id: \(resolvedTeamId)")

        app_store_connect:
          key_id: ${ASC_KEY_ID}
          issuer_id: ${ASC_ISSUER_ID}
          # key_path: ./.secrets/AuthKey.p8  # Local dev only; keep out of git

        code_signing:
          type: automatic
          # Use `vault` or `manual` if you want ShipIt-managed certificates/profiles.
          # storage: git
          # git_url: git@github.com:yourteam/certs.git
          # profile_type: appstore

        build:
          configuration: Release
          derived_data_path: ./DerivedData

        archive:
          export_method: app-store
          include_symbols: true
          output_path: ./build/\(detectedScheme ?? "MyApp").xcarchive

        export:
          output_directory: ./build/export

        testflight:
          skip_waiting_for_build_processing: false
          distribute_external: true
          changelog: "Bug fixes and improvements"

        metadata:
          directory: ./metadata
          submit_for_review: false
          automatic_release: false
          phased_release: true

        versioning:
          strategy: sequential
          source: xcodeproj

        notifications:
          slack:
            webhook_url: ${SLACK_WEBHOOK_URL}
            channel: "#releases"
            on_success: true
            on_failure: true

        # Named workflows for `shipit run <workflow>`
        workflows:
          # Local development: build, optionally test, archive, and export.
          # To run tests, fill in the destinations array below.
          # Run `xcodebuild -showdestinations -scheme <scheme>` to list valid values,
          # or use `shipit ai-session --goal local` which discovers them for you.
          local:
            - action: build
            - action: test
              options:
                destinations:
                  # - "platform=iOS Simulator,name=<SimulatorName>,OS=<Version>"
            - action: archive
            - action: export

          beta:
            - action: version
              options: { bump: build }
            - action: archive
              options: { configuration: Release, export_method: app-store }
            - action: export
              options: { output_directory: ./build/export }
            - action: testflight
              options: { groups: ["Internal QA"] }
            - action: notify
              options:
                slack:
                  message: "Beta uploaded!"

          release:
            - action: version
              options: { bump: build }
            - action: archive
              options: { configuration: Release, export_method: app-store }
            - action: export
              options: { output_directory: ./build/export }
            - action: metadata
              options: { push: true }
            - action: upload
              options: { submit_for_review: true, phased_release: true }
            - action: notify
              options:
                slack:
                  message: "App submitted for review!"
        """

        let outputPath = "./Shipfile.yml"

        if FileManager.default.fileExists(atPath: outputPath) {
            formatter.printWarning("Shipfile.yml already exists at \(outputPath). Use --non-interactive to overwrite without prompting.")
        }

        try shipfileContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
        formatter.printSuccess("Created Shipfile.yml at \(outputPath)")
        formatter.print("")
        printNextSteps(formatter: formatter)
    }

    private func printNextSteps(formatter: HumanFormatter) {
        formatter.print("")
        formatter.print("Next steps:")
        formatter.print("  1. Edit Shipfile.yml to fit your project settings")
        formatter.print("  2. Set up App Store Connect credentials:")
        formatter.print("     Required for ASC API actions: ASC_KEY_ID + ASC_ISSUER_ID + one private key source")
        formatter.print("     Skip this if you only use build/test/archive/export locally")
        formatter.print("     App Store Connect > Users and Access > Integrations > App Store Connect API")
        formatter.print("     export ASC_KEY_ID=your-key-id")
        formatter.print("     export ASC_ISSUER_ID=your-issuer-id")
        formatter.print("     export ASC_PRIVATE_KEY=$(cat ~/AuthKey_xxx.p8)  # or use ASC_PRIVATE_KEY_PATH")
        formatter.print("  3. Set up code signing:")
        formatter.print("     shipit sign init --git-url git@github.com:yourteam/certs.git")
        formatter.print("     shipit sign sync --type appstore")
        formatter.print("  4. Run your first workflow:")
        formatter.print("     shipit run beta")
    }

    // MARK: - Simple detection helpers (interactive path only)

    private func detectWorkspace() -> String? {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: ".")) ?? []
        return contents.first { $0.hasSuffix(".xcworkspace") }
    }

    private func detectScheme() -> String? {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: ".")) ?? []
        if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return (workspace as NSString).deletingPathExtension
        }
        if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return (project as NSString).deletingPathExtension
        }
        return nil
    }
}
