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
    ///
    /// - Parameters:
    ///   - runner: The tool that produced the XML. It decides the rerun selector: `swift test` filters differ
    ///     from Gradle's `--tests`.
    ///   - buildSystem: The project's build system when known (`.kmp` makes native targets unsupported for reruns).
    ///   - destination: Where the tests ran, for runners that run on the host (`swift test`). Gradle results derive
    ///     it from the task that wrote them (and, for connected tests, the device AGP records), so none is needed.
    public func parse(
        reportDirectory: String, runner: TestRunner = .gradle, buildSystem: BuildSystem? = nil, identityRoot: String? = nil,
        destination: TestDestination? = nil
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
        var destinations: [TestDestination] = []
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
            // Retries show up as a repeated name: a retry plugin writes one `testcase` per attempt. A repeat only
            // means a retry when an attempt failed (retries follow failures), so those are folded into one test
            // that keeps its attempt count. Repeats that all passed are genuine duplicates and stay separate: the
            // first keeps the plain ID so a one-test rerun still lines up, later ones get `#<n>`.
            let folded = Self.fold(delegate.cases)
            var ids: [String] = []
            for entry in folded {
                ids.append(
                    "junit-case:\(scope):\(entry.item.selector)"
                        + ((entry.occurrence?.index ?? 1) > 1 ? "#\(entry.occurrence?.index ?? 1)" : ""))
            }
            // Declared totals count every attempt; restate them for the folded view so a recovered test is not
            // still counted as a failure.
            let rawCounts = Self.counts(delegate.cases.map(\.status))
            let foldedCounts = Self.counts(folded.map(\.item.status))
            declaredPassed += foldedCounts.passed - rawCounts.passed
            declaredFailed += foldedCounts.failed - rawCounts.failed
            declaredErrors += foldedCounts.errored - rawCounts.errored
            declaredSkipped += foldedCounts.skipped - rawCounts.skipped
            for (offset, entry) in folded.enumerated() {
                let item = entry.item
                let suiteID = "junit-suite:\(scope):\(item.suite ?? "tests")"
                let selector = item.selector
                var metadata = Self.metadata(scope: scope, item: item)
                // Where it ran: given by the caller, or read from the Gradle task and device that wrote the report.
                let placed: TestDestination? =
                    destination
                    ?? metadata["gradle_task"].map { TestDestination.gradle(task: $0, device: metadata["device"]) }
                if let placed, !destinations.contains(placed) { destinations.append(placed) }
                if let occurrence = entry.occurrence { metadata["occurrence"] = "\(occurrence.index)/\(occurrence.total)" }
                cases.append(
                    ParsedTestCase(
                        stableID: ids[offset], suite: item.suite,
                        name: item.name, status: item.status, durationSeconds: item.duration,
                        message: item.message, file: item.file, line: item.line,
                        rerunSelector: Self.rerunSelector(selector, runner: runner, buildSystem: buildSystem, destination: placed),
                        metadata: metadata, stackTrace: item.stack, attempts: 1 + item.retries,
                        totalDurationSeconds: item.retries > 0 ? item.totalDuration : nil, destinationID: placed?.id))
                if !suites.contains(where: { $0.stableID == suiteID }) {
                    suites.append(
                        ParsedTestSuite(
                            name: item.suite ?? "tests", stableID: suiteID, file: file.path,
                            testCaseIDs: folded.enumerated().filter { $0.element.item.suite == item.suite }.map { ids[$0.offset] }))
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
            runner: runner, buildSystem: buildSystem, source: reportDirectory, destinations: destinations, summary: summary,
            suites: suites, testCases: cases, diagnostics: diagnostics)
    }
}
extension AndroidJUnitTestParser {
    /// Folds the attempts a retry plugin wrote as separate `testcase` entries into one result per test.
    ///
    /// The deciding attempt is the last one. The folded test keeps how many executions it took (`retries`), the
    /// time they cost, and why the first attempt failed. It is flaky when it passed after an earlier failure.
    fileprivate static func fold(
        _ raw: [JUnitResultDelegate.Case]
    ) -> [(item: JUnitResultDelegate.Case, occurrence: (index: Int, total: Int)?)] {
        var order: [String] = []
        var groups: [String: [JUnitResultDelegate.Case]] = [:]
        for item in raw {
            if groups[item.selector] == nil { order.append(item.selector) }
            groups[item.selector, default: []].append(item)
        }
        func failed(_ item: JUnitResultDelegate.Case) -> Bool { item.status == .failed || item.status == .errored }
        var result: [(item: JUnitResultDelegate.Case, occurrence: (index: Int, total: Int)?)] = []
        for selector in order {
            guard let group = groups[selector], let last = group.last else { continue }
            guard group.count > 1, group.contains(where: failed) else {
                for (index, item) in group.enumerated() { result.append((item, group.count > 1 ? (index + 1, group.count) : nil)) }
                continue
            }
            var folded = last
            folded.retries = group.reduce(0) { $0 + 1 + $1.retries } - 1
            let durations = group.compactMap(\.duration)
            folded.totalDuration = durations.isEmpty ? nil : durations.reduce(0, +)
            let earlier = group.dropLast()
            folded.flaky = last.status == .passed && (earlier.contains(where: failed) || group.contains { $0.flaky })
            if let first = earlier.first(where: failed), let message = first.message ?? first.stack {
                folded.firstFailure = String(message.prefix(500))
            }
            result.append((folded, nil))
        }
        return result
    }

