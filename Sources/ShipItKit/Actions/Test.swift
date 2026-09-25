import Foundation
import Logging
import SwiftyShell

/// What category of test is being run.
///
/// This drives whether ShipIt needs to orchestrate devices before executing.
/// - `unit`: JVM/host tests — no device needed.
/// - `instrumented`: Tests requiring the Android framework (emulator or physical device).
/// - `e2e`: Full user-journey tests via an external tool (Maestro, Detox, etc.) — reserved for future use.
public enum TestKind: String, Codable, Sendable, CaseIterable {
    case unit
    case instrumented
    case e2e
}

extension ParsedTestCase {
    fileprivate var legacyOutputName: String {
        switch rerunSelector {
        case .xcodeOnlyTesting(let value):
            return Self.formatXCTestName(value)
        case .gradleTestFilter(let value):
            return Self.formatGradleTestName(value)
        case .jest(_, let fullName):
            return Self.formatJestName(fullName)
        case .flutter(let name):
            return name
        case .unsupported(let rawIdentifier):
            return rawIdentifier
        case .none:
            return name
        }
    }

    /// `-[Module.Class testMethod]` → `Class.testMethod`
    fileprivate static func formatXCTestName(_ raw: String) -> String {
        // Strip leading `-[` and trailing `]`
        var s = raw
        if s.hasPrefix("-[") { s = String(s.dropFirst(2)) }
        if s.hasSuffix("]") { s = String(s.dropLast()) }
        // Split on the first space: left = "Module.ClassName", right = "testMethod"
        guard let spaceIdx = s.firstIndex(of: " ") else { return raw }
        let classPath = String(s[s.startIndex..<spaceIdx])
        let method = String(s[s.index(after: spaceIdx)...])
        let className = classPath.split(separator: ".").last.map(String.init) ?? classPath
        return "\(className).\(method)"
    }

    /// `com.example.SomeTest.someMethod` → `SomeTest.someMethod`
    private static func formatGradleTestName(_ raw: String) -> String {
        let parts = raw.split(separator: ".")
        guard parts.count >= 2 else { return raw }
        return parts.suffix(2).joined(separator: ".")
    }

    /// Jest fullName is already readable ("Suite testName") — reformat as "Suite > testName"
    private static func formatJestName(_ fullName: String) -> String {
        // Jest concatenates describe + test with a space: "SuiteName test name here"
        // Split on first space to separate suite from test description.
        guard let spaceIdx = fullName.firstIndex(of: " ") else { return fullName }
        let suite = String(fullName[fullName.startIndex..<spaceIdx])
        let test = String(fullName[fullName.index(after: spaceIdx)...])
        return "\(suite) > \(test)"
    }
}

private struct TestExecutionSnapshot: Sendable {
    let summary: TestSummary
    let passedTests: [String]
    let failedTests: [String]
    let parsedRun: ParsedTestRun?

    init(
        summary: TestSummary,
        passedTests: [String] = [],
        failedTests: [String] = [],
        parsedRun: ParsedTestRun? = nil
    ) {
        self.summary = summary
        self.passedTests = passedTests
        self.failedTests = failedTests
        self.parsedRun = parsedRun
    }
}

extension TestExecutionSnapshot {
    fileprivate var failedParsedTests: [ParsedTestCase] {
        if let parsedRun {
            return parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored }
        }
        return failedTests.map {
            ParsedTestCase(
                stableID: $0,
                name: $0,
                status: .failed,
                rerunSelector: .unsupported(rawIdentifier: $0)
            )
        }
    }
}

/// Where the Gradle task is qualified from.
///
/// - `module`: Task is prefixed with the module path, e.g. `:app:testDebugUnitTest`.
/// - `root`: Task runs from the Gradle root without qualification, e.g. `testDebugUnitTest`.
public enum GradleTaskScope: String, Codable, Sendable, CaseIterable {
    case module
    case root
}

/// How devices are provisioned for instrumented or e2e tests.
public enum TestDeviceStrategy: String, Codable, Sendable, CaseIterable {
    /// No device needed (unit tests).
    case none
    /// Use whatever device/emulator is already connected.
    case connected
    /// Boot specific AVDs by name.
    case namedEmulators = "named_emulators"
    /// Use Gradle Managed Devices (task name encodes the device).
    case managed
}

/// Device configuration for test runs requiring a device.
///
/// ## Shipfile.yml Example
/// ```yaml
/// devices:
///   strategy: named_emulators
///   emulators:
///     - Pixel_9_API_35
///   prompt_locally: true
/// ```
public struct TestDeviceConfig: Codable, Sendable {
    /// How devices are provisioned.
    public var strategy: TestDeviceStrategy

    /// AVD names to boot (only for ``TestDeviceStrategy/namedEmulators``).
    public var emulators: [String]?

    /// Gradle managed device group name (only for ``TestDeviceStrategy/managed``).
    public var group: String?

    /// Allow interactive emulator selection when not in CI (only for ``TestDeviceStrategy/namedEmulators``).
    public var promptLocally: Bool?

    enum CodingKeys: String, CodingKey {
        case strategy
        case emulators
        case group
        case promptLocally = "prompt_locally"
    }

    /// Creates a `TestDeviceConfig`.
    public init(
        strategy: TestDeviceStrategy = .none,
        emulators: [String]? = nil,
        group: String? = nil,
        promptLocally: Bool? = nil
    ) {
        self.strategy = strategy
        self.emulators = emulators
        self.group = group
        self.promptLocally = promptLocally
    }
}

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
///     with: .init(kind: .unit, scope: .module, module: "app"),
///     context: androidContext
/// )
/// print("Passed: \(result.passCount), Failed: \(result.failCount)")
/// ```
public struct TestAction: Action {
    public static let name = "test"
    public static let description = "Run unit and UI tests (iOS: xcodebuild test, Android: gradlew test)"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", TestAction.self)
    private let promptForAndroidEmulatorsHandler: @Sendable ([String]) -> [String]
    private let isInteractiveTerminalHandler: @Sendable () -> Bool

    /// Cross-platform infrastructure retry options.
    ///
    /// This is a typealias to `InfrastructureRetryScheduler.Options` which provides
    /// retry configuration shared across all platforms (iOS, Android, Flutter, RN, KMP).
    public typealias InfrastructureRetryOptions = InfrastructureRetryScheduler.Options

    /// Selective failed-test rerun options.
    public struct FailedTestRerunOptions: Codable, Sendable {
        /// Enable selective reruns for failing tests when the runner supports it.
        public var enabled: Bool

        /// Maximum attempts including the initial run. Default: 2.
        public var maxAttempts: Int

        public init(enabled: Bool = false, maxAttempts: Int = 2) {
            self.enabled = enabled
            self.maxAttempts = maxAttempts
        }
    }

    /// Creates a `TestAction`.
    public init() {
        self.promptForAndroidEmulatorsHandler = AndroidDeviceProvisioner.defaultPromptForEmulators
        self.isInteractiveTerminalHandler = AndroidDeviceProvisioner.defaultIsInteractiveTerminal
    }

    init(
        promptForAndroidEmulatorsHandler: @escaping @Sendable ([String]) -> [String],
        isInteractiveTerminalHandler: @escaping @Sendable () -> Bool
    ) {
        self.promptForAndroidEmulatorsHandler = promptForAndroidEmulatorsHandler
        self.isInteractiveTerminalHandler = isInteractiveTerminalHandler
    }

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

        /// Selectively rerun only the failed tests when the runner supports it.
        public var rerunFailedTests: FailedTestRerunOptions?

