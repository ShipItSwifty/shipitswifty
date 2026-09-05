import ArgumentParser
import Foundation
import ShipItKit

/// AI-agent oriented session bootstrap — stable, versioned JSON contract.
///
/// Returns a single JSON payload containing everything an AI agent needs to guide a user
/// through configuring and running a ShipItSwifty workflow:
/// - detected app config with confidence and provenance
/// - missing required fields with secret descriptors
/// - suggested Shipfile.yml content
/// - readiness diagnosis with blocker list and signing risk
/// - the next deterministic step (command + reason)
/// - a recommended agent system prompt
/// - the single best follow-up question to ask the user
///
/// ## Usage
/// ```
/// shipit ai session
/// shipit ai session --goal release --path /path/to/project
/// shipit ai session --goal beta --platform android
/// ```
///
/// Always exits with code `2` when the project is not ready to run the requested workflow.
///
/// > Renamed from the top-level `shipit ai-session` in 0.7.0 to live under the `shipit ai`
/// > command group alongside `shipit ai prompt` and `shipit ai instructions`. There is no
/// > backwards-compatible alias — scripts and CI invoking `shipit ai-session` must be updated
/// > to `shipit ai session`.
struct AISessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Structured AI-agent session bootstrap — stable JSON contract (v\(AISessionBuilder.contractVersion))"
    )

    @OptionGroup var options: AISessionOptions

    @Option(name: .long, help: "Goal to optimize for: local, beta, or release")
    var goal: SuggestionGoal = .beta

    @Option(name: .long, help: "Root path to inspect (defaults to current directory)")
    var path: String = FileManager.default.currentDirectoryPath

    func run() async throws {
        // Pass through any user-defined custom actions so the generated agent
        // prompt can enumerate them and steer agents toward reuse.
        let payload = try await buildAISessionPayload(goal: goal, path: path, options: options)

        let reporter = JSONReporter()
        let envelope = ActionResultEnvelope(
            action: "ai session",
            status: payload.readiness.isReady ? "success" : "failure",
            payload: aiSessionPayloadJSON(payload)
        )
        print(try reporter.encode(envelope))

        if !payload.readiness.isReady {
            throw ExitCode(2)
        }
    }
}
