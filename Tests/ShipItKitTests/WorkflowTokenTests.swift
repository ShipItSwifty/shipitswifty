import Foundation
import SwiftyShell
import Synchronization
import Testing

@testable import ShipItKit

@Suite("Workflow reserved tokens and `when:` conditions")
struct WorkflowTokenTests {

    // MARK: - Helpers

    /// A descriptor that records the (already token-substituted) options it receives and
    /// how many times it ran.
    private func makeOptionsCaptureDescriptor(
        name: String
    ) -> (descriptor: ActionDescriptor, received: @Sendable () -> [JSONValue?]) {
        let storage = Mutex<[JSONValue?]>([])
        let descriptor = ActionDescriptor(
            name: name,
            description: "Capture received options",
            runJSON: { options, _ in
                storage.withLock { $0.append(options) }
                return ActionResultEnvelope(action: name, status: "success", payload: nil)
            }
        )
        return (descriptor, { storage.withLock { $0 } })
    }

    /// A stub `version` descriptor that emits the given payload, mimicking what
    /// `VersionAction` produces so the token resolver can capture it.
    private func makeVersionStub(
        version: String, buildNumber: String, versionChanged: Bool
    ) -> ActionDescriptor {
        ActionDescriptor(
            name: VersionAction.name,
            description: "Stub version",
            runJSON: { _, _ in
                ActionResultEnvelope(
                    action: VersionAction.name,
                    status: "success",
                    payload: .object([
                        "version": .string(version),
                        "buildNumber": .string(buildNumber),
                        "versionChanged": .bool(versionChanged),
                    ])
                )
            }
        )
    }

    private func makeRegistry(descriptors: [ActionDescriptor]) async throws -> ActionRegistry {
        let registry = ActionRegistry()
        for descriptor in descriptors {
            try await registry.register(descriptor)
        }
        return registry
    }

    private func makeContext() -> ActionContext {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let shell = ShellContext(executor: executor)
        let config = ResolvedConfig(platform: .android, androidModule: "app")
        let logger = Logger.forType(subsystem: "ShipItSwiftyTests", Workflow.self)
        #if os(macOS)
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(
            keyID: "MOCKKEY", issuerID: "mock-issuer-id", privateKeyData: dummyKeyData)
        return ActionContext(
            shell: shell, logger: logger, config: config, appStoreConnect: ascClient, platform: .android)
        #else
        return ActionContext(shell: shell, logger: logger, config: config, platform: .android)
        #endif
    }

    private func optionString(_ options: JSONValue?, key: String) -> String? {
        guard case .object(let dict)? = options, case .string(let s)? = dict[key] else { return nil }
        return s
    }

    // MARK: - Token substitution

    @Test("`{{version}}`/`{{build_number}}`/`{{version_changed}}` resolve from a prior version step")
    func tokensResolveFromVersionStep() async throws {
        let versionStub = makeVersionStub(version: "1.2.3", buildNumber: "42", versionChanged: true)
        let (capture, received) = makeOptionsCaptureDescriptor(name: "git")
        let registry = try await makeRegistry(descriptors: [versionStub, capture])

        let workflow = Workflow(
            "release",
            steps: [
                WorkflowStep(action: "version"),
                WorkflowStep(
                    action: "git",
                    options: .object(["tag_name": .string("v{{version}}+{{build_number}} ({{version_changed}})")])),
            ]
        )

        _ = try await workflow.run(context: makeContext(), registry: registry)

        #expect(optionString(received().first ?? nil, key: "tag_name") == "v1.2.3+42 (true)")
    }

    @Test("Unknown tokens are left literal")
    func unknownTokenLeftLiteral() async throws {
        let (capture, received) = makeOptionsCaptureDescriptor(name: "notify")
        let registry = try await makeRegistry(descriptors: [capture])

        let workflow = Workflow(
            "x",
            steps: [
                WorkflowStep(action: "notify", options: .object(["message": .string("x{{not_a_token}}y")]))
            ]
        )

        _ = try await workflow.run(context: makeContext(), registry: registry)

        #expect(optionString(received().first ?? nil, key: "message") == "x{{not_a_token}}y")
    }

    // MARK: - `when:` conditions

    @Test("Step with truthy `when` runs")
    func whenTruthyRuns() async throws {
        let versionStub = makeVersionStub(version: "1.2.3", buildNumber: "42", versionChanged: true)
        let (capture, received) = makeOptionsCaptureDescriptor(name: "git")
        let registry = try await makeRegistry(descriptors: [versionStub, capture])

        let workflow = Workflow(
            "release",
            steps: [
                WorkflowStep(action: "version"),
                WorkflowStep(action: "git", options: nil, when: "{{version_changed}}"),
            ]
        )

        let result = try await workflow.run(context: makeContext(), registry: registry)

        #expect(received().count == 1)
        #expect(result.stepResults.last?.status == "success")
    }

    @Test("Step with falsy `when` is skipped and the workflow continues")
    func whenFalsySkips() async throws {
        let versionStub = makeVersionStub(version: "1.2.3", buildNumber: "43", versionChanged: false)
        let (capture, received) = makeOptionsCaptureDescriptor(name: "git")
        let registry = try await makeRegistry(descriptors: [versionStub, capture])

        let workflow = Workflow(
            "release",
            steps: [
                WorkflowStep(action: "version"),
                WorkflowStep(action: "git", options: nil, when: "{{version_changed}}"),
            ]
        )

        let result = try await workflow.run(context: makeContext(), registry: registry)

        #expect(received().isEmpty)  // git step never ran
        #expect(result.stepResults.count == 2)
        #expect(result.stepResults.last?.action == "git")
        #expect(result.stepResults.last?.status == "skipped")
        #expect(result.succeeded)
    }
}
