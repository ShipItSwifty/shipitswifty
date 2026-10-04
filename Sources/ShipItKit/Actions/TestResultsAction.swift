import Foundation
import Logging
import SwiftyShell

/// Reads and normalizes test-result artifacts produced by a prior test run.
///
/// ShipItSwifty does **not** generate test results here — it reads and
/// normalizes artifacts that the platform toolchain already produced:
/// - **iOS**: `.xcresult` bundles created by `xcodebuild test -resultBundlePath ...`
/// - **Android**: Gradle JUnit XML reports written under `build/test-results/...`
///
/// ## Usage
/// ```swift
/// let result = try await TestResultsAction().run(
///     with: .init(xcresultPath: "./build/MyApp-tests.xcresult"),
///     context: context
/// )
///
/// print(result.report.summary.failed)
/// ```
public struct TestResultsAction: Action {
    public static let name = "test-results"
    public static let description = "Read and normalize test-result artifacts (iOS: xcresult, Android: JUnit XML)"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", TestResultsAction.self)

    public init() {}

    public struct Options: Codable, Sendable {
        public var inputs: [String]?
        public var inputFormat: TestInputFormat?
        public var runner: String?
        public var coverageInputs: [String]?
        public var coverageFormat: CoverageInputFormat?
        public var evidencePaths: [String]?
        public var exportDirectory: String?
        public var format: TestResultsFormat?
        public var platform: String?
        public var xcresultPath: String?
        public var reportPath: String?
        public var failedOnly: Bool?
        public var includePassed: Bool?
        public var reportOutputPath: String?

        public init(
            inputs: [String]? = nil,
            inputFormat: TestInputFormat? = nil,
            runner: String? = nil,
            coverageInputs: [String]? = nil,
            coverageFormat: CoverageInputFormat? = nil,
            evidencePaths: [String]? = nil,
            exportDirectory: String? = nil,
            format: TestResultsFormat? = nil,
            platform: String? = nil,
            xcresultPath: String? = nil,
            reportPath: String? = nil,
            failedOnly: Bool? = nil,
            includePassed: Bool? = nil,
            reportOutputPath: String? = nil
        ) {
            self.inputs = inputs
            self.inputFormat = inputFormat
            self.runner = runner
            self.coverageInputs = coverageInputs
            self.coverageFormat = coverageFormat
            self.evidencePaths = evidencePaths
            self.exportDirectory = exportDirectory
            self.format = format
            self.platform = platform
            self.xcresultPath = xcresultPath
            self.reportPath = reportPath
            self.failedOnly = failedOnly
            self.includePassed = includePassed
            self.reportOutputPath = reportOutputPath
        }
    }

    public struct Result: Codable, Sendable {
        public let exportManifest: EvidenceManifest?
        public let parsedRun: ParsedTestRun
        public let report: TestRunReport
        public let reportPath: String?

