import OSLog
import SwiftyShell

/// Runs unit and UI tests using `xcodebuild test`.
///
/// Supports running tests against one or more destinations in a single invocation.
/// When multiple destinations are provided ShipIt runs a separate `xcodebuild test`
/// pass for each destination, aggregating pass/fail/skip counts across all runs.
///
/// If `destinations` is empty or `nil` and no `destination` fallback is provided,
/// the action throws `ShipItError.invalidConfiguration` rather than inventing a
/// simulator name that may not exist on the current machine. Use
/// `DestinationDiscovery` to enumerate valid destinations before configuring this action.
///
/// ## Usage
/// ```swift
/// let result = try await TestAction().run(
///     with: .init(
///         scheme: "MyApp",
///         destinations: ["platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2"],
///         enableCodeCoverage: true
///     ),
///     context: context
/// )
/// print("Passed: \(result.passCount), Failed: \(result.failCount), Skipped: \(result.skipCount)")
/// if let bundle = result.resultBundlePath {
///     print("Result bundle: \(bundle)")
/// }
/// ```
public struct TestAction: Action {
    public static let name = "test"
    public static let description = "Run unit and UI tests using xcodebuild test"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", TestAction.self)

    /// Creates a `TestAction`.
    public init() {}

    /// Configuration for the test action.
    public struct Options: Codable, Sendable {
        /// Xcode scheme containing the test targets.
        public var scheme: String?

        /// One or more xcodebuild destination strings.
        ///
        /// Each entry is passed as `-destination <value>` to a separate `xcodebuild test`
        /// invocation. Results are aggregated across all destinations.
        ///
        /// Example entries:
        /// - `"platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2"`
        /// - `"platform=iOS,name=My iPhone"`
        ///
        /// When non-nil and non-empty this field takes precedence over `destination`.
        /// Use `DestinationDiscovery` to populate this from available devices rather
        /// than constructing strings by hand.
        public var destinations: [String]?

        /// Single simulator or device destination string.
        ///
        /// Kept for backward compatibility with existing Shipfiles that set a single
        /// destination. When both `destinations` and `destination` are set, `destinations`
        /// wins. When only `destination` is set it is promoted to a one-element
        /// `destinations` list internally.
        ///
        /// Prefer `destinations` for new configuration.
        public var destination: String?

        /// Build configuration. Default: `Debug`.
        public var configuration: String?

        /// Whether to enable code coverage collection.
        /// When `true` and `resultBundlePath` is not set, a default path of
        /// `./build/<scheme>-tests.xcresult` is used automatically.
        public var enableCodeCoverage: Bool?

        /// Path to write the `.xcresult` bundle. Auto-derived when
        /// `enableCodeCoverage` is `true` and this is `nil`.
        ///
        /// If the bundle already exists at this path it is removed before
        /// `xcodebuild test` is invoked, making repeated runs safe without
        /// requiring manual cleanup between runs.
        public var resultBundlePath: String?

        /// Test plan name to run (if multiple plans exist).
        public var testPlan: String?

        /// Restrict the run to specific test targets or test cases.
        /// Each entry maps to a separate `-only-testing` argument.
        /// Example: `["MyAppTests/MyFeatureTests", "MyAppTests/MyFeatureTests/testSomething"]`
        public var onlyTesting: [String]?

        /// Skip specific test targets or test cases.
        /// Each entry maps to a separate `-skip-testing` argument.
        public var skipTesting: [String]?

        /// Automatically retry failing tests once before reporting failure.
        public var retryOnFailure: Bool?

        /// Creates `Options` for the test action.
        ///
        /// All parameters are optional; unset values fall back to `ResolvedConfig`.
        public init(
            scheme: String? = nil,
            destinations: [String]? = nil,
            destination: String? = nil,
            configuration: String? = nil,
            enableCodeCoverage: Bool? = nil,
            resultBundlePath: String? = nil,
            testPlan: String? = nil,
            onlyTesting: [String]? = nil,
            skipTesting: [String]? = nil,
            retryOnFailure: Bool? = nil
        ) {
            self.scheme = scheme
            self.destinations = destinations
            self.destination = destination
            self.configuration = configuration
            self.enableCodeCoverage = enableCodeCoverage
            self.resultBundlePath = resultBundlePath
            self.testPlan = testPlan
            self.onlyTesting = onlyTesting
            self.skipTesting = skipTesting
            self.retryOnFailure = retryOnFailure
        }

