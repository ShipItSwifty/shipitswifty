import Foundation

/// Minimal SAX parser that extracts test counts from a JUnit XML `<testsuite>` element.
///
/// JUnit XML format (as written by Gradle):
/// ```xml
/// <testsuite name="..." tests="10" skipped="0" failures="1" errors="0" ...>
///   <testcase .../>
/// </testsuite>
/// ```
///
/// This parser only reads attributes from the root `<testsuite>` element and ignores
/// everything else, making it fast and allocation-light for large test suites.
final class JUnitXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private(set) var tests: Int = 0
    private(set) var failures: Int = 0
    private(set) var errors: Int = 0
    private(set) var skipped: Int = 0
    private var foundTestsuite = false

    init(data: Data) {
        self.data = data
    }

    func parse() {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        guard elementName == "testsuite", !foundTestsuite else { return }
        foundTestsuite = true
        tests = Int(attributes["tests"] ?? "0") ?? 0
        failures = Int(attributes["failures"] ?? "0") ?? 0
        errors = Int(attributes["errors"] ?? "0") ?? 0
        skipped = Int(attributes["skipped"] ?? "0") ?? 0
    }
}
