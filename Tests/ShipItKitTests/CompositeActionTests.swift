import Foundation
import SwiftyShell
import Synchronization
import Testing

@testable import ShipItKit

// MARK: - Composite Action Tests

@Suite("CompositeAction")
struct CompositeActionTests {

    // MARK: Parameter substitution

    @Test("substitute preserves typed values when the whole string is {{param.X}}")
    func typedWholeStringSubstitution() {
        let params: [String: JSONValue] = [
            "enabled": .bool(true),
            "count": .int(7),
            "items": .array([.string("a"), .string("b")]),
        ]
        let input: JSONValue = .object([
            "enabled": .string("{{param.enabled}}"),
            "count": .string("  {{param.count}}  "),
            "items": .string("{{param.items}}"),
        ])
        let output = CompositeAction.substitute(value: input, params: params, compositeName: "x", stepIndex: 0)

        guard case .object(let dict) = output else {
            Issue.record("expected object")
            return
        }
        #expect(dict["enabled"] == .bool(true))
        #expect(dict["count"] == .int(7))
        #expect(dict["items"] == .array([.string("a"), .string("b")]))
    }

    @Test("substitute interpolates parameters inside larger strings")
    func interpolatedSubstitution() {
        let params: [String: JSONValue] = [
            "track": .string("beta"),
            "suffix": .int(42),
        ]
        let input: JSONValue = .string("release-{{param.track}}-{{param.suffix}}")
        let output = CompositeAction.substitute(value: input, params: params, compositeName: "x", stepIndex: 0)
        #expect(output == .string("release-beta-42"))
    }

    @Test("substitute preserves unknown references literally for later diagnosis")
    func unknownParameterPreserved() {
        let input: JSONValue = .string("hello-{{param.nope}}")
        let output = CompositeAction.substitute(value: input, params: [:], compositeName: "x", stepIndex: 0)
        #expect(output == .string("hello-{{param.nope}}"))
    }

    @Test("substitute recurses into arrays and nested objects")
    func deepSubstitution() {
        let params: [String: JSONValue] = ["name": .string("MyApp")]
        let input: JSONValue = .object([
            "groups": .array([.string("{{param.name}}-QA"), .string("plain")]),
            "nested": .object(["scheme": .string("{{param.name}}")]),
        ])
        let output = CompositeAction.substitute(value: input, params: params, compositeName: "x", stepIndex: 0)
        let expected: JSONValue = .object([
            "groups": .array([.string("MyApp-QA"), .string("plain")]),
            "nested": .object(["scheme": .string("MyApp")]),
        ])
        #expect(output == expected)
    }

    // MARK: Parameter resolution

