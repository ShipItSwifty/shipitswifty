import Foundation
import Testing

@testable import ShipItKit

@Suite("JSONValue")
struct JSONValueTests {

    // MARK: - Literal Conformances

    @Test("null literal creates .null")
    func nullLiteral() {
        let value: JSONValue = nil
        #expect(value == .null)
        #expect(value.isNull)
    }

    @Test("bool literal creates .bool")
    func boolLiteral() {
        let trueValue: JSONValue = true
        let falseValue: JSONValue = false
        #expect(trueValue == .bool(true))
        #expect(falseValue == .bool(false))
        #expect(trueValue.boolValue == true)
    }

    @Test("int literal creates .int")
    func intLiteral() {
        let value: JSONValue = 42
        #expect(value == .int(42))
        #expect(value.intValue == 42)
    }

    @Test("double literal creates .double")
    func doubleLiteral() {
        let value: JSONValue = 3.14
        #expect(value == .double(3.14))
        #expect(value.doubleValue == 3.14)
    }

    @Test("string literal creates .string")
    func stringLiteral() {
        let value: JSONValue = "hello"
        #expect(value == .string("hello"))
        #expect(value.stringValue == "hello")
    }

    @Test("array literal creates .array")
    func arrayLiteral() {
        let value: JSONValue = [1, 2, 3]
        #expect(value == .array([.int(1), .int(2), .int(3)]))
        #expect(value.arrayValue?.count == 3)
    }

    @Test("dictionary literal creates .object")
    func dictionaryLiteral() {
        let value: JSONValue = ["key": "value"]
        #expect(value == .object(["key": .string("value")]))
        #expect(value.objectValue?["key"] == .string("value"))
    }

    // MARK: - Codable Round-trip

    @Test("null encodes and decodes correctly")
    func encodeDecodeNull() throws {
        let original: JSONValue = .null
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .null)
    }

    @Test("bool encodes and decodes correctly")
    func encodeDecodeBool() throws {
        let original: JSONValue = .bool(true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .bool(true))
    }

    @Test("int encodes and decodes correctly")
    func encodeDecodeInt() throws {
        let original: JSONValue = .int(42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .int(42))
    }

    @Test("double encodes and decodes correctly")
    func encodeDecodeDouble() throws {
        let original: JSONValue = .double(3.14)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .double(3.14))
    }

    @Test("string encodes and decodes correctly")
    func encodeDecodeString() throws {
        let original: JSONValue = .string("hello world")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .string("hello world"))
    }

    @Test("array encodes and decodes correctly")
    func encodeDecodeArray() throws {
        let original: JSONValue = .array([.int(1), .string("two"), .bool(true)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == original)
    }

    @Test("object encodes and decodes correctly")
    func encodeDecodeObject() throws {
        let original: JSONValue = .object([
            "name": .string("test"),
            "count": .int(5),
            "active": .bool(true),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == original)
    }

    @Test("nested object round-trips correctly")
    func encodeDecodeNestedObject() throws {
        let original: JSONValue = .object([
            "config": .object([
                "scheme": .string("MyApp"),
                "targets": .array([.string("Debug"), .string("Release")]),
            ]),
            "version": .int(2),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Accessor Properties

    @Test("accessor returns nil for wrong case")
    func accessorWrongCase() {
        let value: JSONValue = .string("hello")
        #expect(value.intValue == nil)
        #expect(value.boolValue == nil)
        #expect(value.doubleValue == nil)
        #expect(value.arrayValue == nil)
        #expect(value.objectValue == nil)
        #expect(value.isNull == false)
    }

    // MARK: - Decode from JSON

    @Test("decodes from raw JSON string")
    func decodeFromRawJSON() throws {
        let json = """
            {"name": "MyApp", "version": 42, "active": true, "tags": ["ios", "swift"]}
            """
        let data = Data(json.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)

        guard case .object(let obj) = value else {
            #expect(Bool(false), "Expected object")
            return
        }

        #expect(obj["name"] == .string("MyApp"))
        #expect(obj["version"] == .int(42))
        #expect(obj["active"] == .bool(true))
        #expect(obj["tags"] == .array([.string("ios"), .string("swift")]))
    }
}
