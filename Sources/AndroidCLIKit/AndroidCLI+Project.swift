import Foundation

// MARK: - Project, environment, and documentation commands

extension AndroidCLI {

    /// `android create --name=<name> --output=<dir> [--minSdk=<n>] [--verbose] [template]` —
    /// Scaffold a new Android project. **Mutating.**
    ///
    /// - Parameters:
    ///   - name: Application name.
    ///   - output: Directory to create the project in. Defaults to the current directory.
    ///   - template: Optional template name (see ``listTemplates()``).
    ///   - minSDK: Optional minimum SDK level.
    ///   - verbose: Emit verbose output.
    public func create(
        name: String,
        output: String = ".",
        template: String? = nil,
        minSDK: Int? = nil,
        verbose: Bool = false
    ) -> Self {
        var args = ["create", "--name=\(name)", "--output=\(output)"]
        if let minSDK { args.append("--minSdk=\(minSDK)") }
        if verbose { args.append("--verbose") }
        if let template { args.append(template) }
        return rawArguments(args)
    }

    /// `android create --list` — List available project templates.
    public func listTemplates() -> Self { rawArguments(["create", "--list"]) }

    /// `android describe [--project_dir=<dir>]` — Describe the project's modules, variants,
    /// and build outputs.
    public func describe(projectDirectory: String? = nil) -> Self {
        rawArguments(["describe"] + (projectDirectory.map { ["--project_dir=\($0)"] } ?? []))
    }

    /// `android info [field]` — Print environment information (SDK location, versions). Parse
    /// the `key: value` output with ``AndroidCLIOutputParser/keyValues(from:)``.
    public func info(field: String? = nil) -> Self { rawArguments(["info"] + (field.map { [$0] } ?? [])) }

    /// `android init` — Initialize AndroidCLI for the current environment. **Mutating.**
    public func initialize() -> Self { rawArguments(["init"]) }

    /// `android docs search <query>` — Search Android developer documentation.
    public func docsSearch(_ query: String) -> Self { rawArguments(["docs", "search", query]) }

    /// `android docs fetch <url>` — Fetch one documentation page as text.
    public func docsFetch(_ url: String) -> Self { rawArguments(["docs", "fetch", url]) }
}
