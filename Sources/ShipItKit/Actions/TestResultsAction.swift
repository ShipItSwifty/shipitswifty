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
        public var format: TestResultsFormat?
        public var platform: String?
        public var xcresultPath: String?
        public var reportPath: String?
        public var failedOnly: Bool?
        public var includePassed: Bool?
        public var reportOutputPath: String?

        public init(
            format: TestResultsFormat? = nil,
            platform: String? = nil,
            xcresultPath: String? = nil,
            reportPath: String? = nil,
            failedOnly: Bool? = nil,
            includePassed: Bool? = nil,
            reportOutputPath: String? = nil
        ) {
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
        public let parsedRun: ParsedTestRun
        public let report: TestRunReport
        public let reportPath: String?

        public init(parsedRun: ParsedTestRun, report: TestRunReport, reportPath: String? = nil) {
            self.parsedRun = parsedRun
            self.report = report
            self.reportPath = reportPath
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let explicitPlatform = options.platform.flatMap(Platform.init(rawValue:))
        let platform = explicitPlatform ?? context.platform

        let parsedRun: ParsedTestRun
        switch platform {
        case .ios:
            #if os(macOS)
            guard let xcresultPath = resolveXCResultPath(options: options, config: context.config) else {
                throw ShipItError.invalidConfiguration(
                    reason: "No .xcresult bundle found. Provide --xcresult <path>, or run `shipit test` with --result-bundle-path first."
                )
            }
            logger.info("Reading iOS test results from \(xcresultPath)")
            parsedRun = try await IOSXCResultTestParser(shell: context.shell, logger: logger).parse(xcresultPath: xcresultPath)
            #else
            throw ShipItError.invalidConfiguration(reason: "iOS test-result parsing requires macOS.")
            #endif
        case .android:
            guard let reportPath = resolveAndroidReportPath(options: options, config: context.config) else {
                throw ShipItError.invalidConfiguration(
                    reason: "No JUnit XML report directory found. Provide --report <path>, or run the Gradle test task first."
                )
            }
            logger.info("Reading Android test results from \(reportPath)")
            parsedRun = try await AndroidJUnitTestParser(logger: logger).parse(reportDirectory: reportPath)
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
            initialFailedTests: failedTests,
            flakyTests: [],
            persistentFailedTests: failedTests,
            summary: filteredRun.summary
        )

        if let reportOutputPath = options.reportOutputPath {
            try writeReport(report, to: reportOutputPath)
        }

        return Result(parsedRun: filteredRun, report: report, reportPath: options.reportOutputPath)
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

        let summary = TestSummary(
            passed: filteredCases.filter { $0.status == .passed }.count,
            failed: filteredCases.filter { $0.status == .failed }.count,
            skipped: filteredCases.filter { $0.status == .skipped }.count,
            flaky: filteredCases.filter { $0.status == .flaky }.count,
            errored: filteredCases.filter { $0.status == .errored }.count
        )

        return ParsedTestRun(
            platform: parsedRun.platform,
            runner: parsedRun.runner,
            source: parsedRun.source,
            summary: summary,
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
