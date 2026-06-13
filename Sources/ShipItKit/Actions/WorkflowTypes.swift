import Foundation
import Logging

/// A single step within a workflow, referencing a registered action by name.
///
/// Steps are defined in `Shipfile.yml` under `workflows:` and decoded into
/// `[WorkflowStep]` sequences for execution by `Workflow.run(context:registry:)`.
public struct WorkflowStep: Codable, Sendable {
    /// The registered action name to execute (e.g. `"build"`, `"testflight"`).
    public let action: String

    /// Options to forward to the action, decoded from YAML or JSON.
    public let options: JSONValue?

    /// Optional condition controlling whether the step runs.
    ///
    /// Reserved workflow tokens (e.g. `{{version_changed}}`) are substituted first, then
    /// the result is evaluated for truthiness (`true`/`1`/`yes`, case-insensitive). When
    /// non-nil and falsy, the step is skipped (recorded with status `"skipped"`) and the
    /// workflow continues.
    public let when: String?

    /// Creates a `WorkflowStep`.
    ///
    /// - Parameters:
    ///   - action: The registered action name to execute.
    ///   - options: Optional JSON options forwarded to the action.
    ///   - when: Optional truthy-token condition; when falsy the step is skipped.
    public init(action: String, options: JSONValue? = nil, when: String? = nil) {
        self.action = action
        self.options = options
        self.when = when
    }
}

/// A result builder for constructing workflow step sequences with Swift DSL syntax.
///
/// Supports conditionals, loops, and optional steps, enabling ergonomic
/// programmatic workflow construction alongside YAML-defined workflows.
///
/// ## Usage
/// ```swift
/// let workflow = Workflow("beta") {
///     WorkflowStep(action: "version", options: .object(["bump": .string("build")]))
///     WorkflowStep(action: "archive")
///     if uploadToTestFlight {
///         WorkflowStep(action: "testflight")
///     }
/// }
/// ```
@resultBuilder
public enum WorkflowBuilder {
    /// Builds a step sequence from varargs.
    public static func buildBlock(_ components: [WorkflowStep]...) -> [WorkflowStep] { components.flatMap { $0 } }

    /// Builds from an array of step arrays (e.g. from `for` loops).
    public static func buildArray(_ components: [[WorkflowStep]]) -> [WorkflowStep] { components.flatMap { $0 } }

    /// Handles `if` without `else` (returns empty if nil).
    public static func buildOptional(_ component: [WorkflowStep]?) -> [WorkflowStep] { component ?? [] }

    /// Handles the first branch of an `if/else`.
    public static func buildEither(first component: [WorkflowStep]) -> [WorkflowStep] { component }

    /// Handles the second branch of an `if/else`.
    public static func buildEither(second component: [WorkflowStep]) -> [WorkflowStep] { component }

    /// Wraps a single step in an array (to allow returning `WorkflowStep` directly).
    public static func buildExpression(_ step: WorkflowStep) -> [WorkflowStep] { [step] }
}

/// A named sequence of actions forming a release workflow.
///
/// Workflows are defined in `Shipfile.yml` or programmatically using the `@WorkflowBuilder` DSL.
///
/// ## Usage
/// ```swift
/// let beta = Workflow("beta") {
///     WorkflowStep(action: "version", options: .object(["bump": .string("build")]))
///     WorkflowStep(action: "archive")
///     WorkflowStep(action: "export")
///     WorkflowStep(action: "testflight")
/// }
/// let result = try await beta.run(context: context, registry: registry)
/// ```
public struct Workflow: Sendable {
    /// The unique workflow name, referenced by `shipit run <workflow>`.
    public let name: String

    /// The ordered sequence of steps in this workflow.
    public let steps: [WorkflowStep]

    /// Optional build variant override for all steps in this workflow.
    /// When set, overrides `config.androidBuildVariant` in the `ActionContext` passed to each step.
    public let buildVariant: String?

