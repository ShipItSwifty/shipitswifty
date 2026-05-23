import Foundation
import Logging
import SwiftyShell

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

public struct TestAction: Action {
    public static let name = "test"
    public static let description = "Run unit and UI tests (iOS: xcodebuild test, Android: gradlew test)"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", TestAction.self)

    /// Cross-platform infrastructure retry options.
    ///
    /// This is a typealias to `InfrastructureRetryScheduler.Options` which provides
    /// retry configuration shared across all platforms (iOS, Android, Flutter, RN, KMP).
    public typealias InfrastructureRetryOptions = InfrastructureRetryScheduler.Options

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

        let scheduler = InfrastructureRetryScheduler(
            options: options.infrastructureRetry ?? .init(),
            classifier: FlutterInfrastructureClassifier()
        )

        return try await scheduler.execute(label: "flutter test") {
            let flutter = FlutterCLI(context: context.shell).test()
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
            let (pass, fail, skip) = self.parseFlutterCounts(from: output.stdout)
            self.logger.info("Flutter tests complete — pass: \(pass), fail: \(fail), skip: \(skip)")
            return Result(passCount: pass, failCount: fail, skipCount: skip)
        } extractContext: { error in
            if let shipItError = error as? ShipItError,
               case .testFailed(_, _, let log) = shipItError {
                return .init(log: log, underlyingError: shipItError)
            }
            return nil
        }
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

        let scheduler = InfrastructureRetryScheduler(
            options: options.infrastructureRetry ?? .init(),
            classifier: ReactNativeInfrastructureClassifier()
        )

        return try await scheduler.execute(label: "npm test") {
            let output = try await runner.run(script: "test")
            let (pass, fail, skip) = self.parseJSTestCounts(from: output.stdout + output.stderr)
            self.logger.info("React Native tests complete — pass: \(pass), fail: \(fail), skip: \(skip)")
            return Result(passCount: pass, failCount: fail, skipCount: skip)
        } extractContext: { error in
            // JSScriptRunner throws ShipItError.testFailed or generic errors
            if let shipItError = error as? ShipItError,
               case .testFailed(_, _, let log) = shipItError {
                return .init(log: log, underlyingError: shipItError)
            }
            // For non-ShipItError throws, try to extract message
            return .init(log: error.localizedDescription, underlyingError: error)
        }
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

        let scheduler = InfrastructureRetryScheduler(
            options: options.infrastructureRetry ?? .init(),
            classifier: KMPInfrastructureClassifier()
        )

