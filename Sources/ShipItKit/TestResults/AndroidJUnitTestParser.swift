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
            // A name that repeats inside one file (a retry plugin's attempts, repeated parameterized names) keeps
            // every occurrence under its own ID: the first keeps the plain ID so a selective rerun, which sees
            // only one occurrence, still lines up with it, and later ones get `#<n>`.
            var totals: [String: Int] = [:]
            for item in delegate.cases { totals[item.selector, default: 0] += 1 }
            var seen: [String: Int] = [:]
            var occurrences: [Int] = []
            var ids: [String] = []
            for item in delegate.cases {
                let occurrence = (seen[item.selector] ?? 0) + 1
                seen[item.selector] = occurrence
                occurrences.append(occurrence)
                ids.append("junit-case:\(scope):\(item.selector)" + (occurrence > 1 ? "#\(occurrence)" : ""))
            }
            for (offset, item) in delegate.cases.enumerated() {
                let suiteID = "junit-suite:\(scope):\(item.suite ?? "tests")"
                let selector = item.selector
                var metadata = Self.metadata(scope: scope, item: item)
                if let total = totals[selector], total > 1 { metadata["occurrence"] = "\(occurrences[offset])/\(total)" }
                cases.append(
                    ParsedTestCase(
                        stableID: ids[offset], suite: item.suite,
                        name: item.name, status: item.status, durationSeconds: item.duration,
                        message: item.message, file: item.file, line: item.line,
                        rerunSelector: runner == "swift-test"
                            ? .swiftTestFilter(
                                selector.replacingOccurrences(of: ".", with: "/", range: selector.range(of: ".", options: .backwards)))
                            : runner == "kmp-native" ? .unsupported(rawIdentifier: selector) : .gradleTestFilter(selector),
                        metadata: metadata, stackTrace: item.stack))
                if !suites.contains(where: { $0.stableID == suiteID }) {
                    suites.append(
                        ParsedTestSuite(
                            name: item.suite ?? "tests", stableID: suiteID, file: file.path,
                            testCaseIDs: delegate.cases.enumerated().filter { $0.element.suite == item.suite }.map { ids[$0.offset] }))
                }
            }
            if !delegate.output.isEmpty { diagnostics.append(.init(severity: .info, message: delegate.output, source: file.path)) }
        }
        let flakyCount = cases.filter { $0.metadata?["flaky"] == "true" }.count
        let summary = TestSummary(
            passed: max(declaredPassed, cases.filter { $0.status == .passed }.count),
            failed: max(declaredFailed, cases.filter { $0.status == .failed }.count),
            skipped: max(declaredSkipped, cases.filter { $0.status == .skipped }.count),
            flaky: flakyCount,
            errored: max(declaredErrors, cases.filter { $0.status == .errored }.count))
        // The `max` above keeps a report that omits passing testcases from under-counting; a disagreement is still
        // worth surfacing rather than hiding.
        let declaredTotal = declaredPassed + declaredFailed + declaredErrors + declaredSkipped
        if declaredTotal != cases.count {
            diagnostics.append(
                .init(
                    severity: .warning,
                    message: "Suites declare \(declaredTotal) tests but the reports contain \(cases.count) test cases",
                    source: reportDirectory))
        }
        return ParsedTestRun(
            platform: platform, runner: runner, source: reportDirectory, summary: summary,
            suites: suites, testCases: cases, diagnostics: diagnostics)
    }
}
extension AndroidJUnitTestParser {
    /// Where a result came from, derived from the report's location and the properties AGP writes for
    /// connected runs. Only evidence that is actually present is recorded.
    fileprivate static func metadata(scope: String, item: JUnitResultDelegate.Case) -> [String: String] {
        var metadata = ["report": scope]
        let parts = scope.split(separator: "/").map(String.init)
        if let build = parts.firstIndex(of: "build"), build > 0 { metadata["module"] = parts[..<build].joined(separator: "/") }
        if let results = parts.firstIndex(of: "test-results"), results + 2 < parts.count {
            metadata["task"] = parts[results + 1]
        } else if parts.contains("androidTest-results") {
            metadata["task"] = "connected"
        }
        for key in ["device", "flavor", "project"] {
            if let value = item.properties[key], !value.isEmpty { metadata[key] = value }
        }
        if let type = item.failureType, !type.isEmpty { metadata["failure_type"] = type }
        if item.retries > 0 { metadata["retries"] = String(item.retries) }
        if item.flaky { metadata["flaky"] = "true" }
        return metadata
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
        var stack: String?
        var failureType: String?
        var file: String?
        var line: Int?
        /// Surefire `flaky*` elements: the test failed, then passed on a retry.
        var flaky = false
        /// Number of retried executions recorded for this test (`flaky*` / `rerun*` elements).
        var retries = 0
        var properties: [String: String] = [:]
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
    private var suiteProperties: [String: String] = [:]
    private var current: Case?
    private var textElement: String?
    /// The `failure` / `error` / `skipped` element whose body is being collected.
    private var bodyElement: String?
    private var body = ""
    /// Depth inside retry elements, whose own messages, traces and output describe earlier executions.
    private var retryDepth = 0
    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        switch elementName {
        case "testsuite":
            recognized = true
            if suiteNames.isEmpty {
                suiteProperties = [:]
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
        case "property":
            if current == nil, let name = attributes["name"], let value = attributes["value"] { suiteProperties[name] = value }
        case "testcase":
            let name = attributes["name"] ?? "unnamed"
            let className = attributes["classname"] ?? suiteNames.last ?? ""
            current = Case(
                name: name, selector: className.isEmpty ? name : "\(className).\(name)",
                suite: suiteNames.last ?? className, duration: attributes["time"].flatMap(Double.init),
                file: attributes["file"], line: attributes["line"].flatMap(Int.init), properties: suiteProperties)
        case "failure", "error", "skipped":
            guard retryDepth == 0 else { break }
            current?.status = elementName == "failure" ? .failed : elementName == "error" ? .errored : .skipped
            current?.message = attributes["message"]
            current?.failureType = attributes["type"]
            bodyElement = elementName
            body = ""
        case "flakyFailure", "flakyError":
            retryDepth += 1
            current?.flaky = true
            current?.retries += 1
        case "rerunFailure", "rerunError":
            retryDepth += 1
            current?.retries += 1
        case "system-out", "system-err":
            if retryDepth == 0 { textElement = elementName }
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
        } else if bodyElement != nil {
            body += string
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "failure", "error", "skipped":
            if elementName == bodyElement {
                finishBody()
                bodyElement = nil
            }
        case "flakyFailure", "flakyError", "rerunFailure", "rerunError":
            retryDepth = max(0, retryDepth - 1)
        case "testcase":
            if let current {
                cases.append(current)
                self.current = nil
            }
        case "testsuite":
            _ = suiteNames.popLast()
        default: break
        }
        if elementName == textElement { textElement = nil }
    }

    /// The element's body is the stack trace when the `message` attribute already says what went wrong, and the
    /// message itself when the attribute is absent.
    private func finishBody() {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        body = ""
        guard !text.isEmpty, let item = current else { return }
        if let message = item.message, !message.isEmpty {
            current?.stack = text == message ? nil : text
        } else {
            let first = text.split(separator: "\n", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? text
            current?.message = first
            current?.stack = text.contains("\n") ? text : nil
        }
    }
}
