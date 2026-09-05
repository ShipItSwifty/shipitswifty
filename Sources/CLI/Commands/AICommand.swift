import ArgumentParser
import Foundation
import ShipItKit

/// Parent command grouping ShipItSwifty's AI-agent-oriented surface.
///
/// `shipit ai` is the entrypoint an agent (or a human driving one) should discover first —
/// `shipit ai session` bootstraps a machine-readable session against the current project,
/// `shipit ai prompt` prints just the recommended system prompt for that project,
/// `shipit ai instructions` prints ShipItSwifty's own operating guidance for agents, and
/// `shipit ai skills` prints curated, task-oriented playbooks for common jobs (React Native
/// setup, Firebase distribution, fastlane migration, KMP, custom actions). None of these
/// (except `session`) require a project to already exist.
///
/// ## Usage
/// ```
/// shipit ai session --goal beta
/// shipit ai prompt --goal beta
/// shipit ai instructions
/// shipit ai skills list
/// shipit ai skills show react-native-setup
/// ```
struct AICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai",
        abstract: "AI-agent oriented commands: session bootstrap, system prompt, instructions, and skills",
        subcommands: [
            AISessionCommand.self,
            AIPromptCommand.self,
            AIInstructionsCommand.self,
            AISkillsCommand.self,
        ],
        defaultSubcommand: AISessionCommand.self
    )
}

/// Prints just the recommended agent system prompt for the current project — the `agentPrompt`
/// field of `shipit ai session`'s payload, without the rest of the session contract.
///
/// Useful when a driving agent already has its own way of discovering project state and only
/// needs the ready-made prompt text to seed a sub-session or hand to another model.
///
/// ## Usage
/// ```
/// shipit ai prompt
/// shipit ai prompt --goal release --path /path/to/project
/// ```
struct AIPromptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prompt",
        abstract: "Print the recommended AI agent system prompt for the current project"
    )

    @OptionGroup var options: AISessionOptions

    @Option(name: .long, help: "Goal to optimize for: local, beta, or release")
    var goal: SuggestionGoal = .beta

    @Option(name: .long, help: "Root path to inspect (defaults to current directory)")
    var path: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Output format: human | json")
    var output: OutputFormat = .human

    func run() async throws {
        let payload = try await buildAISessionPayload(goal: goal, path: path, options: options)

        switch output {
        case .human:
            print(payload.agentPrompt)
        case .json:
            let reporter = JSONReporter()
            let envelope = ActionResultEnvelope(
                action: "ai prompt",
                status: "success",
                payload: .object(["agentPrompt": .string(payload.agentPrompt)])
            )
            print(try reporter.encode(envelope))
        }
    }
}

/// Prints ShipItSwifty's own operating guidance for AI agents — how to discover this tool,
/// which command is the canonical entrypoint, and the hard invariants agents should not violate.
///
/// Unlike `shipit ai session` and `shipit ai prompt`, this performs no project inspection: it is
/// static guidance about the tool itself, safe to run before a Shipfile or even a project exists.
/// A repository's own `AGENTS.md`, when present, is the authoritative source for project-specific
/// conventions — this command covers the tool, not the project.
///
/// ## Usage
/// ```
/// shipit ai instructions
/// shipit ai instructions --output json
/// ```
struct AIInstructionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "instructions",
        abstract: "Print ShipItSwifty's operating guidance for AI agents"
    )

    @Option(name: .long, help: "Output format: human | json")
    var output: OutputFormat = .human

    func run() throws {
        switch output {
        case .human:
            print(Self.instructionsText)
        case .json:
            let reporter = JSONReporter()
            let envelope = ActionResultEnvelope(
                action: "ai instructions",
                status: "success",
                payload: .object(["instructions": .string(Self.instructionsText)])
            )
            print(try reporter.encode(envelope))
        }
    }

    static let instructionsText = """
        # Working with ShipItSwifty as an agent

        1. Start with `shipit ai session --goal <local|beta|release>` from the project root. It \
        inspects the project, tells you what's already configured, what's missing, and returns a \
        ready-made system prompt (also available alone via `shipit ai prompt`) plus the single next \
        command to run. This is the canonical entrypoint — prefer it over guessing a workflow by \
        hand.
        2. If a Shipfile already exists, run `shipit doctor` and `shipit validate yml` before making \
        changes — they report drift and schema errors that are cheaper to fix before a build than \
        after one.
        3. Use `shipit schema --output json` (optionally `--workflow <goal>`) to get the exact \
        options each action accepts — do not guess option names or types from memory.
        4. Prefer `--dry-run --output json` on `shipit run <workflow>` to preview the resolved step \
        list before executing anything that builds, signs, or uploads.
        5. If the project's own `AGENTS.md` exists, its guidance for that specific codebase takes \
        precedence over general assumptions about ShipItSwifty's defaults.
        6. For a common job (React Native/Expo setup, Firebase distribution, migrating a \
        Fastfile, KMP dual-platform, custom actions), check `shipit ai skills list` before \
        working it out from the full reference docs — a matching playbook gives the exact \
        steps and keys involved.

        Hard invariants (do not work around these):
        - Never invoke `xcodebuild`, `gradlew`, or other build tools directly when a `shipit` action \
        exists for the same purpose — ShipIt's actions add capped concurrency, retry, and reporting \
        that a direct invocation skips.
        - Never hardcode credentials into `Shipfile.yml`. Use `${ENV_VAR}` expansion and the \
        documented environment variables (see `shipit env`).
        - A workflow name must be run with `shipit run <name>`, not assembled by chaining individual \
        actions unless that's what the user explicitly asked for.
        """
}

