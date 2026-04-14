import Foundation

/// Factory and runtime for user-defined composite actions declared in
/// `Shipfile.yml` under `custom_actions:`.
///
/// A custom action is a named, parameterized sequence of other action steps.
/// At registration time each `CustomActionConfig` is converted into an
/// ``ActionDescriptor`` that, when invoked, substitutes call-site parameters
/// into each sub-step's options and dispatches through the shared
/// ``ActionRegistry``.
///
/// ## Parameter substitution
/// String leaves inside a step's `options:` block may reference declared
/// parameters using the `{{param.NAME}}` syntax. The substitution runs
/// *after* Shipfile's `${ENV_VAR}` expansion and does not collide with
/// GitHub Actions' `${{ ... }}` or CircleCI's `<< ... >>` templating.
///
/// - When a string is *exactly* `{{param.NAME}}`, the typed JSON value of
///   the parameter is substituted (preserving `bool`, `int`, `array`, etc.).
/// - When a string contains `{{param.NAME}}` interpolated with other text,
///   the parameter is stringified into the surrounding string.
public enum CompositeAction {

    /// Error namespace for composite-action authoring mistakes surfaced at
    /// registration or runtime.
    public enum CompositeError: Error, CustomStringConvertible, Sendable {
        case unknownParameter(compositeName: String, parameter: String, stepIndex: Int)
        case missingRequiredParameter(compositeName: String, parameter: String)
        case unknownStepAction(compositeName: String, stepIndex: Int, action: String)

        public var description: String {
            switch self {
            case .unknownParameter(let composite, let parameter, let stepIndex):
                return "Custom action '\(composite)' step \(stepIndex + 1) references undeclared parameter '\(parameter)'. Add it under custom_actions.\(composite).parameters."
            case .missingRequiredParameter(let composite, let parameter):
                return "Custom action '\(composite)' is missing required parameter '\(parameter)'."
            case .unknownStepAction(let composite, let stepIndex, let action):
                return "Custom action '\(composite)' step \(stepIndex + 1) references unknown action '\(action)'."
            }
        }
    }

    /// Build an ``ActionDescriptor`` for the given composite definition that
    /// delegates sub-steps through the provided registry at run time.
    ///
    /// - Parameters:
    ///   - name: The composite action name as declared in
    ///     `custom_actions.<name>`.
    ///   - config: The Shipfile-level definition.
    ///   - registry: The registry used to resolve sub-step actions at run
    ///     time. Must be the same registry the composite itself is
    ///     registered into so nested composites are resolvable.
    public static func descriptor(
        name: String,
        config: CustomActionConfig,
        registry: ActionRegistry
    ) -> ActionDescriptor {
        let description = config.description ?? "Custom composite action."
        let optionSchema = parameterSchema(for: config)

        return ActionDescriptor(
            name: name,
            description: description,
            optionSchema: optionSchema,
            runJSON: { optionsJSON, context in
                let callParams = optionsJSON?.objectValue ?? [:]
                let resolved = try resolveParameters(
                    compositeName: name,
                    declared: config.parameters ?? [:],
                    provided: callParams
                )

                var childResults: [JSONValue] = []
                for (index, step) in config.steps.enumerated() {
                    let substituted = substitute(
                        value: step.options ?? .object([:]),
                        params: resolved,
                        compositeName: name,
                        stepIndex: index
                    )

                    guard let descriptor = await registry.descriptor(named: step.action) else {
                        throw CompositeError.unknownStepAction(
                            compositeName: name,
                            stepIndex: index,
                            action: step.action
                        )
                    }

                    let envelope = try await descriptor.runJSON(substituted, context)
                    let encoded = try JSONEncoder().encode(envelope)
                    let asJSON = try JSONDecoder().decode(JSONValue.self, from: encoded)
                    childResults.append(asJSON)
                }

                return ActionResultEnvelope(
                    action: name,
                    status: "success",
                    payload: .object([
                        "composite": .string(name),
                        "steps": .array(childResults),
                    ])
                )
            }
        )
    }

    // MARK: - Parameter resolution

    /// Applies defaults and enforces required parameters.
    static func resolveParameters(
        compositeName: String,
        declared: [String: CustomActionParameter],
        provided: [String: JSONValue]
    ) throws -> [String: JSONValue] {
        var resolved: [String: JSONValue] = [:]
        // Start with declared defaults.
        for (key, spec) in declared {
            if let value = provided[key] {
                resolved[key] = value
            } else if let defaultValue = spec.defaultValue {
                resolved[key] = defaultValue
            } else if spec.isRequired {
                throw CompositeError.missingRequiredParameter(compositeName: compositeName, parameter: key)
            }
        }
        // Tolerate extra (undeclared) keys — they simply aren't reachable via {{param.X}}.
        for (key, value) in provided where resolved[key] == nil {
            resolved[key] = value
        }
        return resolved
    }

