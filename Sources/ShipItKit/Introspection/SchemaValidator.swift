import Foundation
import Yams

public enum SchemaValidator {
    public static func validate(value: JSONValue, against fields: [SchemaField]) -> [ValidationIssue] {
        guard case .object(let object) = value else {
            return [ValidationIssue(severity: .error, path: "$", message: "Expected a top-level object.")]
        }

        return validateObject(object, fields: fields, path: "$")
    }

    public static func jsonValue(fromYAML text: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> JSONValue {
        let expanded = expandEnvironmentVariables(in: text, environment: environment)
        let loaded = try Yams.load(yaml: expanded)
        return try jsonValue(fromYAMLObject: loaded as Any)
    }

    public static func expandEnvironmentVariables(in text: String, environment: [String: String]) -> String {
        environment.reduce(into: text) { result, pair in
            result = result.replacingOccurrences(of: "${\(pair.key)}", with: pair.value)
        }
    }

    public static func jsonValue(fromYAMLObject value: Any) throws -> JSONValue {
        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if number.doubleValue.rounded(.towardZero) == number.doubleValue {
                return .int(number.intValue)
            }
            return .double(number.doubleValue)
        case let array as [Any]:
            return .array(try array.map { try jsonValue(fromYAMLObject: $0) })
        case let dictionary as [String: Any]:
            return .object(try dictionary.mapValues { try jsonValue(fromYAMLObject: $0) })
        case let dictionary as [AnyHashable: Any]:
            var object: [String: JSONValue] = [:]
            for (key, value) in dictionary {
                guard let stringKey = key as? String else {
                    throw ShipItError.invalidConfiguration(reason: "YAML object keys must be strings.")
                }
                object[stringKey] = try jsonValue(fromYAMLObject: value)
            }
            return .object(object)
        default:
            throw ShipItError.invalidConfiguration(reason: "Unsupported YAML value encountered during validation.")
        }
    }

    private static func validateObject(_ object: [String: JSONValue], fields: [SchemaField], path: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let knownFields = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })

        for field in fields where field.required && object[field.name] == nil {
            issues.append(.init(severity: .error, path: joined(path, field.name), message: "Missing required field."))
        }

        for (key, value) in object {
            guard let field = knownFields[key] else {
                issues.append(.init(severity: .error, path: joined(path, key), message: "Unknown field."))
                continue
            }
            issues.append(contentsOf: validate(field: field, value: value, path: joined(path, key)))
        }

        return issues
    }

    private static func validate(field: SchemaField, value: JSONValue, path: String) -> [ValidationIssue] {
        if field.type != .any && !matchesType(value, expected: field.type) {
            return [ValidationIssue(severity: .error, path: path, message: "Expected \(field.type.rawValue) value.")]
        }

        if !field.allowedValues.isEmpty && !field.allowedValues.contains(value) {
            let allowed = field.allowedValues.map(stringify).joined(separator: ", ")
            return [ValidationIssue(severity: .error, path: path, message: "Invalid value. Allowed values: \(allowed)")]
        }

        switch field.type {
        case .object:
            guard let object = value.objectValue else { return [] }
            return validateNestedObject(field: field, object: object, path: path)
        case .array:
            guard let array = value.arrayValue else { return [] }
            guard let itemSchema = field.itemValue else { return [] }
            return array.enumerated().flatMap { index, item in
                validate(field: itemSchema, value: item, path: "\(path)[\(index)]")
            }
        default:
            return []
        }
    }

    private static func validateNestedObject(field: SchemaField, object: [String: JSONValue], path: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let properties = field.propertyValues
        let knownFields = Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0) })

        for property in properties where property.required && object[property.name] == nil {
            issues.append(.init(severity: .error, path: joined(path, property.name), message: "Missing required field."))
        }

        for (key, value) in object {
            if let property = knownFields[key] {
                issues.append(contentsOf: validate(field: property, value: value, path: joined(path, key)))
                continue
            }

            if field.allowsAdditionalProperties {
                if let dynamicSchema = field.additionalPropertyValue {
                    issues.append(contentsOf: validate(field: dynamicSchema, value: value, path: joined(path, key)))
                }
                continue
            }

            issues.append(.init(severity: .error, path: joined(path, key), message: "Unknown field."))
        }

        return issues
    }

    private static func matchesType(_ value: JSONValue, expected: SchemaValueKind) -> Bool {
        switch expected {
        case .any:
            true
        case .string:
            value.stringValue != nil
        case .integer:
            value.intValue != nil
        case .number:
            value.intValue != nil || value.doubleValue != nil
        case .boolean:
            value.boolValue != nil
        case .object:
            value.objectValue != nil
        case .array:
            value.arrayValue != nil
        }
    }

    private static func joined(_ path: String, _ component: String) -> String {
        path == "$" ? "$.\(component)" : "\(path).\(component)"
    }

    private static func stringify(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let bool):
            return bool ? "true" : "false"
        case .int(let int):
            return String(int)
        case .double(let double):
            return String(double)
        case .string(let string):
            return string
        case .array:
            return "[array]"
        case .object:
            return "{object}"
        }
    }
}