        /// Optional path to write a structured JSON test report.
        public var reportPath: String?

        /// Retries the entire iOS test invocation for transient simulator/runner failures.
        public var infrastructureRetry: InfrastructureRetryOptions?

        // MARK: Android options

        /// What category of test to run. Drives device orchestration behavior. (Android only)
        ///
        /// - `unit`: JVM tests — no device needed. Default when `devices` is nil.
        /// - `instrumented`: Requires an emulator or device.
        /// - `e2e`: Reserved for future external-tool tests (Maestro, Detox).
        public var kind: TestKind?

        /// Where to qualify the Gradle task from. (Android only)
        ///
        /// - `module`: Prefix with module path, e.g. `:app:testDebugUnitTest`.
        /// - `root`: Run unqualified from Gradle root.
        public var scope: GradleTaskScope?

        /// Gradle module to test (e.g. `"app"`). Defaults to `config.androidModule`. (Android only)
        public var module: String?

        /// Build variant to test (e.g. `"debug"`, `"release"`). Default: `debug`. (Android only)
        public var buildVariant: String?

        /// Explicit Gradle task name to run (e.g. `"testDebugUnitTest"`). (Android only)
        ///
        /// When set, this overrides the automatic task selection based on `buildVariant`
        /// and `kind`. Useful for running aggregate root-level tasks or
        /// flavor-specific test tasks like `testProdDebugUnitTest`.
        public var task: String?

        /// Device configuration for instrumented test runs. (Android only)
        ///
        /// When `kind` is `.instrumented`, this controls how devices are provisioned.
        /// If nil and kind is `.instrumented`, defaults to `.connected` strategy.
        public var devices: TestDeviceConfig?

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
            rerunFailedTests: FailedTestRerunOptions? = nil,
            reportPath: String? = nil,
            infrastructureRetry: InfrastructureRetryOptions? = nil,
            kind: TestKind? = nil,
            scope: GradleTaskScope? = nil,
            module: String? = nil,
            buildVariant: String? = nil,
            task: String? = nil,
            devices: TestDeviceConfig? = nil
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
            self.rerunFailedTests = rerunFailedTests
            self.reportPath = reportPath
            self.infrastructureRetry = infrastructureRetry
            self.kind = kind
            self.scope = scope
            self.module = module
            self.buildVariant = buildVariant
            self.task = task
            self.devices = devices
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

        /// Names of tests that passed when they can be extracted from tool output.
        public let passedTests: [String]

        /// Names of tests that failed when they can be extracted from tool output.
        public let failedTests: [String]

        /// Path to the `.xcresult` bundle (present when `resultBundlePath` was set
        /// or auto-derived because `enableCodeCoverage` was `true`). (iOS only)
        public let resultBundlePath: String?

        /// Structured multi-attempt report for this test run.
        public let report: TestRunReport?

        /// Whether all executed tests passed (no failures).
        public var succeeded: Bool { failCount == 0 }

