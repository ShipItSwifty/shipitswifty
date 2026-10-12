import Foundation
import SwiftyShell
import TestCommons
import Testing

@testable import ShipItKit

@Suite("Introspection")
struct IntrospectionTests {

    #if os(macOS)
    @Test("Built-in action schema includes workflow option metadata")
    func builtInActionSchemaIncludesOptions() {
        let uploadSchema = BuiltInSchemaCatalog.actionSchemas().first { $0.name == "upload" }

        #expect(uploadSchema != nil)
        #expect(uploadSchema?.options.contains(where: { $0.name == "ipa_path" }) == true)
        #expect(uploadSchema?.options.contains(where: { $0.name == "submit_for_review" }) == true)
    }

    @Test("validate bundle schema documents auto-discovery note")
    func validateBundleSchemaDocumentsAutoDiscovery() {
        let schema = BuiltInSchemaCatalog.actionSchemas().first { $0.name == "validate_bundle" }
        let aabField = schema?.options.first { $0.name == "aab_path" }

        #expect(aabField?.notes.contains(where: { $0.contains("Optional when using conventional native Gradle") }) == true)
    }

    @Test("test-results schema includes artifact paths")
    func testResultsSchemaIncludesArtifactPaths() {
        let schema = BuiltInSchemaCatalog.actionSchemas().first { $0.name == "test-results" }

        #expect(schema?.options.contains(where: { $0.name == "xcresult_path" }) == true)
        #expect(schema?.options.contains(where: { $0.name == "report_path" }) == true)
    }

