import Foundation
import SwiftyShell
import Synchronization
import Testing

@testable import ShipItKit

@Suite("Workflow-level build_variant/flavor overrides")
struct WorkflowOverrideTests {

    // MARK: - Helpers

    /// Creates a no-op action descriptor that captures the context config it receives.
    /// Returns the descriptor and a closure to retrieve captured configs.
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

    private func makeAndroidContext(buildVariant: String = "release") -> ActionContext {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let shell = ShellContext(executor: executor)
        let config = ResolvedConfig(
            platform: .android,
            androidModule: "app",
            androidBuildVariant: buildVariant,
            androidPackageName: "com.example.test"
        )
        let logger = Logger.forType(subsystem: "ShipItSwiftyTests", Workflow.self)
        #if os(macOS)
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(
            keyID: "MOCKKEY",
            issuerID: "mock-issuer-id",
            privateKeyData: dummyKeyData
        )
        return ActionContext(
            shell: shell,
            logger: logger,
            config: config,
            appStoreConnect: ascClient,
            platform: .android
        )
        #else
        return ActionContext(
            shell: shell,
            logger: logger,
            config: config,
            platform: .android
        )
        #endif
    }

    // MARK: - Tests

    @Test("Workflow with build_variant overrides context.config.androidBuildVariant for all steps")
    func workflowBuildVariantOverridesConfig() async throws {
        let (archiveDesc, archiveConfigs) = makeCaptureDescriptor(name: "archive")
        let (playStoreDesc, playStoreConfigs) = makeCaptureDescriptor(name: "play-store")
        let registry = try await makeRegistry(descriptors: [archiveDesc, playStoreDesc])

        let context = makeAndroidContext(buildVariant: "release")

        let workflow = Workflow(
            "release",
            steps: [
                WorkflowStep(action: "archive"),
                WorkflowStep(action: "play-store"),
            ],
            buildVariant: "prodRelease"
        )

        _ = try await workflow.run(context: context, registry: registry)

        #expect(archiveConfigs().first?.androidBuildVariant == "prodRelease")
        #expect(playStoreConfigs().first?.androidBuildVariant == "prodRelease")
    }

    @Test("Workflow without build_variant preserves original context config")
    func workflowWithoutOverridePreservesConfig() async throws {
        let (buildDesc, buildConfigs) = makeCaptureDescriptor(name: "build")
        let registry = try await makeRegistry(descriptors: [buildDesc])

        let context = makeAndroidContext(buildVariant: "release")

        let workflow = Workflow(
            "debug",
            steps: [WorkflowStep(action: "build")]
        )

        _ = try await workflow.run(context: context, registry: registry)

        #expect(buildConfigs().first?.androidBuildVariant == "release")
    }

    @Test("Workflow with flavor overrides androidGradleProperties flavor")
    func workflowFlavorOverridesGradleProperties() async throws {
        let (buildDesc, buildConfigs) = makeCaptureDescriptor(name: "build")
        let registry = try await makeRegistry(descriptors: [buildDesc])

        let context = makeAndroidContext()

        let workflow = Workflow(
            "staging",
            steps: [WorkflowStep(action: "build")],
            flavor: "staging"
        )

        _ = try await workflow.run(context: context, registry: registry)

        #expect(buildConfigs().first?.androidGradleProperties["flavor"] == "staging")
    }

    // MARK: - WorkflowConfig Decoding

    @Test("WorkflowConfig decodes from plain array (backward compat)")
    func decodesFromPlainArray() throws {
        let json = """
            [{"action": "build"}, {"action": "test"}]
            """
        let config = try JSONDecoder().decode(WorkflowConfig.self, from: Data(json.utf8))
        #expect(config.steps.count == 2)
        #expect(config.steps[0].action == "build")
        #expect(config.steps[1].action == "test")
        #expect(config.buildVariant == nil)
        #expect(config.flavor == nil)
    }

    @Test("WorkflowConfig decodes from struct with overrides")
    func decodesFromStructWithOverrides() throws {
        let json = """
            {"build_variant": "prodRelease", "flavor": "prod", "steps": [{"action": "archive"}, {"action": "play-store"}]}
            """
        let config = try JSONDecoder().decode(WorkflowConfig.self, from: Data(json.utf8))
        #expect(config.buildVariant == "prodRelease")
        #expect(config.flavor == "prod")
        #expect(config.steps.count == 2)
        #expect(config.steps[0].action == "archive")
        #expect(config.steps[1].action == "play-store")
    }

    @Test("WorkflowConfig encodes as plain array when no overrides set")
    func encodesAsArrayWithoutOverrides() throws {
        let config = WorkflowConfig(steps: [
            WorkflowStepConfig(action: "build"),
            WorkflowStepConfig(action: "test"),
        ])
        let data = try JSONEncoder().encode(config)
        let json = try JSONDecoder().decode([WorkflowStepConfig].self, from: data)
        #expect(json.count == 2)
    }

    @Test("WorkflowConfig encodes as object when overrides are set")
    func encodesAsObjectWithOverrides() throws {
        let config = WorkflowConfig(
            buildVariant: "prodRelease",
            steps: [
                WorkflowStepConfig(action: "archive")
            ])
        let data = try JSONEncoder().encode(config)
        // Should have "build_variant" key
        let dict = try JSONDecoder().decode([String: JSONValue].self, from: data)
        #expect(dict["build_variant"] == .string("prodRelease"))
        #expect(dict["steps"] != nil)
    }
}
