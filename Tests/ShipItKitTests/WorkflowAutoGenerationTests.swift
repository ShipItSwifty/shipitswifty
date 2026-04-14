import Foundation
import Testing
import SwiftyShell
@testable import ShipItKit

@Suite("Workflow auto-generation")
struct WorkflowAutoGenerationTests {

    /// Helper: makes a no-op action descriptor that always succeeds.
    private func makeNoOpDescriptor(name: String) -> ActionDescriptor {
        ActionDescriptor(
            name: name,
            description: "Test no-op action",
            runJSON: { _, _ in
                ActionResultEnvelope(action: name, status: "success", payload: nil)
            }
        )
    }

    /// Helper: makes a registry with the given action names registered as no-ops.
    private func makeRegistry(actionNames: [String]) async throws -> ActionRegistry {
        let registry = ActionRegistry()
        for name in actionNames {
            try await registry.register(makeNoOpDescriptor(name: name))
        }
        return registry
    }

    // MARK: - requiresXcodeContainer

    @Test("Workflow with build step triggers auto-generation")
    func workflowWithBuildStepTriggersGeneration() async throws {
        let (executor, commands) = makeCaptureExecutor { command, _ in
            // The generate_project command
            ShellOutput(stdout: "Generated project\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationAutoGenerate: true
            // Note: no projectGenerationOutputProject — so FileManager check for existence is skipped
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", Workflow.self),
            config: config,
            appStoreConnect: ascClient
        )

        let registry = try await makeRegistry(actionNames: ["build"])

        let workflow = Workflow("test-workflow", steps: [
            WorkflowStep(action: "build"),
        ])

        let result = try await workflow.run(context: context, registry: registry)

        #expect(result.succeeded)
        // The generation command should have been executed
        #expect(commands().contains { $0.contains("xcodegen") && $0.contains("generate") })
    }

    @Test("Workflow without Xcode-dependent steps does not trigger generation")
    func workflowWithoutXcodeStepsSkipsGeneration() async throws {
        let (executor, commands) = makeCaptureExecutor()

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationAutoGenerate: true
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", Workflow.self),
            config: config,
            appStoreConnect: ascClient
        )

        // Register a non-Xcode action (e.g. "testflight", "notify")
        let registry = try await makeRegistry(actionNames: ["notify"])

        let workflow = Workflow("notify-only", steps: [
            WorkflowStep(action: "notify"),
        ])

        let result = try await workflow.run(context: context, registry: registry)

        #expect(result.succeeded)
        // No generation command should have been executed
        #expect(!commands().contains { $0.contains("xcodegen") })
    }

    @Test("Workflow skips generation when project generation is not configured")
    func workflowSkipsGenerationWhenNotConfigured() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            // build action no-op (the workflow descriptor handles it, but this handles
            // any ensureProjectGenerated shell calls)
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        // No project generation configured (default ActionContext.mock)
        let context = ActionContext.mock(executor: executor)
        let registry = try await makeRegistry(actionNames: ["build"])

        let workflow = Workflow("basic-build", steps: [
            WorkflowStep(action: "build"),
        ])

        let result = try await workflow.run(context: context, registry: registry)

        #expect(result.succeeded)
        // No xcodegen calls
        #expect(!commands().contains { $0.contains("xcodegen") })
    }

    @Test("Workflow skips generation when auto_generate is false")
    func workflowSkipsGenerationWhenAutoGenerateDisabled() async throws {
        let (executor, commands) = makeCaptureExecutor()

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationAutoGenerate: false  // disabled
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", Workflow.self),
            config: config,
            appStoreConnect: ascClient
        )

        let registry = try await makeRegistry(actionNames: ["build"])

        let workflow = Workflow("build-no-autogen", steps: [
            WorkflowStep(action: "build"),
        ])

        let result = try await workflow.run(context: context, registry: registry)

        #expect(result.succeeded)
        #expect(commands().isEmpty, "No shell commands should run when auto_generate is false")
    }

    @Test("Workflow runs steps sequentially and reports results")
    func workflowRunsStepsSequentially() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        let registry = try await makeRegistry(actionNames: ["build", "archive"])

        let workflow = Workflow("multi-step", steps: [
            WorkflowStep(action: "build"),
            WorkflowStep(action: "archive"),
        ])

        let result = try await workflow.run(context: context, registry: registry)

        #expect(result.succeeded)
        #expect(result.stepResults.count == 2)
        #expect(result.stepResults[0].action == "build")
        #expect(result.stepResults[1].action == "archive")
        #expect(result.workflowName == "multi-step")
    }

    @Test("Workflow throws for unknown action")
    func workflowThrowsForUnknownAction() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let registry = ActionRegistry()

        let workflow = Workflow("bad-workflow", steps: [
            WorkflowStep(action: "nonexistent_action"),
        ])

        await #expect(throws: ShipItError.self) {
            _ = try await workflow.run(context: context, registry: registry)
        }
    }
}

// MARK: - ensureProjectGenerated unit tests

@Suite("ensureProjectGenerated")
struct EnsureProjectGeneratedTests {

    @Test("ensureProjectGenerated is a no-op when project generation is not configured")
    func noOpWithoutConfig() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        // Should not throw — no project generation configured
        try await context.ensureProjectGenerated()
    }

    @Test("ensureProjectGenerated is a no-op when auto_generate is false")
    func noOpWhenAutoGenerateDisabled() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationAutoGenerate: false
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", ActionContext.self),
            config: config,
            appStoreConnect: ascClient
        )

        try await context.ensureProjectGenerated()
    }

    @Test("ensureProjectGenerated runs generation when output project is missing")
    func runsGenerationWhenOutputMissing() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Generated\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationOutputProject: "/nonexistent/MyApp.xcodeproj",
            projectGenerationAutoGenerate: true
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", ActionContext.self),
            config: config,
            appStoreConnect: ascClient
        )

        // Output project doesn't exist, so it should try to generate
        // (Note: the generation will fail verification because the output won't actually
        //  be created by the mock, but we can verify the command was attempted)
        do {
            try await context.ensureProjectGenerated()
        } catch {
            // Expected: generation command runs but output not created → throws
        }

        // The generation command should have been executed
        #expect(commands().contains { $0.contains("xcodegen") && $0.contains("generate") })
    }

    @Test("ensureProjectGenerated skips when output project already exists")
    func skipsWhenOutputExists() async throws {
        // Create a temp directory to act as the output project
        let dir = NSTemporaryDirectory() + "ShipItTests-\(UUID().uuidString)"
        let projectPath = dir + "/MyApp.xcodeproj"
        try FileManager.default.createDirectory(atPath: projectPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let (executor, commands) = makeCaptureExecutor()

        let config = ResolvedConfig(
            appScheme: "MockApp",
            projectGenerationTool: "xcodegen",
            projectGenerationCommand: "xcodegen generate",
            projectGenerationOutputProject: projectPath,
            projectGenerationAutoGenerate: true
        )
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", ActionContext.self),
            config: config,
            appStoreConnect: ascClient
        )

        try await context.ensureProjectGenerated()

        // No generation command should have been executed
        #expect(commands().isEmpty, "Should not generate when output project already exists")
    }
}
