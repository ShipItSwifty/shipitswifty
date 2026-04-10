import Foundation

// MARK: - Inference metadata

/// How a configuration value was determined.
public enum InferenceSource: String, Codable, Sendable, Hashable {
    /// Directly read from Xcode build settings or project files.
    case detected
    /// Derived from naming conventions or project structure.
    case inferred
    /// A reasonable default was applied.
    case assumed
    /// Could not be determined; a placeholder or user input is needed.
    case unresolved
}

/// Confidence level for an inferred value.
public enum InferenceConfidence: String, Codable, Sendable, Hashable {
    case high
    case medium
    case low
}

/// A configuration value with full provenance — what was found, how, and why.
public struct InferredConfigEntry: Codable, Sendable, Hashable {
    /// Dot-separated Shipfile key path (e.g. `app.scheme`).
    public let keyPath: String
    /// The resolved value, or `nil` when unresolved.
    public let value: JSONValue?
    /// How the value was obtained.
    public let source: InferenceSource
    /// Confidence in the inferred value. `nil` when `source == .unresolved`.
    public let confidence: InferenceConfidence?
    /// Human-readable rationale for the source and confidence level.
    public let why: String

    public init(
        keyPath: String,
        value: JSONValue?,
        source: InferenceSource,
        confidence: InferenceConfidence? = nil,
        why: String
    ) {
        self.keyPath = keyPath
        self.value = value
        self.source = source
        self.confidence = confidence
        self.why = why
    }
}

// MARK: - Secrets

/// Describes a required secret: what it is, how to obtain it, and how to supply it.
///
/// Agents should use this to ask precise follow-up questions rather than requesting
/// raw secret values.
public struct SecretDescriptor: Codable, Sendable, Hashable {
    /// Shipfile config key path (e.g. `app_store_connect.key_id`).
    public let keyPath: String
    /// The environment variable that supplies this secret (e.g. `ASC_KEY_ID`).
    public let envVar: String
    /// Accepted value formats or representations.
    public let acceptedFormats: [String]
    /// Where the user can obtain this secret.
    public let exampleSource: String
    /// Whether a file path is preferred over an inline value.
    public let preferFile: Bool
    /// Human-readable description of the secret's purpose.
    public let description: String

    public init(
        keyPath: String,
        envVar: String,
        acceptedFormats: [String],
        exampleSource: String,
        preferFile: Bool,
        description: String
    ) {
        self.keyPath = keyPath
        self.envVar = envVar
        self.acceptedFormats = acceptedFormats
        self.exampleSource = exampleSource
        self.preferFile = preferFile
        self.description = description
    }
}

// MARK: - Ambiguities

/// A field where multiple valid options exist and the agent cannot auto-select.
///
/// The agent should surface these to the user and ask for confirmation before
/// generating or writing configuration.
public struct AmbiguityFlag: Codable, Sendable, Hashable {
    /// The Shipfile key path this ambiguity affects.
    public let field: String
    /// The candidate values that were discovered.
    public let options: [JSONValue]
    /// Human-readable description of the ambiguity.
    public let message: String

    public init(field: String, options: [JSONValue], message: String) {
        self.field = field
        self.options = options
        self.message = message
    }
}

// MARK: - Next action

/// The single next deterministic step the agent should take.
///
/// Agents should execute `command` (if present) or follow `reason` to make progress.
public struct NextAction: Codable, Sendable, Hashable {
    /// Stable machine identifier for the action kind.
    ///
    /// Known values: `resolve_ambiguity`, `resolve_blocker`, `create_shipfile`,
    /// `complete_config`, `run_workflow`.
    public let action: String
    /// The exact CLI command to run next, if applicable.
    public let command: String?
    /// Why this action was chosen as the next step.
    public let reason: String

    public init(action: String, command: String? = nil, reason: String) {
        self.action = action
        self.command = command
        self.reason = reason
    }
}

// MARK: - Readiness

/// Ready-to-run diagnosis for a specific workflow goal.
public struct AIReadiness: Codable, Sendable, Hashable {
    public let goal: String
    /// Whether all required config is in place to run the workflow.
    public let isReady: Bool
    /// Human-readable blockers that must be resolved before the workflow can run.
    public let blockers: [String]
    /// Required secrets for this goal, with descriptors for how to obtain them.
    public let missingSecrets: [SecretDescriptor]
    /// Signing complexity risk: `"low"`, `"medium"`, or `"high"`.
    public let signingRisk: String
    /// Ordered steps to resolve blockers and reach a runnable state.
    public let unblockSteps: [String]

    public init(
        goal: String,
        isReady: Bool,
        blockers: [String],
        missingSecrets: [SecretDescriptor],
        signingRisk: String,
        unblockSteps: [String]
    ) {
        self.goal = goal
        self.isReady = isReady
        self.blockers = blockers
        self.missingSecrets = missingSecrets
        self.signingRisk = signingRisk
        self.unblockSteps = unblockSteps
    }
}

// MARK: - Session payload

/// The full structured payload returned by `shipit ai-session`.
///
/// This is a stable, versioned JSON contract for AI agent consumption.
/// Check `version` before parsing to detect breaking changes.
///
/// ## Contract version history
/// - `"1"` — initial release
public struct AISessionPayload: Codable, Sendable, Hashable {
    /// Contract version. Increment on breaking payload changes.
    public let version: String
    /// The goal this session was built for.
    public let goal: String
    /// Inferred configuration entries with full provenance and confidence.
    public let appConfig: [InferredConfigEntry]
    /// Fields that are required for the goal but could not be resolved.
    public let missing: [SuggestedShipfile.MissingValue]
    /// Fields where multiple candidates exist and user confirmation is needed.
    public let ambiguities: [AmbiguityFlag]
    /// Suggested Shipfile.yml content — ready to write after reviewing `missing`.
    public let suggestedShipfile: String
    /// Ready-to-build diagnosis for the requested goal.
    public let readiness: AIReadiness
    /// The single next deterministic step the agent should take.
    public let nextAction: NextAction
    /// A concise system prompt the host agent should include in its context.
    public let agentPrompt: String
    /// The single most valuable question to ask the user, or `nil` if ready to proceed.
    public let nextQuestion: String?

    public init(
        version: String,
        goal: String,
        appConfig: [InferredConfigEntry],
        missing: [SuggestedShipfile.MissingValue],
        ambiguities: [AmbiguityFlag],
        suggestedShipfile: String,
        readiness: AIReadiness,
        nextAction: NextAction,
        agentPrompt: String,
        nextQuestion: String?
    ) {
        self.version = version
        self.goal = goal
        self.appConfig = appConfig
        self.missing = missing
        self.ambiguities = ambiguities
        self.suggestedShipfile = suggestedShipfile
        self.readiness = readiness
        self.nextAction = nextAction
        self.agentPrompt = agentPrompt
        self.nextQuestion = nextQuestion
    }
}
