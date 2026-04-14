import OSLog

/// A single step within a workflow, referencing a registered action by name.
///
/// Steps are defined in `Shipfile.yml` under `workflows:` and decoded into
/// `[WorkflowStep]` sequences for execution by `Workflow.run(context:registry:)`.
public struct WorkflowStep: Codable, Sendable {
    /// The registered action name to execute (e.g. `"build"`, `"testflight"`).
    public let action: String

    /// Options to forward to the action, decoded from YAML or JSON.
    public let options: JSONValue?

    /// Creates a `WorkflowStep`.
    ///
    /// - Parameters:
    ///   - action: The registered action name to execute.
    ///   - options: Optional JSON options forwarded to the action.
    public init(action: String, options: JSONValue? = nil) {
        self.action = action
        self.options = options
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

    private let logger = Logger.forType(subsystem: "ShipItSwifty", Workflow.self)

    /// Initialize from an explicit array (used by the YAML config decoder).
    ///
    /// - Parameters:
    ///   - name: The workflow identifier.
    ///   - steps: Array of steps to execute in order.
    public init(_ name: String, steps: [WorkflowStep]) {
        self.name = name
        self.steps = steps
    }

    /// Initialize using the `@WorkflowBuilder` result-builder DSL.
    ///
    /// - Parameters:
    ///   - name: The workflow identifier.
    ///   - builder: A result builder closure producing workflow steps.
    public init(_ name: String, @WorkflowBuilder _ builder: () -> [WorkflowStep]) {
        self.name = name
        self.steps = builder()
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

        // Auto-generate project before running any Xcode-dependent steps
        if Self.requiresXcodeContainer(steps: steps) {
            try await context.ensureProjectGenerated()
        }

        for (index, step) in steps.enumerated() {
            logger.info("Workflow '\(name)' step \(index + 1)/\(steps.count): \(step.action)")

            guard let descriptor = await registry.descriptor(named: step.action) else {
                throw ShipItError.invalidConfiguration(
                    reason: "Workflow '\(name)': unknown action '\(step.action)'"
                )
            }

            let result = try await descriptor.runJSON(step.options, context)
            stepResults.append(result)
            logger.info("Workflow '\(name)' step '\(step.action)' succeeded")
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.info("Workflow '\(name)' completed in \(String(format: "%.1f", duration))s")
        return WorkflowResult(workflowName: name, stepResults: stepResults, duration: duration)
    }

    /// Actions that require an `.xcodeproj` or `.xcworkspace` to be present.
    private static let xcodeContainerActions: Set<String> = [
        "build", "test", "archive", "export", "version", "lint", "snapshot", "coverage",
    ]

    /// Returns `true` when any step in the workflow is an action that needs an Xcode container.
    private static func requiresXcodeContainer(steps: [WorkflowStep]) -> Bool {
        steps.contains { xcodeContainerActions.contains($0.action) }
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