/// Shared session-payload construction used by both `shipit ai session` and `shipit ai prompt`.
func buildAISessionPayload(
    goal: SuggestionGoal, path: String, options: AISessionOptions
) async throws -> AISessionPayload {
    let inspection = try await ProjectInspector(rootPath: path).inspect()
    let resolvedShipfilePath = URL(fileURLWithPath: path)
        .appendingPathComponent(options.shipfile).path
    let hasExistingShipfile = FileManager.default.fileExists(atPath: resolvedShipfilePath)

    let platform = options.platform ?? autoDetectAIPlatform(at: path)

    let customActions: [String: CustomActionConfig]
    if hasExistingShipfile {
        let resolver = ConfigResolver()
        let resolved = try? await resolver.resolve(
            cliOptions: CLIOptions(ci: false, platform: platform),
            shipfilePath: resolvedShipfilePath
        )
        customActions = resolved?.customActions ?? [:]
    } else {
        customActions = [:]
    }

    return AISessionBuilder().build(
        goal: goal,
        inspection: inspection,
        hasExistingShipfile: hasExistingShipfile,
        platform: platform,
        customActions: customActions
    )
}

/// Auto-detect platform from project files at `rootPath`.
///
/// Rules (first match wins):
/// - `gradlew` or `build.gradle.kts` present → `.android`
/// - `*.xcworkspace` or `*.xcodeproj` present → `.ios`
/// - Default → `.ios`
func autoDetectAIPlatform(at rootPath: String) -> Platform {
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

/// Parent command for curated, built-in agent playbooks.
///
/// This is a fixed, in-binary catalog (`AISkillsCatalog`) — not an installable package
/// registry. There is no `install`/`add` subcommand because there is nothing to install:
/// every playbook already ships in the `shipit` binary.
///
/// ## Usage
/// ```
/// shipit ai skills list
/// shipit ai skills show react-native-setup
/// ```
struct AISkillsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "Curated, task-oriented agent playbooks (built-in, no installation)",
        subcommands: [
            AISkillsListCommand.self,
            AISkillsShowCommand.self,
        ],
        defaultSubcommand: AISkillsListCommand.self
    )
}

/// Lists the built-in agent playbooks.
struct AISkillsListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available agent playbooks"
    )

    @Option(name: .long, help: "Output format: human | json")
    var output: OutputFormat = .human

    func run() throws {
        switch output {
        case .human:
            let idWidth = AISkillsCatalog.all.map(\.id.count).max() ?? 0
            for skill in AISkillsCatalog.all {
                print("\(skill.id.padding(toLength: idWidth, withPad: " ", startingAt: 0))  \(skill.summary)")
            }
            print("\nRun `shipit ai skills show <id>` for the full playbook.")
        case .json:
            let reporter = JSONReporter()
            let skills: JSONValue = .array(
                AISkillsCatalog.all.map {
                    .object(["id": .string($0.id), "title": .string($0.title), "summary": .string($0.summary)])
                })
            let envelope = ActionResultEnvelope(
                action: "ai skills list",
                status: "success",
                payload: .object(["skills": skills])
            )
            print(try reporter.encode(envelope))
        }
    }
}

/// Prints one built-in agent playbook by id.
struct AISkillsShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print one agent playbook"
    )

    @Argument(help: "Playbook id, from `shipit ai skills list`")
    var id: String

    @Option(name: .long, help: "Output format: human | json")
    var output: OutputFormat = .human

    func run() throws {
        guard let skill = AISkillsCatalog.skill(id: id) else {
            let available = AISkillsCatalog.all.map(\.id).joined(separator: ", ")
            throw ValidationError("Unknown skill '\(id)'. Available skills: \(available)")
        }

        switch output {
        case .human:
            print(skill.content)
        case .json:
            let reporter = JSONReporter()
            let envelope = ActionResultEnvelope(
                action: "ai skills show",
                status: "success",
                payload: .object(["id": .string(skill.id), "title": .string(skill.title), "content": .string(skill.content)])
            )
            print(try reporter.encode(envelope))
        }
    }
}
