import Foundation

// MARK: - Validation types

/// The context passed to each `ActionValidationRule` during Shipfile validation.
///
/// Provides access to the step's resolved options, its position in the workflow,
/// the surrounding steps, and the fully-resolved `ResolvedConfig` for the Shipfile.
public struct ActionValidationContext: Sendable {
    /// Parsed options for this workflow step (`step.options` object, or empty).
    public let options: [String: JSONValue]

    /// Zero-based index of this step within its parent workflow.
    public let stepIndex: Int

    /// All steps in the parent workflow, useful for checking step ordering dependencies.
    public let allSteps: [WorkflowStepConfig]

    /// The fully-resolved configuration for the Shipfile being validated.
    public let config: ResolvedConfig

    public init(
        options: [String: JSONValue],
        stepIndex: Int,
        allSteps: [WorkflowStepConfig],
        config: ResolvedConfig
    ) {
        self.options = options
        self.stepIndex = stepIndex
        self.allSteps = allSteps
        self.config = config
    }
}

/// A single semantic validation rule attached to an `ActionDescriptor`.
///
/// Rules are evaluated during `shipit validate yml` for every workflow step that
/// references the owning action.  A rule may be scoped to a specific set of
/// platforms; if `platforms` is non-nil, the rule is skipped when the resolved
/// platform is not in that set.
///
/// Return `nil` to indicate the rule passed; return a `ValidationIssue` to
/// report an error or warning.
public struct ActionValidationRule: Sendable {
    /// Optional platform scope.  `nil` means the rule applies to all platforms.
    public let platforms: Set<Platform>?

    /// Closure that evaluates the rule.  Returns `nil` on success, a
    /// `ValidationIssue` on failure.
    public let evaluate: @Sendable (ActionValidationContext) -> ValidationIssue?

    /// Creates an `ActionValidationRule`.
    ///
    /// - Parameters:
    ///   - platforms: Platforms this rule applies to, or `nil` for all platforms.
    ///   - evaluate: Closure returning `nil` (pass) or a `ValidationIssue` (fail).
    public init(
        platforms: Set<Platform>? = nil,
        evaluate: @Sendable @escaping (ActionValidationContext) -> ValidationIssue?
    ) {
        self.platforms = platforms
        self.evaluate = evaluate
    }

    /// Evaluates the rule, respecting its platform scope.
    ///
    /// Returns `nil` when the rule is not applicable for the given platform or
    /// when the underlying evaluation passes.
    func evaluate(context: ActionValidationContext) -> ValidationIssue? {
        if let platforms, !platforms.contains(context.config.platform) {
            return nil
        }
        return evaluate(context)
    }
}

// MARK: - Action protocol

/// A discrete, composable unit of work in the release pipeline.
///
/// Actions are the fundamental building block of ShipItSwifty.
/// Each action performs a single well-defined task (build, sign, upload, etc.)
/// and can be composed into workflows for release automation.
///
/// ## Conformance
/// Provide a human-readable `name`, declare `Options` for configuration,
/// and implement `run(with:context:)` to perform the work.
///
/// ## Example
/// ```swift
/// struct MyAction: Action {
///     static let name = "my-action"
///     static let description = "Does something useful"
///     struct Options: Codable, Sendable { var verbose: Bool = false }
///     struct Result: Codable, Sendable { var message: String }
///     func run(with options: Options, context: ActionContext) async throws -> Result {
///         return Result(message: "Done!")
///     }
/// }
/// ```
public protocol Action: Sendable {
    /// The typed configuration for this action, decoded from Shipfile YAML or CLI flags.
    associatedtype Options: Codable & Sendable

    /// The typed result returned after this action completes.
    associatedtype Result: Codable & Sendable

    /// Human-readable identifier, e.g. `"build"`, `"upload"`.
    static var name: String { get }

    /// Long-form description for `--help` output and documentation.
    static var description: String { get }

    /// Execute the action with the given options.
    ///
    /// - Parameters:
    ///   - options: Decoded from Shipfile, CLI flags, or environment.
    ///   - context: Shared execution context (shell, logger, config).
    /// - Returns: A typed, `Codable` result.
    /// - Throws: `ShipItError` variants appropriate to the action type.
    func run(with options: Options, context: ActionContext) async throws -> Result
}

