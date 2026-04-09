import Foundation

public struct ShipfileSuggester: Sendable {
    public init() {}

    public func suggest(goal: SuggestionGoal, from inspection: ProjectInspection) -> SuggestedShipfile {
        let app = inspection.suggestedAppConfig
        var missingValues: [SuggestedShipfile.MissingValue] = []
        var warnings = inspection.warnings

        if app.scheme == nil {
            missingValues.append(.init(keyPath: "app.scheme", reason: "No shared runnable scheme was detected."))
        }
        if app.bundleID == nil {
            missingValues.append(.init(keyPath: "app.bundle_id", reason: "Bundle identifier could not be inferred from Xcode build settings.", envVar: "SHIPIT_APP__BUNDLE_ID"))
        }
        if app.teamID == nil {
            missingValues.append(.init(keyPath: "app.team_id", reason: "Development team could not be inferred from Xcode build settings.", envVar: "SHIPIT_APP__TEAM_ID"))
        }

        if goal == .beta || goal == .release {
            missingValues.append(.init(keyPath: "app_store_connect.key_id", reason: "App Store Connect automation needs an API key.", envVar: "ASC_KEY_ID"))
            missingValues.append(.init(keyPath: "app_store_connect.issuer_id", reason: "App Store Connect automation needs an issuer ID.", envVar: "ASC_ISSUER_ID"))
            missingValues.append(.init(keyPath: "app_store_connect.private_key or app_store_connect.key_path", reason: "Provide exactly one private key source for App Store Connect.", envVar: "ASC_PRIVATE_KEY or ASC_PRIVATE_KEY_PATH"))
        }

        if !inspection.existingShipfiles.isEmpty {
            warnings.append("Existing Shipfile-like configs were found: \(inspection.existingShipfiles.joined(separator: ", ")).")
        }
        if !inspection.fastlaneFiles.isEmpty {
            warnings.append("Fastlane files were detected. Review migrated lanes before replacing them with generated workflows.")
        }

        let yaml = renderYAML(goal: goal, app: app)
        return SuggestedShipfile(goal: goal, inspection: inspection, missingValues: missingValues, warnings: warnings, yaml: yaml)
    }

    private func renderYAML(goal: SuggestionGoal, app: ProjectInspection.SuggestedAppConfig) -> String {
        let scheme = app.scheme ?? "MyApp"
        let archivePath = "./build/\(scheme).xcarchive"

        var lines: [String] = [
            "# Shipfile.yml — suggested by `shipit suggest-config`",
            "# Review detected values before committing this file.",
            "",
            "app:",
        ]

        if let workspace = app.workspace {
            lines.append("  workspace: \(workspace)")
        } else if let project = app.project {
            lines.append("  project: \(project)")
        } else {
            lines.append("  # workspace: MyApp.xcworkspace")
        }

        if let scheme = app.scheme {
            lines.append("  scheme: \(scheme)")
        } else {
            lines.append("  # scheme: MyApp")
        }

        if let bundleID = app.bundleID {
            lines.append("  bundle_id: \(bundleID)")
        } else {
            lines.append("  # bundle_id: com.example.myapp")
        }

        if let teamID = app.teamID {
            lines.append("  team_id: \(teamID)")
        } else {
            lines.append("  # team_id: ABCDE12345")
        }

        if goal == .beta || goal == .release {
            lines.append(contentsOf: [
                "",
                "app_store_connect:",
                "  key_id: ${ASC_KEY_ID}",
                "  issuer_id: ${ASC_ISSUER_ID}",
                "  # key_path: ./.secrets/AuthKey_XXXXXXXXXX.p8",
            ])
        }

        lines.append(contentsOf: [
            "",
            "code_signing:",
            "  type: automatic",
            "",
            "build:",
            "  configuration: Release",
            "  derived_data_path: ./DerivedData",
            "",
            "archive:",
            "  export_method: app-store",
            "  include_symbols: true",
            "  output_path: \(archivePath)",
            "",
            "export:",
            "  archive_path: \(archivePath)",
            "  output_directory: ./build/export",
        ])

        if goal == .beta || goal == .release {
            lines.append(contentsOf: [
                "",
                "testflight:",
                "  skip_waiting_for_build_processing: false",
                goal == .beta ? "  distribute_external: true" : "  distribute_external: false",
                "  groups:",
                "    - Internal QA",
                "  changelog: \"Bug fixes and improvements\"",
            ])
        }

        if goal == .release {
            lines.append(contentsOf: [
                "",
                "metadata:",
                "  directory: ./metadata",
                "  submit_for_review: true",
                "  automatic_release: false",
                "  phased_release: true",
            ])
        }

        lines.append(contentsOf: [
            "",
            "versioning:",
            "  strategy: sequential",
            "  source: xcodeproj",
            "",
            "workflows:",
        ])

        switch goal {
        case .local:
            lines.append(contentsOf: [
                "  local:",
                "    - action: build",
                "    - action: test",
                "    - action: archive",
                "    - action: export",
            ])
        case .beta:
            lines.append(contentsOf: [
                "  beta:",
                "    - action: version",
                "      options: { bump: build }",
                "    - action: archive",
                "    - action: export",
                "    - action: testflight",
                "      options:",
                "        groups: [\"Internal QA\"]",
            ])
        case .release:
            lines.append(contentsOf: [
                "  release:",
                "    - action: version",
                "      options: { bump: build }",
                "    - action: archive",
                "    - action: export",
                "    - action: precheck",
                "      options: { directory: ./metadata }",
                "    - action: metadata",
                "      options: { push: true }",
                "    - action: upload",
                "      options: { submit_for_review: true, phased_release: true }",
            ])
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
