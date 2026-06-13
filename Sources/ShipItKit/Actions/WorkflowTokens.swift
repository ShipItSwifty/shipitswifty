import Foundation

/// Resolves reserved workflow interpolation tokens inside step `options` and `when`
/// values at run time.
///
/// Unlike composite-action `{{param.NAME}}` substitution (see ``CompositeAction``), these
/// tokens are produced by the workflow itself as it runs — chiefly the marketing version
/// and build number emitted by a `version` step — and fed into later steps. This lets a
/// release workflow tag with the freshly-bumped version without external glue:
///
/// ```yaml
/// - action: version
///   options: { bump: patch }
/// - action: git
///   when: "{{version_changed}}"
///   options: { operation: tag, tagName: "v{{version}}" }
/// ```
///
/// Recognized tokens:
/// - `{{version}}` — the marketing version (e.g. `1.2.3`).
/// - `{{build_number}}` — the build number (e.g. `42`).
/// - `{{version_changed}}` — `true`/`false`: whether the marketing version changed.
///
/// Resolution is scoped to **top-level workflow steps**. Tokens are recognized by an
/// allowlist of names; any other `{{…}}` reference (including composite `{{param.X}}`) is
/// left untouched so it can be handled by its own mechanism or surface downstream.
struct WorkflowTokenResolver: Sendable {
    /// Reserved token names this resolver substitutes.
    static let reservedTokens: Set<String> = ["version", "build_number", "version_changed"]

    /// Current token values, keyed by token name.
    private var values: [String: String]

    /// Creates a resolver with optional seed values (e.g. from the versioning source).
    init(values: [String: String] = [:]) {
        self.values = values
    }

    /// Token names that are reserved but have no value yet (referenced too early).
    /// Used by callers to emit a single deterministic warning.
    func unresolvedReferences(in string: String) -> Set<String> {
        var out: Set<String> = []
        forEachToken(in: string) { name in
            if Self.reservedTokens.contains(name), values[name] == nil {
                out.insert(name)
            }
        }
        return out
    }

    /// Updates the token map from a completed step's result envelope.
    ///
    /// Captures `version`, `buildNumber`, and `versionChanged` from a `version` step's
    /// payload (encoded camelCase by `runJSON`).
    mutating func update(from envelope: ActionResultEnvelope) {
        guard envelope.action == VersionAction.name,
            case .object(let payload)? = envelope.payload
        else { return }
        if let v = payload["version"].flatMap(Self.scalarString) { values["version"] = v }
        if let b = payload["buildNumber"].flatMap(Self.scalarString) { values["build_number"] = b }
        if let c = payload["versionChanged"].flatMap(Self.scalarString) { values["version_changed"] = c }
    }

    // MARK: - Substitution

    /// Recursively walks `value`, replacing reserved tokens in string leaves.
    func substitute(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let s):
            return .string(substitute(in: s))
        case .array(let items):
            return .array(items.map { substitute($0) })
        case .object(let dict):
            var out: [String: JSONValue] = [:]
            for (k, v) in dict { out[k] = substitute(v) }
            return .object(out)
        case .null, .bool, .int, .double:
            return value
        }
    }

    /// Replaces reserved `{{token}}` references within a single string. Unknown or
    /// not-yet-resolved tokens are left literal so the reference surfaces rather than
    /// silently expanding to empty.
    func substitute(in input: String) -> String {
        var result = ""
        var cursor = input.startIndex
        while cursor < input.endIndex {
            guard let openRange = input.range(of: "{{", range: cursor..<input.endIndex) else {
                result.append(contentsOf: input[cursor..<input.endIndex])
                break
            }
            result.append(contentsOf: input[cursor..<openRange.lowerBound])

            guard let closeRange = input.range(of: "}}", range: openRange.upperBound..<input.endIndex) else {
                // Unterminated — leave the rest as-is.
                result.append(contentsOf: input[openRange.lowerBound..<input.endIndex])
                break
            }

            let name = String(input[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)

            if let value = values[name] {
                result.append(value)
            } else {
                // Preserve the literal reference (unknown name or not yet resolved).
                result.append(contentsOf: input[openRange.lowerBound..<closeRange.upperBound])
            }
            cursor = closeRange.upperBound
        }
        return result
    }

    // MARK: - Conditions

    /// Evaluates a `when:` expression: truthy when it equals `true`, `1`, or `yes`
    /// (case-insensitive) after token substitution. Everything else — including an
    /// unresolved literal token — is falsy.
    static func isTruthy(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "1", "yes": return true
        default: return false
        }
    }

    // MARK: - Helpers

    private func forEachToken(in input: String, _ body: (String) -> Void) {
        var cursor = input.startIndex
        while let open = input.range(of: "{{", range: cursor..<input.endIndex) {
            guard let close = input.range(of: "}}", range: open.upperBound..<input.endIndex) else { break }
            let name = String(input[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
            body(name)
            cursor = close.upperBound
        }
    }

    private static func scalarString(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .null, .array, .object: return nil
        }
    }
}
