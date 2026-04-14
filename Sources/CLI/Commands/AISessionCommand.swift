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
/// shipit ai-session
/// shipit ai-session --goal release --path /path/to/project
/// shipit ai-session --goal beta --platform android
/// ```
///
/// Always exits with code `2` when the project is not ready to run the requested workflow.
struct AISessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai-session",
        abstract: "Structured AI-agent session bootstrap — stable JSON contract (v\(AISessionBuilder.contractVersion))"
    )

    @OptionGroup var options: AIBootstrapOptions

    @Option(name: .long, help: "Goal to optimize for: local, beta, or release")
    var goal: SuggestionGoal = .beta

    @Option(name: .long, help: "Root path to inspect (defaults to current directory)")
    var path: String = FileManager.default.currentDirectoryPath

    func run() async throws {
        let inspection = try await ProjectInspector(rootPath: path).inspect()
        let resolvedShipfilePath = URL(fileURLWithPath: path)
            .appendingPathComponent(options.shipfile).path
        let hasExistingShipfile = FileManager.default.fileExists(atPath: resolvedShipfilePath)

        let platform = options.platform ?? autoDetectPlatform(at: path)

        // Pass through any user-defined custom actions so the generated agent
        // prompt can enumerate them and steer agents toward reuse.
        let customActions: [String: CustomActionConfig]
        if hasExistingShipfile {
            let resolver = ConfigResolver()
            let resolved = try? await resolver.resolve(
                cliOptions: CLIOptions(ci: options.ci, platform: platform),
                shipfilePath: resolvedShipfilePath
            )
            customActions = resolved?.customActions ?? [:]
        } else {
            customActions = [:]
        }

        let payload = AISessionBuilder().build(
            goal: goal,
            inspection: inspection,
            hasExistingShipfile: hasExistingShipfile,
            platform: platform,
            customActions: customActions
        )

        let reporter = JSONReporter()
        let envelope = ActionResultEnvelope(
            action: "ai-session",
            status: payload.readiness.isReady ? "success" : "failure",
            payload: aiSessionPayloadJSON(payload)
        )
        print(try reporter.encode(envelope))

        if !payload.readiness.isReady {
            throw ExitCode(2)
        }
    }

    /// Auto-detect platform from project files at `rootPath`.
    ///
    /// Rules (first match wins):
    /// - `gradlew` or `build.gradle.kts` present → `.android`
    /// - `*.xcworkspace` or `*.xcodeproj` present → `.ios`
    /// - Default → `.ios`
    private func autoDetectPlatform(at rootPath: String) -> Platform {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: rootPath) else { return .ios }
        if contents.contains("gradlew") || contents.contains("build.gradle.kts") {
            return .android
        }
        if contents.contains(where: { $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".xcodeproj") }) {
            return .ios
        }
        return .ios
    }
}

