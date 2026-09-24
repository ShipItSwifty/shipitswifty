import Foundation

// MARK: - Agent skill commands

extension AndroidCLI {

    /// `android skills add [--all] [--agent=a,b] [--project=<dir>] [skill]` — Install Android
    /// agent skills into a project. **Mutating.** Never run automatically: install only skills the
    /// user asked for.
    ///
    /// - Parameters:
    ///   - skill: The skill to add; omit with `all: true` to add every skill.
    ///   - all: Add every available skill.
    ///   - agents: Agents to install for (e.g. `["claude", "gemini"]`). Defaults to all detected.
    ///   - project: Project directory. Defaults to the current directory.
    public func skillsAdd(skill: String? = nil, all: Bool = false, agents: [String] = [], project: String? = nil) -> Self {
        rawArguments(skillsArguments(operation: "add", skill: skill, all: all, agents: agents, project: project))
    }

    /// `android skills remove [--agent=a,b] [--project=<dir>] <skill>` — Remove an installed skill.
    /// **Mutating.**
    public func skillsRemove(skill: String, agents: [String] = [], project: String? = nil) -> Self {
        rawArguments(skillsArguments(operation: "remove", skill: skill, all: false, agents: agents, project: project))
    }

    /// `android skills list [--long] [--project=<dir>]` — List available and installed skills.
    public func skillsList(long: Bool = false, project: String? = nil) -> Self {
        var args = ["skills", "list"]
        if long { args.append("--long") }
        if let project { args.append("--project=\(project)") }
        return rawArguments(args)
    }

    /// `android skills find <keyword>` — Search skills by keyword.
    public func skillsFind(_ keyword: String) -> Self { rawArguments(["skills", "find", keyword]) }

    private func skillsArguments(operation: String, skill: String?, all: Bool, agents: [String], project: String?) -> [String] {
        var args = ["skills", operation]
        if all { args.append("--all") }
        if !agents.isEmpty { args.append("--agent=\(agents.joined(separator: ","))") }
        if let project { args.append("--project=\(project)") }
        if let skill { args.append(skill) }
        return args
    }
}