    /// Optional product flavor override for all steps in this workflow.
    /// When set, overrides `config.androidGradleProperties["flavor"]` in the `ActionContext`.
    public let flavor: String?

    private let logger = Logger.forType(subsystem: "ShipItSwifty", Workflow.self)

    /// Initialize from an explicit array (used by the YAML config decoder).
    ///
    /// - Parameters:
    ///   - name: The workflow identifier.
    ///   - steps: Array of steps to execute in order.
    ///   - buildVariant: Optional build variant override for all steps.
    ///   - flavor: Optional product flavor override for all steps.
    public init(_ name: String, steps: [WorkflowStep], buildVariant: String? = nil, flavor: String? = nil) {
        self.name = name
        self.steps = steps
        self.buildVariant = buildVariant
        self.flavor = flavor
    }

    /// Initialize using the `@WorkflowBuilder` result-builder DSL.
    ///
    /// - Parameters:
    ///   - name: The workflow identifier.
    ///   - buildVariant: Optional build variant override for all steps.
    ///   - flavor: Optional product flavor override for all steps.
    ///   - builder: A result builder closure producing workflow steps.
    public init(_ name: String, buildVariant: String? = nil, flavor: String? = nil, @WorkflowBuilder _ builder: () -> [WorkflowStep]) {
        self.name = name
        self.steps = builder()
        self.buildVariant = buildVariant
        self.flavor = flavor
    }