    /// Kotlin/Native targets cannot be selected by Gradle's `--tests` filter, so a rerun for them is reported as
    /// unsupported instead of being attempted.
    fileprivate static func rerunSelector(
        _ selector: String, runner: TestRunner, buildSystem: BuildSystem?, destination: TestDestination?
    ) -> TestRerunSelector {
        if runner == .swiftTest {
            return .swiftTestFilter(selector.replacingOccurrences(of: ".", with: "/", range: selector.range(of: ".", options: .backwards)))
        }
        if buildSystem == .kmp, let platform = destination?.platform, platform != .jvm, platform != .android {
            return .unsupported(rawIdentifier: selector)
        }
        return .gradleTestFilter(selector)
    }

    fileprivate static func counts(_ statuses: [TestCaseStatus]) -> (passed: Int, failed: Int, errored: Int, skipped: Int) {
        (
            statuses.filter { $0 == .passed }.count, statuses.filter { $0 == .failed }.count,
            statuses.filter { $0 == .errored }.count, statuses.filter { $0 == .skipped }.count
        )
    }

    /// Where a result came from, derived from the report's location and the properties AGP writes for
    /// connected runs. Only evidence that is actually present is recorded.
    fileprivate static func metadata(scope: String, item: JUnitResultDelegate.Case) -> [String: String] {
        var metadata = ["report": scope]
        let parts = scope.split(separator: "/").map(String.init)
        if let build = parts.firstIndex(of: "build"), build > 0 { metadata["module"] = parts[..<build].joined(separator: "/") }
        if let results = parts.firstIndex(of: "test-results"), results + 2 < parts.count {
            metadata["gradle_task"] = parts[results + 1]
        } else if parts.contains("androidTest-results") {
            metadata["gradle_task"] = "connected"
        }
        for key in ["device", "flavor", "project"] {
            if let value = item.properties[key], !value.isEmpty { metadata[key] = value }
        }
        if let type = item.failureType, !type.isEmpty { metadata["failure_type"] = type }
        if item.flaky { metadata["flaky"] = "true" }
        if let firstFailure = item.firstFailure { metadata["first_failure"] = firstFailure }
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
        /// Executions beyond the first: Surefire `flaky*` / `rerun*` elements, plus attempts folded from a retry
        /// plugin's repeated `testcase` entries.
        var retries = 0
        /// Time across all attempts, set when attempts were folded.
        var totalDuration: Double?
        /// Why the first failed attempt failed, kept when attempts were folded.
        var firstFailure: String?
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
