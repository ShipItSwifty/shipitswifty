import ArgumentParser
import ShipItKit

extension TestKind: ExpressibleByArgument {}
extension GradleTaskScope: ExpressibleByArgument {}
extension TestDeviceStrategy: ExpressibleByArgument {}

/// Run unit and UI tests using `xcodebuild test`.
struct TestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run unit and UI tests using xcodebuild test"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Xcode scheme to test")
    var scheme: String?

    @Option(name: .long, help: "Simulator or device destination (e.g. 'platform=iOS Simulator,name=iPhone 16')")
    var destination: String?

    @Option(name: .long, help: "Build configuration (default: Debug)")
    var configuration: String?

    @Flag(name: .long, help: "Enable code coverage collection (auto-generates result bundle path if --result-bundle-path is not set)")
    var codeCoverage: Bool = false

    @Option(name: .long, help: "Path to write the .xcresult bundle")
    var resultBundlePath: String?

    @Option(name: .long, help: "Test plan name to run")
    var testPlan: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Restrict run to specific test targets or test cases (repeatable, e.g. MyAppTests/MyFeatureTests)"
    )
    var onlyTesting: [String] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Skip specific test targets or test cases (repeatable)"
    )
    var skipTesting: [String] = []

    @Flag(name: .long, help: "Retry failing tests once before reporting failure")
    var retryOnFailure: Bool = false

    @Flag(name: .customLong("rerun-failed-tests"), help: "Rerun only the failed tests when the runner supports it")
    var rerunFailedTests: Bool = false

    @Option(name: .customLong("max-rerun-attempts"), help: "Maximum attempts including the initial run when rerunning failed tests")
    var maxRerunAttempts: Int?

    @Option(name: .customLong("report-path"), help: "Write the structured JSON test report to a file")
    var reportPath: String?

    @Option(name: .long, help: "Test kind: unit | instrumented | e2e (Android)")
    var kind: TestKind?

    @Option(name: .long, help: "Gradle task scope: module | root (Android)")
    var scope: GradleTaskScope?

    @Option(name: .long, help: "Gradle module to test (Android) or KMP shared module (iOS KMP)")
    var module: String?

    @Option(name: .long, help: "Gradle build variant to test (Android, default: debug)")
    var buildVariant: String?

    @Option(name: .long, help: "Explicit Gradle task name (Android, overrides variant-based selection)")
    var task: String?

    @Option(name: .long, help: "Device strategy: none | connected | named_emulators | managed (Android)")
    var deviceStrategy: TestDeviceStrategy?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Android emulator AVD names to boot for instrumented tests (repeatable)"
    )
    var emulators: [String] = []

    @Option(name: .long, help: "Gradle managed device group name (Android)")
    var deviceGroup: String?

    @Flag(name: .long, help: "Prompt locally for Android emulator selection when running instrumented tests")
    var promptLocally: Bool = false

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(scheme: scheme, ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(
                config: config, verbose: global.verbose, jsonOutput: global.output == .json)
            let formatter = makeHumanFormatter(global: global)

            // Build device config from CLI flags
            let devices: TestDeviceConfig?
            if deviceStrategy != nil || !emulators.isEmpty || deviceGroup != nil || promptLocally {
                devices = TestDeviceConfig(
                    strategy: deviceStrategy ?? .none,
                    emulators: emulators.isEmpty ? nil : emulators,
                    group: deviceGroup,
                    promptLocally: promptLocally ? true : nil
                )
            } else {
                devices = nil
            }

            let options = TestAction.Options(
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                enableCodeCoverage: codeCoverage ? true : nil,
                resultBundlePath: resultBundlePath,
                testPlan: testPlan,
                onlyTesting: onlyTesting.isEmpty ? nil : onlyTesting,
                skipTesting: skipTesting.isEmpty ? nil : skipTesting,
                retryOnFailure: retryOnFailure ? true : nil,
                rerunFailedTests: rerunFailedTests ? .init(enabled: true, maxAttempts: maxRerunAttempts ?? 2) : nil,
                reportPath: reportPath,
                kind: kind,
                scope: scope,
                module: module,
                buildVariant: buildVariant,
                task: task,
                devices: devices
            )

            if global.dryRun {
                if config.platform == .android {
                    let effectiveModule = module ?? config.androidModule
                    let effectiveKind = kind ?? config.androidTestKind
                    let effectiveScope = scope ?? config.androidScope
                    let effectiveTask =
                        task
                        ?? (effectiveKind == .instrumented
                            ? "connectedDebugAndroidTest"
                            : "test\(buildVariant ?? config.androidBuildVariant)UnitTest")
                    if effectiveScope == .root {
                        formatter.print("DRY RUN: Would run root Gradle task '\(effectiveTask)'")
                    } else {
                        formatter.print(
                            "DRY RUN: Would run Gradle task ':\(effectiveModule):\(effectiveTask)'"
                        )
                    }
                } else if config.iosBuildSystem == .kmp {
                    formatter.print(
                        "DRY RUN: Would run KMP iOS test task '\(config.kmpTestTask)' in module '\(module ?? config.kmpSharedModule)'")
                } else {
                    formatter.print("DRY RUN: Would test scheme '\(scheme ?? config.appScheme ?? "unknown")'")
                }
                return
            }

            let result = try await TestAction().run(with: options, context: context)
            outputResult(action: "test", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
