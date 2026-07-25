import Foundation
import SwiftyShell
import Synchronization
import Testing
import Yams

@testable import ShipItKit

@Suite("Workflow-level iOS overrides")
struct WorkflowIOSOverrideTests {

    // MARK: - Helpers

    /// Creates a no-op action descriptor that captures the context config it receives.
    private func makeCaptureDescriptor(
        name: String
    ) -> (descriptor: ActionDescriptor, configs: @Sendable () -> [ResolvedConfig]) {
        let storage = Mutex<[ResolvedConfig]>([])
        let descriptor = ActionDescriptor(
            name: name,
            description: "Capture context config",
            runJSON: { _, context in
                storage.withLock { $0.append(context.config) }
                return ActionResultEnvelope(action: name, status: "success", payload: nil)
            }
        )
        return (descriptor, { storage.withLock { $0 } })
    }

    private func makeRegistry(descriptors: [ActionDescriptor]) async throws -> ActionRegistry {
        let registry = ActionRegistry()
        for descriptor in descriptors {
            try await registry.register(descriptor)
        }
        return registry
    }

    /// A resolved config standing in for a production iOS Shipfile.
    private func productionConfig() -> ResolvedConfig {
        ResolvedConfig(
            appProject: "MyApp.xcodeproj",
            appScheme: "MyApp",
            bundleID: "com.example.app",
            teamID: "TEAM12345",
            buildConfiguration: "Release",
            archiveExportMethod: "app-store",
            archiveOutputPath: "./build/MyApp.xcarchive",
            exportArchivePath: "./build/MyApp.xcarchive",
            exportOutputDirectory: "./build/export",
            platform: .ios
        )
    }

    private func makeIOSContext() -> ActionContext {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let shell = ShellContext(executor: executor)
        let logger = Logger.forType(subsystem: "ShipItSwiftyTests", Workflow.self)
        #if os(macOS)
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        return ActionContext(
            shell: shell,
            logger: logger,
            config: productionConfig(),
            appStoreConnect: AppStoreConnectClient(
                keyID: "MOCKKEY", issuerID: "mock-issuer-id", privateKeyData: dummyKeyData),
            platform: .ios
        )
        #else
        return ActionContext(
            shell: shell, logger: logger, config: productionConfig(), platform: .ios)
        #endif
    }

    // MARK: - Applying overrides at run time

    @Test("Staging overrides reach every step in the workflow")
    func overridesReachEveryStep() async throws {
        let (archiveDesc, archiveConfigs) = makeCaptureDescriptor(name: "archive")
        let (exportDesc, exportConfigs) = makeCaptureDescriptor(name: "export")
        let registry = try await makeRegistry(descriptors: [archiveDesc, exportDesc])

        let workflow = Workflow(
            "staging",
            steps: [WorkflowStep(action: "archive"), WorkflowStep(action: "export")],
            app: AppConfig(scheme: "MyApp-QA", bundleId: "com.example.app.qa"),
            build: BuildConfig(configuration: "QA"),
            archive: ArchiveConfig(
                exportMethod: "ad-hoc", outputPath: "./build/MyApp-QA.xcarchive"),
            export: ExportConfig(
                archivePath: "./build/MyApp-QA.xcarchive",
                outputDirectory: "./build/staging-export")
        )

        _ = try await workflow.run(context: makeIOSContext(), registry: registry)

        let archived = try #require(archiveConfigs().first)
        #expect(archived.appScheme == "MyApp-QA")
        #expect(archived.bundleID == "com.example.app.qa")
        #expect(archived.buildConfiguration == "QA")
        #expect(archived.archiveExportMethod == "ad-hoc")
        #expect(archived.archiveOutputPath == "./build/MyApp-QA.xcarchive")

        let exported = try #require(exportConfigs().first)
        #expect(exported.exportArchivePath == "./build/MyApp-QA.xcarchive")
        #expect(exported.exportOutputDirectory == "./build/staging-export")
        #expect(exported.appScheme == "MyApp-QA")
    }

    @Test("A production workflow in the same Shipfile keeps its own settings")
    func productionWorkflowIsUnaffected() async throws {
        let (stagingDesc, stagingConfigs) = makeCaptureDescriptor(name: "archive")
        let stagingRegistry = try await makeRegistry(descriptors: [stagingDesc])
        let context = makeIOSContext()

        let staging = Workflow(
            "staging",
            steps: [WorkflowStep(action: "archive")],
            app: AppConfig(scheme: "MyApp-QA", bundleId: "com.example.app.qa"),
            archive: ArchiveConfig(exportMethod: "ad-hoc")
        )
        _ = try await staging.run(context: context, registry: stagingRegistry)

        // Same shared context, run afterwards: production must not inherit staging's overrides.
        let (betaDesc, betaConfigs) = makeCaptureDescriptor(name: "archive")
        let betaRegistry = try await makeRegistry(descriptors: [betaDesc])
        let beta = Workflow("beta", steps: [WorkflowStep(action: "archive")])
        _ = try await beta.run(context: context, registry: betaRegistry)

        #expect(stagingConfigs().first?.archiveExportMethod == "ad-hoc")
        #expect(betaConfigs().first?.appScheme == "MyApp")
        #expect(betaConfigs().first?.bundleID == "com.example.app")
        #expect(betaConfigs().first?.archiveExportMethod == "app-store")
    }

