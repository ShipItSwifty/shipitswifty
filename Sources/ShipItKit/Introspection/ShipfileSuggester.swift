import Foundation

public struct ShipfileSuggester: Sendable {
    public init() {}

    public func suggest(goal: SuggestionGoal, from inspection: ProjectInspection) -> SuggestedShipfile {
        suggest(goal: goal, platform: inspection.detectedPlatform, from: inspection)
    }

    public func suggest(
        goal: SuggestionGoal, platform: Platform, from inspection: ProjectInspection
    )
        -> SuggestedShipfile
    {
        switch platform {
        case .ios:
            switch inspection.detectedBuildSystem {
            case .flutter:
                return suggestFlutter(goal: goal, from: inspection)
            case .reactNative:
                return suggestReactNative(goal: goal, platform: .ios, from: inspection)
            default:
                return suggestIOS(goal: goal, from: inspection)
            }
        case .android:
            switch inspection.detectedBuildSystem {
            case .flutter:
                return suggestFlutter(goal: goal, from: inspection)
            case .reactNative:
                return suggestReactNative(goal: goal, platform: .android, from: inspection)
            default:
                return suggestAndroid(goal: goal, from: inspection)
            }
        }
    }

    private func suggestIOS(
        goal: SuggestionGoal, from inspection: ProjectInspection
    )
        -> SuggestedShipfile
    {
        let app = inspection.suggestedAppConfig
        var missingValues: [SuggestedShipfile.MissingValue] = []
        var warnings = inspection.warnings

        if app.workspace == nil, app.project == nil {
            missingValues.append(
                .init(
                    keyPath: "app.workspace or app.project",
                    reason:
                        "No Xcode workspace or project was detected. Provide one if xcodebuild cannot resolve the app from the working directory.",
                    envVar: "SHIPIT_APP__WORKSPACE or SHIPIT_APP__PROJECT"))
        }
        if app.scheme == nil {
            missingValues.append(
                .init(
                    keyPath: "app.scheme", reason: "No shared runnable scheme was detected.",
                    envVar: "SHIPIT_APP__SCHEME"))
        }
        if app.bundleID == nil {
            missingValues.append(
                .init(
                    keyPath: "app.bundle_id",
                    reason: "Bundle identifier could not be inferred from Xcode build settings.",
                    envVar: "SHIPIT_APP__BUNDLE_ID"))
        }
        if app.teamID == nil {
            missingValues.append(
                .init(
                    keyPath: "app.team_id",
                    reason: "Development team could not be inferred from Xcode build settings.",
                    envVar: "SHIPIT_APP__TEAM_ID"))
        }

        // ASC credentials are only required for release, or for beta when a testflight/upload
        // step is present. The beta template generates a local-only workflow by default so
        // the user is not blocked before they confirm they want to upload.
        if goal == .release {
            missingValues.append(
                .init(
                    keyPath: "app_store_connect.key_id",
                    reason: "App Store Connect automation needs an API key.", envVar: "ASC_KEY_ID"))
            missingValues.append(
                .init(
                    keyPath: "app_store_connect.issuer_id",
                    reason: "App Store Connect automation needs an issuer ID.", envVar: "ASC_ISSUER_ID"))
            missingValues.append(
                .init(
                    keyPath: "app_store_connect.private_key or app_store_connect.key_path",
                    reason: "Provide exactly one private key source for App Store Connect.",
                    envVar: "ASC_PRIVATE_KEY or ASC_PRIVATE_KEY_PATH"))
        }

        // For the local goal, the test step is included but destinations are required.
        // Surface this as a missing value so the user knows they must fill it in before
        // running the workflow.
        if goal == .local {
            missingValues.append(
                .init(
                    keyPath: "workflows.local[test].options.destinations",
                    reason:
                        "Test destinations must be set to the simulators or devices available on your machine. Run `xcodebuild -showdestinations -scheme <scheme>` or `shipit ai-session --goal local` to discover valid values. Remove the test step to skip testing.",
                    envVar: nil
                ))
        }

        if !inspection.existingShipfiles.isEmpty {
            warnings.append(
                "Existing Shipfile-like configs were found: \(inspection.existingShipfiles.joined(separator: ", "))."
            )
        }
        if !inspection.fastlaneFiles.isEmpty {
            warnings.append(
                "Fastlane files were detected. Review migrated lanes before replacing them with generated workflows."
            )
        }

        let yaml = renderIOSYAML(goal: goal, app: app)
        return SuggestedShipfile(
            goal: goal, inspection: inspection, missingValues: missingValues, warnings: warnings,
            yaml: yaml)
    }