        /// Creates a `Result`.
        public init(
            passCount: Int = 0,
            failCount: Int = 0,
            skipCount: Int = 0,
            passedTests: [String] = [],
            failedTests: [String] = [],
            resultBundlePath: String? = nil,
            report: TestRunReport? = nil
        ) {
            self.passCount = passCount
            self.failCount = failCount
            self.skipCount = skipCount
            self.passedTests = passedTests
            self.failedTests = failedTests
            self.resultBundlePath = resultBundlePath
            self.report = report
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
        case (.ios, .reactNative):
            // Explicit native options (scheme, destinations, or kind) bypass Jest and run
            // xcodebuild test directly — useful for running XCTest alongside Jest in a workflow.
            #if os(macOS)
            if options.scheme != nil || !(options.destinations ?? []).isEmpty || options.kind != nil {
                return try await runIOS(options: options, context: context)
            }
            #endif
            return try await runReactNativeTests(options: options, context: context)
        case (.android, .reactNative):
            // Explicit kind bypasses Jest and runs Gradle unit/instrumented tests directly.
            // For RN projects the gradlew lives in `android/`, not the project root — patch
            // the context so runAndroid finds the right Gradle wrapper.
            if options.kind != nil {
                let rnContext = reactNativeAndroidContext(context: context)
                return try await runAndroid(options: options, context: rnContext)
            }
            return try await runReactNativeTests(options: options, context: context)
        }
    }

    // MARK: - Flutter Tests (flutter test)

    /// Runs `flutter test` for Flutter projects (both iOS and Android platforms).
    private func runFlutterTests(options: Options, context: ActionContext) async throws -> Result {
        logger.info("Running Flutter tests (flutter test)")

        return try await InfrastructureRetryScheduler.executeIfConfigured(
            options: options.infrastructureRetry,
            classifier: FlutterInfrastructureClassifier(),
            label: "flutter test"
        ) {
            let flutter = FlutterCLI(context: context.shell).testMachine()
            let output: ShellOutput
            do {
                output = try await flutter.run()
            } catch let ShellError.exitFailure(_, shellOutput) {
                let combinedLog = ShellRunHelpers.combinedLog(shellOutput)
                let failCount = self.parseFlutterFailureCount(from: combinedLog)
                self.logger.error("Flutter tests failed with \(failCount) failure(s)")
                throw ShipItError.testFailed(
                    exitCode: Int(shellOutput.exitCode),
                    failureCount: failCount,
                    log: combinedLog
                )
            }
            if output.exitCode != 0 {
                let combinedLog = ShellRunHelpers.combinedLog(output)
                let failCount = self.parseFlutterFailureCount(from: combinedLog)
                throw ShipItError.testFailed(
                    exitCode: Int(output.exitCode),
                    failureCount: failCount,
                    log: combinedLog
                )
            }
            // Prefer the machine-output parser, but only when it actually parsed test
            // cases. `flutter test --machine` emits newline-delimited JSON; if the output
            // is human-format (older Flutter, or a wrapper that ignores `--machine`), the
            // parser returns an empty run rather than throwing, so fall back to the
            // stdout regex parser instead of reporting zero tests.
            if let parsedRun = try? await FlutterMachineOutputParser(logger: logger).parse(machineOutput: output.stdout),
                !parsedRun.testCases.isEmpty
            {
                let named = legacyNamedResults(from: parsedRun)
                let report = TestRunReport(
                    platform: "flutter",
                    runner: "flutter-test",
                    source: "machine-output",
                    attempts: [
                        TestAttempt(
                            attemptNumber: 1, summary: parsedRun.summary,
                            failedTests: parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored })
                    ],
                    initialFailedTests: parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored },
                    flakyTests: [],
                    persistentFailedTests: parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored },
                    summary: parsedRun.summary
                )
                try writeTestReportIfNeeded(report, to: options.reportPath)
                self.logger.info(
                    "Flutter tests complete — pass: \(parsedRun.summary.passed), fail: \(parsedRun.summary.failed), skip: \(parsedRun.summary.skipped)"
                )
                return Result(
                    passCount: parsedRun.summary.passed,
                    failCount: parsedRun.summary.failed,
                    skipCount: parsedRun.summary.skipped,
                    passedTests: named.passedTests,
                    failedTests: named.failedTests,
                    report: report
                )
            }

            let parsed = self.parseFlutterCounts(from: output.stdout)
            let report = TestRunReport(
                platform: "flutter",
                runner: "flutter-test",
                source: "stdout",
                attempts: [
                    TestAttempt(attemptNumber: 1, summary: TestSummary(passed: parsed.pass, failed: parsed.fail, skipped: parsed.skip))
                ],
                initialFailedTests: parsed.failedTests.map {
                    ParsedTestCase(stableID: $0, name: $0, status: .failed, rerunSelector: .flutter(name: $0))
                },
                flakyTests: [],
                persistentFailedTests: parsed.failedTests.map {
                    ParsedTestCase(stableID: $0, name: $0, status: .failed, rerunSelector: .flutter(name: $0))
                },
                summary: TestSummary(passed: parsed.pass, failed: parsed.fail, skipped: parsed.skip)
            )
            try writeTestReportIfNeeded(report, to: options.reportPath)
            self.logger.info("Flutter tests complete — pass: \(parsed.pass), fail: \(parsed.fail), skip: \(parsed.skip)")
            return Result(
                passCount: parsed.pass,
                failCount: parsed.fail,
                skipCount: parsed.skip,
                passedTests: parsed.passedTests,
                failedTests: parsed.failedTests,
                report: report
            )
        } extractContext: { error in
            if let shipItError = error as? ShipItError,
                case .testFailed(_, _, let log) = shipItError
            {
                return .init(log: log)
            }
            return nil
        }
    }

    /// Returns a context whose `gradleProjectDir` points to `./android` when the project root
    /// has no `gradlew` at the top level (standard React Native layout).
    private func reactNativeAndroidContext(context: ActionContext) -> ActionContext {
        let root = context.config.projectRoot
        let gradleDir = context.config.gradleProjectDir
        guard gradleDir == root else { return context }
        let androidDir = "\(root)/android"
        guard FileManager.default.fileExists(atPath: "\(androidDir)/gradlew") else { return context }
        return context.withGradleProjectDir(androidDir)
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

        return try await InfrastructureRetryScheduler.executeIfConfigured(
            options: options.infrastructureRetry,
            classifier: ReactNativeInfrastructureClassifier(),
            label: "npm test"
        ) {
            let outputFile = URL(fileURLWithPath: projectRoot).appendingPathComponent(".shipit-jest-results.json")
            let arguments =
                runner.scriptUsesJest("test")
                ? ["--json", "--outputFile", outputFile.path]
                : []
            let output = try await runner.run(
                script: "test",
                arguments: arguments
            )

            if FileManager.default.fileExists(atPath: outputFile.path),
                let parsedRun = try? await JestJSONTestParser(logger: logger).parse(jsonFilePath: outputFile.path)
            {
                let named = legacyNamedResults(from: parsedRun)
                let report = TestRunReport(
                    platform: "react_native",
                    runner: "jest",
                    source: outputFile.path,
                    attempts: [
                        TestAttempt(
                            attemptNumber: 1, summary: parsedRun.summary,
                            failedTests: parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored })
                    ],
                    initialFailedTests: parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored },
                    flakyTests: [],
                    persistentFailedTests: parsedRun.testCases.filter { $0.status == .failed || $0.status == .errored },
                    summary: parsedRun.summary
                )
                try writeTestReportIfNeeded(report, to: options.reportPath)
                self.logger.info(
                    "React Native tests complete — pass: \(parsedRun.summary.passed), fail: \(parsedRun.summary.failed), skip: \(parsedRun.summary.skipped)"
                )
                return Result(
                    passCount: parsedRun.summary.passed,
                    failCount: parsedRun.summary.failed,
                    skipCount: parsedRun.summary.skipped,
                    passedTests: named.passedTests,
                    failedTests: named.failedTests,
                    report: report
                )
            }

            let parsed = self.parseJSTestCounts(from: output.stdout + output.stderr)
            let report = TestRunReport(
                platform: "react_native",
                runner: "jest",
                source: "stdout",
                attempts: [
                    TestAttempt(attemptNumber: 1, summary: TestSummary(passed: parsed.pass, failed: parsed.fail, skipped: parsed.skip))
                ],
                initialFailedTests: parsed.failedTests.map {
                    ParsedTestCase(stableID: $0, name: $0, status: .failed, rerunSelector: .unsupported(rawIdentifier: $0))
                },
                flakyTests: [],
                persistentFailedTests: parsed.failedTests.map {
                    ParsedTestCase(stableID: $0, name: $0, status: .failed, rerunSelector: .unsupported(rawIdentifier: $0))
                },
                summary: TestSummary(passed: parsed.pass, failed: parsed.fail, skipped: parsed.skip)
            )
            try writeTestReportIfNeeded(report, to: options.reportPath)
            self.logger.info("React Native tests complete — pass: \(parsed.pass), fail: \(parsed.fail), skip: \(parsed.skip)")
            return Result(
                passCount: parsed.pass,
                failCount: parsed.fail,
                skipCount: parsed.skip,
                passedTests: parsed.passedTests,
                failedTests: parsed.failedTests,
                report: report
            )
        } extractContext: { error in
            // JSScriptRunner throws ShipItError.testFailed or generic errors
            if let shipItError = error as? ShipItError,
                case .testFailed(_, _, let log) = shipItError
            {
                return .init(log: log)
            }
            // For non-ShipItError throws, try to extract message
            return .init(log: error.localizedDescription)
        }
    }

    // MARK: - Flutter / RN parse helpers

    static func parseFlutterTestCountsForTesting(from output: String) -> (pass: Int, fail: Int, skip: Int) {
        let parsed = Self().parseFlutterCounts(from: output)
        return (pass: parsed.pass, fail: parsed.fail, skip: parsed.skip)
    }

    static func parseJSTestCountsForTesting(from output: String) -> (pass: Int, fail: Int, skip: Int) {
        let parsed = Self().parseJSTestCounts(from: output)
        return (pass: parsed.pass, fail: parsed.fail, skip: parsed.skip)
    }

    private func legacyNamedResults(from parsed: ParsedTestRun) -> (passedTests: [String], failedTests: [String]) {
        (
            passedTests: parsed.testCases.filter { $0.status == .passed }.map(\.legacyOutputName),
            failedTests: parsed.testCases.filter { $0.status == .failed || $0.status == .errored }.map(\.legacyOutputName)
        )
    }

    private func parseFlutterCounts(from output: String) -> (pass: Int, fail: Int, skip: Int, passedTests: [String], failedTests: [String])
    {
        // Flutter test output format (one status line per test result, final line is summary):
        //   "00:01 +12: All tests passed!"       → 12 passed
        //   "00:02 +11 -2: Some tests failed."   → 11 passed (cumulative), 2 failed
        var bestPass = 0
        var bestFail = 0
        var bestSkip = 0
        var passedTests: [String] = []
        var failedTests: [String] = []
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

            if let bracketIndex = line.firstIndex(of: ":") {
                let candidate = line[line.index(after: bracketIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty,
                    !candidate.contains("All tests passed"),
                    !candidate.contains("Some tests failed")
                {
                    if lineFail > 0 {
                        failedTests.append(candidate)
                    } else if lineSkip == 0 {
                        passedTests.append(candidate)
                    }
                }
            }
        }
        return (
            pass: bestPass,
            fail: bestFail,
            skip: bestSkip,
            passedTests: passedTests,
            failedTests: failedTests
        )
    }

    private func parseFlutterFailureCount(from output: String) -> Int {
        parseFlutterCounts(from: output).fail
    }

    private func parseJSTestCounts(from output: String) -> (pass: Int, fail: Int, skip: Int, passedTests: [String], failedTests: [String]) {
        // Jest output: "Tests: 1 failed, 2 skipped, 12 passed, 15 total"
        var pass = 0
        var fail = 0
        var skip = 0
        var passedTests: [String] = []
        var failedTests: [String] = []
        for line in output.components(separatedBy: "\n") {
            guard line.contains("Tests:") else { continue }
            let words =
                line
                .components(separatedBy: CharacterSet.whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",")) }
                .filter { !$0.isEmpty }
            for (i, word) in words.enumerated() {
                guard i > 0 else { continue }
                if word == "passed",
                    let n = Int(words[i - 1])
                {
                    pass = n
                }
                if word == "failed",
                    let n = Int(words[i - 1])
                {
                    fail = n
                }
                if word == "skipped" || word == "todo",
                    let n = Int(words[i - 1])
                {
                    skip = n
                }
            }
        }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("PASS ") {
                passedTests.append(String(trimmed.dropFirst(5)))
            } else if trimmed.hasPrefix("FAIL ") {
                failedTests.append(String(trimmed.dropFirst(5)))
            }
        }
        return (pass: pass, fail: fail, skip: skip, passedTests: passedTests, failedTests: failedTests)
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

        return try await InfrastructureRetryScheduler.executeIfConfigured(
            options: options.infrastructureRetry,
            classifier: KMPInfrastructureClassifier(),
            label: task.name
        ) {
            let gradle = context.gradle()
                .task(task)

            let output: ShellOutput
            do {
                output = try await gradle.run()
            } catch let ShellError.exitFailure(_, shellOutput) {
                let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let failCount = self.parseGradleFailureCount(from: combinedLog)
                self.logger.error("KMP iOS tests failed with \(failCount) failure(s)")
                throw ShipItError.testFailed(
                    exitCode: Int(shellOutput.exitCode),
                    failureCount: failCount,
                    log: combinedLog
                )
            }

            if output.exitCode != 0 {
                let combinedLog = output.stdout + "\n" + output.stderr
                let failCount = self.parseGradleFailureCount(from: combinedLog)
                throw ShipItError.testFailed(
                    exitCode: Int(output.exitCode),
                    failureCount: failCount,
                    log: combinedLog
                )
            }

            let parsed = self.parseGradleCounts(from: output.stdout)
            let pass = parsed.pass
            let fail = parsed.fail
            let skip = parsed.skip
            self.logger.info("KMP iOS tests complete — pass: \(pass), fail: \(fail), skip: \(skip)")
            return Result(
                passCount: pass,
                failCount: fail,
                skipCount: skip,
                passedTests: parsed.passedTests,
                failedTests: parsed.failedTests
            )
        } extractContext: { error in
            if let shipItError = error as? ShipItError,
                case .testFailed(_, _, let log) = shipItError
            {
                return .init(log: log)
            }
            return nil
        }
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

        let rerunOptions = options.rerunFailedTests ?? .init()
        let maxAttempts = max(rerunOptions.maxAttempts, 1)
        // xcodebuild exits non-zero (65) when a test fails. Capture that failure from the result
        // bundle so the failed tests can be re-run. Limited to a single destination: with several,
        // the first failing destination stops the loop, so later ones never ran and a passing
        // rerun of just the failed tests would overstate what was verified.
        let canRerunFailedTests =
            rerunOptions.enabled && maxAttempts > 1 && effectiveResultBundlePath != nil && effectiveDestinations.count == 1

        let (initialSnapshot, initialFailure) = try await runCapturingTestFailure(enabled: canRerunFailedTests) {
            try await self.runIOSAttempt(
                scheme: scheme,
                destinations: effectiveDestinations,
                configuration: configuration,
                resultBundlePath: effectiveResultBundlePath,
                options: options,
                context: context,
                overrideOnlyTesting: nil
            )
        } snapshot: { _ in
            await self.iosFailureSnapshot(resultBundlePath: effectiveResultBundlePath, context: context)
        }
        var lastFailure = initialFailure

        var attempts = [
            TestAttempt(
                attemptNumber: 1,
                summary: initialSnapshot.summary,
                failedTests: initialSnapshot.failedParsedTests,
                source: effectiveResultBundlePath
            )
        ]

        var flakyTests: [ParsedTestCase] = []
        var persistentFailedTests = initialSnapshot.failedParsedTests

        if canRerunFailedTests {
            for attemptNumber in 2...maxAttempts {
                let selectors = persistentFailedTests.compactMap { test -> String? in
                    guard case .xcodeOnlyTesting(let selector) = test.rerunSelector else { return nil }
                    return selector
                }
                guard !selectors.isEmpty else { break }
                let rerunSnapshot: TestExecutionSnapshot
                (rerunSnapshot, lastFailure) = try await runCapturingTestFailure(enabled: canRerunFailedTests) {
                    try await self.runIOSAttempt(
                        scheme: scheme,
                        destinations: effectiveDestinations,
                        configuration: configuration,
                        resultBundlePath: effectiveResultBundlePath,
                        options: options,
                        context: context,
                        overrideOnlyTesting: selectors
                    )
                } snapshot: { _ in
                    await self.iosFailureSnapshot(resultBundlePath: effectiveResultBundlePath, context: context)
                }
                attempts.append(
                    TestAttempt(
                        attemptNumber: attemptNumber,
                        summary: rerunSnapshot.summary,
                        failedTests: rerunSnapshot.failedParsedTests,
                        source: effectiveResultBundlePath
                    )
                )

                let reconciled = Self.reconcileRerun(
                    previousFailures: persistentFailedTests, snapshot: rerunSnapshot, failure: lastFailure)
                flakyTests += reconciled.passed
                persistentFailedTests = reconciled.failed
            }
        }

        let finalPassedTests =
            persistentFailedTests.isEmpty
            ? Array(Set(initialSnapshot.passedTests + flakyTests.map(\.legacyOutputName))).sorted()
            : initialSnapshot.passedTests
        let finalFailedTests = persistentFailedTests.map(\.legacyOutputName)
        let finalPassCount =
            persistentFailedTests.isEmpty
            ? initialSnapshot.summary.passed + flakyTests.count
            : initialSnapshot.summary.passed
        let finalFailCount = persistentFailedTests.count

        let report = TestRunReport(
            platform: "ios",
            runner: "xcodebuild",
            source: effectiveResultBundlePath ?? scheme,
            attempts: attempts,
            initialFailedTests: initialSnapshot.failedParsedTests,
            flakyTests: flakyTests,
            persistentFailedTests: persistentFailedTests,
            summary: TestSummary(
                passed: finalPassCount,
                failed: finalFailCount,
                skipped: initialSnapshot.summary.skipped,
                flaky: flakyTests.count,
                errored: 0
            )
        )

        try writeTestReportIfNeeded(report, to: options.reportPath)
        try Self.rethrowPersistentFailure(
            lastFailure ?? (finalFailCount > 0 ? initialFailure : nil), persistentFailureCount: finalFailCount)

        logger.info("Tests complete — pass: \(finalPassCount), fail: \(finalFailCount), skip: \(initialSnapshot.summary.skipped)")

        return Result(
            passCount: finalPassCount,
            failCount: finalFailCount,
            skipCount: initialSnapshot.summary.skipped,
            passedTests: finalPassedTests,
            failedTests: finalFailedTests,
            resultBundlePath: effectiveResultBundlePath,
            report: report
        )
    }

    private func runIOSAttempt(
        scheme: String,
        destinations: [String],
        configuration: String,
        resultBundlePath: String?,
        options: Options,
        context: ActionContext,
        overrideOnlyTesting: [String]?
    ) async throws -> TestExecutionSnapshot {
        var totalPass = 0
        var totalFail = 0
        var totalSkip = 0
        var passedTests: [String] = []
        var failedTests: [String] = []
        var destinationResultBundlePaths: [String] = []

        for (index, destination) in destinations.enumerated() {
            logger.info("Testing scheme '\(scheme)' on '\(destination)'")
            let destinationResultBundlePath = resultBundlePath.map {
                destinations.count == 1 ? $0 : indexedResultBundlePath(basePath: $0, index: index)
            }

            let singleResult = try await runSingle(
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                resultBundlePath: destinationResultBundlePath,
                options: options,
                context: context,
                overrideOnlyTesting: overrideOnlyTesting
            )
            totalPass += singleResult.pass
            totalFail += singleResult.fail
            totalSkip += singleResult.skip
            passedTests += singleResult.passedTests
            failedTests += singleResult.failedTests
            if let destinationResultBundlePath {
                destinationResultBundlePaths.append(destinationResultBundlePath)
            }
        }

        let parsedRun: ParsedTestRun?
        if let resultBundlePath {
            if destinationResultBundlePaths.count > 1 {
                try await mergeResultBundles(
                    destinationResultBundlePaths,
                    outputPath: resultBundlePath,
                    context: context
                )
            }
            parsedRun = try? await IOSXCResultTestParser(shell: context.shell, logger: logger).parse(xcresultPath: resultBundlePath)
        } else {
            parsedRun = nil
        }

        if let parsedRun {
            let named = legacyNamedResults(from: parsedRun)
            return TestExecutionSnapshot(
                summary: TestSummary(
                    passed: parsedRun.summary.passed,
                    failed: parsedRun.summary.failed + parsedRun.summary.errored,
                    skipped: parsedRun.summary.skipped,
                    flaky: parsedRun.summary.flaky,
                    errored: parsedRun.summary.errored
                ),
                passedTests: named.passedTests,
                failedTests: named.failedTests,
                parsedRun: parsedRun
            )
        }

        return TestExecutionSnapshot(
            summary: TestSummary(passed: totalPass, failed: totalFail, skipped: totalSkip),
            passedTests: passedTests,
            failedTests: failedTests,
            parsedRun: nil
        )
    }

    /// Reads the failed tests of a failed `xcodebuild test` run back from its result bundle.
    /// Returns `nil` when there is no bundle or it records no failed tests (e.g. a build error).
    private func iosFailureSnapshot(resultBundlePath: String?, context: ActionContext) async -> TestExecutionSnapshot? {
        guard let resultBundlePath,
            let parsedRun = try? await IOSXCResultTestParser(shell: context.shell, logger: logger).parse(xcresultPath: resultBundlePath),
            parsedRun.summary.failed + parsedRun.summary.errored > 0
        else { return nil }

        let named = legacyNamedResults(from: parsedRun)
        return TestExecutionSnapshot(
            summary: TestSummary(
                passed: parsedRun.summary.passed,
                failed: parsedRun.summary.failed + parsedRun.summary.errored,
                skipped: parsedRun.summary.skipped,
                flaky: parsedRun.summary.flaky,
                errored: parsedRun.summary.errored
            ),
            passedTests: named.passedTests,
            failedTests: named.failedTests,
            parsedRun: parsedRun
        )
    }

    private func indexedResultBundlePath(basePath: String, index: Int) -> String {
        let url = URL(fileURLWithPath: basePath)
        let extensionName = url.pathExtension
        let stem = extensionName.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let fileName = extensionName.isEmpty ? "\(stem)-\(index + 1)" : "\(stem)-\(index + 1).\(extensionName)"
        return url.deletingLastPathComponent().appendingPathComponent(fileName).path
    }

    private func mergeResultBundles(
        _ inputPaths: [String],
        outputPath: String,
        context: ActionContext
    ) async throws {
        try removeStaleResultBundleIfNeeded(outputPath)
        logger.info("Merging \(inputPaths.count) destination result bundles into '\(outputPath)'")
        do {
            _ = try await Xcrun(context: context.shell)
                .tool("xcresulttool")
                .trailingArguments(["merge", "--output-path", outputPath] + inputPaths)
                .command()
                .run(in: context.shell)
            for inputPath in inputPaths {
                try? FileManager.default.removeItem(atPath: inputPath)
            }
            logger.info("Merged destination result bundles into '\(outputPath)'")
        } catch let ShellError.exitFailure(_, output) {
            logger.error("Failed to merge destination result bundles: \(output.stderr)")
            throw ShipItError.testFailed(
                exitCode: Int(output.exitCode),
                failureCount: 0,
                log: "Failed to merge xcresult bundles: \(output.stderr)"
            )
        }
    }

    // MARK: - Single destination run (iOS)

    private func runSingle(
        scheme: String,
        destination: String,
        configuration: String,
        resultBundlePath: String?,
        options: Options,
        context: ActionContext,
        overrideOnlyTesting: [String]?
    ) async throws -> (pass: Int, fail: Int, skip: Int, passedTests: [String], failedTests: [String]) {
        return try await InfrastructureRetryScheduler.executeIfConfigured(
            options: options.infrastructureRetry,
            classifier: IOSInfrastructureClassifier(),
            label: destination
        ) {
            try await self.resetIOSAppInstallationIfNeeded(
                scheme: scheme,
                destination: destination,
                context: context
            )
            try self.removeStaleResultBundleIfNeeded(resultBundlePath)

            var xcodeBuild = context.streamingXcodeBuild()
                .option(.scheme(scheme))
                .option(.configuration(configuration))
                .option(.destination(destination))
                .test()

            if let workspace = context.config.appWorkspace {
                xcodeBuild = xcodeBuild.workspace(workspace)
            } else if let project = context.config.appProject {
                xcodeBuild = xcodeBuild.project(project)
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

            for target in overrideOnlyTesting ?? options.onlyTesting ?? [] {
                xcodeBuild = xcodeBuild.option(.onlyTesting(target))
            }

            for target in options.skipTesting ?? [] {
                xcodeBuild = xcodeBuild.option(.skipTesting(target))
            }

            if options.retryOnFailure == true {
                xcodeBuild = xcodeBuild.option(.retryTestsOnFailure)
            }

            do {
                let output = try await xcodeBuild.run()

                if output.exitCode != 0 {
                    let combinedLog = output.stdout + output.stderr
                    let failCount = self.parseFailureCount(from: combinedLog)
                    self.logger.error("Tests failed on '\(destination)' with \(failCount) failure(s)")
                    throw ShipItError.testFailed(
                        exitCode: Int(output.exitCode),
                        failureCount: failCount,
                        log: combinedLog
                    )
                }

                let summary = XcodeBuildSummary.parse(output.stdout)
                if let line = summary.resultLine { self.logger.info("\(line)") }
                if summary.warningCount > 0 || summary.errorCount > 0 {
                    self.logger.info("\(summary.warningCount) warning(s), \(summary.errorCount) error(s)")
                }
                let parsed = self.parseCounts(from: output.stdout)
                let pass = parsed.pass
                let skip = parsed.skip
                self.logger.info("'\(destination)' — passed: \(pass), skipped: \(skip)")
                return (
                    pass: pass,
                    fail: 0,
                    skip: skip,
                    passedTests: parsed.passedTests,
                    failedTests: []
                )
            } catch let ShellError.exitFailure(_, shellOutput) {
                let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                let failCount = self.parseFailureCount(from: combinedLog)
                self.logger.error("Tests failed on '\(destination)' with \(failCount) failure(s)")
                throw ShipItError.testFailed(
                    exitCode: Int(shellOutput.exitCode),
                    failureCount: failCount,
                    log: combinedLog
                )
            }
        } extractContext: { error in
            if let shipItError = error as? ShipItError,
                case .testFailed(_, _, let log) = shipItError
            {
                return .init(log: log)
            }
            return nil
        }
    }

    #endif

    // MARK: - Android Test (gradlew test / connectedAndroidTest)

    private func runAndroid(options: Options, context: ActionContext) async throws -> Result {
        let module = options.module ?? context.config.androidModule
        let variant = options.buildVariant ?? context.config.androidBuildVariant
        let kind = options.kind ?? context.config.androidTestKind
        let devices = options.devices ?? context.config.androidTestDevices

        // For connected/emulator instrumented tests, feature modules hold the tests while the
        // app module typically has none. Default to root scope so the root-level
        // connectedAndroidTest task cascades across every module. Managed-device tasks are
        // module-specific by design (the group task is defined per module), so keep the module
        // default there. Users can always override by setting scope explicitly.
        let isUnscopedInstrumented = kind == .instrumented && options.scope == nil
        let isManagedDevice = devices.strategy == .managed
        let defaultScope: GradleTaskScope =
            isUnscopedInstrumented && !isManagedDevice ? .root : context.config.androidScope
        let scope = options.scope ?? defaultScope

        // Choose task: explicit task name, or derive from kind/variant
        let task: GradleTask
        if let customTask = options.task, !customTask.isEmpty {
            task = GradleTask(name: customTask)
        } else {
            switch kind {
            case .instrumented:
                if devices.strategy == .managed, let group = devices.group, !group.isEmpty {
                    task = .managedDeviceAndroidTest(device: group, variant: variant)
                } else if variant.lowercased() == "release" {
                    task = .connectedAndroidTest
                } else {
                    task = .connectedAndroidTest(variant: variant)
                }
            case .unit, .e2e:
                task = .unitTest(variant: variant)
            }
        }

        // Qualify based on scope
        let scopedTask: GradleTask
        switch scope {
        case .root:
            scopedTask = task
        case .module:
            scopedTask = task.qualified(module: module)
        }

        // Orchestrate devices if needed
        let provisioner = AndroidDeviceProvisioner(
            context: context,
            logger: logger,
            promptForEmulators: promptForAndroidEmulatorsHandler,
            isInteractiveTerminal: isInteractiveTerminalHandler
        )
        var spawnedEmulators: [any SpawnedProcess] = []
        if kind == .instrumented {
            spawnedEmulators = try await provisioner.prepare(devices: devices)
            try await provisioner.resetAppInstallations(packageName: context.config.androidPackageName)
        }

        logger.info("Running Android test task '\(scopedTask.name)'")

        let rerunOptions = options.rerunFailedTests ?? .init()
        let maxAttempts = max(rerunOptions.maxAttempts, 1)
        let canRerunFailedTests = kind == .unit && rerunOptions.enabled && maxAttempts > 1

        do {
            // Gradle exits non-zero when any test fails. When reruns are enabled, that failure is
            // captured as a snapshot so its failed tests can be retried; infrastructure retries
            // still see the raw error first.
            let (initialSnapshot, initialFailure) = try await runCapturingTestFailure(enabled: canRerunFailedTests) {
                try await InfrastructureRetryScheduler.executeIfConfigured(
                    options: options.infrastructureRetry,
                    classifier: AndroidInfrastructureClassifier(),
                    label: scopedTask.name
                ) {
                    try await self.runAndroidAttempt(
                        scopedTask: scopedTask,
                        baseTask: scopedTask,
                        kind: kind,
                        context: context,
                        testFilters: nil
                    )
                } extractContext: { error in
                    if let shipItError = error as? ShipItError,
                        case .testFailed(_, _, let log) = shipItError
                    {
                        return .init(log: log)
                    }
                    return nil
                }
            } snapshot: { error in
                await self.androidFailureSnapshot(from: error, context: context, task: scopedTask)
            }
            var lastFailure = initialFailure
            var attempts = [
                TestAttempt(
                    attemptNumber: 1,
                    summary: initialSnapshot.summary,
                    failedTests: initialSnapshot.failedParsedTests,
                    source: task.name
                )
            ]

            var flakyTests: [ParsedTestCase] = []
            var persistentFailedTests = initialSnapshot.failedParsedTests
            var finalSnapshot = initialSnapshot

            if canRerunFailedTests {
                for attemptNumber in 2...maxAttempts {
                    let rerunFilters = Self.gradleRerunFilters(for: persistentFailedTests)
                    guard !rerunFilters.isEmpty else { break }
                    logger.info("Re-running \(rerunFilters.count) failed Android test(s)")
                    let rerunSnapshot: TestExecutionSnapshot
                    (rerunSnapshot, lastFailure) = try await runCapturingTestFailure(enabled: true) {
                        try await self.runAndroidAttempt(
                            scopedTask: scopedTask,
                            baseTask: scopedTask,
                            kind: kind,
                            context: context,
                            testFilters: rerunFilters
                        )
                    } snapshot: { error in
                        await self.androidFailureSnapshot(from: error, context: context, task: scopedTask)
                    }
                    finalSnapshot = rerunSnapshot
                    attempts.append(
                        TestAttempt(
                            attemptNumber: attemptNumber,
                            summary: rerunSnapshot.summary,
                            failedTests: rerunSnapshot.failedParsedTests,
                            source: task.name
                        )
                    )

                    let reconciled = Self.reconcileRerun(
                        previousFailures: persistentFailedTests, snapshot: rerunSnapshot, failure: lastFailure)
                    flakyTests += reconciled.passed
                    persistentFailedTests = reconciled.failed
                }
            }

            let finalPassedTests =
                persistentFailedTests.isEmpty
                ? Array(Set(initialSnapshot.passedTests + flakyTests.map(\.legacyOutputName))).sorted()
                : initialSnapshot.passedTests
            let finalFailedTests = persistentFailedTests.map(\.legacyOutputName)
            let finalPassCount =
                persistentFailedTests.isEmpty
                ? initialSnapshot.summary.passed + flakyTests.count
                : initialSnapshot.summary.passed
            let finalFailCount = persistentFailedTests.count
            let report = TestRunReport(
                platform: "android",
                runner: "gradle",
                source: task.name,
                attempts: attempts,
                initialFailedTests: initialSnapshot.failedParsedTests,
                flakyTests: flakyTests,
                persistentFailedTests: persistentFailedTests,
                summary: TestSummary(
                    passed: finalPassCount,
                    failed: finalFailCount,
                    skipped: finalSnapshot.summary.skipped,
                    flaky: flakyTests.count,
                    errored: 0
                )
            )

            try writeTestReportIfNeeded(report, to: options.reportPath)

            try Self.rethrowPersistentFailure(
                lastFailure ?? (finalFailCount > 0 ? initialFailure : nil), persistentFailureCount: finalFailCount)

            await provisioner.teardown(spawnedEmulators)
            return Result(
                passCount: finalPassCount,
                failCount: finalFailCount,
                skipCount: finalSnapshot.summary.skipped,
                passedTests: finalPassedTests,
                failedTests: finalFailedTests,
                report: report
            )
        } catch {
            await provisioner.teardown(spawnedEmulators)
            throw error
        }
    }

    private func runAndroidAttempt(
        scopedTask: GradleTask,
        baseTask: GradleTask,
        kind: TestKind,
        context: ActionContext,
        testFilters: [String]?
    ) async throws -> TestExecutionSnapshot {
        // `--tests` is a task option: it must follow the task name, not precede it as a global flag.
        let filteredTask = kind == .unit ? scopedTask.filteringTests(testFilters ?? []) : scopedTask
        var gradle = context.streamingGradle().task(filteredTask)
        // Complete independent modules before collecting failures for a root-scoped rerun.
        if kind == .unit && !scopedTask.name.contains(":") { gradle = gradle.flag(.continueAfterFailure) }

        let output: ShellOutput
        do {
            output = try await gradle.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let failCount = self.parseGradleFailureCount(from: combinedLog)
            self.logger.error("Android tests failed with \(failCount) failure(s)")
            throw ShipItError.testFailed(
                exitCode: Int(shellOutput.exitCode),
                failureCount: failCount,
                log: combinedLog
            )
        }

        if output.exitCode != 0 {
            let combinedLog = output.stdout + "\n" + output.stderr
            let failCount = self.parseGradleFailureCount(from: combinedLog)
            throw ShipItError.testFailed(
                exitCode: Int(output.exitCode),
                failureCount: failCount,
                log: combinedLog
            )
        }

        let parsed = self.parseGradleCounts(from: output.stdout + "\n" + output.stderr)
        // Output already streamed live via streamingGradle()'s .tee destination — no debug re-dump.

        if parsed.pass == 0 && parsed.fail == 0 && parsed.skip == 0 {
            if let run = try await parseJUnitReports(projectDir: context.config.gradleProjectDir, task: baseTask.name) {
                let named = legacyNamedResults(from: run)
                return TestExecutionSnapshot(
                    summary: run.summary, passedTests: named.passedTests,
                    failedTests: named.failedTests, parsedRun: run)
            }
        }

        return TestExecutionSnapshot(
            summary: TestSummary(passed: parsed.pass, failed: parsed.fail, skipped: parsed.skip),
            passedTests: parsed.passedTests,
            failedTests: parsed.failedTests,
            parsedRun: nil
        )
    }

    // MARK: - Failed-test rerun support

    /// Runs one test attempt, capturing a test failure as a snapshot instead of throwing it.
    ///
    /// Test runners (`gradlew`, `xcodebuild`) exit non-zero whenever a test fails, which surfaces as
    /// `ShipItError.testFailed`. To re-run only the failed tests, that failure has to be turned back
    /// into a snapshot naming them. When `enabled` is false, or `snapshot` cannot name any failed
    /// test (e.g. a compilation error), the original error is re-thrown unchanged.
    ///
    /// - Returns: The attempt's snapshot and, when a failure was captured, the error to re-throw
    ///   if the failures persist (see ``rethrowPersistentFailure(_:persistentFailureCount:)``).
    private func runCapturingTestFailure(
        enabled: Bool,
        attempt: () async throws -> TestExecutionSnapshot,
        snapshot: (ShipItError) async -> TestExecutionSnapshot?
    ) async throws -> (TestExecutionSnapshot, ShipItError?) {
        do {
            return (try await attempt(), nil)
        } catch let error as ShipItError where enabled {
            guard let captured = await snapshot(error), !captured.failedParsedTests.isEmpty else { throw error }
            return (captured, error)
        }
    }

    /// A missing failure is not proof of a pass when the rerun failed or skipped tests.
    /// Keep unresolved original failures and all newly reported failures.
    private static func reconcileRerun(
        previousFailures: [ParsedTestCase], snapshot: TestExecutionSnapshot, failure: ShipItError?
    ) -> (passed: [ParsedTestCase], failed: [ParsedTestCase]) {
        let latestFailures = snapshot.failedParsedTests
        let failedIDs = Set(latestFailures.map(\.stableID))
        let passedIDs = Set(snapshot.parsedRun?.testCases.filter { $0.status == .passed }.map(\.stableID) ?? [])
        let successfulUnskippedRun =
            failure == nil && snapshot.parsedRun == nil
            && snapshot.summary.failed == 0 && snapshot.summary.skipped == 0
            && snapshot.summary.passed >= previousFailures.count
        let passed = previousFailures.filter {
            !failedIDs.contains($0.stableID) && (passedIDs.contains($0.stableID) || successfulUnskippedRun)
        }
        let resolvedIDs = Set(passed.map(\.stableID))
        let unresolved = previousFailures.filter { !resolvedIDs.contains($0.stableID) && !failedIDs.contains($0.stableID) }
        return (passed, unresolved + latestFailures)
    }

    /// Re-throws a captured test failure when tests still fail after the rerun, preserving the
    /// runner's original non-zero exit semantics so workflows stop exactly as they would without
    /// reruns. `failureCount` is updated to the persistent failures.
    private static func rethrowPersistentFailure(_ failure: ShipItError?, persistentFailureCount: Int) throws {
        guard let failure else { return }
        if case .testFailed(let exitCode, _, let log) = failure {
            throw ShipItError.testFailed(exitCode: exitCode, failureCount: max(persistentFailureCount, 1), log: log)
        }
        throw failure
    }

    /// Converts a failed Gradle test invocation into a snapshot of its failed tests so they can be
    /// re-run. Prefers the JUnit XML reports (fully-qualified names) and falls back to parsing the
    /// console log. Returns `nil` when the failure is not a test failure or names no failed tests
    /// (e.g. a compilation error), in which case the caller re-throws the original error.
    private func androidFailureSnapshot(
        from error: ShipItError,
        context: ActionContext,
        task: GradleTask
    ) async -> TestExecutionSnapshot? {
        guard case .testFailed(_, _, let log) = error else { return nil }

        if let parsed = try? await parseJUnitReports(projectDir: context.config.gradleProjectDir, task: task.name),
            parsed.summary.failed + parsed.summary.errored > 0
        {
            let named = legacyNamedResults(from: parsed)
            return TestExecutionSnapshot(
                summary: TestSummary(
                    passed: parsed.summary.passed,
                    failed: parsed.summary.failed + parsed.summary.errored,
                    skipped: parsed.summary.skipped
                ),
                passedTests: named.passedTests,
                failedTests: named.failedTests,
                parsedRun: parsed
            )
        }

        let parsed = parseGradleCounts(from: log)
        guard !parsed.failedTests.isEmpty else { return nil }
        return TestExecutionSnapshot(
            summary: TestSummary(
                passed: parsed.pass,
                failed: max(parsed.fail, parsed.failedTests.count),
                skipped: parsed.skip
            ),
            passedTests: parsed.passedTests,
            failedTests: parsed.failedTests
        )
    }

    /// Gradle `--tests` filters for the failed tests in `snapshot`.
    ///
    /// JUnit-derived selectors are already `package.Class.method`; console-derived names use
    /// Gradle's `Class > method FAILED` shape, which is normalized to `Class.method`. JUnit 5's
    /// trailing `()` is dropped because Gradle filters match on the bare method name.
    private static func gradleRerunFilters(for failures: [ParsedTestCase]) -> [String] {
        let raw = failures.compactMap { test -> String? in
            switch test.rerunSelector {
            case .gradleTestFilter(let selector): return selector
            case .unsupported(let identifier): return identifier
            default: return nil
            }
        }

        var seen = Set<String>()
        return raw.compactMap { name in
            var filter = name.replacingOccurrences(of: " > ", with: ".")
                .trimmingCharacters(in: .whitespaces)
            if filter.hasSuffix("()") { filter = String(filter.dropLast(2)) }
            guard !filter.isEmpty, seen.insert(filter).inserted else { return nil }
            return filter
        }
    }

    #if os(macOS)
    private func resetIOSAppInstallationIfNeeded(
        scheme: String,
        destination: String,
        context: ActionContext
    ) async throws {
        guard let bundleID = context.config.bundleID, !bundleID.isEmpty else { return }
        guard
            let simulatorUDID = try await resolveSimulatorUDID(
                scheme: scheme,
                destination: destination,
                context: context
            )
        else { return }

        logger.info("Uninstalling existing iOS app '\(bundleID)' from simulator '\(simulatorUDID)' before test run")
        do {
            _ = try await Simctl(context: context.shell)
                .uninstall(simulatorUDID, bundleIdentifier: bundleID)
                .run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            logger.debug("iOS uninstall skipped for simulator '\(simulatorUDID)': \(combinedLog)")
        } catch {
            logger.debug("iOS uninstall skipped for simulator '\(simulatorUDID)': \(error.localizedDescription)")
        }
    }

    private func resolveSimulatorUDID(
        scheme: String,
        destination: String,
        context: ActionContext
    ) async throws -> String? {
        let requestedParts = parseDestinationComponents(destination)
        guard let platform = requestedParts["platform"], platform.contains("Simulator") else { return nil }

        let discoverer = DestinationDiscovery(shell: context.shell)
        let destinations = try await discoverer.availableDestinations(
            scheme: scheme,
            workspace: context.config.appWorkspace,
            project: context.config.appProject
        )

        return destinations.first {
            $0.isSimulator
                && $0.platform == platform
                && (requestedParts["name"] == nil || $0.name == requestedParts["name"])
                && (requestedParts["OS"] == nil || $0.os == requestedParts["OS"])
        }?.udid
    }

    private func parseDestinationComponents(_ destination: String) -> [String: String] {
        var parts: [String: String] = [:]
        for segment in destination.split(separator: ",") {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator])
            let value = String(trimmed[trimmed.index(after: separator)...])
            parts[key] = value
        }
        return parts
    }
    #endif

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
    private func parseCounts(from output: String) -> (pass: Int, skip: Int, passedTests: [String]) {
        let passedTests = output.components(separatedBy: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("Test Case '-[") || trimmed.hasPrefix("Test Case '") else { return nil }
            guard trimmed.contains(" passed") else { return nil }
            let withoutPrefix = trimmed.replacingOccurrences(of: "Test Case '", with: "")
            guard let raw = withoutPrefix.components(separatedBy: "' ").first else { return nil }
            return ParsedTestCase.formatXCTestName(raw)
        }
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

            return (pass: total - skipped, skip: skipped, passedTests: passedTests)
        }
        return (pass: 0, skip: 0, passedTests: passedTests)
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

    private func removeStaleResultBundleIfNeeded(_ resultBundlePath: String?) throws {
        guard let bundlePath = resultBundlePath else { return }

        let fm = FileManager.default
        guard fm.fileExists(atPath: bundlePath) else { return }

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

    #endif

    /// Parses Gradle test output for pass/fail/skip counts.
    ///
    /// Gradle prints a summary like:
    /// ```
    /// 12 tests completed, 2 failed, 1 skipped
    /// ```
    func parseGradleCounts(from output: String) -> (pass: Int, fail: Int, skip: Int, passedTests: [String], failedTests: [String]) {
        // Gradle may print one summary per module and omit zero-valued failure/skip fields.
        let pattern = #"(\d+)\s+tests?\s+completed(?:,\s*(\d+)\s+failed)?(?:,\s*(\d+)\s+skipped)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (0, 0, 0, [], [])
        }
        var passed = 0
        var failed = 0
        var skipped = 0
        for match in regex.matches(in: output, range: NSRange(output.startIndex..., in: output)) {
            func number(_ index: Int) -> Int {
                guard let range = Range(match.range(at: index), in: output) else { return 0 }
                return Int(output[range]) ?? 0
            }
            let total = number(1)
            let failures = number(2)
            let skips = number(3)
            passed += max(0, total - failures - skips)
            failed += failures
            skipped += skips
        }
        let named = parseGradleNamedTests(from: output)
        return (passed, failed, skipped, named.passedTests, named.failedTests)
    }

    /// Uses the same summary grammar as the report, including a terminal `failed` field.
    private func parseGradleFailureCount(from output: String) -> Int {
        parseGradleCounts(from: output).fail
    }

    // MARK: - JUnit XML Report Parsing

    /// Aggregates test counts from JUnit XML reports written by Gradle.
    ///
    /// Gradle writes one XML file per test class to:
    /// `<module>/build/test-results/<taskName>/TEST-*.xml`
    ///
    /// Each file has a `<testsuite>` root with attributes:
    /// `tests`, `failures`, `errors`, `skipped`.
    ///
    /// - Parameters:
    ///   - projectDir: The Gradle project root directory.
    ///   - task: The Gradle task name (e.g. `"testDebugUnitTest"`) used to locate report directories.
    /// - Returns: Aggregated (pass, fail, skip) counts across all XML reports.
    func aggregateJUnitXMLResults(
        projectDir: String, task: String
    ) async throws -> (pass: Int, fail: Int, skip: Int, passedTests: [String], failedTests: [String]) {
        guard let parsed = try await parseJUnitReports(projectDir: projectDir, task: task) else {
            return (pass: 0, fail: 0, skip: 0, passedTests: [], failedTests: [])
        }
        let named = legacyNamedResults(from: parsed)
        return (
            parsed.summary.passed, parsed.summary.failed + parsed.summary.errored, parsed.summary.skipped,
            named.passedTests, named.failedTests
        )
    }

    /// Qualified tasks read only their module; root tasks collect every exact task directory.
    private func parseJUnitReports(projectDir: String, task: String) async throws -> ParsedTestRun? {
        let parts = task.split(separator: ":").map(String.init)
        guard let taskName = parts.last else { return nil }
        let root = URL(fileURLWithPath: projectDir)
        let directories: [URL]
        if parts.count > 1 {
            let module = parts.dropLast().joined(separator: "/")
            directories = [root.appendingPathComponent("\(module)/build/test-results/\(taskName)")]
        } else {
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            directories = (enumerator?.allObjects as? [URL] ?? []).filter {
                $0.lastPathComponent == taskName && $0.deletingLastPathComponent().lastPathComponent == "test-results"
                    && $0.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "build"
            }.sorted { $0.path < $1.path }
        }
        var cases: [ParsedTestCase] = []
        var passed = 0
        var failed = 0
        var skipped = 0
        var found = false
        for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
            let run = try await AndroidJUnitTestParser(logger: logger).parse(reportDirectory: directory.path)
            found = true
            passed += run.summary.passed
            failed += run.summary.failed + run.summary.errored
            skipped += run.summary.skipped
            cases += run.testCases.map {
                ParsedTestCase(
                    stableID: directory.path + ":" + $0.stableID, suite: $0.suite, name: $0.name,
                    status: $0.status, durationSeconds: $0.durationSeconds, message: $0.message,
                    file: $0.file, line: $0.line, rerunSelector: $0.rerunSelector)
            }
        }
        guard found else { return nil }
        return ParsedTestRun(
            platform: "android", runner: "gradle", source: projectDir,
            summary: TestSummary(passed: passed, failed: failed, skipped: skipped), testCases: cases)
    }

    private func parseGradleNamedTests(from output: String) -> (passedTests: [String], failedTests: [String]) {
        var passedTests: [String] = []
        var failedTests: [String] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasSuffix(" FAILED") {
                failedTests.append(String(trimmed.dropLast(" FAILED".count)))
                continue
            }

            if trimmed.hasSuffix(" PASSED") {
                passedTests.append(String(trimmed.dropLast(" PASSED".count)))
            }
        }

        return (passedTests: passedTests, failedTests: failedTests)
    }

    private func writeTestReportIfNeeded(_ report: TestRunReport, to path: String?) throws {
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url)
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