    @Test("Only the named settings are overridden; the rest fall through")
    func partialOverridesFallThrough() async throws {
        let (archiveDesc, archiveConfigs) = makeCaptureDescriptor(name: "archive")
        let registry = try await makeRegistry(descriptors: [archiveDesc])

        let workflow = Workflow(
            "staging",
            steps: [WorkflowStep(action: "archive")],
            app: AppConfig(scheme: "MyApp-QA")
        )
        _ = try await workflow.run(context: makeIOSContext(), registry: registry)

        let captured = try #require(archiveConfigs().first)
        #expect(captured.appScheme == "MyApp-QA")
        #expect(captured.bundleID == "com.example.app")
        #expect(captured.teamID == "TEAM12345")
        #expect(captured.buildConfiguration == "Release")
        #expect(captured.archiveExportMethod == "app-store")
        #expect(captured.appProject == "MyApp.xcodeproj")
    }

    // MARK: - overriding()

    @Test("Overriding does not mutate the config it derives from")
    func doesNotMutateSource() {
        let production = productionConfig()
        _ = production.overriding(
            app: AppConfig(scheme: "MyApp-QA", bundleId: "com.example.app.qa"),
            build: BuildConfig(configuration: "QA"),
            archive: ArchiveConfig(exportMethod: "ad-hoc"))

        #expect(production.appScheme == "MyApp")
        #expect(production.bundleID == "com.example.app")
        #expect(production.buildConfiguration == "Release")
        #expect(production.archiveExportMethod == "app-store")
    }

    @Test("An overridden bundle ID wins over one auto-detected from build settings")
    func overriddenBundleIDClearsDetectionFlag() {
        let detected = ResolvedConfig(
            appScheme: "MyApp",
            bundleID: "com.example.app",
            bundleIDFromTargetBuildSettings: true,
            platform: .ios
        )
        let overridden = detected.overriding(app: AppConfig(bundleId: "com.example.app.qa"))

        #expect(overridden.bundleID == "com.example.app.qa")
        // Otherwise the detected production ID would keep winning downstream.
        #expect(overridden.bundleIDFromTargetBuildSettings == false)
    }

    @Test("A code_signing type override updates the automatic-signing flag")
    func codeSigningOverrideUpdatesAutomaticFlag() {
        let automatic = ResolvedConfig(
            appScheme: "MyApp", codeSigningType: "automatic", automaticCodeSigning: true,
            platform: .ios)
        let manual = automatic.overriding(codeSigning: CodeSigningConfig(type: "manual"))

        #expect(manual.codeSigningType == "manual")
        #expect(manual.automaticCodeSigning == false)
    }

    @Test("A code_signing profile-path override is applied")
    func codeSigningProfilePathOverride() {
        let config = productionConfig()
        let overridden = config.overriding(
            codeSigning: CodeSigningConfig(
                provisioningProfilePath: "./profiles/qa-adhoc.mobileprovision"))

        #expect(
            overridden.codeSigningProvisioningProfilePath == "./profiles/qa-adhoc.mobileprovision")
    }

    // MARK: - Decoding

    @Test("Decodes iOS override groups from a Shipfile workflow object")
    func decodesIOSOverrides() throws {
        let shipfile = try YAMLDecoder().decode(
            Shipfile.self,
            from: """
                platform: ios
                workflows:
                  staging:
                    app:
                      scheme: MyApp-QA
                      bundle_id: com.example.app.qa
                    build:
                      configuration: QA
                    archive:
                      export_method: ad-hoc
                      output_path: ./build/MyApp-QA.xcarchive
                    export:
                      archive_path: ./build/MyApp-QA.xcarchive
                      output_directory: ./build/staging-export
                    code_signing:
                      type: manual
                      provisioning_profile_path: ./profiles/qa-adhoc.mobileprovision
                    steps:
                      - action: archive
                      - action: export
                """)

        let staging = try #require(shipfile.workflows?["staging"])
        #expect(staging.app?.scheme == "MyApp-QA")
        #expect(staging.app?.bundleId == "com.example.app.qa")
        #expect(staging.build?.configuration == "QA")
        #expect(staging.archive?.exportMethod == "ad-hoc")
        #expect(staging.archive?.outputPath == "./build/MyApp-QA.xcarchive")
        #expect(staging.export?.archivePath == "./build/MyApp-QA.xcarchive")
        #expect(staging.export?.outputDirectory == "./build/staging-export")
        #expect(staging.codeSigning?.type == "manual")
        #expect(
            staging.codeSigning?.provisioningProfilePath == "./profiles/qa-adhoc.mobileprovision")
        #expect(staging.steps.map(\.action) == ["archive", "export"])
    }

    @Test("A legacy plain-array workflow still decodes with no overrides")
    func decodesLegacyArrayForm() throws {
        let shipfile = try YAMLDecoder().decode(
            Shipfile.self,
            from: """
                platform: ios
                workflows:
                  beta:
                    - action: archive
                    - action: testflight
                """)

        let beta = try #require(shipfile.workflows?["beta"])
        #expect(beta.steps.map(\.action) == ["archive", "testflight"])
        #expect(beta.app == nil)
        #expect(beta.build == nil)
        #expect(beta.archive == nil)
        #expect(beta.export == nil)
        #expect(beta.codeSigning == nil)
    }

    @Test("A workflow with only iOS overrides re-encodes as an object, not an array")
    func encodesWithIOSOverridesAsObject() throws {
        let config = WorkflowConfig(
            app: AppConfig(scheme: "MyApp-QA"),
            steps: [WorkflowStepConfig(action: "archive")])
        let data = try JSONEncoder().encode(config)
        let dict = try JSONDecoder().decode([String: JSONValue].self, from: data)

        #expect(dict["app"] != nil)
        #expect(dict["steps"] != nil)
    }
}