        /// Returns the effective list of destination strings to use.
        ///
        /// Resolution order:
        /// 1. `destinations` when non-nil and non-empty
        /// 2. `[destination]` when `destination` is non-nil (backward compat)
        /// 3. `nil` — caller must treat as "no destinations configured"
        var resolvedDestinations: [String]? {
            if let destinations, !destinations.isEmpty { return destinations }
            if let destination { return [destination] }
            return nil
        }
    }

    /// Result of a test run.
    public struct Result: Codable, Sendable {
        /// Number of tests that passed (summed across all destinations).
        public let passCount: Int

        /// Number of tests that failed (summed across all destinations).
        public let failCount: Int

        /// Number of tests that were skipped (summed across all destinations).
        public let skipCount: Int

        /// Path to the `.xcresult` bundle (present when `resultBundlePath` was set
        /// or auto-derived because `enableCodeCoverage` was `true`).
        public let resultBundlePath: String?

        /// Whether all executed tests passed (no failures).
        public var succeeded: Bool { failCount == 0 }

        /// Creates a `Result`.
        public init(
            passCount: Int = 0,
            failCount: Int = 0,
            skipCount: Int = 0,
            resultBundlePath: String? = nil
        ) {
            self.passCount = passCount
            self.failCount = failCount
            self.skipCount = skipCount
            self.resultBundlePath = resultBundlePath
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        guard let scheme else {
            throw ShipItError.invalidConfiguration(
                reason: "Test requires a scheme. Set app.scheme in Shipfile.yml or pass --scheme."
            )
        }

        guard let effectiveDestinations = options.resolvedDestinations, !effectiveDestinations.isEmpty else {
            throw ShipItError.invalidConfiguration(
                reason: """
                Test requires at least one destination. \
                Use `DestinationDiscovery` to find available destinations for scheme '\(scheme)', \
                then set `destinations` in the test step options. \
                Example: destinations: ["platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2"]
                """
            )
        }

        let configuration = options.configuration ?? "Debug"

        // Auto-derive a result bundle path when coverage is requested but no path was given.
        let effectiveResultBundlePath: String?
        if options.enableCodeCoverage == true, options.resultBundlePath == nil {
            effectiveResultBundlePath = "./build/\(scheme)-tests.xcresult"
        } else {
            effectiveResultBundlePath = options.resultBundlePath
        }

        // Remove any stale .xcresult bundle before invoking xcodebuild.
        // xcodebuild exits with code 64 when the result bundle path already exists,
        // so we proactively remove it to make repeated runs safe.
        if let bundlePath = effectiveResultBundlePath {
            let fm = FileManager.default
            if fm.fileExists(atPath: bundlePath) {
                logger.info("Removing stale result bundle at '\(bundlePath)'")
                do {
                    try fm.removeItem(atPath: bundlePath)
                } catch {
                    logger.error("Failed to remove stale result bundle at '\(bundlePath)': \(error)")
                    throw ShipItError.invalidConfiguration(
                        reason: "Could not remove existing result bundle at '\(bundlePath)': \(error.localizedDescription)"
                    )
                }
            }
        }

        // Run a separate xcodebuild test pass for each destination, aggregating counts.
        var totalPass = 0
        var totalFail = 0
        var totalSkip = 0

        for destination in effectiveDestinations {
            logger.info("Testing scheme '\(scheme)' on '\(destination)'")

            let (pass, fail, skip) = try await runSingle(
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                resultBundlePath: effectiveResultBundlePath,
                options: options,
                context: context
            )
            totalPass += pass
            totalFail += fail
            totalSkip += skip
        }

        logger.info("Tests complete — pass: \(totalPass), fail: \(totalFail), skip: \(totalSkip)")

        return Result(
            passCount: totalPass,
            failCount: totalFail,
            skipCount: totalSkip,
            resultBundlePath: effectiveResultBundlePath
        )
    }

    // MARK: - Single destination run

