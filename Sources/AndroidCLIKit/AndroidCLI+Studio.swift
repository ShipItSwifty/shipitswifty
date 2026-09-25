import Foundation

// MARK: - Android Studio integration commands
//
// These talk to a running Android Studio instance. `pid` selects the Studio process when several
// are running; `project` selects the open project.

extension AndroidCLI {

    /// `android studio check` — Verify that a reachable Android Studio instance is running.
    public func studioCheck() -> Self { rawArguments(["studio", "check"]) }

    /// `android studio analyze-file <path>` — Report Studio inspections for one file.
    public func studioAnalyzeFile(path: String, pid: Int? = nil, project: String? = nil) -> Self {
        rawArguments(studioArguments(operation: "analyze-file", pid: pid, project: project) + [path])
    }

    /// `android studio find-declaration <symbol>` — Resolve where a symbol is declared.
    ///
    /// - Parameters:
    ///   - symbol: The symbol to resolve.
    ///   - contextFile: File that provides the resolution context (imports, package).
    ///   - short: Emit a compact result.
    public func studioFindDeclaration(
        symbol: String, contextFile: String? = nil, short: Bool = false, pid: Int? = nil, project: String? = nil
    ) -> Self {
        var args = studioArguments(operation: "find-declaration", pid: pid, project: project)
        if short { args.append("--short") }
        if let contextFile { args.append("--context-file=\(contextFile)") }
        return rawArguments(args + [symbol])
    }

    /// `android studio find-usages <symbol>` — List usages of a symbol across the project.
    public func studioFindUsages(symbol: String, short: Bool = false, pid: Int? = nil, project: String? = nil) -> Self {
        var args = studioArguments(operation: "find-usages", pid: pid, project: project)
        if short { args.append("--short") }
        return rawArguments(args + [symbol])
    }

    /// `android studio open-file <path>` — Open a file in the Studio editor.
    public func studioOpenFile(path: String, pid: Int? = nil, project: String? = nil) -> Self {
        rawArguments(studioArguments(operation: "open-file", pid: pid, project: project) + [path])
    }

    /// `android studio render-compose-preview <path> <composable>` — Render a `@Preview`
    /// composable to an image, optionally printing its semantics tree.
    public func studioRenderComposePreview(
        path: String, composable: String, outputImageFile: String? = nil,
        printSemantics: Bool = false, pid: Int? = nil, project: String? = nil
    ) -> Self {
        var args = studioArguments(operation: "render-compose-preview", pid: pid, project: project)
        if printSemantics { args.append("--print-semantics") }
        if let outputImageFile { args.append("--output-image-file=\(outputImageFile)") }
        return rawArguments(args + [path, composable])
    }

    /// `android studio version-lookup <artifact…>` — Look up the latest versions of Maven
    /// artifacts (e.g. `"androidx.compose.ui:ui"`).
    public func studioVersionLookup(artifacts: [String], pid: Int? = nil, project: String? = nil) -> Self {
        rawArguments(studioArguments(operation: "version-lookup", pid: pid, project: project) + artifacts)
    }

    private func studioArguments(operation: String, pid: Int?, project: String?) -> [String] {
        var args = ["studio", operation]
        if let pid { args.append("--pid=\(pid)") }
        if let project { args.append("--project=\(project)") }
        return args
    }
}