    /// Run all steps in this workflow sequentially.
    ///
    /// When the context has project generation configured and the output project
    /// does not exist, this method auto-generates the Xcode project before
    /// executing the first step that requires an Xcode container.
    ///
    /// - Parameters:
    ///   - context: Shared execution context passed to each action.
    ///   - registry: The action registry used to look up descriptors by name.
    /// - Returns: A `WorkflowResult` summarizing the outcomes of all steps.
    /// - Throws: The first error encountered (workflow execution stops on error).
    public func run(
        context: ActionContext,
        registry: ActionRegistry
    ) async throws -> WorkflowResult {
        logger.info("Starting workflow '\(name)' with \(steps.count) step(s)")
        var stepResults: [ActionResultEnvelope] = []
        let startTime = Date()

        // Apply workflow-level overrides to the context config
        let effectiveContext: ActionContext
        if buildVariant != nil || flavor != nil {
            let overriddenConfig = context.config.overriding(
                buildVariant: buildVariant,
                flavor: flavor
            )
            effectiveContext = context.withConfig(overriddenConfig)
            logger.info("Workflow '\(name)' overrides: build_variant=\(buildVariant ?? "(none)"), flavor=\(flavor ?? "(none)")")
        } else {
            effectiveContext = context
        }

        // Auto-generate project before running any Xcode-dependent steps
        #if os(macOS)
        if Self.requiresXcodeContainer(steps: steps, customActions: effectiveContext.config.customActions) {
            try await effectiveContext.ensureProjectGenerated()
        }
        #endif

        // Reserved-token resolver (`{{version}}`, `{{build_number}}`, `{{version_changed}}`).
        // Seed best-effort from the current versioning source so tokens resolve even when
        // referenced before a `version` step runs; updated after each step.
        var tokens = await Self.seededTokenResolver(steps: steps, context: effectiveContext)

        for (index, step) in steps.enumerated() {
            logger.info("Workflow '\(name)' step \(index + 1)/\(steps.count): \(step.action)")

            // Evaluate an optional `when:` condition after token substitution.
            if let condition = step.when {
                let resolved = tokens.substitute(in: condition)
                if !WorkflowTokenResolver.isTruthy(resolved) {
                    logger.info(
                        "Workflow '\(name)' step '\(step.action)' skipped (when: '\(condition)' → '\(resolved)')")
                    stepResults.append(
                        ActionResultEnvelope(action: step.action, status: "skipped", payload: nil))
                    continue
                }
            }

            guard let descriptor = await registry.descriptor(named: step.action) else {
                throw ShipItError.invalidConfiguration(
                    reason: "Workflow '\(name)': unknown action '\(step.action)'"
                )
            }

            let substitutedOptions = step.options.map { tokens.substitute($0) }
            let result = try await descriptor.runJSON(substitutedOptions, effectiveContext)
            stepResults.append(result)
            tokens.update(from: result)
            logger.info("Workflow '\(name)' step '\(step.action)' succeeded")
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.info("Workflow '\(name)' completed in \(String(format: "%.1f", duration))s")
        return WorkflowResult(workflowName: name, stepResults: stepResults, duration: duration)
    }

    /// Builds a token resolver seeded best-effort from the current versioning source.
    ///
    /// Seeding lets `{{version}}` / `{{build_number}}` resolve even when referenced before
    /// a `version` step runs. `{{version_changed}}` seeds to `false` (nothing has changed
    /// yet). Reading is skipped entirely when no step references a token, and any read
    /// failure is non-fatal — tokens simply remain unresolved until a `version` step
    /// supplies them.
    private static func seededTokenResolver(
        steps: [WorkflowStep],
        context: ActionContext
    ) async -> WorkflowTokenResolver {
        guard stepsReferenceTokens(steps) else { return WorkflowTokenResolver() }
        guard let preview = try? await VersionBumper(context: context).preview(options: .init(bump: .build))
        else { return WorkflowTokenResolver() }
        return WorkflowTokenResolver(values: [
            "version": preview.currentVersion,
            "build_number": preview.currentBuildNumber,
            "version_changed": "false",
        ])
    }

    /// Returns `true` when any step's `when` or `options` contains a `{{…}}` reference.
    private static func stepsReferenceTokens(_ steps: [WorkflowStep]) -> Bool {
        for step in steps {
            if step.when?.contains("{{") == true { return true }
            if let options = step.options, jsonContainsToken(options) { return true }
        }
        return false
    }

    private static func jsonContainsToken(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let s): return s.contains("{{")
        case .array(let items): return items.contains(where: jsonContainsToken)
        case .object(let dict): return dict.values.contains(where: jsonContainsToken)
        case .null, .bool, .int, .double: return false
        }
    }

    /// Actions that require an `.xcodeproj` or `.xcworkspace` to be present.
    private static let xcodeContainerActions: Set<String> = [
        "build", "test", "archive", "export", "version", "lint", "snapshot", "coverage",
    ]

    /// Returns `true` when any step in the workflow is an action that needs an Xcode container.
    private static func requiresXcodeContainer(
        steps: [WorkflowStep],
        customActions: [String: CustomActionConfig],
        visited: Set<String> = []
    ) -> Bool {
        for step in steps {
            if xcodeContainerActions.contains(step.action) {
                return true
            }

            guard let customAction = customActions[step.action], !visited.contains(step.action) else {
                continue
            }

            if requiresXcodeContainer(
                steps: customAction.steps.map { WorkflowStep(action: $0.action, options: $0.options) },
                customActions: customActions,
                visited: visited.union([step.action])
            ) {
                return true
            }
        }

        return false
    }
}

/// The result of executing a named workflow.
///
/// Contains the per-step results and overall execution duration.
public struct WorkflowResult: Codable, Sendable {
    /// The name of the workflow that was executed.
    public let workflowName: String

    /// Results for each step, in execution order.
    public let stepResults: [ActionResultEnvelope]

    /// Total wall-clock duration in seconds.
    public let duration: TimeInterval

    /// Whether all steps completed with `"success"` status.
    public var succeeded: Bool {
        stepResults.allSatisfy { $0.status == "success" }
    }

    /// Creates a `WorkflowResult`.
    ///
    /// - Parameters:
    ///   - workflowName: The name of the workflow that was executed.
    ///   - stepResults: Ordered results for each step.
    ///   - duration: Total wall-clock execution time in seconds.
    public init(workflowName: String, stepResults: [ActionResultEnvelope], duration: TimeInterval) {
        self.workflowName = workflowName
        self.stepResults = stepResults
        self.duration = duration
    }
}
