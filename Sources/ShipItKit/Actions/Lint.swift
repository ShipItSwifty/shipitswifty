import OSLog
import SwiftyShell

/// Runs static analysis and lint checks on the codebase.
///
/// - **iOS**: Runs `xcodebuild analyze` to surface static analyzer warnings.
/// - **Android**: Runs `./gradlew lint` and optionally a specific module lint task.
///
/// ## Usage
/// ```swift
/// // iOS
/// let result = try await LintAction().run(
///     with: .init(scheme: "MyApp"),
///     context: context
/// )
/// print("iOS analyzer warnings: \(result.warningCount)")
///
/// // Android
/// let result = try await LintAction().run(
///     with: .init(module: "app"),
///     context: androidContext
/// )
/// print("Android lint issues: \(result.issueCount)")
/// print("Report: \(result.reportPath ?? "N/A")")
/// ```
///
/// ## Topics
/// ### Configuration
/// - ``Options``
/// ### Results
/// - ``Result``
public struct LintAction: Action {
    /// The registered name used in Shipfile lanes.
    public static let name = "lint"

    /// Human-readable description for `--help` output.
    public static let description = "Run static analysis and lint checks (iOS: xcodebuild analyze, Android: gradlew lint)"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", LintAction.self)

    /// Creates a `LintAction`.
    public init() {}

    /// Configuration options for the lint action.
    public struct Options: Codable, Sendable {
        // MARK: iOS options

        /// Xcode scheme to analyze. Overrides `config.appScheme`. (iOS only)
        public var scheme: String?

        /// Build configuration. Default: `Debug`. (iOS only)
        public var configuration: String?

        // MARK: Android options

        /// Gradle module to lint (e.g. `"app"`). Defaults to `config.androidModule`. (Android only)
        public var module: String?

        /// Build variant to lint (e.g. `"release"`). When set, runs `lint<Variant>` instead of `lint`. (Android only)
        public var buildVariant: String?

        /// Path to write the lint HTML/XML report. Defaults to `./build/reports/lint-results.html`. (Android only)
        public var reportPath: String?

        /// Whether to fail the build if lint errors are found. Default: `true`.
        public var failOnError: Bool?

        /// Creates `Options` for the lint action.
        public init(
            scheme: String? = nil,
            configuration: String? = nil,
            module: String? = nil,
            buildVariant: String? = nil,
            reportPath: String? = nil,
            failOnError: Bool? = nil
        ) {
            self.scheme = scheme
            self.configuration = configuration
            self.module = module
            self.buildVariant = buildVariant
            self.reportPath = reportPath
            self.failOnError = failOnError
        }
    }

    /// Result of a lint run.
    public struct Result: Codable, Sendable {
        /// Number of warnings emitted (iOS: static analyzer, Android: lint warnings).
        public let warningCount: Int

        /// Number of errors/issues emitted (Android lint errors; 0 for iOS analyze).
        public let issueCount: Int

        /// Path to the generated report file (Android only).
        public let reportPath: String?

        /// Exit code from the underlying tool.
        public let exitCode: Int

        /// Whether the lint run succeeded (no errors that would fail the build).
        public var succeeded: Bool { exitCode == 0 }

        /// Creates a `Result`.
        public init(
            warningCount: Int = 0,
            issueCount: Int = 0,
            reportPath: String? = nil,
            exitCode: Int = 0
        ) {
            self.warningCount = warningCount
            self.issueCount = issueCount
            self.reportPath = reportPath
            self.exitCode = exitCode
        }
    }

    /// Execute the lint action.
    ///
    /// - Parameters:
    ///   - options: Lint configuration options.
    ///   - context: Shared execution context.
    /// - Returns: Lint result with issue counts and report path.
    /// - Throws: ``ShipItError/buildFailed(exitCode:log:)`` if lint exits non-zero and `failOnError` is true.
    public func run(with options: Options, context: ActionContext) async throws -> Result {
        switch context.platform {
        case .ios:
            return try await runIOS(options: options, context: context)
        case .android:
            return try await runAndroid(options: options, context: context)
        }
    }

    // MARK: - iOS Lint (xcodebuild analyze)