    private func suggestAndroid(
        goal: SuggestionGoal, from inspection: ProjectInspection
    )
        -> SuggestedShipfile
    {
        var missingValues: [SuggestedShipfile.MissingValue] = []
        var warnings = inspection.warnings

        if inspection.gradleFiles.isEmpty {
            missingValues.append(
                .init(
                    keyPath: "android.gradlew_path",
                    reason: "No Gradle wrapper or Gradle build files were detected.",
                    envVar: "SHIPIT_ANDROID__GRADLEW_PATH"
                ))
        }

        missingValues.append(
            .init(
                keyPath: "android.package_name",
                reason: "Android package name cannot be inferred reliably yet.",
                envVar: "SHIPIT_ANDROID__PACKAGE_NAME"
            ))

        if goal == .beta || goal == .release {
            missingValues.append(
                .init(
                    keyPath: "android.keystore_path",
                    reason: "Signed release artifacts need a keystore path.",
                    envVar: "SHIPIT_ANDROID__KEYSTORE_PATH"
                ))
            missingValues.append(
                .init(
                    keyPath: "android.keystore_alias",
                    reason: "Signed release artifacts need a key alias.",
                    envVar: "SHIPIT_ANDROID__KEY_ALIAS"
                ))
            missingValues.append(
                .init(
                    keyPath: "android.keystore_password",
                    reason: "Keystore password should be supplied from the environment.",
                    envVar: "SHIPIT_ANDROID__KEYSTORE_PASSWORD"
                ))
            missingValues.append(
                .init(
                    keyPath: "android.key_password",
                    reason: "Signing key password should be supplied from the environment.",
                    envVar: "SHIPIT_ANDROID__KEY_PASSWORD"
                ))
        }

        if goal == .release {
            missingValues.append(
                .init(
                    keyPath: "environment.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
                    reason: "Google Play upload needs a service account JSON source.",
                    envVar: "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH"
                ))
        }

        if !inspection.existingShipfiles.isEmpty {
            warnings.append(
                "Existing Shipfile-like configs were found: \(inspection.existingShipfiles.joined(separator: ", "))."
            )
        }

        let yaml = renderAndroidYAML(goal: goal)
        return SuggestedShipfile(
            goal: goal, inspection: inspection, missingValues: missingValues, warnings: warnings,
            yaml: yaml)
    }

    private func suggestFlutter(
        goal: SuggestionGoal, from inspection: ProjectInspection
    ) -> SuggestedShipfile {
        let missingValues: [SuggestedShipfile.MissingValue] = []
        var warnings = inspection.warnings

        if goal == .beta || goal == .release {
            warnings.append(
                "Flutter iOS distribution requires a valid Apple Developer account and code signing configuration."
            )
        }

        let yaml = renderFlutterYAML(goal: goal)
        return SuggestedShipfile(
            goal: goal, inspection: inspection, missingValues: missingValues, warnings: warnings,
            yaml: yaml)
    }

    private func suggestReactNative(
        goal: SuggestionGoal, platform: Platform, from inspection: ProjectInspection
    ) -> SuggestedShipfile {
        var missingValues: [SuggestedShipfile.MissingValue] = []
        let warnings = inspection.warnings

        if platform == .ios, goal == .beta || goal == .release {
            missingValues.append(
                .init(
                    keyPath: "app.scheme",
                    reason: "React Native iOS archive requires an Xcode scheme for the generated project.",
                    envVar: "SHIPIT_APP__SCHEME"
                ))
        }
        if platform == .android, goal == .beta || goal == .release {
            missingValues.append(
                .init(
                    keyPath: "android.keystore_path",
                    reason: "Signed release artifacts need a keystore path.",
                    envVar: "SHIPIT_ANDROID__KEYSTORE_PATH"
                ))
        }

        let yaml = renderReactNativeYAML(goal: goal, platform: platform)
        return SuggestedShipfile(
            goal: goal, inspection: inspection, missingValues: missingValues, warnings: warnings,
            yaml: yaml)
    }

