import XCTest

final class HelloWorldTests: XCTestCase {

    // MARK: - Bundle / Identity

    func testAppBundleIdentifierIsSet() {
        let bundleID = Bundle.main.bundleIdentifier
        // In a unit test host, bundle ID comes from the test runner — just assert it's non-nil.
        XCTAssertNotNil(bundleID)
    }

    func testBundleExecutableExists() {
        let executable = Bundle.main.executablePath
        XCTAssertNotNil(executable)
    }

    // MARK: - Arithmetic

    func testBasicAddition() {
        XCTAssertEqual(2 + 2, 4)
    }

    func testBasicSubtraction() {
        XCTAssertEqual(10 - 3, 7)
    }

    func testBasicMultiplication() {
        XCTAssertEqual(6 * 7, 42)
    }

    func testBasicDivision() {
        XCTAssertEqual(20 / 4, 5)
    }

    func testModulo() {
        XCTAssertEqual(17 % 5, 2)
    }

    // MARK: - String Operations

    func testStringIsNotEmpty() {
        let appName = "HelloWorld"
        XCTAssertFalse(appName.isEmpty)
    }

    func testStringHasCorrectPrefix() {
        let appName = "HelloWorld"
        XCTAssertTrue(appName.hasPrefix("Hello"))
    }

    func testStringHasCorrectSuffix() {
        let appName = "HelloWorld"
        XCTAssertTrue(appName.hasSuffix("World"))
    }

    func testStringCount() {
        let appName = "HelloWorld"
        XCTAssertEqual(appName.count, 10)
    }

    func testStringLowercased() {
        XCTAssertEqual("HelloWorld".lowercased(), "helloworld")
    }

    func testStringUppercased() {
        XCTAssertEqual("hello".uppercased(), "HELLO")
    }

    func testStringContains() {
        XCTAssertTrue("HelloWorld".contains("World"))
    }

    func testStringSplit() {
        let parts = "Hello,World".split(separator: ",")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], "Hello")
        XCTAssertEqual(parts[1], "World")
    }

    // MARK: - Collection Operations

    func testArrayCount() {
        let items = [1, 2, 3, 4, 5]
        XCTAssertEqual(items.count, 5)
    }

    func testArraySum() {
        let items = [1, 2, 3, 4, 5]
        XCTAssertEqual(items.reduce(0, +), 15)
    }

    func testArrayFilter() {
        let evens = [1, 2, 3, 4, 5, 6].filter { $0 % 2 == 0 }
        XCTAssertEqual(evens, [2, 4, 6])
    }

    func testArrayMap() {
        let doubled = [1, 2, 3].map { $0 * 2 }
        XCTAssertEqual(doubled, [2, 4, 6])
    }

    func testArraySorted() {
        let sorted = [3, 1, 4, 1, 5].sorted()
        XCTAssertEqual(sorted, [1, 1, 3, 4, 5])
    }

    func testDictionaryLookup() {
        let config: [String: String] = ["env": "production", "platform": "iOS"]
        XCTAssertEqual(config["env"], "production")
        XCTAssertNil(config["missing"])
    }

    // MARK: - Optionals

    func testOptionalUnwrapping() {
        let value: Int? = 42
        XCTAssertNotNil(value)
        XCTAssertEqual(value!, 42)
    }

    func testOptionalNilCheck() {
        let value: String? = nil
        XCTAssertNil(value)
    }

    func testOptionalDefaultValue() {
        let value: Int? = nil
        XCTAssertEqual(value ?? 0, 0)
    }

    // MARK: - Counter Logic (mirrors counterUtils)

    func testClamp() {
        func clamp(_ value: Int, min: Int, max: Int) -> Int {
            Swift.min(Swift.max(value, min), max)
        }
        XCTAssertEqual(clamp(5, min: 0, max: 10), 5)
        XCTAssertEqual(clamp(-1, min: 0, max: 10), 0)
        XCTAssertEqual(clamp(15, min: 0, max: 10), 10)
    }

    func testPluralize() {
        func pluralize(_ count: Int, _ singular: String, _ plural: String) -> String {
            count == 1 ? singular : plural
        }
        XCTAssertEqual(pluralize(1, "tap", "taps"), "tap")
        XCTAssertEqual(pluralize(0, "tap", "taps"), "taps")
        XCTAssertEqual(pluralize(5, "tap", "taps"), "taps")
    }

    func testIsEven() {
        XCTAssertTrue(4 % 2 == 0)
        XCTAssertFalse(3 % 2 == 0)
        XCTAssertTrue(0 % 2 == 0)
    }
}
