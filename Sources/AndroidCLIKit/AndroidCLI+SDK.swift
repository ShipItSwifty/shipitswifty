import Foundation

// MARK: - SDK package commands

extension AndroidCLI {

    /// `android sdk install [flags] <package…>` — Install SDK packages. **Mutating.**
    ///
    /// - Parameters:
    ///   - packages: SDK package paths, e.g. `["platforms/android-35", "build-tools/35.0.0"]`.
    ///   - beta: Include the beta channel.
    ///   - canary: Include the canary channel.
    ///   - force: Reinstall even if already present.
    ///   - platform: Host platform override (e.g. `"linux"`).
    public func sdkInstall(
        packages: [String], beta: Bool = false, canary: Bool = false,
        force: Bool = false, platform: String? = nil
    ) -> Self {
        rawArguments(sdkArguments(operation: "install", values: packages, beta: beta, canary: canary, force: force, platform: platform))
    }

    /// `android sdk update [flags] [package]` — Update one package, or all when `package` is `nil`.
    /// **Mutating.**
    public func sdkUpdate(
        package: String? = nil, beta: Bool = false, canary: Bool = false,
        force: Bool = false, platform: String? = nil
    ) -> Self {
        rawArguments(
            sdkArguments(
                operation: "update", values: package.map { [$0] } ?? [], beta: beta, canary: canary, force: force, platform: platform))
    }

    /// `android sdk remove <package…>` — Uninstall SDK packages. **Mutating.**
    public func sdkRemove(packages: [String]) -> Self { rawArguments(["sdk", "remove"] + packages) }

    /// `android sdk list [flags] [pattern]` — List installed (or, with `all`, available) packages.
    ///
    /// - Parameters:
    ///   - pattern: Optional package filter.
    ///   - all: Include packages that are not installed.
    ///   - allVersions: Include every version rather than only the latest.
    ///   - beta: Include the beta channel.
    ///   - canary: Include the canary channel.
    public func sdkList(
        pattern: String? = nil, all: Bool = false, allVersions: Bool = false, beta: Bool = false, canary: Bool = false
    ) -> Self {
        var args = ["sdk", "list"]
        if all { args.append("--all") }
        if allVersions { args.append("--all-versions") }
        if beta { args.append("--beta") }
        if canary { args.append("--canary") }
        if let pattern { args.append(pattern) }
        return rawArguments(args)
    }

    private func sdkArguments(operation: String, values: [String], beta: Bool, canary: Bool, force: Bool, platform: String?) -> [String] {
        var args = ["sdk", operation]
        if beta { args.append("--beta") }
        if canary { args.append("--canary") }
        if force { args.append("--force") }
        if let platform { args.append("--platform=\(platform)") }
        return args + values
    }
}