    private func renderFlutterYAML(goal: SuggestionGoal) -> String {
        var lines: [String] = [
            "# Shipfile.yml — generated by `shipit generate`",
            "# Flutter project detected. Review before committing.",
            "",
            "ios:",
            "  build_system: flutter",
            "android:",
            "  build_system: flutter",
            "",
            "workflows:",
        ]

        switch goal {
        case .local:
            lines.append(contentsOf: [
                "  local:",
                "    - action: lint",
                "    - action: test",
                "      # Optional: retry whole test runs for transient simulator/tool failures.",
                "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                "    - action: build",
            ])
        case .beta:
            lines.append(contentsOf: [
                "  beta-ios:",
                "    - action: test",
                "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                "    - action: archive",
                "      options: { platform: ios }",
                "    # Flutter iOS: archive produces build/ios/ipa/*.ipa directly (no export step needed).",
                "    # Uncomment testflight when App Store Connect credentials are configured:",
                "    # - action: testflight",
                "  beta-android:",
                "    - action: test",
                "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                "    - action: archive",
                "      options: { platform: android }",
                "    # - action: play-store",
                "    #   options: { track: internal }",
            ])
        case .release:
            lines.append(contentsOf: [
                "  release-ios:",
                "    - action: test",
                "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                "    - action: archive",
                "      options: { platform: ios }",
                "    - action: testflight",
                "  release-android:",
                "    - action: test",
                "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                "    - action: archive",
                "      options: { platform: android }",
                "    - action: play-store",
                "      options: { track: production }",
            ])
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func renderReactNativeYAML(goal: SuggestionGoal, platform: Platform) -> String {
        var lines: [String] = [
            "# Shipfile.yml — generated by `shipit generate`",
            "# React Native project detected. Review before committing.",
            "",
        ]

        if platform == .ios {
            lines.append(contentsOf: [
                "app:",
                "  scheme: ${SHIPIT_APP__SCHEME}",
                "  bundle_id: ${SHIPIT_APP__BUNDLE_ID}",
                "  team_id: ${SHIPIT_APP__TEAM_ID}",
                "",
                "ios:",
                "  build_system: react_native",
                "",
            ])
        } else {
            lines.append(contentsOf: [
                "android:",
                "  build_system: react_native",
                "  package_name: ${SHIPIT_ANDROID__PACKAGE_NAME}",
                "",
            ])
        }

        lines.append("workflows:")

        if platform == .ios {
            switch goal {
            case .local:
                lines.append(contentsOf: [
                    "  local:",
                    "    - action: lint",
                    "    - action: test",
                    "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                    "    - action: build",
                ])
            case .beta:
                lines.append(contentsOf: [
                    "  beta:",
                    "    - action: lint",
                    "    - action: test",
                    "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                    "    # RN iOS: build validates the bundle, archive+export produces the IPA.",
                    "    - action: archive",
                    "    - action: export",
                    "    # - action: testflight",
                ])
            case .release:
                lines.append(contentsOf: [
                    "  release:",
                    "    - action: lint",
                    "    - action: test",
                    "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                    "    - action: archive",
                    "    - action: export",
                    "    - action: testflight",
                ])
            }
        } else {
            switch goal {
            case .local:
                lines.append(contentsOf: [
                    "  local:",
                    "    - action: lint",
                    "    - action: test",
                    "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                    "    - action: build",
                ])
            case .beta:
                lines.append(contentsOf: [
                    "  beta:",
                    "    - action: lint",
                    "    - action: test",
                    "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                    "    - action: archive",
                    "    # - action: play-store",
                    "    #   options: { track: internal }",
                ])
            case .release:
                lines.append(contentsOf: [
                    "  release:",
                    "    - action: lint",
                    "    - action: test",
                    "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                    "    - action: archive",
                    "    - action: play-store",
                    "      options: { track: production }",
                ])
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func renderIOSYAML(
        goal: SuggestionGoal, app: ProjectInspection.SuggestedAppConfig
    )
        -> String
    {
        let scheme = app.scheme ?? "MyApp"
        let archivePath = "./build/\(scheme).xcarchive"

        var lines: [String] = [
            "# Shipfile.yml — generated by `shipit generate`",
            "# Review detected values before committing this file.",
            "platform: ios",
            "",
            "app:",
        ]

        if let workspace = app.workspace {
            lines.append("  workspace: \(workspace)")
        } else if let project = app.project {
            lines.append("  project: \(project)")
        } else {
            lines.append("  # workspace: MyApp.xcworkspace")
            lines.append("  # project: MyApp.xcodeproj")
        }

        if let scheme = app.scheme {
            lines.append("  scheme: \(scheme)")
        } else {
            lines.append("  scheme: ${SHIPIT_APP__SCHEME}")
        }

        if let bundleID = app.bundleID {
            lines.append("  bundle_id: \(bundleID)")
        } else {
            lines.append("  bundle_id: ${SHIPIT_APP__BUNDLE_ID}")
        }

        if let teamID = app.teamID {
            lines.append("  team_id: \(teamID)")
        } else {
            lines.append("  team_id: ${SHIPIT_APP__TEAM_ID}")
        }

        if goal == .beta {
            lines.append(contentsOf: [
                "",
                "# App Store Connect credentials are only needed when you want to upload to TestFlight.",
                "# Uncomment this section and add a `testflight` step to the beta workflow when ready.",
                "# app_store_connect:",
                "#   key_id: ${ASC_KEY_ID}",
                "#   issuer_id: ${ASC_ISSUER_ID}",
                "#   key_path: ${ASC_PRIVATE_KEY_PATH}",
            ])
        } else if goal == .release {
            lines.append(contentsOf: [
                "",
                "app_store_connect:",
                "  key_id: ${ASC_KEY_ID}",
                "  issuer_id: ${ASC_ISSUER_ID}",
                "  key_path: ${ASC_PRIVATE_KEY_PATH}",
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
                "    # Test step: set destinations to the simulators/devices you want to run on.",
                "    # Run `xcodebuild -showdestinations -scheme <scheme>` to list valid values,",
                "    # or use `shipit ai-session --goal local` which discovers them automatically.",
                "    # Remove this step (or leave destinations empty) to skip tests.",
                "    - action: test",
                "      options:",
                "        destinations:",
                "          # - \"platform=iOS Simulator,name=<SimulatorName>,OS=<Version>\"",
                "        # infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }",
                "    - action: archive",
                "    - action: export",
            ])
        case .beta:
            lines.append(contentsOf: [
                "  beta:",
                "    # 1. Bump CFBundleVersion (integer build number) only — marketing version unchanged.",
                "    - action: version",
                "      options: { bump: build }",
                "    - action: archive",
                "    # 2. Export .ipa locally. No App Store Connect credentials required.",
                "    - action: export",
                "    # To upload to TestFlight, uncomment the app_store_connect section above and add:",
                "    # - action: testflight",
                "    #   options:",
                "    #     groups: [\"Internal QA\"]",
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

    private func renderAndroidYAML(goal: SuggestionGoal) -> String {
        var lines: [String] = [
            "# Shipfile.yml — generated by `shipit generate`",
            "# Review detected values before committing this file.",
            "platform: android",
            "",
            "android:",
            "  module: ${SHIPIT_ANDROID__MODULE}",
            "  build_variant: release",
            "  build_type: aab",
            "  package_name: ${SHIPIT_ANDROID__PACKAGE_NAME}",
            "  gradlew_path: ./gradlew",
            "  keystore_path: ${SHIPIT_ANDROID__KEYSTORE_PATH}",
            "  keystore_alias: ${SHIPIT_ANDROID__KEY_ALIAS}",
            "  # Keep passwords in environment variables:",
            "  #   SHIPIT_ANDROID__KEYSTORE_PASSWORD",
            "  #   SHIPIT_ANDROID__KEY_PASSWORD",
            "  # Google Play credentials are only needed when uploading:",
            "  #   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH",
            "",
            "versioning:",
            "  strategy: sequential",
            "  source: gradle",
            "",
            "workflows:",
        ]

        switch goal {
        case .local:
            lines.append(contentsOf: [
                "  local:",
                "    - action: lint",
                "    - action: test",
                "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                "    - action: build",
            ])
        case .beta:
            lines.append(contentsOf: [
                "  beta:",
                "    # Bump versionCode only — versionName unchanged.",
                "    - action: version",
                "      options: { bump: build }",
                "    - action: lint",
                "    - action: test",
                "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                "    - action: archive",
                "    # Add this when you are ready to upload to Google Play:",
                "    # - action: play-store",
                "    #   options: { track: internal }",
            ])
        case .release:
            lines.append(contentsOf: [
                "  release:",
                "    - action: version",
                "      options: { bump: build }",
                "    - action: lint",
                "    - action: test",
                "      # options: { infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 } }",
                "    - action: archive",
                "    - action: play-store",
                "      options: { track: production }",
            ])
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
