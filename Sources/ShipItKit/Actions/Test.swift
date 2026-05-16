import Foundation
import Logging
import SwiftyShell

/// Runs unit and UI tests.
///
/// - **iOS**: Uses `xcodebuild test`. Supports running against one or more destinations
///   in a single invocation, aggregating pass/fail/skip counts.
/// - **Android**: Uses `./gradlew test` (JVM unit tests) or `connectedAndroidTest`
///   (instrumented on-device tests).
///
/// When multiple destinations are provided (iOS), ShipIt runs a separate `xcodebuild test`
/// pass for each destination, aggregating pass/fail/skip counts across all runs.
///
/// If `destinations` is empty or `nil` and no `destination` fallback is provided (iOS),
/// the action throws `ShipItError.invalidConfiguration` rather than inventing a
/// simulator name that may not exist on the current machine. Use
/// `DestinationDiscovery` to enumerate valid destinations before configuring this action.
///
/// ## Usage
/// ```swift
/// // iOS
/// let result = try await TestAction().run(
///     with: .init(
///         scheme: "MyApp",
///         destinations: ["platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2"],
///         enableCodeCoverage: true
///     ),
///     context: context
/// )
/// print("Passed: \(result.passCount), Failed: \(result.failCount), Skipped: \(result.skipCount)")
///
/// // Android
/// let result = try await TestAction().run(
///     with: .init(module: "app", instrumented: false),
///     context: androidContext
/// )
/// print("Passed: \(result.passCount), Failed: \(result.failCount)")
/// ```
public struct TestAction: Action {
    public static let name = "test"
    public static let description = "Run unit and UI tests (iOS: xcodebuild test, Android: gradlew test)"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", TestAction.self)

    /// Creates a `TestAction`.
    public init() {}

    /// Configuration for the test action.
    public struct Options: Codable, Sendable {
        // MARK: iOS options

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

        /// Whether to enable code coverage collection. (iOS only)
        /// When `true` and `resultBundlePath` is not set, a default path of
        /// `./build/<scheme>-tests.xcresult` is used automatically.
        public var enableCodeCoverage: Bool?

        /// Path to write the `.xcresult` bundle. Auto-derived when
        /// `enableCodeCoverage` is `true` and this is `nil`. (iOS only)
        ///
        /// If the bundle already exists at this path it is removed before
        /// `xcodebuild test` is invoked, making repeated runs safe without
        /// requiring manual cleanup between runs.
        public var resultBundlePath: String?

        /// Test plan name to run (if multiple plans exist). (iOS only)
        public var testPlan: String?

        /// Restrict the run to specific test targets or test cases. (iOS only)
        /// Each entry maps to a separate `-only-testing` argument.
        /// Example: `["MyAppTests/MyFeatureTests", "MyAppTests/MyFeatureTests/testSomething"]`
        public var onlyTesting: [String]?

        /// Skip specific test targets or test cases. (iOS only)
        /// Each entry maps to a separate `-skip-testing` argument.
        public var skipTesting: [String]?

        /// Automatically retry failing tests once before reporting failure. (iOS only)
        public var retryOnFailure: Bool?

        // MARK: Android options

        /// Gradle module to test (e.g. `"app"`). Defaults to `config.androidModule`. (Android only)
        public var module: String?

        /// Build variant to test (e.g. `"debug"`, `"release"`). Default: `debug`. (Android only)
        public var buildVariant: String?

        /// When `true`, runs `connectedAndroidTest` (instrumented) instead of `test` (JVM). Default: `false`. (Android only)
        public var instrumented: Bool?

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
            retryOnFailure: Bool? = nil,
            module: String? = nil,
            buildVariant: String? = nil,
            instrumented: Bool? = nil
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
            self.module = module
            self.buildVariant = buildVariant
            self.instrumented = instrumented
        }

        /// Returns the effective list of destination strings to use (iOS).
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
        /// or auto-derived because `enableCodeCoverage` was `true`). (iOS only)
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
        let buildSystem: BuildSystem =
            context.platform == .ios
            ? context.config.iosBuildSystem
            : context.config.androidBuildSystem