extension Action {
    /// Creates a type-erased `ActionDescriptor` for registering this action in `ActionRegistry`.
    ///
    /// The descriptor captures the action's `run(with:context:)` implementation,
    /// decoding JSON options at runtime and wrapping results in `ActionResultEnvelope`.
    ///
    /// - Parameters:
    ///   - instance: An instance of the action used to capture its `run` implementation.
    ///   - optionSchema: Schema fields describing the action's configurable options.
    ///   - platforms: Platforms this action is supported on, or `nil` for all platforms.
    ///   - validationRules: Semantic validation rules evaluated during `shipit validate yml`.
    public static func descriptor(
        for instance: Self,
        optionSchema: [SchemaField] = [],
        platforms: Set<Platform>? = nil,
        validationRules: [ActionValidationRule] = []
    ) -> ActionDescriptor {
        ActionDescriptor(
            name: Self.name,
            description: Self.description,
            optionSchema: optionSchema,
            platforms: platforms,
            validationRules: validationRules,
            runJSON: { optionsJSON, context in
                let options: Options
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let json = optionsJSON {
                    let data = try JSONEncoder().encode(json)
                    options = try decoder.decode(Options.self, from: data)
                } else {
                    let data = try JSONEncoder().encode(JSONValue.object([:]))
                    options = try decoder.decode(Options.self, from: data)
                }
                let result = try await instance.run(with: options, context: context)
                let resultData = try JSONEncoder().encode(result)
                let resultJSON = try JSONDecoder().decode(JSONValue.self, from: resultData)
                return ActionResultEnvelope(action: Self.name, status: "success", payload: resultJSON)
            }
        )
    }
}

/// Type-erased registration metadata used by CLI commands, Shipfile workflows,
/// and plugins to resolve actions by name at runtime.
public struct ActionDescriptor: Sendable {
    /// The unique action name (matches `Action.name`).
    public let name: String

    /// Human-readable description of the action.
    public let description: String

    /// Machine-readable workflow option schema for this action.
    public let optionSchema: [SchemaField]

    /// The platforms this action supports.  `nil` means supported on all platforms.
    public let platforms: Set<Platform>?

    /// Semantic validation rules evaluated during `shipit validate yml` for every
    /// workflow step that references this action.
    public let validationRules: [ActionValidationRule]

    /// Type-erased execution closure. Accepts optional JSON options and returns a result envelope.
    public let runJSON: @Sendable (_ options: JSONValue?, _ context: ActionContext) async throws -> ActionResultEnvelope

    /// Creates an `ActionDescriptor`.
    ///
    /// - Parameters:
    ///   - name: The unique identifier for this action.
    ///   - description: Human-readable description.
    ///   - optionSchema: Schema fields describing the action's configurable options.
    ///   - platforms: Platforms this action supports, or `nil` for all platforms.
    ///   - validationRules: Semantic validation rules for this action.
    ///   - runJSON: Type-erased execution closure.
    public init(
        name: String,
        description: String,
        optionSchema: [SchemaField] = [],
        platforms: Set<Platform>? = nil,
        validationRules: [ActionValidationRule] = [],
        runJSON: @Sendable @escaping (_ options: JSONValue?, _ context: ActionContext) async throws -> ActionResultEnvelope
    ) {
        self.name = name
        self.description = description
        self.optionSchema = optionSchema
        self.platforms = platforms
        self.validationRules = validationRules
        self.runJSON = runJSON
    }
}

/// Standardized result wrapper emitted by the CLI and workflow runner.
///
/// Encodes action outcomes as a JSON-serializable envelope for `--output json` mode.
public struct ActionResultEnvelope: Codable, Sendable {
    /// The name of the action that produced this result.
    public let action: String

    /// Outcome status: `"success"` or `"failure"`.
    public let status: String

    /// The typed result payload, or `nil` for void-result actions.
    public let payload: JSONValue?

    /// Creates an `ActionResultEnvelope`.
    ///
    /// - Parameters:
    ///   - action: The name of the action that produced this result.
    ///   - status: Outcome string — `"success"` or `"failure"`.
    ///   - payload: Optional typed result payload.
    public init(action: String, status: String, payload: JSONValue?) {
        self.action = action
        self.status = status
        self.payload = payload
    }
}