    @Test("Project inspector prefers workspace and extracts schemes")
    func projectInspectorDetectsWorkspaceAndSchemes() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let tempDirectory = scratch.url

        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Example.xcworkspace"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Example.xcodeproj"),
            withIntermediateDirectories: true)

        let executor = MockExecutor { command, _ in
            if command.arguments.contains("-list") {
                return ShellOutput(
                    stdout:
                        "Information about workspace \"Example\":\n    Schemes:\n        Example\n        ExampleTests\n",
                    stderr: "",
                    exitCode: 0
                )
            }

            if command.arguments.contains("-showBuildSettings") {
                return ShellOutput(
                    stdout:
                        "    PRODUCT_BUNDLE_IDENTIFIER = com.example.app\n    DEVELOPMENT_TEAM = TEAM12345\n",
                    stderr: "",
                    exitCode: 0
                )
            }

            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let inspection = try await ProjectInspector(
            rootPath: tempDirectory.path,
            shell: ShellContext(executor: executor)
        ).inspect()

        #expect(inspection.preferredContainer?.kind == "workspace")
        #expect(inspection.suggestedAppConfig.workspace == "Example.xcworkspace")
        #expect(inspection.suggestedAppConfig.scheme == "Example")
        #expect(inspection.suggestedAppConfig.bundleID == "com.example.app")
        #expect(inspection.suggestedAppConfig.teamID == "TEAM12345")
    }
    #endif

    @Test("Shipfile suggester generates beta workflow")
    func shipfileSuggesterGeneratesBetaWorkflow() {
        let inspection = ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(
                    name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app",
                    teamID: "TEAM12345", likelyRunnable: true)
            ],
            suggestedAppConfig: .init(
                workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app",
                teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )

        let suggestion = ShipfileSuggester().suggest(goal: .beta, from: inspection)

        #expect(suggestion.yaml.contains("workflows:"))
        #expect(suggestion.yaml.contains("beta:"))
        #expect(suggestion.yaml.contains("# - action: testflight"))
        #expect(suggestion.yaml.contains("archive_path: ./build/App.xcarchive"))
        #expect(suggestion.yaml.contains("- action: test"))
        #expect(suggestion.yaml.contains("infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }"))
    }

    @Test("Shipfile suggester uses a detected single iOS test plan")
    func shipfileSuggesterUsesDetectedTestPlan() {
        let inspection = ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "project", path: "App.xcodeproj")],
            preferredContainer: .init(kind: "project", path: "App.xcodeproj"),
            schemes: [],
            testPlans: ["App.xcodeproj/xcshareddata/xctestplans/Regression.xctestplan"],
            suggestedAppConfig: .init(project: "App.xcodeproj", scheme: "App"),
            existingShipfiles: [], fastlaneFiles: [], ciFiles: [], warnings: []
        )

        let suggestion = ShipfileSuggester().suggest(goal: .beta, platform: .ios, from: inspection)

        #expect(suggestion.yaml.contains("test_plan: \"Regression\""))
        #expect(suggestion.yaml.contains("infrastructure_retry: { max_attempts: 3, initial_delay_seconds: 2, max_delay_seconds: 30 }"))
    }

    @Test("Project inspector discovers test plans inside Xcode project bundles")
    func projectInspectorDiscoversTestPlans() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let tempDirectory = scratch.url
        let planDirectory =
            tempDirectory
            .appendingPathComponent("App.xcodeproj/xcshareddata/xctestplans")
        try FileManager.default.createDirectory(at: planDirectory, withIntermediateDirectories: true)
        try "{}".write(to: planDirectory.appendingPathComponent("Regression.xctestplan"), atomically: true, encoding: .utf8)

        let inspection = try await ProjectInspector(rootPath: tempDirectory.path).inspect()

        #expect(inspection.testPlans == ["App.xcodeproj/xcshareddata/xctestplans/Regression.xctestplan"])
    }

    @Test("Shipfile suggester generates Android workflow")
    func shipfileSuggesterGeneratesAndroidWorkflow() {
        let inspection = ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [],
            preferredContainer: nil,
            schemes: [],
            suggestedAppConfig: .init(),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: [],
            suggestedAndroidPackageName: "com.example.app",
            detectedPlatform: .android,
            gradleFiles: ["gradlew", "build.gradle.kts"]
        )

        let suggestion = ShipfileSuggester().suggest(
            goal: .release, platform: .android, from: inspection)

        #expect(suggestion.yaml.contains("platform: android"))
        #expect(suggestion.yaml.contains("android:"))
        #expect(suggestion.yaml.contains("package_name: com.example.app"))
        #expect(suggestion.yaml.contains("- action: play-store"))
        #expect(!suggestion.missingValues.contains { $0.keyPath == "android.package_name" })
        // Release scaffold tags the bumped version with a conditional git tail.
        #expect(suggestion.yaml.contains("bump: patch"))
        #expect(suggestion.yaml.contains("operation: tag"))
        #expect(suggestion.yaml.contains("tag_name: \"v{{version}}\""))
        #expect(suggestion.yaml.contains("when: \"{{version_changed}}\""))
        #expect(suggestion.yaml.contains("operation: push"))
    }

    @Test("Shipfile suggester generates iOS release workflow with conditional tag tail")
    func shipfileSuggesterGeneratesIOSReleaseTagTail() {
        let inspection = ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(
                    name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app",
                    teamID: "TEAM12345", likelyRunnable: true)
            ],
            suggestedAppConfig: .init(
                workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app",
                teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )

        let suggestion = ShipfileSuggester().suggest(goal: .release, platform: .ios, from: inspection)

        #expect(suggestion.yaml.contains("bump: patch"))
        #expect(suggestion.yaml.contains("operation: tag"))
        #expect(suggestion.yaml.contains("tag_name: \"v{{version}}\""))
        #expect(suggestion.yaml.contains("when: \"{{version_changed}}\""))
        #expect(suggestion.yaml.contains("operation: push"))
    }

    @Test("Shipfile suggester generates single-platform React Native beta workflows")
    func shipfileSuggesterGeneratesSinglePlatformReactNativeBetaWorkflows() {
        let inspection = ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(
                    name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app",
                    teamID: "TEAM12345", likelyRunnable: true)
            ],
            suggestedAppConfig: .init(
                workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app",
                teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: [],
            suggestedAndroidPackageName: "com.example.app",
            detectedBuildSystem: .reactNative,
            buildSystemFiles: ["package.json"]
        )

        // Neither generated file may name a `platform` option on a step — it is not a valid
        // action option (platform is resolved once for the whole Shipfile), and doing so used
        // to produce a Shipfile that failed the tool's own `validate yml`.
        let iosSuggestion = ShipfileSuggester().suggest(goal: .beta, platform: .ios, from: inspection)
        #expect(iosSuggestion.yaml.contains("platform: ios"))
        #expect(iosSuggestion.yaml.contains("ios:\n  build_system: react_native"))
        #expect(iosSuggestion.yaml.contains("  beta:"))
        #expect(!iosSuggestion.yaml.contains("beta-ios"))
        #expect(!iosSuggestion.yaml.contains("options: { platform:"))
        #expect(iosSuggestion.yaml.contains("    # RN iOS: build validates the bundle; archive + export produces the IPA."))
        #expect(iosSuggestion.yaml.contains("    # - action: testflight"))
        #expect(iosSuggestion.missingValues.contains { $0.keyPath == "app.scheme" })

        let androidSuggestion = ShipfileSuggester().suggest(goal: .beta, platform: .android, from: inspection)
        #expect(androidSuggestion.yaml.contains("platform: android"))
        #expect(androidSuggestion.yaml.contains("android:\n  build_system: react_native"))
        #expect(androidSuggestion.yaml.contains("  package_name: com.example.app"))
        #expect(androidSuggestion.yaml.contains("  beta:"))
        #expect(!androidSuggestion.yaml.contains("beta-android"))
        #expect(!androidSuggestion.yaml.contains("options: { platform:"))
        #expect(androidSuggestion.yaml.contains("    # - action: play-store"))
        #expect(androidSuggestion.missingValues.contains { $0.keyPath == "android.keystore_path" })
    }

    @Test("Schema validator catches unknown fields")
    func schemaValidatorRejectsUnknownFields() {
        let issues = SchemaValidator.validate(
            value: .object([
                "app": .object([
                    "scheme": .string("App"),
                    "unknown_key": .string("value"),
                ])
            ]),
            against: BuiltInSchemaCatalog.shipfileFields()
        )

        #expect(issues.contains { $0.path == "$.app.unknown_key" && $0.severity == .error })
    }

    #if os(macOS)
    @Test("Shipfile validator flags TestFlight workflow without export context")
    func shipfileValidatorFlagsMissingIPAContext() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let tempDirectory = scratch.url

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          project: Example.xcodeproj
          scheme: Example
          bundle_id: com.example.app
        workflows:
          beta:
            - action: testflight
              options:
                groups: [\"Internal QA\"]
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let report = await ShipfileValidator().validate(
            shipfilePath: shipfileURL.path,
            actionDescriptors: [
                TestFlightAction.descriptor(
                    for: TestFlightAction(),
                    optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestFlightAction.name),
                    validationRules: TestFlightAction.validationRules
                )
            ]
        )

        #expect(report.isValid == false)
        #expect(report.issues.contains { $0.path.contains("$.workflows.beta[0].options.ipa") })
    }

    @Test("Shipfile validator can validate generated YAML directly")
    func shipfileValidatorValidatesGeneratedYAML() async throws {
        let inspection = ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(
                    name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app",
                    teamID: "TEAM12345", likelyRunnable: true)
            ],
            suggestedAppConfig: .init(
                workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app",
                teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )

        let suggestion = ShipfileSuggester().suggest(goal: .beta, from: inspection)
        let report = await ShipfileValidator().validate(
            shipfileContents: suggestion.yaml,
            shipfilePath: "<suggested>",
            actionDescriptors: [
                VersionAction.descriptor(
                    for: VersionAction(),
                    optionSchema: BuiltInSchemaCatalog.optionSchema(for: VersionAction.name)),
                ArchiveAction.descriptor(
                    for: ArchiveAction(),
                    optionSchema: BuiltInSchemaCatalog.optionSchema(for: ArchiveAction.name)),
                TestAction.descriptor(
                    for: TestAction(),
                    optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestAction.name)),
                ExportAction.descriptor(
                    for: ExportAction(),
                    optionSchema: BuiltInSchemaCatalog.optionSchema(for: ExportAction.name)),
                TestFlightAction.descriptor(
                    for: TestFlightAction(),
                    optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestFlightAction.name)),
            ]
        )

        #expect(report.shipfilePath == "<suggested>")
        #expect(report.isValid)
    }
    #endif

    @Test("Shipfile suggester uses env placeholders when app detection is missing")
    func shipfileSuggesterUsesEnvPlaceholdersForMissingDetection() {
        let inspection = ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [],
            preferredContainer: nil,
            schemes: [],
            suggestedAppConfig: .init(),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )

        let suggestion = ShipfileSuggester().suggest(goal: .beta, from: inspection)

        #expect(suggestion.yaml.contains("scheme: ${SHIPIT_APP__SCHEME}"))
        #expect(suggestion.yaml.contains("bundle_id: ${SHIPIT_APP__BUNDLE_ID}"))
        #expect(suggestion.yaml.contains("team_id: ${SHIPIT_APP__TEAM_ID}"))
        #expect(suggestion.yaml.contains("key_path: ${ASC_PRIVATE_KEY_PATH}"))
    }

    #if os(macOS)
    @Test("Project inspector infers Android package name from Gradle applicationId")
    func projectInspectorInfersAndroidPackageNameFromGradle() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let tempDirectory = scratch.url

        let appDirectory = tempDirectory.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try """
        android {
            namespace = "com.example.namespace"
            defaultConfig {
                applicationId = "com.example.application"
            }
        }
        """.write(to: appDirectory.appendingPathComponent("build.gradle.kts"), atomically: true, encoding: .utf8)

        let inspection = try await ProjectInspector(rootPath: tempDirectory.path).inspect()

        #expect(inspection.suggestedAndroidPackageName == "com.example.application")
    }
    #endif

    @Test("Package generation and AI readiness select a test workflow without app credentials")
    func packageTestWorkflowGuidance() throws {
        let inspection = ProjectInspection(
            rootPath: "/package", xcodeContainers: [], preferredContainer: nil, schemes: [], suggestedAppConfig: .init(),
            existingShipfiles: [], fastlaneFiles: [], ciFiles: [], warnings: [],
            swiftPackage: .init(name: "Lib", productCount: 1, hostIncompatibleSources: []))
        let suggestion = ShipfileSuggester().suggest(goal: .local, from: inspection)
        #expect(suggestion.kind == .swiftPackage)
        #expect(suggestion.yaml.contains("test_workflow: tests"))
        #expect(suggestion.yaml.contains("action: swift-test"))
        #expect(suggestion.yaml.contains("infrastructure_retry"))
        #expect(!suggestion.yaml.contains("artifacts:"), "evidence is staged under the artifact root without a declaration")
        #expect(suggestion.missingValues.isEmpty)
        let session = AISessionBuilder().build(goal: .local, inspection: inspection, hasExistingShipfile: true)
        #expect(session.readiness.isReady)
        #expect(session.nextAction.command == "shipit test")
        #expect(session.nextQuestion == nil)
    }

    @Test("A package's agent prompt is about testing a library, not releasing an app")
    func packagePromptHasNoAppReleaseGuidance() {
        let inspection = ProjectInspection(
            rootPath: "/package", xcodeContainers: [], preferredContainer: nil, schemes: [], suggestedAppConfig: .init(),
            existingShipfiles: [], fastlaneFiles: [], ciFiles: [], warnings: [],
            swiftPackage: .init(name: "Lib", productCount: 1, hostIncompatibleSources: []))
        let prompt = AISessionBuilder().build(goal: .local, inspection: inspection, hasExistingShipfile: false).agentPrompt
        #expect(prompt.contains("test a Swift package"))
        #expect(prompt.contains("shipit test --output json"))
        #expect(prompt.contains("swift-test"))
        for appGuidance in [
            "release pipeline", "shipit run local", "validate metadata", "validate archive", "xcodebuild -showdestinations",
        ] {
            #expect(!prompt.contains(appGuidance), "\(appGuidance)")
        }
    }

    @Test("A package that imports UIKit is tested on a simulator through the scheme Xcode generates for it")
    func deviceOnlyPackageUsesXcodeTest() {
        let inspection = ProjectInspection(
            rootPath: "/package", xcodeContainers: [], preferredContainer: nil, schemes: [], suggestedAppConfig: .init(),
            existingShipfiles: [], fastlaneFiles: [], ciFiles: [], warnings: [],
            swiftPackage: .init(name: "UIThing", productCount: 2, hostIncompatibleSources: ["Sources/UIThing/View.swift"]))
        let suggestion = ShipfileSuggester().suggest(goal: .local, from: inspection)
        #expect(suggestion.kind == .swiftPackage)
        #expect(suggestion.yaml.contains("- action: test\n"))
        #expect(suggestion.yaml.contains("scheme: UIThing-Package"))
        #expect(!suggestion.yaml.contains("swift-test"))
        #expect(suggestion.missingValues.isEmpty)
        let session = AISessionBuilder().build(goal: .local, inspection: inspection, hasExistingShipfile: true)
        #expect(session.nextAction.command == "shipit test")
        #expect(session.agentPrompt.contains("cannot build"))
        #expect(session.agentPrompt.contains("UIThing-Package"))
        #expect(
            session.appConfig.contains { $0.keyPath == "workflows.tests[test].options.scheme" && $0.value == .string("UIThing-Package") })
    }

    @Test(
        "Xcode names a package's scheme after the package, adding -Package when it has several products",
        arguments: [(1, "Lib"), (0, "Lib"), (2, "Lib-Package")])
    func packageTestScheme(products: Int, scheme: String) {
        #expect(SwiftPackageSummary(name: "Lib", productCount: products, hostIncompatibleSources: []).testScheme == scheme)
    }

    @Test("The inspector reads the package manifest and finds unguarded device-only imports")
    func inspectorReadsSwiftPackage() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let root = scratch.url
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "UIThing",
            platforms: [.iOS(.v17)],
            products: [
                .library(name: "UIThing", targets: ["UIThing"]),
                .executable(name: "tool", targets: ["Tool"]),
            ],
            targets: [.target(name: "UIThing"), .executableTarget(name: "Tool"), .testTarget(name: "UIThingTests")]
        )
        """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let files = [
            "Sources/UIThing/View.swift": "import UIKit\npublic final class V: UIView {}\n",
            "Sources/UIThing/Guarded.swift": "#if canImport(UIKit)\nimport UIKit\n#endif\n",
            "Sources/UIThing/Plain.swift": "import Foundation\n",
            "Tests/UIThingTests/ViewTests.swift": "import Testing\n@preconcurrency import UIKit\n",
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let inspection = try await ProjectInspector(rootPath: root.path).inspect()
        let package = try #require(inspection.swiftPackage)
        #expect(package.name == "UIThing")
        #expect(package.productCount == 2)
        #expect(package.hostIncompatibleSources == ["Sources/UIThing/View.swift", "Tests/UIThingTests/ViewTests.swift"])
        #expect(!package.isHostTestable)
        #expect(package.testScheme == "UIThing-Package")
        #expect(!inspection.warnings.contains { $0.contains("No .xcworkspace") }, "a package needs no Xcode project")
        #expect(inspection.warnings.contains { $0.contains("cannot build") })
    }

    @Test("A directory without Package.swift has no package summary")
    func inspectorWithoutPackage() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let inspection = try await ProjectInspector(rootPath: scratch.url.path).inspect()
        #expect(inspection.swiftPackage == nil)
    }

}