    // MARK: - Substitution

    /// Recursively walks `value` and replaces `{{param.X}}` references in
    /// string leaves. Keys and non-string scalars are left untouched.
    static func substitute(
        value: JSONValue,
        params: [String: JSONValue],
        compositeName: String,
        stepIndex: Int
    ) -> JSONValue {
        switch value {
        case .string(let s):
            return substituteString(s, params: params, compositeName: compositeName, stepIndex: stepIndex)
        case .array(let items):
            return .array(items.map {
                substitute(value: $0, params: params, compositeName: compositeName, stepIndex: stepIndex)
            })
        case .object(let dict):
            var out: [String: JSONValue] = [:]
            for (k, v) in dict {
                out[k] = substitute(value: v, params: params, compositeName: compositeName, stepIndex: stepIndex)
            }
            return .object(out)
        case .null, .bool, .int, .double:
            return value
        }
    }

    /// Substitutes `{{param.X}}` within a single string.
    ///
    /// If the whole trimmed string is exactly one `{{param.X}}` reference the
    /// underlying typed ``JSONValue`` is returned to preserve `bool` / `int` /
    /// `array` types. Otherwise occurrences are stringified inline.
    static func substituteString(
        _ input: String,
        params: [String: JSONValue],
        compositeName: String,
        stepIndex: Int
    ) -> JSONValue {
        // Whole-string typed substitution.
        if let key = wholeStringParameterKey(input),
           let value = params[key] {
            return value
        }

        // Interpolated substitution. Walk all `{{param.X}}` occurrences.
        var result = ""
        var cursor = input.startIndex
        while cursor < input.endIndex {
            guard let openRange = input.range(of: "{{param.", range: cursor ..< input.endIndex) else {
                result.append(contentsOf: input[cursor ..< input.endIndex])
                break
            }
            result.append(contentsOf: input[cursor ..< openRange.lowerBound])

            guard let closeRange = input.range(of: "}}", range: openRange.upperBound ..< input.endIndex) else {
                // Unterminated — leave the rest as-is.
                result.append(contentsOf: input[openRange.lowerBound ..< input.endIndex])
                break
            }

            let key = String(input[openRange.upperBound ..< closeRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)

            if let value = params[key] {
                result.append(stringify(value))
            } else {
                // Preserve the literal reference so callers get a deterministic
                // error downstream rather than a silent empty expansion.
                result.append(contentsOf: input[openRange.lowerBound ..< closeRange.upperBound])
            }
            cursor = closeRange.upperBound
        }
        return .string(result)
    }

    /// Returns the parameter key if the whole (trimmed) string is exactly
    /// `{{param.NAME}}`, otherwise `nil`.
    private static func wholeStringParameterKey(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{{param."), trimmed.hasSuffix("}}") else { return nil }
        let inside = trimmed.dropFirst("{{param.".count).dropLast(2)
        let key = String(inside).trimmingCharacters(in: .whitespaces)
        // Reject if there are additional `{{` / `}}` markers inside.
        guard !key.contains("{{"), !key.contains("}}") else { return nil }
        return key.isEmpty ? nil : key
    }

    private static func stringify(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .null: return ""
        case .array, .object:
            // Fall back to compact JSON for structured values.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(value),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return ""
        }
    }

    // MARK: - Schema

    /// Projects a composite's declared parameters into a ``SchemaField``
    /// array so `shipit schema` and validation surfaces call-site options.
    public static func parameterSchema(for config: CustomActionConfig) -> [SchemaField] {
        (config.parameters ?? [:]).sorted { $0.key < $1.key }.map { (name, spec) in
            let kind = schemaKind(for: spec.type ?? "string")
            return SchemaField(
                name: name,
                type: kind,
                required: spec.isRequired,
                description: spec.description ?? "Custom action parameter '\(name)'.",
                defaultValue: spec.defaultValue
            )
        }
    }

    private static func schemaKind(for raw: String) -> SchemaValueKind {
        switch raw.lowercased() {
        case "string": return .string
        case "bool", "boolean": return .boolean
        case "int", "integer": return .integer
        case "double", "number": return .number
        case "array", "list": return .array
        case "object", "map", "dict": return .object
        default: return .any
        }
    }
}
