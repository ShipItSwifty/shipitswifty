import Foundation
import Logging

#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads JUnit XML from a file or directory, preserving failures, errors, and output.
///
/// ## Usage
/// ```swift
/// let run = try await AndroidJUnitTestParser().parse(reportDirectory: "app/build/test-results")
/// ```
public struct AndroidJUnitTestParser: Sendable {
    private let logger: Logger
    public init(logger: Logger = Logger.forType(subsystem: "ShipItSwifty", AndroidJUnitTestParser.self)) { self.logger = logger }

    /// Parses JUnit XML at `reportDirectory`.
    ///
    /// - Parameter identityRoot: Directory that test identities are made relative to, normally the Gradle
    ///   project root. Live runs and offline inspection must pass the same root so a test keeps one
    ///   `stableID` on every machine; without it identities are relative to `reportDirectory` itself.
    public func parse(
        reportDirectory: String, platform: String = "android", runner: String = "gradle", identityRoot: String? = nil
    ) async throws -> ParsedTestRun {
        let root = URL(fileURLWithPath: reportDirectory)
        let identityBase = identityRoot.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let files: [URL]
        if root.pathExtension.lowercased() == "xml" {
            files = [root]
        } else {
            files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                .filter { $0.pathExtension.lowercased() == "xml" }.sorted { $0.path < $1.path }
        }
        guard !files.isEmpty else { throw ShipItError.invalidConfiguration(reason: "No JUnit XML files found at \(reportDirectory).") }
        var cases: [ParsedTestCase] = []
        var suites: [ParsedTestSuite] = []
        var diagnostics: [ParsingDiagnostic] = []
        var declaredPassed = 0
        var declaredFailed = 0
        var declaredErrors = 0
        var declaredSkipped = 0
        for file in files {
            try Task.checkCancellation()
            let delegate = JUnitResultDelegate()
            let parser = XMLParser(data: try Data(contentsOf: file))
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), delegate.recognized, delegate.complete else {
                throw ShipItError.invalidConfiguration(
                    reason: "Invalid JUnit XML at \(file.path): \(parser.parserError?.localizedDescription ?? "missing testsuite")")
            }
            declaredPassed += delegate.passed
            declaredFailed += delegate.failed
            declaredErrors += delegate.errors
            declaredSkipped += delegate.skipped
            let scope: String
            if let identityBase, file.standardizedFileURL.path.hasPrefix(identityBase + "/") {
                scope = String(file.standardizedFileURL.path.dropFirst(identityBase.count + 1))
            } else {
                scope = root.pathExtension == "xml" ? file.lastPathComponent : String(file.path.dropFirst(root.path.count + 1))
            }
            for item in delegate.cases {
                let suiteID = "junit-suite:\(scope):\(item.suite ?? "tests")"
                let selector = item.selector
                cases.append(
                    ParsedTestCase(
                        stableID: "junit-case:\(scope):\(selector)", suite: item.suite,
                        name: item.name, status: item.status, durationSeconds: item.duration,
                        message: item.message, file: item.file, line: item.line,
                        rerunSelector: runner == "swift-test"
                            ? .swiftTestFilter(
                                selector.replacingOccurrences(of: ".", with: "/", range: selector.range(of: ".", options: .backwards)))
                            : runner == "kmp-native" ? .unsupported(rawIdentifier: selector) : .gradleTestFilter(selector)))
                if !suites.contains(where: { $0.stableID == suiteID }) {
                    suites.append(
                        ParsedTestSuite(
                            name: item.suite ?? "tests", stableID: suiteID, file: file.path,
                            testCaseIDs: delegate.cases.filter { $0.suite == item.suite }.map { "junit-case:\(scope):\($0.selector)" }))
                }
            }
            if !delegate.output.isEmpty { diagnostics.append(.init(severity: .info, message: delegate.output, source: file.path)) }
        }
        let summary = TestSummary(
            passed: max(declaredPassed, cases.filter { $0.status == .passed }.count),
            failed: max(declaredFailed, cases.filter { $0.status == .failed }.count),
            skipped: max(declaredSkipped, cases.filter { $0.status == .skipped }.count),
            errored: max(declaredErrors, cases.filter { $0.status == .errored }.count))
        return ParsedTestRun(
            platform: platform, runner: runner, source: reportDirectory, summary: summary,
            suites: suites, testCases: cases, diagnostics: diagnostics)
    }
}
extension AndroidJUnitTestParser: TestResultParser {
    public func parse(_ input: String) async throws -> ParsedTestRun { try await parse(reportDirectory: input) }
}

// Confined to one synchronous XMLParser invocation; never crosses an isolation boundary.
private final class JUnitResultDelegate: NSObject, XMLParserDelegate {
    struct Case {
        var name: String
        var selector: String
        var suite: String?
        var status: TestCaseStatus = .passed
        var duration: Double?
        var message: String?
        var file: String?
        var line: Int?
    }
    var passed = 0
    var failed = 0
    var errors = 0
    var skipped = 0
    var complete: Bool { recognized && suiteNames.isEmpty && current == nil }
    var recognized = false
    var cases: [Case] = []
    var output = ""
    private var suiteNames: [String] = []
    private var current: Case?
    private var textElement: String?
    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        switch elementName {
        case "testsuite":
            recognized = true
            if suiteNames.isEmpty {
                let total = attributes["tests"].flatMap(Int.init) ?? 0
                let failures = attributes["failures"].flatMap(Int.init) ?? 0
                let errorCount = attributes["errors"].flatMap(Int.init) ?? 0
                let skips = attributes["skipped"].flatMap(Int.init) ?? 0
                passed += max(0, total - failures - errorCount - skips)
                failed += failures
                errors += errorCount
                skipped += skips
            }
            suiteNames.append(attributes["name"] ?? "tests")
        case "testcase":
            let name = attributes["name"] ?? "unnamed"
            let className = attributes["classname"] ?? suiteNames.last ?? ""
            current = Case(
                name: name, selector: className.isEmpty ? name : "\(className).\(name)",
                suite: suiteNames.last ?? className, duration: attributes["time"].flatMap(Double.init),
                file: attributes["file"], line: attributes["line"].flatMap(Int.init))
        case "failure", "error", "skipped":
            current?.status = elementName == "failure" ? .failed : elementName == "error" ? .errored : .skipped
            current?.message = attributes["message"]
            textElement = elementName
        case "system-out", "system-err": textElement = elementName
        default: break
        }
    }
    // Gradle writes stack traces and suite output as CDATA. Foundation delivers those blocks here (not to
    // `foundCharacters`) whenever the delegate implements this method, so handle both identically.
    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        if let text = String(data: block, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if textElement == "system-out" || textElement == "system-err" {
            output += string
        } else if textElement != nil, var item = current {
            item.message = (item.message ?? "") + string
            current = item
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "testcase", let current {
            cases.append(current)
            self.current = nil
        }
        if elementName == "testsuite" { _ = suiteNames.popLast() }
        if elementName == textElement { textElement = nil }
    }
}
