import ArgumentParser
import Foundation
import ShipItKit

/// Read and normalize native test-result artifacts produced by a prior test run.
struct TestResultsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-results",
        abstract: "Inspect and export saved test results across supported runners"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .customLong("input"), help: "Result artifact path (repeatable); works without a Shipfile")
    var inputs: [String] = []
    @Option(name: .long, help: "Input format: xcresult | junit | swift | flutter | jest | shipit | manifest")
    var inputFormat: String?
    @Option(
        name: .long,
        help:
            "Tool that produced the results: xcodebuild | gradle | swift-test | flutter-test | jest. Needed for JUnit XML, which Gradle and `swift test` both write."
    )
    var runner: String?
    @Option(
        name: .long,
        help: "Project build system, since a bare result file does not say: native | kmp | flutter | react_native"
    )
    var buildSystem: String?
    @Option(name: .customLong("coverage-input"), help: "Coverage artifact (repeatable)")
    var coverageInputs: [String] = []
    @Option(name: .long, help: "Coverage format: lcov | swift | jacoco | kover")
    var coverageFormat: String?
    @Option(name: .customLong("evidence"), help: "Additional screenshots, logs, or attachment paths (repeatable)")
    var evidencePaths: [String] = []
    @Option(name: .long, help: "New directory for portable results and evidence")
    var exportDirectory: String?

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
        if let buildSystem, BuildSystem(rawValue: buildSystem) == nil {
            throw ValidationError("Unknown build system: \(buildSystem). Use native, kmp, flutter or react_native.")
        }
        if let inputFormat, TestInputFormat(rawValue: inputFormat) == nil { throw ValidationError("Unknown input format: \(inputFormat)") }
        if let coverageFormat, CoverageInputFormat(rawValue: coverageFormat) == nil {
            throw ValidationError("Unknown coverage format: \(coverageFormat)")
        }
        if !coverageInputs.isEmpty, coverageFormat == nil { throw ValidationError("--coverage-format is required with --coverage-input") }
        if !inputs.isEmpty, xcresultPath != nil || report != nil { throw ValidationError("Use --input or a legacy source flag, not both") }
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
            let hasExplicitArtifact = !inputs.isEmpty || xcresultPath != nil || report != nil
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
                inputs: inputs.isEmpty ? nil : inputs, inputFormat: inputFormat.flatMap(TestInputFormat.init(rawValue:)),
                runner: runner.map(TestRunner.init(rawValue:)),
                buildSystem: buildSystem.flatMap(BuildSystem.init(rawValue:)),
                coverageInputs: coverageInputs, coverageFormat: coverageFormat.flatMap(CoverageInputFormat.init(rawValue:)),
                evidencePaths: evidencePaths, exportDirectory: exportDirectory,
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