    @Test("resolveParameters applies defaults and enforces required params")
    func resolveParametersRules() throws {
        let declared: [String: CustomActionParameter] = [
            "method": CustomActionParameter(type: "string", required: true),
            "track": CustomActionParameter(type: "string", defaultValue: .string("internal")),
        ]

        let resolved = try CompositeAction.resolveParameters(
            compositeName: "c",
            declared: declared,
            provided: ["method": .string("app-store")]
        )
        #expect(resolved["method"] == .string("app-store"))
        #expect(resolved["track"] == .string("internal"))

        #expect(throws: CompositeAction.CompositeError.self) {
            _ = try CompositeAction.resolveParameters(
                compositeName: "c",
                declared: declared,
                provided: [:]
            )
        }
    }

    // MARK: Cycle detection + collisions

    @Test("detectCycle finds direct self-reference")
    func detectsSelfCycle() {
        let actions: [String: CustomActionConfig] = [
            "a": CustomActionConfig(steps: [WorkflowStepConfig(action: "a")])
        ]
        #expect(ActionRegistry.detectCycle(in: actions) != nil)
    }

    @Test("detectCycle finds indirect a -> b -> a cycle")
    func detectsIndirectCycle() {
        let actions: [String: CustomActionConfig] = [
            "a": CustomActionConfig(steps: [WorkflowStepConfig(action: "b")]),
            "b": CustomActionConfig(steps: [WorkflowStepConfig(action: "a")]),
        ]
        #expect(ActionRegistry.detectCycle(in: actions) != nil)
    }

    @Test("detectCycle passes when composites only reference built-ins")
    func noCycleForBuiltInReferences() {
        let actions: [String: CustomActionConfig] = [
            "a": CustomActionConfig(steps: [
                WorkflowStepConfig(action: "test"),
                WorkflowStepConfig(action: "archive"),
            ])
        ]
        #expect(ActionRegistry.detectCycle(in: actions) == nil)
    }

    @Test("registry rejects composites that collide with built-ins")
    func rejectsBuiltInCollision() async throws {
        let registry = ActionRegistry()
        try await registry.register(
            ActionDescriptor(
                name: "archive",
                description: "dummy",
                runJSON: { _, _ in ActionResultEnvelope(action: "archive", status: "success", payload: nil) }
            ))

        do {
            try await registry.registerCustomActions([
                "archive": CustomActionConfig(steps: [WorkflowStepConfig(action: "test")])
            ])
            Issue.record("expected collision error")
        } catch let error as ShipItError {
            if case .invalidConfiguration(let reason) = error {
                #expect(reason.contains("collides"))
            } else {
                Issue.record("unexpected error kind: \(error)")
            }
        }
    }

    // MARK: End-to-end execution

    @Test("composite expands to its sub-steps and forwards substituted options")
    func endToEndExpansion() async throws {
        // A recording action that captures the options it was called with.
        let recorder = OptionsRecorder()
        let registry = ActionRegistry()
        try await registry.register(
            ActionDescriptor(
                name: "record",
                description: "test-only action",
                runJSON: { options, _ in
                    recorder.record(options)
                    return ActionResultEnvelope(action: "record", status: "success", payload: options)
                }
            ))

        let config = CustomActionConfig(
            description: "test composite",
            parameters: ["method": CustomActionParameter(type: "string", required: true)],
            steps: [
                WorkflowStepConfig(action: "record", options: .object(["method": .string("{{param.method}}")])),
                WorkflowStepConfig(action: "record", options: .object(["marker": .string("second")])),
            ]
        )
        try await registry.registerCustomActions(["build_and_sign": config])

        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor)

        let descriptor = try #require(await registry.descriptor(named: "build_and_sign"))
        let envelope = try await descriptor.runJSON(.object(["method": .string("app-store")]), context)

        #expect(envelope.action == "build_and_sign")
        #expect(envelope.status == "success")

        let captured = recorder.snapshot()
        #expect(captured.count == 2)
        #expect(captured[0] == .object(["method": .string("app-store")]))
        #expect(captured[1] == .object(["marker": .string("second")]))
    }

    // MARK: Integration — YAML round-trip

    @Test("custom_actions decode from YAML through ConfigResolver")
    func yamlRoundTrip() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let shipfileURL = tempDirectory.appendingPathComponent("Shipfile.yml")
        try """
        app:
          scheme: Example
          bundle_id: com.example.app
        custom_actions:
          build_and_sign:
            description: "Shared build+sign sequence."
            parameters:
              method:
                type: string
                required: true
              track:
                type: string
                default: internal
            steps:
              - action: test
              - action: archive
              - action: export
                options:
                  method: "{{param.method}}"
        workflows:
          beta:
            - action: build_and_sign
              options:
                method: app-store
        """.write(to: shipfileURL, atomically: true, encoding: .utf8)

        let resolver = ConfigResolver(environment: Environment(env: [:]))
        let resolved = try await resolver.resolve(shipfilePath: shipfileURL.path)

        let composite = try #require(resolved.customActions["build_and_sign"])
        #expect(composite.description == "Shared build+sign sequence.")
        #expect(composite.steps.count == 3)
        #expect(composite.steps.map { $0.action } == ["test", "archive", "export"])

        let params = try #require(composite.parameters)
        #expect(params["method"]?.isRequired == true)
        #expect(params["track"]?.defaultValue == .string("internal"))
        #expect(params["track"]?.isRequired == false)

        let exportOptions = composite.steps[2].options?.objectValue ?? [:]
        #expect(exportOptions["method"] == .string("{{param.method}}"))
    }

    // MARK: Integration — ShipfileValidator

    @Test("validator flags custom action colliding with built-in name")
    func validatorRejectsBuiltInCollision() async {
        let yml = """
            app: { scheme: X, bundle_id: com.example.x }
            custom_actions:
              archive:
                steps:
                  - action: test
            """
        let report = await ShipfileValidator().validate(
            shipfileContents: yml,
            actionDescriptors: Self.validationDescriptorsForValidator()
        )
        #expect(report.isValid == false)
        #expect(
            report.issues.contains {
                $0.severity == .error && $0.message.contains("collides")
            })
    }

    @Test("validator flags undeclared {{param.X}} references")
    func validatorRejectsUndeclaredParamRef() async {
        let yml = """
            app: { scheme: X, bundle_id: com.example.x }
            custom_actions:
              ship:
                parameters:
                  method:
                    type: string
                steps:
                  - action: export
                    options:
                      method: "{{param.method}}"
                      track: "{{param.missing}}"
            """
        let report = await ShipfileValidator().validate(
            shipfileContents: yml,
            actionDescriptors: Self.validationDescriptorsForValidator()
        )
        #expect(report.isValid == false)
        #expect(
            report.issues.contains {
                $0.severity == .error && $0.message.contains("undeclared parameter 'missing'")
            })
    }

    @Test("validator flags unknown sub-step action names")
    func validatorRejectsUnknownSubAction() async {
        let yml = """
            app: { scheme: X, bundle_id: com.example.x }
            custom_actions:
              ship:
                steps:
                  - action: not_a_real_action
            """
        let report = await ShipfileValidator().validate(
            shipfileContents: yml,
            actionDescriptors: Self.validationDescriptorsForValidator()
        )
        #expect(report.isValid == false)
        #expect(
            report.issues.contains {
                $0.severity == .error && $0.message.contains("Unknown action 'not_a_real_action'")
            })
    }

    @Test("validator flags cycles between composites")
    func validatorRejectsCycle() async {
        let yml = """
            app: { scheme: X, bundle_id: com.example.x }
            custom_actions:
              a:
                steps:
                  - action: b
              b:
                steps:
                  - action: a
            """
        let report = await ShipfileValidator().validate(
            shipfileContents: yml,
            actionDescriptors: Self.validationDescriptorsForValidator()
        )
        #expect(report.isValid == false)
        #expect(
            report.issues.contains {
                $0.severity == .error && $0.message.contains("cycle detected")
            })
    }

    @Test("validator flags empty steps list")
    func validatorRejectsEmptySteps() async {
        let yml = """
            app: { scheme: X, bundle_id: com.example.x }
            custom_actions:
              ship:
                steps: []
            """
        let report = await ShipfileValidator().validate(
            shipfileContents: yml,
            actionDescriptors: Self.descriptorsForValidator()
        )
        #expect(report.isValid == false)
        #expect(
            report.issues.contains {
                $0.severity == .error && $0.message.contains("must declare at least one step")
            })
    }

    @Test("validator accepts a well-formed custom action")
    func validatorAcceptsValidCompositie() async {
        let yml = """
            app: { scheme: X, bundle_id: com.example.x }
            custom_actions:
              build_and_sign:
                parameters:
                  method: { type: string, required: true }
                steps:
                  - action: test
                  - action: archive
                  - action: export
                    options:
                      method: "{{param.method}}"
            """
        let report = await ShipfileValidator().validate(
            shipfileContents: yml,
            actionDescriptors: Self.validationDescriptorsForValidator()
        )
        // No custom-action errors should be raised. (Other unrelated issues
        // may still exist because descriptorsForValidator is a minimal set,
        // but none of them should come from $.custom_actions.)
        let customActionErrors = report.issues.filter {
            $0.severity == .error && $0.path.hasPrefix("$.custom_actions")
        }
        #expect(customActionErrors.isEmpty)
    }

    @Test("validation descriptors include iOS-only actions on every host")
    func validationDescriptorsIncludeIOSOnlyActions() {
        let names = Set(BuiltInSchemaCatalog.validationActionSchemas().map(\.name))

        #expect(names.contains("export"))
        #expect(names.contains("testflight"))
        #expect(names.contains("metadata"))
        #expect(names.contains("validate_archive"))
    }

    // MARK: Integration — Registry cycle rejection

    @Test("registerCustomActions throws invalidConfiguration on cycle")
    func registerCustomActionsRejectsCycle() async throws {
        let registry = ActionRegistry()
        let cyclic: [String: CustomActionConfig] = [
            "a": CustomActionConfig(steps: [WorkflowStepConfig(action: "b")]),
            "b": CustomActionConfig(steps: [WorkflowStepConfig(action: "a")]),
        ]
        do {
            try await registry.registerCustomActions(cyclic)
            Issue.record("expected cycle rejection")
        } catch let error as ShipItError {
            if case .invalidConfiguration(let reason) = error {
                #expect(reason.contains("cycle"))
            } else {
                Issue.record("unexpected ShipItError: \(error)")
            }
        }
    }

    // MARK: Integration — Workflow.run end-to-end

    @Test("Workflow.run executes a composite and its sub-steps in order")
    func workflowRunExpandsComposite() async throws {
        let recorder = OptionsRecorder()
        let registry = ActionRegistry()
        try await registry.register(
            ActionDescriptor(
                name: "record",
                description: "test-only action",
                runJSON: { options, _ in
                    recorder.record(options)
                    return ActionResultEnvelope(action: "record", status: "success", payload: options)
                }
            ))

        let composite = CustomActionConfig(
            parameters: ["method": CustomActionParameter(type: "string", required: true)],
            steps: [
                WorkflowStepConfig(action: "record", options: .object(["phase": .string("a"), "method": .string("{{param.method}}")])),
                WorkflowStepConfig(action: "record", options: .object(["phase": .string("b")])),
            ]
        )
        try await registry.registerCustomActions(["ship": composite])

        let workflow = Workflow(
            "beta",
            steps: [
                WorkflowStep(action: "ship", options: .object(["method": .string("app-store")]))
            ])

        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor)
        let result = try await workflow.run(context: context, registry: registry)

        #expect(result.stepResults.count == 1)
        #expect(result.stepResults[0].action == "ship")

        let captured = recorder.snapshot()
        #expect(captured.count == 2)
        #expect(captured[0] == .object(["phase": .string("a"), "method": .string("app-store")]))
        #expect(captured[1] == .object(["phase": .string("b")]))
    }

    // MARK: Integration — Nested composites

    @Test("nested composite forwards parameters through two layers")
    func nestedCompositeForwardsParameters() async throws {
        let recorder = OptionsRecorder()
        let registry = ActionRegistry()
        try await registry.register(
            ActionDescriptor(
                name: "record",
                description: "test-only action",
                runJSON: { options, _ in
                    recorder.record(options)
                    return ActionResultEnvelope(action: "record", status: "success", payload: options)
                }
            ))

        // inner takes `track`, forwards to record.
        let inner = CustomActionConfig(
            parameters: ["track": CustomActionParameter(type: "string", required: true)],
            steps: [
                WorkflowStepConfig(action: "record", options: .object(["track": .string("{{param.track}}")]))
            ]
        )
        // outer takes `method`, calls inner with a literal track derived from `method`.
        let outer = CustomActionConfig(
            parameters: ["method": CustomActionParameter(type: "string", required: true)],
            steps: [
                WorkflowStepConfig(action: "inner", options: .object(["track": .string("via-{{param.method}}")]))
            ]
        )
        try await registry.registerCustomActions(["inner": inner, "outer": outer])

        let descriptor = try #require(await registry.descriptor(named: "outer"))
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor)
        _ = try await descriptor.runJSON(.object(["method": .string("app-store")]), context)

        let captured = recorder.snapshot()
        #expect(captured.count == 1)
        #expect(captured[0] == .object(["track": .string("via-app-store")]))
    }

    // MARK: Integration — AISessionBuilder prompt enumeration

    @Test("agentPrompt enumerates declared custom actions with params and description")
    func agentPromptEnumeratesCustomActions() {
        let customActions: [String: CustomActionConfig] = [
            "build_and_sign": CustomActionConfig(
                description: "Shared build+sign sequence.",
                parameters: [
                    "method": CustomActionParameter(type: "string", required: true),
                    "track": CustomActionParameter(type: "string", defaultValue: .string("internal")),
                ],
                steps: [WorkflowStepConfig(action: "archive")]
            )
        ]

        let payload = AISessionBuilder().build(
            goal: .beta,
            inspection: Self.inspectionForPromptTest(),
            hasExistingShipfile: true,
            platform: .ios,
            customActions: customActions
        )

        let prompt = payload.agentPrompt
        #expect(prompt.contains("Custom actions:"))
        #expect(prompt.contains("Defined in this project:"))
        #expect(prompt.contains("build_and_sign"))
        #expect(prompt.contains("method"))
        #expect(prompt.contains("track"))
        #expect(prompt.contains("Shared build+sign sequence."))
        #expect(prompt.contains("Prefer invoking an existing custom action"))
    }

    @Test("agentPrompt omits 'Defined in this project' when no custom actions exist")
    func agentPromptOmitsEnumerationWhenEmpty() {
        let payload = AISessionBuilder().build(
            goal: .beta,
            inspection: Self.inspectionForPromptTest(),
            hasExistingShipfile: false,
            platform: .ios,
            customActions: [:]
        )
        #expect(payload.agentPrompt.contains("Custom actions:"))
        #expect(payload.agentPrompt.contains("Defined in this project:") == false)
    }

    // MARK: - Fixtures

    static func inspectionForPromptTest() -> ProjectInspection {
        ProjectInspection(
            rootPath: "/tmp/project",
            xcodeContainers: [.init(kind: "workspace", path: "App.xcworkspace")],
            preferredContainer: .init(kind: "workspace", path: "App.xcworkspace"),
            schemes: [
                .init(name: "App", containerPath: "App.xcworkspace", bundleID: "com.example.app", teamID: "TEAM12345", likelyRunnable: true)
            ],
            suggestedAppConfig: .init(workspace: "App.xcworkspace", scheme: "App", bundleID: "com.example.app", teamID: "TEAM12345"),
            existingShipfiles: [],
            fastlaneFiles: [],
            ciFiles: [],
            warnings: []
        )
    }

    static func descriptorsForValidator() -> [ActionDescriptor] {
        var descriptors: [ActionDescriptor] = [
            TestAction.descriptor(for: TestAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestAction.name)),
            ArchiveAction.descriptor(for: ArchiveAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: ArchiveAction.name)),
        ]
        #if os(macOS)
        descriptors.append(contentsOf: [
            ExportAction.descriptor(for: ExportAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: ExportAction.name)),
            TestFlightAction.descriptor(
                for: TestFlightAction(), optionSchema: BuiltInSchemaCatalog.optionSchema(for: TestFlightAction.name)),
        ])
        #endif
        return descriptors
    }

    static func validationDescriptorsForValidator() -> [ActionDescriptor] {
        BuiltInSchemaCatalog.validationActionSchemas().map { schema in
            ActionDescriptor(
                name: schema.name,
                description: schema.description,
                optionSchema: schema.options,
                runJSON: { _, _ in
                    ActionResultEnvelope(action: schema.name, status: "success", payload: nil)
                }
            )
        }
    }
}

// MARK: - Helpers

final class OptionsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [JSONValue] = []

    func record(_ value: JSONValue?) {
        lock.lock()
        defer { lock.unlock() }
        captured.append(value ?? .null)
    }

    func snapshot() -> [JSONValue] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}
