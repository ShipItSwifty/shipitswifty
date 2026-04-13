import ArgumentParser
import ShipItKit
import Foundation

/// Read and summarize native coverage artifacts produced by a prior test run.
///
/// ShipItSwifty does **not** generate coverage — it reads and normalises the
/// artifacts that the platform toolchain already produces:
/// - **iOS**: `.xcresult` bundles (via `xcrun xccov`)
/// - **Android**: JaCoCo XML reports (via Gradle's `jacocoTestReport` task)
///
/// ## Usage
/// ```
/// shipit coverage
/// shipit coverage --format json
/// shipit coverage --summary
/// shipit coverage --targets
/// shipit coverage --files
/// shipit coverage --first-party-only
/// shipit coverage --include-target NovalingoFeatureRoot
/// shipit coverage --exclude-target GoogleSignIn
/// shipit coverage --xcresult ./build/MyApp-tests.xcresult
/// shipit coverage --platform android --report ./app/build/reports/jacoco/test/jacocoTestReport.xml
/// ```
struct CoverageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coverage",
        abstract: "Read and summarize native coverage artifacts (iOS: xcresult/xccov, Android: JaCoCo XML)"
    )

    @OptionGroup var global: GlobalOptions

    // MARK: - Display options

    @Flag(name: .long, help: "Print a single overall coverage line and exit")
    var summary: Bool = false

    @Flag(name: [.long, .customShort("t")], help: "Show per-target (iOS) or per-module (Android) breakdown")
    var targets: Bool = false

    @Flag(name: [.long, .customShort("f")], help: "Show per-file breakdown within each target/module")
    var files: Bool = false

    @Flag(name: .long, help: "Show per-function breakdown when available (iOS only)")
    var functions: Bool = false

    @Flag(name: .long, help: "Show only first-party targets/modules (suppresses test bundles, SPM deps, vendor frameworks)")
    var firstPartyOnly: Bool = false

    @Option(
        name: .customLong("include-target"),
        help: "Include a specific target or module by name (repeatable). Overrides first-party filter."
    )
    var includeTargets: [String] = []

    @Option(
        name: .customLong("exclude-target"),
        help: "Exclude a specific target or module by name (repeatable)."
    )
    var excludeTargets: [String] = []

    @Option(name: .long, help: "Sort order: coverage (lowest first) | name")
    var sort: String = "coverage"

    @Option(name: .long, help: "Limit number of targets/modules shown")
    var limit: Int?

    @Option(name: .long, help: "Output format: text | json | markdown")
    var format: String?

    // MARK: - Source overrides

    @Option(name: .customLong("xcresult"), help: "Explicit path to .xcresult bundle (iOS). Auto-discovered when omitted.")
    var xcresultPath: String?

    @Option(name: .long, help: "Explicit path to JaCoCo XML report (Android). Auto-discovered when omitted.")
    var report: String?

    // MARK: - Run

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(
                    ci: global.ci,
                    dryRun: global.dryRun,
                    platform: global.platform
                )
            )
            let context = try await buildActionContext(config: config)

            let coverageFormat = resolvedCoverageFormat()

            let options = CoverageAction.Options(
                format: coverageFormat,
                firstPartyOnly: firstPartyOnly ? true : nil,
                summary: summary ? true : nil,
                showTargets: targets ? true : nil,
                showFiles: files ? true : nil,
                showFunctions: functions ? true : nil,
                includeTargets: includeTargets.isEmpty ? nil : includeTargets,
                excludeTargets: excludeTargets.isEmpty ? nil : excludeTargets,
                sort: CoverageSort(rawValue: sort),
                limit: limit,
                xcresultPath: xcresultPath,
                reportPath: report
            )

            if global.dryRun {
                let formatter = makeHumanFormatter(global: global)
                let platform = context.platform.rawValue
                let source = xcresultPath ?? report ?? "<auto-discovered>"
                formatter.print("DRY RUN: Would read \(platform) coverage from '\(source)'")
                return
            }

            let result = try await CoverageAction().run(with: options, context: context)

            switch coverageFormat {
            case .json:
                outputResult(action: CoverageAction.name, result: result, format: .json, colorMode: global.effectiveColorMode)
            case .markdown:
                printMarkdown(result: result, options: options)
            case .text, .none:
                printHuman(result: result, options: options, global: global)
            }
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }

    // MARK: - Format Resolution

    private func resolvedCoverageFormat() -> CoverageFormat? {
        // --format flag wins over --output
        if let explicit = format {
            return CoverageFormat(rawValue: explicit)
        }
        // Map global --output json → coverage .json
        switch global.output {
        case .json: return .json
        case .human: return .text
        }
    }

    // MARK: - Human Output

    private func printHuman(result: CoverageAction.Result, options: CoverageAction.Options, global: GlobalOptions) {
        let formatter = makeHumanFormatter(global: global)

        // Overall line (shared by summary and full modes)
        let overallBar = coverageBar(result.overallLineCoverage)
        let overallLine = "Overall  \(overallBar)  \(String(format: "%.1f", result.overallLineCoverage))%  (\(result.coveredLines)/\(result.executableLines) lines)"

        // --summary: single line only
        if options.summary == true {
            formatter.print(overallLine)
            return
        }

        let sorted = sortedTargets(result.targets, by: options.sort ?? .coverage)
        let limited = applyLimit(sorted, limit: options.limit)

        let platformLabel = result.platform == "ios" ? "iOS" : "Android"
        let filterNote = result.firstPartyOnly ? " (first-party only)" : ""

        formatter.printSuccess("\(platformLabel) Coverage Summary\(filterNote)")
        formatter.print("Source: \(result.source)")
        formatter.print("")
        formatter.print(overallLine)

        // Per-target breakdown
        if limited.isEmpty { return }

        formatter.print("")
        let header = result.platform == "ios" ? "Target" : "Module"
        formatter.print(String(format: "%-48@  %8@  %8@", header as NSString, "Coverage" as NSString, "Lines" as NSString))
        formatter.print(String(repeating: "-", count: 70))

        for target in limited {
            let lineInfo = "\(target.coveredLines)/\(target.executableLines)"
            formatter.print(String(format: "%-48@  %6.1f%%  %@",
                                   trimName(target.name, maxLength: 48) as NSString,
                                   target.lineCoverage,
                                   lineInfo as NSString))

            // Per-file breakdown
            if options.showFiles == true && !target.files.isEmpty {
                let sortedFiles = target.files.sorted { $0.lineCoverage < $1.lineCoverage }
                for file in sortedFiles {
                    let shortPath = URL(fileURLWithPath: file.path).lastPathComponent
                    formatter.print(String(format: "  %-46@  %6.1f%%  %@",
                                          trimName(shortPath, maxLength: 46) as NSString,
                                          file.lineCoverage,
                                          "\(file.coveredLines)/\(file.executableLines)" as NSString))
                }
            }
        }

    }

    // MARK: - Markdown Output

    private func printMarkdown(result: CoverageAction.Result, options: CoverageAction.Options) {
        let sorted = sortedTargets(result.targets, by: options.sort ?? .coverage)
        let limited = applyLimit(sorted, limit: options.limit)
        let platformLabel = result.platform == "ios" ? "iOS" : "Android"
        let filterNote = result.firstPartyOnly ? " *(first-party only)*" : ""

        print("## \(platformLabel) Coverage\(filterNote)")
        print("")
        print("> **\(String(format: "%.1f", result.overallLineCoverage))%** overall — \(result.coveredLines)/\(result.executableLines) lines covered")
        print("> Source: `\(result.source)`")
        print("")

        if options.summary == true { return }
        if limited.isEmpty { return }

        let colHeader = result.platform == "ios" ? "Target" : "Module"
        print("| \(colHeader) | Coverage | Lines |")
        print("|---|---:|---:|")

        for target in limited {
            let lineInfo = "\(target.coveredLines)/\(target.executableLines)"
            print("| `\(target.name)` | \(String(format: "%.1f", target.lineCoverage))% | \(lineInfo) |")

            if options.showFiles == true && !target.files.isEmpty {
                let sortedFiles = target.files.sorted { $0.lineCoverage < $1.lineCoverage }
                for file in sortedFiles {
                    let shortPath = URL(fileURLWithPath: file.path).lastPathComponent
                    print("| &nbsp;&nbsp;`\(shortPath)` | \(String(format: "%.1f", file.lineCoverage))% | \(file.coveredLines)/\(file.executableLines) |")
                }
            }
        }
    }

    // MARK: - Helpers

    private func sortedTargets(_ targets: [CoverageTarget], by sort: CoverageSort) -> [CoverageTarget] {
        switch sort {
        case .coverage:
            return targets.sorted { $0.lineCoverage < $1.lineCoverage }
        case .name:
            return targets.sorted { $0.name < $1.name }
        }
    }

    private func applyLimit(_ targets: [CoverageTarget], limit: Int?) -> [CoverageTarget] {
        guard let limit else { return targets }
        return Array(targets.prefix(limit))
    }

    private func coverageBar(_ coverage: Double) -> String {
        let filled = Int(coverage / 10.0)
        let empty = 10 - filled
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    }

    private func trimName(_ name: String, maxLength: Int) -> String {
        guard name.count > maxLength else { return name }
        return String(name.prefix(maxLength - 1)) + "…"
    }
}