    private func runSingle(
        scheme: String,
        destination: String,
        configuration: String,
        resultBundlePath: String?,
        options: Options,
        context: ActionContext
    ) async throws -> (pass: Int, fail: Int, skip: Int) {
        var xcodeBuild = XcodeBuild(context: context.shell)
            .option(.scheme(scheme))
            .option(.configuration(configuration))
            .option(.destination(destination))
            .trailingArgument("test")

        if let workspace = context.config.appWorkspace {
            xcodeBuild = xcodeBuild.option(.workspace(workspace))
        } else if let project = context.config.appProject {
            xcodeBuild = xcodeBuild.option(.project(project))
        }

        if options.enableCodeCoverage == true {
            xcodeBuild = xcodeBuild.option(.enableCodeCoverage("YES"))
        }

        if let resultPath = resultBundlePath {
            xcodeBuild = xcodeBuild.option(.resultBundlePath(resultPath))
        }

        if let testPlan = options.testPlan {
            xcodeBuild = xcodeBuild.option(.testPlan(testPlan))
        }

        for target in options.onlyTesting ?? [] {
            xcodeBuild = xcodeBuild.option(.onlyTesting(target))
        }

        for target in options.skipTesting ?? [] {
            xcodeBuild = xcodeBuild.option(.skipTesting(target))
        }

        if options.retryOnFailure == true {
            xcodeBuild = xcodeBuild.option(.retryTestsOnFailure)
        }

        let output: ShellOutput
        do {
            output = try await xcodeBuild.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let failCount = parseFailureCount(from: combinedLog)
            logger.error("Tests failed on '\(destination)' with \(failCount) failure(s)")
            throw ShipItError.testFailed(
                exitCode: Int(shellOutput.exitCode),
                failureCount: failCount,
                log: combinedLog
            )
        }

        if output.exitCode != 0 {
            let combinedLog = output.stdout + output.stderr
            let failCount = parseFailureCount(from: combinedLog)
            logger.error("Tests failed on '\(destination)' with \(failCount) failure(s)")
            throw ShipItError.testFailed(
                exitCode: Int(output.exitCode),
                failureCount: failCount,
                log: combinedLog
            )
        }

        let (pass, skip) = parseCounts(from: output.stdout)
        logger.info("'\(destination)' — passed: \(pass), skipped: \(skip)")
        return (pass: pass, fail: 0, skip: skip)
    }

    // MARK: - Private Helpers

    /// Parses `(pass, skip)` from xcodebuild summary output.
    ///
    /// xcodebuild prints a summary line like:
    /// ```
    /// Executed 12 tests, with 2 failures (0 unexpected) in 1.234 (1.567) seconds
    /// ```
    /// or, when tests are skipped:
    /// ```
    /// Executed 12 tests, with 2 skipped and 0 failures (0 unexpected) in 1.234 (1.567) seconds
    /// ```
    private func parseCounts(from output: String) -> (pass: Int, skip: Int) {
        for line in output.components(separatedBy: "\n") {
            guard line.contains("Executed") else { continue }

            let words = line.components(separatedBy: " ")
            guard let executedIdx = words.firstIndex(of: "Executed"),
                  words.indices.contains(executedIdx + 1),
                  let total = Int(words[executedIdx + 1]) else { continue }

            // "X skipped" appears before "Y failures" in the summary
            var skipped = 0
            if let skippedIdx = words.firstIndex(of: "skipped"),
               skippedIdx > 0,
               let s = Int(words[skippedIdx - 1]) {
                skipped = s
            }

            return (pass: total - skipped, skip: skipped)
        }
        return (pass: 0, skip: 0)
    }

    /// Parses failure count from xcodebuild failure summary output.
    ///
    /// Handles both the bulk summary form:
    /// ```
    /// ** TEST FAILED ** (3 failures)
    /// ```
    /// and per-test failure lines (parallelized output):
    /// ```
    /// MyTests.testFoo: FAILED
    /// ```
    private func parseFailureCount(from output: String) -> Int {
        let lines = output.components(separatedBy: "\n")

        // First try the bulk summary "(N failures)" or "(1 failure)"
        for line in lines {
            guard line.contains("TEST FAILED") else { continue }

            let words = line.components(separatedBy: " ")
            for (i, word) in words.enumerated() {
                if (word == "failures)" || word == "failure)") && i > 0 {
                    let raw = words[i - 1].trimmingCharacters(in: .init(charactersIn: "("))
                    if let count = Int(raw) { return count }
                }
            }
            // Summary line found but count not parseable — treat as 1
            return 1
        }

        // Fallback: count individual "FAILED" lines (parallel test output)
        let perTestFailures = lines.filter {
            $0.hasSuffix(": FAILED") || $0.hasSuffix("FAILED)")
        }.count
        return perTestFailures > 0 ? perTestFailures : 0
    }
}
