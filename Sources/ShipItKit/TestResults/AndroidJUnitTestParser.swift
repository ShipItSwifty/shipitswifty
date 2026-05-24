import Foundation
import Logging

/// Parses one or more Android JUnit XML files into a normalized ``ParsedTestRun``.
public struct AndroidJUnitTestParser: Sendable {
    private let logger: Logger

    public init(logger: Logger = Logger.forType(subsystem: "ShipItSwifty", AndroidJUnitTestParser.self)) {
        self.logger = logger
    }

    /// Parses all XML files under the given report directory.
    ///
    /// - Parameter reportDirectory: Directory containing Gradle JUnit XML files.
    /// - Returns: A normalized parsed test run.
    public func parse(reportDirectory: String) async throws -> ParsedTestRun {
        let fileURLs = junitXMLFiles(in: URL(fileURLWithPath: reportDirectory))
        guard !fileURLs.isEmpty else {
            throw ShipItError.invalidConfiguration(
                reason: "No JUnit XML files found at \(reportDirectory)."
            )
        }

        var suites: [ParsedTestSuite] = []
        var testCases: [ParsedTestCase] = []
        var diagnostics: [ParsingDiagnostic] = []
        var totalPassed = 0
        var totalFailed = 0
        var totalSkipped = 0
        var seenCaseIDs = Set<String>()

        for fileURL in fileURLs.sorted(by: { $0.path < $1.path }) {
            do {
                let data = try Data(contentsOf: fileURL)
                let parser = JUnitXMLParser(data: data)
                parser.parse()

                let suiteName = suiteName(for: fileURL, parser: parser)
                let suiteID = "junit-suite:\(suiteName)"
                var suiteCaseIDs: [String] = []

                totalFailed += parser.failures + parser.errors
                totalSkipped += parser.skipped

                for testCase in parser.testCases {
                    let stableID = "junit-case:\(testCase.name)"
                    if !seenCaseIDs.insert(stableID).inserted {
                        diagnostics.append(
                            ParsingDiagnostic(
                                severity: .warning,
                                message: "Duplicate JUnit test case identifier encountered: \(testCase.name)",
                                source: fileURL.path
                            )
                        )
                    }

                    let status: TestCaseStatus
                    if testCase.failed {
                        status = .failed
                    } else if testCase.skipped {
                        status = .skipped
                    } else {
                        status = .passed
                        totalPassed += 1
                    }

                    suiteCaseIDs.append(stableID)
                    testCases.append(
                        ParsedTestCase(
                            stableID: stableID,
                            suite: suiteName,
                            name: displayName(for: testCase.name),
                            status: status,
                            rerunSelector: .gradleTestFilter(testCase.name)
                        )
                    )
                }

                suites.append(
                    ParsedTestSuite(
                        name: suiteName,
                        stableID: suiteID,
                        file: fileURL.lastPathComponent,
                        testCaseIDs: suiteCaseIDs
                    )
                )
            } catch {
                logger.error("Failed to parse JUnit XML at \(fileURL.path): \(error.localizedDescription)")
                diagnostics.append(
                    ParsingDiagnostic(
                        severity: .error,
                        message: "Failed to parse JUnit XML: \(error.localizedDescription)",
                        source: fileURL.path
                    )
                )
            }
        }

        return ParsedTestRun(
            platform: "android",
            runner: "gradle",
            source: reportDirectory,
            summary: TestSummary(passed: totalPassed, failed: totalFailed, skipped: totalSkipped),
            suites: suites,
            testCases: testCases,
            diagnostics: diagnostics
        )
    }

    private func junitXMLFiles(in directoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "xml" {
            results.append(fileURL)
        }
        return results
    }

    private func suiteName(for fileURL: URL, parser: JUnitXMLParser) -> String {
        parser.testCases.first?.name.split(separator: ".").dropLast().joined(separator: ".")
            .nilIfEmpty
            ?? fileURL.deletingPathExtension().lastPathComponent
    }

    private func displayName(for fullyQualifiedName: String) -> String {
        fullyQualifiedName.split(separator: ".").last.map(String.init) ?? fullyQualifiedName
    }
}

extension AndroidJUnitTestParser: TestResultParser {
    public func parse(_ input: String) async throws -> ParsedTestRun {
        try await parse(reportDirectory: input)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