        public init(parsedRun: ParsedTestRun, report: TestRunReport, reportPath: String? = nil, exportManifest: EvidenceManifest? = nil) {
            self.exportManifest = exportManifest
            self.parsedRun = parsedRun
            self.report = report
            self.reportPath = reportPath
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let explicitPlatform = options.platform.flatMap(Platform.init(rawValue:))
        let platform = explicitPlatform ?? context.platform

        let paths: [String]
        if let inputs = options.inputs, !inputs.isEmpty {
            paths = inputs
        } else if let path = options.xcresultPath ?? options.reportPath {
            paths = [path]
        } else {
            switch platform {
            case .ios:
                #if os(macOS)
                guard let path = resolveXCResultPath(options: options, config: context.config) else {
                    throw ShipItError.invalidConfiguration(reason: "No results found; supply --input or --xcresult.")
                }
                paths = [path]
                #else
                throw ShipItError.invalidConfiguration(reason: "Supply an explicit portable test result input on Linux.")
                #endif
            case .android:
                guard let path = resolveAndroidReportPath(options: options, config: context.config) else {
                    throw ShipItError.invalidConfiguration(reason: "No results found; supply --input or --report.")
                }
                paths = [path]
            }
        }
        var runs: [ParsedTestRun] = []
        for path in paths {
            runs.append(try await ResultInspection(shell: context.shell).read(path, format: options.inputFormat, runner: options.runner))
        }
        let parsedRun: ParsedTestRun
        if runs.count == 1 {
            parsedRun = runs[0]
        } else {
            let cases = runs.enumerated().flatMap { index, run in
                run.testCases.map { test in
                    ParsedTestCase(
                        stableID: "input-\(index + 1):" + test.stableID, suite: test.suite, name: test.name,
                        status: test.status, durationSeconds: test.durationSeconds, message: test.message,
                        file: test.file, line: test.line, rerunSelector: test.rerunSelector, metadata: test.metadata)
                }
            }
            parsedRun = ParsedTestRun(
                platform: "multiple", runner: options.runner ?? "multiple", source: paths.joined(separator: ", "),
                summary: TestSummary(
                    passed: runs.reduce(0) { $0 + $1.summary.passed }, failed: runs.reduce(0) { $0 + $1.summary.failed },
                    skipped: runs.reduce(0) { $0 + $1.summary.skipped }, errored: runs.reduce(0) { $0 + $1.summary.errored }),
                testCases: cases, diagnostics: runs.flatMap(\.diagnostics))
        }
        var coverage: [CoverageAction.Result] = []
        for path in options.coverageInputs ?? [] {
            guard let format = options.coverageFormat else {
                throw ShipItError.invalidConfiguration(reason: "coverage_format is required with coverage_inputs")
            }
            coverage.append(try await PortableCoverageReader().read(path, format: format))
        }
        let manifest: EvidenceManifest?
        if let directory = options.exportDirectory {
            manifest = try await EvidenceExporter(shell: context.shell).export(
                runs: runs, sources: paths, coverage: coverage,
                evidence: options.evidencePaths ?? [], to: directory)
        } else {
            manifest = nil
        }

        let filteredRun = filter(parsedRun: parsedRun, options: options)
        let failedTests = filteredRun.testCases.filter { $0.status == .failed || $0.status == .errored }
        let report = TestRunReport(
            platform: filteredRun.platform,
            runner: filteredRun.runner,
            source: filteredRun.source,
            attempts: [
                TestAttempt(
                    attemptNumber: 1,
                    summary: filteredRun.summary,
                    failedTests: failedTests,
                    source: filteredRun.source
                )
            ],
            initialFailedTests: parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored },
            flakyTests: [],
            persistentFailedTests: parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored },
            summary: parsedRun.summary, testCases: parsedRun.testCases
        )

        if let reportOutputPath = options.reportOutputPath {
            try writeReport(report, to: reportOutputPath)
        }

        return Result(parsedRun: filteredRun, report: report, reportPath: options.reportOutputPath, exportManifest: manifest)
    }

    private func filter(parsedRun: ParsedTestRun, options: Options) -> ParsedTestRun {
        let failedOnly = options.failedOnly ?? false
        let includePassed = options.includePassed ?? true

        let filteredCases = parsedRun.testCases.filter { testCase in
            if failedOnly {
                return testCase.status == .failed || testCase.status == .errored
            }
            if !includePassed && testCase.status == .passed {
                return false
            }
            return true
        }

        let filteredCaseIDs = Set(filteredCases.map(\.stableID))
        let filteredSuites = parsedRun.suites.filter { !filteredCaseIDs.isDisjoint(with: $0.testCaseIDs) }

        return ParsedTestRun(
            platform: parsedRun.platform,
            runner: parsedRun.runner,
            source: parsedRun.source,
            summary: parsedRun.summary,
            suites: filteredSuites,
            testCases: filteredCases,
            diagnostics: parsedRun.diagnostics
        )
    }

    private func writeReport(_ report: TestRunReport, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrintedSorted.encode(report)
        try data.write(to: url)
    }

    #if os(macOS)
    private func resolveXCResultPath(options: Options, config: ResolvedConfig) -> String? {
        if let explicit = options.xcresultPath { return explicit }
        if let scheme = config.appScheme {
            let defaultPath = "./build/\(scheme)-tests.xcresult"
            if FileManager.default.fileExists(atPath: defaultPath) {
                return defaultPath
            }
        }
        return firstMatch(in: "./build", suffix: ".xcresult")
    }
    #endif

    private func resolveAndroidReportPath(options: Options, config: ResolvedConfig) -> String? {
        if let explicit = options.reportPath { return explicit }

        let module = config.androidModule
        let variant = config.androidBuildVariant
        let candidates = [
            "\(module)/build/test-results/test\(variant)UnitTest",
            "build/test-results/test\(variant)UnitTest",
            "\(module)/build/test-results/testDebugUnitTest",
            "build/test-results/testDebugUnitTest",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func firstMatch(in directory: String, suffix: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else {
            return nil
        }
        for case let path as String in enumerator where path.hasSuffix(suffix) {
            return (directory as NSString).appendingPathComponent(path)
        }
        return nil
    }
}

public enum TestResultsFormat: String, Codable, Sendable {
    case text
    case json
    case markdown
}

extension JSONEncoder {
    fileprivate static var prettyPrintedSorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