    private func runIOS(options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        guard let scheme else {
            throw ShipItError.invalidConfiguration(
                reason: "Lint requires a scheme. Set app.scheme in Shipfile.yml or pass --scheme."
            )
        }

        let configuration = options.configuration ?? "Debug"
        logger.info("Analyzing iOS scheme '\(scheme)' (\(configuration))")

        var xcodeBuild = XcodeBuild(context: context.shell)
            .option(.scheme(scheme))
            .option(.configuration(configuration))
            .trailingArgument("analyze")

        if let workspace = context.config.appWorkspace {
            xcodeBuild = xcodeBuild.option(.workspace(workspace))
        } else if let project = context.config.appProject {
            xcodeBuild = xcodeBuild.option(.project(project))
        }

        let output: ShellOutput
        do {
            output = try await xcodeBuild.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            logger.error("iOS analyze failed with exit code \(shellOutput.exitCode)")
            throw ShipItError.buildFailed(
                exitCode: Int(shellOutput.exitCode),
                log: [shellOutput.stdout, shellOutput.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
        }

        if output.exitCode != 0 {
            logger.error("iOS analyze failed with exit code \(output.exitCode)")
            throw ShipItError.buildFailed(exitCode: Int(output.exitCode), log: output.stderr)
        }

        let warnings = countWarnings(in: output.stdout)
        logger.info("iOS analyze succeeded — \(warnings) warning(s)")

        return Result(
            warningCount: warnings,
            issueCount: 0,
            reportPath: nil,
            exitCode: Int(output.exitCode)
        )
    }

    // MARK: - Android Lint (gradlew lint)

    private func runAndroid(options: Options, context: ActionContext) async throws -> Result {
        let module = options.module ?? context.config.androidModule
        let reportPath = options.reportPath ?? "./build/reports/lint-results.html"
        let failOnError = options.failOnError ?? true

        // Determine task: lintRelease, lintDebug, or just lint
        let taskName: String
        if let variant = options.buildVariant {
            taskName = "lint\(variant.prefix(1).uppercased() + variant.dropFirst())"
        } else {
            taskName = "lint"
        }

        logger.info("Running Android lint task '\(taskName)' for module '\(module)'")

        let gradle = Gradle(context: context.shell)
            .task(GradleTask(name: "\(module):\(taskName)"))
            .flag(.noDaemon)

        let output: ShellOutput
        do {
            output = try await gradle.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let issueCount = countLintIssues(in: combinedLog)
            logger.error("Android lint failed — \(issueCount) issue(s)")

            if failOnError {
                throw ShipItError.buildFailed(
                    exitCode: Int(shellOutput.exitCode),
                    log: combinedLog
                )
            }

            return Result(
                warningCount: 0,
                issueCount: issueCount,
                reportPath: reportPath,
                exitCode: Int(shellOutput.exitCode)
            )
        }

        let issueCount = countLintIssues(in: output.stdout)
        logger.info("Android lint succeeded — \(issueCount) issue(s). Report: \(reportPath)")

        return Result(
            warningCount: 0,
            issueCount: issueCount,
            reportPath: reportPath,
            exitCode: Int(output.exitCode)
        )
    }

    // MARK: - Private Helpers

    private func countWarnings(in output: String) -> Int {
        output.components(separatedBy: "\n")
            .filter { $0.contains("warning:") }
            .count
    }

    private func countLintIssues(in output: String) -> Int {
        // Gradle lint output: "X errors, Y warnings found in Z files"
        for line in output.components(separatedBy: "\n") {
            if line.contains("errors") && line.contains("warnings") {
                let parts = line.components(separatedBy: " ")
                var total = 0
                for (i, part) in parts.enumerated() {
                    if (part == "errors," || part == "error,") && i > 0, let n = Int(parts[i - 1]) {
                        total += n
                    }
                    if (part == "warnings" || part == "warning") && i > 0, let n = Int(parts[i - 1]) {
                        total += n
                    }
                }
                return total
            }
        }
        // Fallback: count "ERROR:" lines
        return output.components(separatedBy: "\n").filter { $0.contains("ERROR:") }.count
    }
}