        return try await scheduler.execute(label: task.name) {
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

            let (pass, fail, skip) = self.parseGradleCounts(from: output.stdout)
            self.logger.info("KMP iOS tests complete — pass: \(pass), fail: \(fail), skip: \(skip)")
            return Result(passCount: pass, failCount: fail, skipCount: skip)
        } extractContext: { error in
            if let shipItError = error as? ShipItError,
               case .testFailed(_, _, let log) = shipItError {
                return .init(log: log, underlyingError: shipItError)
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
        let scheduler = InfrastructureRetryScheduler(
            options: options.infrastructureRetry ?? .init(),
            classifier: IOSInfrastructureClassifier()
        )

        return try await scheduler.execute(label: destination) {
            try self.removeStaleResultBundleIfNeeded(resultBundlePath)

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

                let (pass, skip) = self.parseCounts(from: output.stdout)
                self.logger.info("'\(destination)' — passed: \(pass), skipped: \(skip)")
                return (pass: pass, fail: 0, skip: skip)
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
               case .testFailed(_, _, let log) = shipItError {
                return .init(log: log, underlyingError: shipItError)
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
        let scope = options.scope ?? context.config.androidScope
        let devices = options.devices ?? context.config.androidTestDevices

        // Choose task: explicit task name, or derive from kind/variant
        let task: GradleTask
        if let customTask = options.task, !customTask.isEmpty {
            task = GradleTask(name: customTask)
        } else {
            switch kind {
            case .instrumented:
                task = variant.lowercased() == "debug"
                    ? .connectedDebugAndroidTest
                    : .connectedAndroidTest
            case .unit, .e2e:
                task = variant.lowercased() == "debug"
                    ? .testDebugUnitTest
                    : .testReleaseUnitTest
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
        var spawnedEmulators: [any SpawnedProcess] = []
        if kind == .instrumented {
            spawnedEmulators = try await prepareAndroidDevices(
                devices: devices,
                context: context
            )
        }

        let emulatorsToTeardown = spawnedEmulators
        defer {
            Task {
                for emulator in emulatorsToTeardown {
                    _ = await emulator.teardownAndWait()
                }
            }
        }

        logger.info("Running Android test task '\(scopedTask.name)'")

        let scheduler = InfrastructureRetryScheduler(
            options: options.infrastructureRetry ?? .init(),
            classifier: AndroidInfrastructureClassifier()
        )

        return try await scheduler.execute(label: scopedTask.name) {
            let gradle = context.gradle()
                .task(scopedTask)

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

            let (pass, fail, skip) = self.parseGradleCounts(from: output.stdout + "\n" + output.stderr)
            context.logShellOutput(output, label: "gradlew test")

            // If stdout parsing found no counts, fall back to JUnit XML reports on disk
            let finalCounts: (pass: Int, fail: Int, skip: Int)
            if pass == 0 && fail == 0 && skip == 0 {
                let xmlCounts = self.aggregateJUnitXMLResults(
                    projectDir: context.config.gradleProjectDir,
                    task: task.name
                )
                finalCounts = xmlCounts
            } else {
                finalCounts = (pass, fail, skip)
            }

            self.logger.info("Android tests complete — pass: \(finalCounts.pass), fail: \(finalCounts.fail), skip: \(finalCounts.skip)")

            return Result(passCount: finalCounts.pass, failCount: finalCounts.fail, skipCount: finalCounts.skip)
        } extractContext: { error in
            if let shipItError = error as? ShipItError,
               case .testFailed(_, _, let log) = shipItError {
                return .init(log: log, underlyingError: shipItError)
            }
            return nil
        }
    }

    private func prepareAndroidDevices(
        devices: TestDeviceConfig,
        context: ActionContext
    ) async throws -> [any SpawnedProcess] {
        switch devices.strategy {
        case .none:
            return []
        case .connected:
            // Assume a device/emulator is already available — nothing to orchestrate.
            return []
        case .managed:
            // Gradle Managed Devices handle their own lifecycle — nothing to orchestrate.
            // The task name itself targets the managed device.
            return []
        case .namedEmulators:
            let shouldPrompt = devices.promptLocally ?? true
            let desiredEmulators = try await resolvedAndroidEmulators(
                configured: devices.emulators,
                shouldPrompt: shouldPrompt,
                shell: context.shell,
                allowInteractiveSelection: !context.configIsCI
            )

            guard !desiredEmulators.isEmpty else { return [] }

            var spawned: [any SpawnedProcess] = []
            for emulator in desiredEmulators {
                if let existingSerial = try await findBootedEmulatorSerial(avdName: emulator, shell: context.shell) {
                    logger.info("Using already booted emulator '\(emulator)' (\(existingSerial))")
                    continue
                }

                logger.info("Booting emulator '\(emulator)'")
                let process = try await Emulator(context: context.shell)
                    .start(avd: emulator, headless: false)
                    .spawn(teardown: .graceful)

                spawned.append(process)
                let serial = try await waitForEmulatorBoot(avdName: emulator, shell: context.shell)
                logger.info("Emulator '\(emulator)' booted as \(serial)")
            }

            return spawned
        }
    }

    private func resolvedAndroidEmulators(
        configured: [String]?,
        shouldPrompt: Bool,
        shell: ShellContext,
        allowInteractiveSelection: Bool
    ) async throws -> [String] {
        if let configured, !configured.isEmpty {
            return configured
        }

        guard allowInteractiveSelection, shouldPrompt, isInteractiveTerminal() else {
            return []
        }

        let available = try await listAvailableEmulators(shell: shell)
        guard !available.isEmpty else { return [] }

        logger.info("No emulators configured for instrumented tests; prompting for local selection")
        return promptForAndroidEmulators(available: available)
    }

    private func listAvailableEmulators(shell: ShellContext) async throws -> [String] {
        let output = try await Emulator(context: shell).list().run()
        return output.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func promptForAndroidEmulators(available: [String]) -> [String] {
        print("\nAvailable Android emulators:")
        for (index, name) in available.enumerated() {
            print("  \(index + 1). \(name)")
        }
        print("Select emulator numbers separated by commas (blank skips): ", terminator: "")

        let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !answer.isEmpty else { return [] }

        let indexes = answer
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 >= 1 && $0 <= available.count }

        return indexes.map { available[$0 - 1] }
    }

    private func isInteractiveTerminal() -> Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    }

    private func findBootedEmulatorSerial(avdName: String, shell: ShellContext) async throws -> String? {
        let output = try await Adb(context: shell).devices(long: true).run()
        for line in output.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("emulator-") else { continue }
            if trimmed.contains("avd:\(avdName)") {
                return trimmed.components(separatedBy: .whitespaces).first
            }
        }
        return nil
    }

    private func waitForEmulatorBoot(avdName: String, shell: ShellContext) async throws -> String {
        let deadline = Date().addingTimeInterval(180)

        while Date() < deadline {
            if let serial = try await findBootedEmulatorSerial(avdName: avdName, shell: shell) {
                let boot = try? await Adb(context: shell)
                    .serial(serial)
                    .shell("getprop sys.boot_completed")
                    .run()
                if boot?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                    return serial
                }
            }

            try await Task.sleep(for: .seconds(2))
        }

        throw ShipItError.invalidConfiguration(
            reason: "Timed out waiting for Android emulator '\(avdName)' to boot."
        )
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
    func aggregateJUnitXMLResults(projectDir: String, task: String) -> (pass: Int, fail: Int, skip: Int) {
        let fileManager = FileManager.default
        var totalTests = 0
        var totalFailures = 0
        var totalErrors = 0
        var totalSkipped = 0

        // Find all test-results directories matching the task name
        guard
            let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: projectDir),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return (pass: 0, fail: 0, skip: 0)
        }

        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            // Match: */build/test-results/<task>/TEST-*.xml
            guard path.contains("/build/test-results/\(task)/"),
                path.hasSuffix(".xml"),
                fileURL.lastPathComponent.hasPrefix("TEST-")
            else { continue }

            guard let data = fileManager.contents(atPath: path) else { continue }
            let counts = parseJUnitXML(data: data)
            totalTests += counts.tests
            totalFailures += counts.failures
            totalErrors += counts.errors
            totalSkipped += counts.skipped
        }

        let failures = totalFailures + totalErrors
        let passed = totalTests - failures - totalSkipped
        return (pass: max(0, passed), fail: failures, skip: totalSkipped)
    }

    /// Parses a single JUnit XML file for test counts from the `<testsuite>` element.
    private func parseJUnitXML(data: Data) -> (tests: Int, failures: Int, errors: Int, skipped: Int) {
        let parser = JUnitXMLParser(data: data)
        parser.parse()
        return (tests: parser.tests, failures: parser.failures, errors: parser.errors, skipped: parser.skipped)
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
