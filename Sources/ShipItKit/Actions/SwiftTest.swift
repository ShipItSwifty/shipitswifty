import Foundation
import SwiftyShell

/// Runs SwiftPM tests with saved Swift Testing events, evidence, and selective reruns.
///
/// ## Usage
/// ```swift
/// try await SwiftTestAction().run(with: .init(packagePath: ".", enableCodeCoverage: true), context: context)
/// ```
public struct SwiftTestAction: Action {
    public static let name = "swift-test"
    public static let description = "Run SwiftPM tests with structured results, coverage, and selective reruns"
    public init() {}
    public struct Options: Codable, Sendable {
        public var packagePath: String?
        public var scratchPath: String?
        public var filter: String?
        public var skip: String?
        public var environment: [String: String]?
        public var enableCodeCoverage: Bool?
        public var outputDirectory: String?
        public var infrastructureRetry: InfrastructureRetryScheduler.Options?
        public var rerunFailedTests: TestAction.FailedTestRerunOptions?
        public init(
            packagePath: String? = nil, scratchPath: String? = nil, filter: String? = nil, skip: String? = nil,
            environment: [String: String]? = nil, enableCodeCoverage: Bool? = nil, outputDirectory: String? = nil,
            rerunFailedTests: TestAction.FailedTestRerunOptions? = nil, infrastructureRetry: InfrastructureRetryScheduler.Options? = nil
        ) {
            self.infrastructureRetry = infrastructureRetry
            self.packagePath = packagePath
            self.scratchPath = scratchPath
            self.filter = filter
            self.skip = skip
            self.environment = environment
            self.enableCodeCoverage = enableCodeCoverage
            self.outputDirectory = outputDirectory
            self.rerunFailedTests = rerunFailedTests
        }
    }
    public struct Result: Codable, Sendable {
        public let report: TestRunReport
        public let outputDirectory: String
        public let coveragePath: String?
        public var succeeded: Bool { report.summary.failed + report.summary.errored == 0 }
    }
    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let root = URL(
            fileURLWithPath: options.outputDirectory ?? (context.evidenceRoot.map { $0 + "/test-runs/" } ?? "build/test-runs/")
                + "swift-\(UUID().uuidString)"
        ).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: root.path) else {
            throw ShipItError.invalidConfiguration(reason: "Test output directory already exists: \(root.path)")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do { return try await execute(options: options, context: context, root: root) } catch {
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent("report.json").path) {
                try? writeJSON(
                    TestRunReport(
                        runner: .swiftTest, buildSystem: .native, source: root.path,
                        attempts: [], summary: .init(errored: 1)), to: root.appendingPathComponent("report.json"))
            }
            throw error
        }
    }
    private func execute(options: Options, context: ActionContext, root: URL) async throws -> Result {
        let maxAttempts = options.rerunFailedTests?.enabled == true ? max(1, options.rerunFailedTests?.maxAttempts ?? 2) : 1
        // `swift test` runs on this machine.
        let destination = TestDestination.host()
        var attempts: [TestAttempt] = []
        var initial: ParsedTestRun?
        var remaining: [ParsedTestCase] = []
        var flaky: [ParsedTestCase] = []
        var coveragePath: String?
        var lastOutput: ShellOutput?
        var number = 1
        var selectedRuns = 0
        var infrastructureAttempts = 1
        var delay = options.infrastructureRetry?.resolvedInitialDelay ?? .zero
        var reason = "initial"
        while selectedRuns < maxAttempts {
            try Task.checkCancellation()
            let directory = root.appendingPathComponent("attempt-\(number)")
            let attachments = directory.appendingPathComponent("attachments")
            try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
            let events = directory.appendingPathComponent("events.jsonl")
            let selector: String?
            if selectedRuns == 0 {
                selector = options.filter
            } else {
                let selectors = remaining.compactMap { test -> String? in
                    guard case .swiftTestFilter(let value) = test.rerunSelector else { return nil }
                    return NSRegularExpression.escapedPattern(for: value)
                }
                guard !selectors.isEmpty else {
                    // Selective rerun needs a selector per failure; say so rather than stopping silently.
                    attempts.append(
                        .init(
                            attemptNumber: number, reason: "failed_tests",
                            metadata: ["rerun": "unsupported", "detail": "no rerun selector for the failed tests"],
                            summary: .init(), failedTests: remaining, source: root.path))
                    break
                }
                selector = "^(?:" + selectors.joined(separator: "|") + ")(?:/|$)"
            }
            var command = SwiftPMCLI(context: context.shell).test(
                package: options.packagePath ?? ".", scratch: options.scratchPath,
                events: events.path, attachments: attachments.path, coverage: options.enableCodeCoverage ?? false,
                skipBuild: selectedRuns > 0, filter: selector, skip: options.skip,
                junit: directory.appendingPathComponent("xctest.xml").path)
            for (key, value) in options.environment ?? [:] { command = command.env(key, value) }
            let output: ShellOutput
            let started = Date()
            do { output = try await command.run() } catch let ShellError.exitFailure(_, captured) { output = captured } catch {
                try? saveInterruptedTestOutput(error, directory: directory)
                throw error
            }
            let duration = Date().timeIntervalSince(started)
            saveEvidence("attempt logs", logger: context.logger) {
                try output.stdout.write(to: directory.appendingPathComponent("stdout.log"), atomically: true, encoding: .utf8)
                try output.stderr.write(to: directory.appendingPathComponent("stderr.log"), atomically: true, encoding: .utf8)
                try writeJSON(
                    CommandRecord(
                        arguments: command.command().arguments, exitCode: [String(output.exitCode)], startedAt: started,
                        durationSeconds: duration), to: directory.appendingPathComponent("command.json"))
            }
            lastOutput = output
            if output.exitCode != 0, SwiftPMInfrastructureClassifier().isRetryable(log: output.stdout + output.stderr),
                let policy = options.infrastructureRetry, infrastructureAttempts < policy.resolvedMaxAttempts
            {
                attempts.append(
                    .init(
                        attemptNumber: number, reason: reason, metadata: ["exit_code": String(output.exitCode)], summary: .init(errored: 1),
                        durationSeconds: duration,
                        source: directory.path))
                infrastructureAttempts += 1
                number += 1
                reason = "infrastructure"
                saveEvidence("attempts", logger: context.logger) {
                    try writeJSON(attempts, to: root.appendingPathComponent("attempts.json"))
                }
                try await Task.sleep(for: InfrastructureRetryScheduler.applyJitter(to: delay))
                delay = InfrastructureRetryScheduler.nextDelay(current: delay, cap: policy.resolvedMaxDelay)
                continue
            }
            selectedRuns += 1
            let swiftRun = try? SwiftEventParser().parse(path: events.path, destination: destination)
            let legacyRun = try? await AndroidJUnitTestParser().parse(
                reportDirectory: directory.appendingPathComponent("xctest.xml").path, runner: .swiftTest, buildSystem: .native,
                destination: destination)
            let cases = (swiftRun?.testCases ?? []) + (legacyRun?.testCases ?? [])
            guard !cases.isEmpty else {
                if initial != nil {
                    // An unreadable rerun must not erase what the first run established: keep the original
                    // failures as persistent, record the attempt as errored, and stop retrying.
                    attempts.append(
                        .init(
                            attemptNumber: number, reason: reason,
                            metadata: ["exit_code": String(output.exitCode), "results": "unavailable"],
                            summary: .init(errored: 1), failedTests: remaining, source: directory.path))
                    break
                }
                saveEvidence("error report", logger: context.logger) {
                    try writeJSON(attempts, to: root.appendingPathComponent("attempts.json"))
                    try writeJSON(
                        TestRunReport(
                            runner: .swiftTest, buildSystem: .native, source: root.path, destinations: [destination], attempts: attempts,
                            summary: .init(errored: 1)),
                        to: root.appendingPathComponent("report.json"))
                }
                throw ShipItError.testFailed(
                    exitCode: Int(output.exitCode == 0 ? 1 : output.exitCode), failureCount: 0,
                    log: "Swift Testing results unavailable or empty. Logs: \(directory.path)\n" + output.stdout + output.stderr)
            }
            let parsed = ParsedTestRun(
                runner: .swiftTest, buildSystem: .native, source: directory.path, destinations: [destination],
                summary: .init(
                    passed: cases.filter { $0.status == .passed }.count,
                    failed: cases.filter { $0.status == .failed }.count, skipped: cases.filter { $0.status == .skipped }.count,
                    errored: cases.filter { $0.status == .errored }.count), testCases: cases,
                diagnostics: (swiftRun?.diagnostics ?? []) + (legacyRun?.diagnostics ?? []))
            saveEvidence("attempt results", logger: context.logger) {
                try writeJSON(parsed, to: directory.appendingPathComponent("results.json"))
            }
            let failures = parsed.testCases.filter { $0.status == .failed || $0.status == .errored }
            attempts.append(
                .init(
                    attemptNumber: number, reason: reason, summary: parsed.summary,
                    failedTests: failures, durationSeconds: duration, source: events.path))
            if initial == nil {
                initial = parsed
                remaining = failures
                if options.enableCodeCoverage == true {
                    let located = try await SwiftPMCLI(context: context.shell).coveragePath(
                        package: options.packagePath ?? ".", scratch: options.scratchPath
                    ).run()
                    let source = located.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !source.isEmpty {
                        // SwiftPM writes no coverage JSON when a test fails, so this recomputes it from the raw
                        // profiles. It must run now, before a rerun adds its own profiles. Coverage is evidence: failing
                        // to save it is logged and never changes the test outcome.
                        let target = root.appendingPathComponent("coverage.json")
                        do {
                            try await saveSwiftPMCoverage(source: source, target: target, shell: context.shell)
                            coveragePath = target.path
                        } catch {
                            if error is CancellationError { throw error }
                            context.logger.warning("Coverage unavailable: \(error)")
                        }
                    }
                }
            } else {
                let passed = Set(parsed.testCases.filter { $0.status == .passed }.map(\.stableID))
                flaky += remaining.filter { passed.contains($0.stableID) }
                remaining = remaining.filter { !passed.contains($0.stableID) }
                for failure in failures where !remaining.contains(where: { $0.stableID == failure.stableID }) { remaining.append(failure) }
            }
            // A nonzero exit without case failures is an execution failure, never a recovered pass.
            if output.exitCode != 0 && failures.isEmpty { break }
            if remaining.isEmpty { break }
            number += 1
            reason = "failed_tests"
            infrastructureAttempts = 1
        }
        guard let initial else { throw ShipItError.invalidConfiguration(reason: "Swift tests produced no initial results") }
        let executionError = remaining.isEmpty && lastOutput?.exitCode != 0
        let report = TestRunReport(
            runner: .swiftTest, buildSystem: .native, source: root.path, destinations: [destination], attempts: attempts,
            initialFailedTests: initial.testCases.filter { $0.status == .failed || $0.status == .errored }, flakyTests: flaky,
            persistentFailedTests: remaining,
            summary: .init(
                passed: initial.summary.passed + flaky.count,
                failed: remaining.filter { $0.status == .failed }.count, skipped: initial.summary.skipped, flaky: flaky.count,
                errored: remaining.filter { $0.status == .errored }.count + (executionError ? 1 : 0)),
            testCases: finalTestCases(initial.testCases, remaining: remaining, flaky: flaky, attempts: attempts)
        ).unifyingFlaky()
        saveEvidence("report", logger: context.logger) { try writeJSON(report, to: root.appendingPathComponent("report.json")) }
        if !remaining.isEmpty || executionError {
            throw ShipItError.testFailed(
                exitCode: Int(lastOutput?.exitCode ?? 1), failureCount: max(1, remaining.count), log: "See \(root.path)/report.json")
        }
        return .init(report: report, outputDirectory: root.path, coveragePath: coveragePath)
    }
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(value).write(to: url, options: .atomic)
}