        switch (context.platform, buildSystem) {
        case (.ios, .native):
            #if os(macOS)
            return try await runIOS(options: options, context: context)
            #else
            throw ShipItError.invalidConfiguration(reason: "iOS tests require macOS.")
            #endif
        case (.android, .native):
            return try await runAndroid(options: options, context: context)
        case (.ios, .kmp):
            #if os(macOS)
            return try await runKMPiOSTests(options: options, context: context)
            #else
            throw ShipItError.invalidConfiguration(reason: "KMP iOS tests require macOS.")
            #endif
        case (.android, .kmp):
            // KMP Android target is a regular Android Gradle module — reuse the native path.
            return try await runAndroid(options: options, context: context)
        case (_, .flutter):
            return try await runFlutterTests(options: options, context: context)
        case (_, .reactNative):
            return try await runReactNativeTests(options: options, context: context)
        }
    }

    // MARK: - Flutter Tests (flutter test)

    /// Runs `flutter test` for Flutter projects (both iOS and Android platforms).
    private func runFlutterTests(options: Options, context: ActionContext) async throws -> Result {
        logger.info("Running Flutter tests (flutter test)")
        let flutter = FlutterCLI(context: context.shell).test()
        let output: ShellOutput
        do {
            output = try await flutter.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let combinedLog = ShellRunHelpers.combinedLog(shellOutput)
            let failCount = parseFlutterFailureCount(from: combinedLog)
            logger.error("Flutter tests failed with \(failCount) failure(s)")
            throw ShipItError.testFailed(
                exitCode: Int(shellOutput.exitCode),
                failureCount: failCount,
                log: combinedLog
            )
        }
        if output.exitCode != 0 {
            let combinedLog = ShellRunHelpers.combinedLog(output)
            let failCount = parseFlutterFailureCount(from: combinedLog)
            throw ShipItError.testFailed(
                exitCode: Int(output.exitCode),
                failureCount: failCount,
                log: combinedLog
            )
        }
        let (pass, fail, skip) = parseFlutterCounts(from: output.stdout)
        logger.info("Flutter tests complete — pass: \(pass), fail: \(fail), skip: \(skip)")
        return Result(passCount: pass, failCount: fail, skipCount: skip)
    }

    // MARK: - React Native Tests (package manager run test)

    /// Runs the `test` script from `package.json` using the detected JS package manager.
    ///
    /// The package manager is auto-detected from lockfiles (`pnpm-lock.yaml` → pnpm,
    /// `yarn.lock` → yarn, otherwise npm). Throws a clear error when the `test` script
    /// is not declared in `package.json`.
    private func runReactNativeTests(
        options: Options, context: ActionContext
    ) async throws -> Result {
        let projectRoot = context.config.projectRoot
        logger.info("Running React Native tests via JS package manager")
        let runner = JSScriptRunner(context: context.shell, projectRoot: projectRoot)
        logger.info(
            "Detected package manager: \(runner.resolvedPackageManager.rawValue)"
        )
        let output = try await runner.run(script: "test")
        let (pass, fail, skip) = parseJSTestCounts(from: output.stdout + output.stderr)
        logger.info("React Native tests complete — pass: \(pass), fail: \(fail), skip: \(skip)")
        return Result(passCount: pass, failCount: fail, skipCount: skip)
    }

    // MARK: - Flutter / RN parse helpers

    static func parseFlutterTestCountsForTesting(from output: String) -> (pass: Int, fail: Int, skip: Int) {
        Self().parseFlutterCounts(from: output)
    }

    static func parseJSTestCountsForTesting(from output: String) -> (pass: Int, fail: Int, skip: Int) {
        Self().parseJSTestCounts(from: output)
    }

    private func parseFlutterCounts(from output: String) -> (pass: Int, fail: Int, skip: Int) {
        // Flutter test output format (one status line per test result, final line is summary):
        //   "00:01 +12: All tests passed!"       → 12 passed
        //   "00:02 +11 -2: Some tests failed."   → 11 passed (cumulative), 2 failed
        var bestPass = 0
        var bestFail = 0
        var bestSkip = 0
        for line in output.components(separatedBy: "\n") {
            let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var lineHasCount = false
            var lineFail = 0
            var lineSkip = 0
            for token in tokens {
                let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: ":,"))
                if stripped.hasPrefix("+"), let pass = Int(stripped.dropFirst()) {
                    bestPass = pass
                    lineHasCount = true
                } else if stripped.hasPrefix("-"), let fail = Int(stripped.dropFirst()) {
                    lineFail = fail
                    lineHasCount = true
                } else if stripped.hasPrefix("~"), let skip = Int(stripped.dropFirst()) {
                    lineSkip = skip
                    lineHasCount = true
                }
            }
            guard lineHasCount else { continue }
            bestFail = lineFail
            bestSkip = lineSkip
        }
        return (pass: bestPass, fail: bestFail, skip: bestSkip)
    }

    private func parseFlutterFailureCount(from output: String) -> Int {
        parseFlutterCounts(from: output).fail
    }

    private func parseJSTestCounts(from output: String) -> (pass: Int, fail: Int, skip: Int) {
        // Jest output: "Tests: 1 failed, 2 skipped, 12 passed, 15 total"
        var pass = 0
        var fail = 0
        var skip = 0
        for line in output.components(separatedBy: "\n") {
            guard line.contains("Tests:") else { continue }
            let words = line
                .components(separatedBy: CharacterSet.whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",")) }
                .filter { !$0.isEmpty }
            for (i, word) in words.enumerated() {
                guard i > 0 else { continue }
                if word == "passed",
                    let n = Int(words[i - 1])
                { pass = n }
                if word == "failed",
                    let n = Int(words[i - 1])
                { fail = n }
                if word == "skipped" || word == "todo",
                    let n = Int(words[i - 1])
                { skip = n }
            }
        }
        return (pass: pass, fail: fail, skip: skip)
    }

    // MARK: - KMP iOS Test (gradlew iosSimulatorArm64Test)

    /// Runs Kotlin-side KMP tests for the iOS target.
    ///
    /// Defaults to `iosSimulatorArm64Test`; consumers can override via `options.module`
    /// (interpreted as the Gradle module containing the KMP `iosX64Test`/`iosArm64Test` tasks)
    /// when their shared module lives at a non-default path.
    private func runKMPiOSTests(options: Options, context: ActionContext) async throws -> Result {
        let module = options.module ?? context.config.kmpSharedModule
        let task = GradleTask(name: context.config.kmpTestTask).qualified(module: module)

        logger.info("Running KMP iOS test task '\(task.name)'")

        let gradle = context.gradle()
            .task(task)

        let output: ShellOutput
        do {
            output = try await gradle.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let failCount = parseGradleFailureCount(from: combinedLog)
            logger.error("KMP iOS tests failed with \(failCount) failure(s)")
            throw ShipItError.testFailed(
                exitCode: Int(shellOutput.exitCode),
                failureCount: failCount,
                log: combinedLog
            )
        }

        if output.exitCode != 0 {
            let failCount = parseGradleFailureCount(from: output.stdout)
            throw ShipItError.testFailed(
                exitCode: Int(output.exitCode),
                failureCount: failCount,
                log: output.stderr
            )
        }

        let (pass, fail, skip) = parseGradleCounts(from: output.stdout)
        logger.info("KMP iOS tests complete — pass: \(pass), fail: \(fail), skip: \(skip)")
        return Result(passCount: pass, failCount: fail, skipCount: skip)
    }

    #if os(macOS)
    // MARK: - iOS Test (xcodebuild test)

    private func runIOS(options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        guard let scheme else {
            throw ShipItError.invalidConfiguration(
                reason: "Test requires a scheme. Set app.scheme in Shipfile.yml or pass --scheme."
            )
        }

        // Resolve destinations — auto-discover if none configured
        let effectiveDestinations: [String]
        if let configured = options.resolvedDestinations, !configured.isEmpty {
            effectiveDestinations = configured
        } else {
            // Attempt auto-discovery of a suitable iPhone simulator
            logger.info("No test destinations configured — auto-discovering available simulators for scheme '\(scheme)'")
            let discovered = try await autoDiscoverDestination(scheme: scheme, context: context)
            effectiveDestinations = [discovered]
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

    // MARK: - Single destination run (iOS)

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

    #endif

    // MARK: - Android Test (gradlew test / connectedAndroidTest)

    private func runAndroid(options: Options, context: ActionContext) async throws -> Result {
        let module = options.module ?? context.config.androidModule
        let variant = options.buildVariant ?? "debug"
        let instrumented = options.instrumented ?? false

        // Choose task: connectedDebugAndroidTest (instrumented) or testDebugUnitTest (JVM)
        let task: GradleTask
        if instrumented {
            task = variant.lowercased() == "debug" ? .connectedDebugAndroidTest : .connectedAndroidTest
        } else {
            task = variant.lowercased() == "debug" ? .testDebugUnitTest : .testReleaseUnitTest
        }

        logger.info("Running Android test task '\(task.name)' for module '\(module)'")

        let gradle = context.gradle()
            .task(task.qualified(module: module))

        let output: ShellOutput
        do {
            output = try await gradle.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let failCount = parseGradleFailureCount(from: combinedLog)
            logger.error("Android tests failed with \(failCount) failure(s)")
            throw ShipItError.testFailed(
                exitCode: Int(shellOutput.exitCode),
                failureCount: failCount,
                log: combinedLog
            )
        }

        if output.exitCode != 0 {
            let failCount = parseGradleFailureCount(from: output.stdout)
            throw ShipItError.testFailed(
                exitCode: Int(output.exitCode),
                failureCount: failCount,
                log: output.stderr
            )
        }

        let (pass, fail, skip) = parseGradleCounts(from: output.stdout)
        logger.info("Android tests complete — pass: \(pass), fail: \(fail), skip: \(skip)")

        return Result(passCount: pass, failCount: fail, skipCount: skip)
    }

    // MARK: - Private Helpers

    #if os(macOS)
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
                let total = Int(words[executedIdx + 1])
            else { continue }

            // "X skipped" appears before "Y failures" in the summary
            var skipped = 0
            if let skippedIdx = words.firstIndex(of: "skipped"),
                skippedIdx > 0,
                let s = Int(words[skippedIdx - 1])
            {
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

    #endif

    /// Parses Gradle test output for pass/fail/skip counts.
    ///
    /// Gradle prints a summary like:
    /// ```
    /// 12 tests completed, 2 failed, 1 skipped
    /// ```
    private func parseGradleCounts(from output: String) -> (pass: Int, fail: Int, skip: Int) {
        for line in output.components(separatedBy: "\n") {
            guard line.contains("tests completed") else { continue }

            let words = line.components(separatedBy: " ")
            var total = 0
            var failed = 0
            var skipped = 0

            for (i, word) in words.enumerated() {
                if word == "completed," && i > 0, let n = Int(words[i - 1]) { total = n }
                if word == "failed," && i > 0, let n = Int(words[i - 1]) { failed = n }
                if (word == "skipped" || word == "skipped,") && i > 0, let n = Int(words[i - 1]) { skipped = n }
            }

            return (pass: total - failed - skipped, fail: failed, skip: skipped)
        }
        return (pass: 0, fail: 0, skip: 0)
    }

    /// Parses failure count from Gradle test failure output.
    private func parseGradleFailureCount(from output: String) -> Int {
        for line in output.components(separatedBy: "\n") {
            guard line.contains("tests completed") else { continue }
            let words = line.components(separatedBy: " ")
            for (i, word) in words.enumerated() {
                if word == "failed," && i > 0, let n = Int(words[i - 1]) { return n }
            }
        }
        return 0
    }

    // MARK: - Automatic Destination Discovery

    #if os(macOS)
    /// Auto-discovers a suitable iPhone simulator destination for test runs.
    ///
    /// Uses `DestinationDiscovery` to enumerate available destinations, then selects
    /// the best iPhone simulator. Prefers the highest OS version, and among equal
    /// versions prefers Pro models.
    ///
    /// - Parameters:
    ///   - scheme: The Xcode scheme to query destinations for.
    ///   - context: Action context providing shell and config.
    /// - Returns: A destination string suitable for `-destination`.
    /// - Throws: `ShipItError.invalidConfiguration` when no suitable simulator is found.
    private func autoDiscoverDestination(scheme: String, context: ActionContext) async throws -> String {
        let discoverer = DestinationDiscovery(shell: context.shell)
        let allDestinations = try await discoverer.availableDestinations(
            scheme: scheme,
            workspace: context.config.appWorkspace,
            project: context.config.appProject
        )

        // Filter to iPhone simulators only
        let iPhoneSimulators = allDestinations.filter {
            $0.isSimulator && $0.name.contains("iPhone")
        }

        guard !iPhoneSimulators.isEmpty else {
            // Build a helpful error message listing what we found
            let found = allDestinations.map { "\($0.platform): \($0.name)" }.joined(separator: "\n  - ")
            let foundSummary =
                allDestinations.isEmpty
                ? "No destinations were found."
                : "Found \(allDestinations.count) destination(s), but none are iPhone simulators:\n  - \(found)"
            throw ShipItError.invalidConfiguration(
                reason: """
                    Could not auto-discover a suitable iPhone simulator for scheme '\(scheme)'. \
                    \(foundSummary)

                    To fix this:
                      1. Install an iOS Simulator runtime: Xcode > Settings > Platforms
                      2. Create a simulator: xcrun simctl create "iPhone 16 Pro" "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
                      3. Or set destinations explicitly in your test step options:
                         destinations: ["platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2"]
                    """
            )
        }

        // Sort: highest OS version first, then prefer Pro models, then by name
        let sorted = iPhoneSimulators.sorted { lhs, rhs in
            let lhsOS = lhs.os ?? "0"
            let rhsOS = rhs.os ?? "0"
            if lhsOS != rhsOS { return lhsOS.compare(rhsOS, options: .numeric) == .orderedDescending }
            let lhsPro = lhs.name.contains("Pro")
            let rhsPro = rhs.name.contains("Pro")
            if lhsPro != rhsPro { return lhsPro }
            return lhs.name < rhs.name
        }

        let selected = sorted[0]
        logger.info("Auto-selected simulator: '\(selected.name)' (OS \(selected.os ?? "?"))")
        return selected.destinationString
    }
    #endif
}
