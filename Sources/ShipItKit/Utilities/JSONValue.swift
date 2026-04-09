/// A lossless JSON/YAML-compatible value type used for dynamically-typed action options.
///
/// Used wherever action options are decoded from Shipfile YAML or CLI JSON flags
/// without a statically known type.
///
/// ## Example
/// ```swift
/// let options: JSONValue = .object([
///     "scheme": .string("MyApp"),
///     "verbose": .bool(true),
///     "retryCount": .int(3)
/// ])
/// ```
@frozen
public enum JSONValue: Codable, Sendable, Hashable {
    /// A JSON null value.
    case null
    /// A JSON boolean value.
    case bool(Bool)
    /// A JSON integer value.
    case int(Int)
    /// A JSON floating-point value.
    case double(Double)
    /// A JSON string value.
    case string(String)
    /// A JSON array value.
    case array([JSONValue])
    /// A JSON object (dictionary) value.
    case object([String: JSONValue])

    // MARK: - Codable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }

        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }

        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
            return
        }

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
            return
        }

        if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
            return
        }

        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Cannot decode JSONValue from the given data"
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    /// Creates a null JSONValue.
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    /// Creates a boolean JSONValue.
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    /// Creates an integer JSONValue.
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    /// Creates a double JSONValue.
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    /// Creates a string JSONValue.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    /// Creates an array JSONValue.
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    /// Creates an object JSONValue.
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension JSONValue {
    /// Returns the string value if this is a `.string` case, otherwise `nil`.
    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// Returns the bool value if this is a `.bool` case, otherwise `nil`.
    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// Returns the integer value if this is an `.int` case, otherwise `nil`.
    public var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    /// Returns the double value if this is a `.double` case, otherwise `nil`.
    public var doubleValue: Double? {
        guard case .double(let value) = self else { return nil }
        return value
    }

    /// Returns the array value if this is an `.array` case, otherwise `nil`.
    public var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    /// Returns the object value if this is an `.object` case, otherwise `nil`.
    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    /// Returns whether this value represents JSON null.
    public var isNull: Bool {
        guard case .null = self else { return false }
        return true
    }
}
