import ArgumentParser
import Foundation
import ShipItKit

/// Read and normalize native test-result artifacts produced by a prior test run.
struct TestResultsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-results",
        abstract: "Read and normalize test-result artifacts (iOS: xcresult, Android: JUnit XML)"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .customLong("xcresult"), help: "Explicit path to .xcresult bundle (iOS). Auto-discovered when omitted.")
    var xcresultPath: String?

    @Option(name: .long, help: "Explicit path to a JUnit XML report directory (Android). Auto-discovered when omitted.")
    var report: String?

    @Flag(name: .long, help: "Only include failed and errored tests")
    var failedOnly: Bool = false

    @Flag(name: .long, help: "Suppress passed tests from the parsed output")
    var excludePassed: Bool = false

    @Option(name: .long, help: "Output format: text | json | markdown")
    var format: String?

    @Option(name: .customLong("report-path"), help: "Write the structured JSON report to a file")
    var reportPath: String?

    mutating func validate() throws {
        if xcresultPath != nil, report != nil {
            throw ValidationError("Specify either --xcresult or --report, not both.")
        }
        if xcresultPath != nil, global.platform == .android {
            throw ValidationError("--xcresult is only valid with --platform ios.")
        }
        if report != nil, global.platform == .ios {
            throw ValidationError("--report is only valid with --platform android.")
        }
        if let format, TestResultsFormat(rawValue: format) == nil {
            throw ValidationError("Invalid --format '\(format)'. Use text, json, or markdown.")
        }
        if global.output == .json, let format, format != TestResultsFormat.json.rawValue {
            throw ValidationError("--output json cannot be combined with --format \(format). Use --format json or omit --format.")
        }
    }

    func run() async throws {
        do {
            let hasExplicitArtifact = xcresultPath != nil || report != nil
            let context: ActionContext
            if hasExplicitArtifact, !FileManager.default.fileExists(atPath: configuredShipfilePath(from: global)) {
                context = try await buildFallbackActionContext(platform: inferredPlatform(), verbose: global.verbose)
            } else {
                let config = try await resolveRequiredConfig(
                    global: global,
                    cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
                )
                context = try await buildActionContext(config: config, verbose: global.verbose)
            }

            let resolvedFormat = resolvedFormat()
            let options = TestResultsAction.Options(
                format: resolvedFormat,
                platform: inferredPlatform().rawValue,
                xcresultPath: xcresultPath,
                reportPath: report,
                failedOnly: failedOnly ? true : nil,
                includePassed: excludePassed ? false : nil,
                reportOutputPath: reportPath
            )

            if global.dryRun {
                let source = xcresultPath ?? report ?? "<auto-discovered>"
                try outputDryRun(
                    action: TestResultsAction.name,
                    message: "Would read \(options.platform ?? inferredPlatform().rawValue) test results from '\(source)'",
                    payload: ["platform": .string(options.platform ?? inferredPlatform().rawValue), "source": .string(source)],
                    global: global
                )
                return
            }

            let result = try await TestResultsAction().run(with: options, context: context)
            switch resolvedFormat {
            case .json:
                outputResult(action: TestResultsAction.name, result: result, format: .json, colorMode: global.effectiveColorMode)
            case .markdown:
                printMarkdown(result: result)
            case .text, .none:
                printHuman(result: result)
            }
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }

    private func inferredPlatform() -> Platform {
        if let platform = global.platform { return platform }
        if xcresultPath != nil { return .ios }
        if report != nil { return .android }
        return .ios
    }

    private func resolvedFormat() -> TestResultsFormat? {
        if let format {
            return TestResultsFormat(rawValue: format)
        }
        switch global.output {
        case .json: return .json
        case .human: return .text
        }
    }

    private func printHuman(result: TestResultsAction.Result) {
        let formatter = makeHumanFormatter(global: global)
        let summary = result.parsedRun.summary
        formatter.printSuccess("Test Results")
        formatter.print("Source: \(result.parsedRun.source)")
        formatter.print("Passed: \(summary.passed), Failed: \(summary.failed), Skipped: \(summary.skipped), Errored: \(summary.errored)")

        let failures = result.parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored }
        if !failures.isEmpty {
            formatter.print("")
            formatter.print("Failures:")
            for test in failures.prefix(10) {
                let suite = test.suite.map { "\($0)/" } ?? ""
                formatter.print("  - \(suite)\(test.name)")
            }
            if failures.count > 10 {
                formatter.print("  - +\(failures.count - 10) more")
            }
        }

        if let reportPath {
            formatter.print("")
            formatter.print("Report written to: \(reportPath)")
        }
    }

    private func printMarkdown(result: TestResultsAction.Result) {
        let summary = result.parsedRun.summary
        print("## Test Results")
        print("")
        print("> Source: `\(result.parsedRun.source)`")
        print("")
        print("| Metric | Count |")
        print("|---|---:|")
        print("| Passed | \(summary.passed) |")
        print("| Failed | \(summary.failed) |")
        print("| Skipped | \(summary.skipped) |")
        print("| Errored | \(summary.errored) |")
    }
}
