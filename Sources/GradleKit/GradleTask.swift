import Foundation

/// A typed Gradle task name.
///
/// Tasks are passed as positional arguments to `gradlew` (e.g. `./gradlew assembleRelease`).
/// Use `GradleTask.custom(_:)` for project-specific tasks not covered by the built-in factories.
///
/// ## Usage
/// ```swift
/// let output = try await Gradle(context: context.shell)
///     .task(.bundleRelease)
///     .run()
/// ```
public struct GradleTask: Sendable, Equatable, Hashable {

    /// The task name argument (e.g. `"assembleRelease"`).
    public let name: String

    /// Task-level options emitted immediately after ``name`` (e.g. `["--tests", "com.example.FooTest"]`).
    ///
    /// Gradle binds task options such as `--tests` to the task that *precedes* them on the command
    /// line, so they cannot be passed as global ``GradleFlag``s (which are emitted before every task
    /// and rejected with "Unknown command-line option").
    public let options: [String]

    /// The command-line arguments for this task: its ``name`` followed by its ``options``.
    public var arguments: [String] { [name] + options }

    // MARK: - Build Tasks

    /// `assembleDebug` — Build a debug APK.
    public static let assembleDebug = GradleTask(name: "assembleDebug")

    /// `assembleRelease` — Build a signed release APK.
    public static let assembleRelease = GradleTask(name: "assembleRelease")

    /// `bundleRelease` — Build a signed release AAB (preferred for Play Store).
    public static let bundleRelease = GradleTask(name: "bundleRelease")

    /// `bundleDebug` — Build a debug AAB.
    public static let bundleDebug = GradleTask(name: "bundleDebug")

    /// `clean` — Clean all build outputs.
    public static let clean = GradleTask(name: "clean")

    /// `build` — Build all variants (assembleDebug + assembleRelease).
    public static let build = GradleTask(name: "build")

    // MARK: - Test Tasks

    /// `test` — Run all unit tests on the JVM.
    public static let test = GradleTask(name: "test")

    /// `testDebugUnitTest` — Run unit tests for the debug build variant.
    public static let testDebugUnitTest = GradleTask(name: "testDebugUnitTest")

    /// `testReleaseUnitTest` — Run unit tests for the release build variant.
    public static let testReleaseUnitTest = GradleTask(name: "testReleaseUnitTest")

    /// `connectedAndroidTest` — Run instrumented tests on connected devices/emulators.
    public static let connectedAndroidTest = GradleTask(name: "connectedAndroidTest")

    /// `connectedDebugAndroidTest` — Run instrumented tests (debug variant) on a connected device.
    public static let connectedDebugAndroidTest = GradleTask(name: "connectedDebugAndroidTest")

    // MARK: - Lint Tasks

    /// `lint` — Run Android lint on all variants.
    public static let lint = GradleTask(name: "lint")

    /// `lintDebug` — Run Android lint on the debug variant only.
    public static let lintDebug = GradleTask(name: "lintDebug")

    /// `lintRelease` — Run Android lint on the release variant only.
    public static let lintRelease = GradleTask(name: "lintRelease")

    // MARK: - Info / Diagnostic Tasks

    /// `signingReport` — Print signing key fingerprints for all variants.
    public static let signingReport = GradleTask(name: "signingReport")

    /// `dependencies` — Print the full dependency tree.
    public static let dependencies = GradleTask(name: "dependencies")

    /// `tasks` — List all available tasks.
    public static let tasks = GradleTask(name: "tasks")

    // MARK: - Flavored Task Helpers

    /// Builds a flavor+variant assemble task such as `assembleFreeRelease`.
    ///
    /// - Parameters:
    ///   - flavor: Product flavor (e.g. `"free"`, `"paid"`).
    ///   - variant: Build variant (e.g. `"release"`, `"debug"`).
    public static func assemble(flavor: String, variant: String) -> GradleTask {
        variantTask(prefix: "assemble", flavor: flavor, variant: variant)
    }

    /// Builds a flavor+variant bundle task such as `bundleFreeRelease`.
    ///
    /// - Parameters:
    ///   - flavor: Product flavor (e.g. `"free"`, `"paid"`).
    ///   - variant: Build variant (e.g. `"release"`, `"debug"`).
    public static func bundle(flavor: String, variant: String) -> GradleTask {
        variantTask(prefix: "bundle", flavor: flavor, variant: variant)
    }

    // MARK: - Variant Task Helpers

    /// `assemble<Variant>` — e.g. `assemble(variant: "stagingRelease")` → `assembleStagingRelease`.
    public static func assemble(variant: String) -> GradleTask {
        variantTask(prefix: "assemble", variant: variant)
    }

    /// `bundle<Variant>` — e.g. `bundle(variant: "prodRelease")` → `bundleProdRelease`.
    public static func bundle(variant: String) -> GradleTask {
        variantTask(prefix: "bundle", variant: variant)
    }

    /// `lint<Variant>` — e.g. `lint(variant: "debug")` → `lintDebug`.
    public static func lint(variant: String) -> GradleTask {
        variantTask(prefix: "lint", variant: variant)
    }

    /// `test<Variant>UnitTest` — e.g. `unitTest(variant: "debug")` → `testDebugUnitTest`.
    public static func unitTest(variant: String) -> GradleTask {
        variantTask(prefix: "test", variant: variant, suffix: "UnitTest")
    }

    /// `connected<Variant>AndroidTest` — e.g. `connectedAndroidTest(variant: "debug")` →
    /// `connectedDebugAndroidTest`.
    public static func connectedAndroidTest(variant: String) -> GradleTask {
        variantTask(prefix: "connected", variant: variant, suffix: "AndroidTest")
    }

    /// `<device><Variant>AndroidTest` — a Gradle Managed Device task such as
    /// `pixel6Api34DebugAndroidTest` (or a device-group task such as `ciGroupDebugAndroidTest`).
    ///
    /// - Parameters:
    ///   - device: The managed device or device-group name declared in `testOptions.managedDevices`.
    ///   - variant: Build variant (e.g. `"debug"`).
    public static func managedDeviceAndroidTest(device: String, variant: String) -> GradleTask {
        variantTask(prefix: device, variant: variant, suffix: "AndroidTest")
    }

    /// Builds a variant-aware task name following the Android Gradle Plugin convention
    /// `<prefix><Flavor><Variant><suffix>`.
    ///
    /// Only the first character of each segment is upper-cased; the rest is preserved, so
    /// camelCase variants such as `"stagingRelease"` stay intact (unlike `String.capitalized`,
    /// which would produce `"Stagingrelease"`).
    ///
    /// ```swift
    /// GradleTask.variantTask(prefix: "bundle", flavor: "free", variant: "release")  // bundleFreeRelease
    /// GradleTask.variantTask(prefix: "test", variant: "debug", suffix: "UnitTest")  // testDebugUnitTest
    /// ```
    ///
    /// - Parameters:
    ///   - prefix: Task verb (e.g. `"assemble"`, `"bundle"`, `"lint"`, `"test"`).
    ///   - flavor: Optional product flavor. `nil` or empty means no flavor segment.
    ///   - variant: Build type or full variant name (e.g. `"release"`, `"prodRelease"`).
    ///   - suffix: Optional trailing segment (e.g. `"UnitTest"`, `"AndroidTest"`).
    public static func variantTask(
        prefix: String,
        flavor: String? = nil,
        variant: String,
        suffix: String = ""
    ) -> GradleTask {
        let flavorSegment = flavor.map(uppercasingFirst) ?? ""
        return GradleTask(name: prefix + flavorSegment + uppercasingFirst(variant) + suffix)
    }

    // MARK: - Kotlin Multiplatform Tasks

    /// `linkDebugFrameworkIosArm64` — Link the debug-configuration Kotlin Multiplatform
    /// iOS framework for the `iosArm64` (device) target.
    public static let linkDebugFrameworkIosArm64 = GradleTask(name: "linkDebugFrameworkIosArm64")

    /// `linkReleaseFrameworkIosArm64` — Link the release-configuration Kotlin Multiplatform
    /// iOS framework for the `iosArm64` (device) target.
    public static let linkReleaseFrameworkIosArm64 = GradleTask(name: "linkReleaseFrameworkIosArm64")

    /// `linkDebugFrameworkIosSimulatorArm64` — Link the debug-configuration KMP iOS framework
    /// for the `iosSimulatorArm64` (Apple-silicon simulator) target.
    public static let linkDebugFrameworkIosSimulatorArm64 = GradleTask(
        name: "linkDebugFrameworkIosSimulatorArm64")

    /// `linkReleaseFrameworkIosSimulatorArm64` — Link the release-configuration KMP iOS framework
    /// for the `iosSimulatorArm64` (Apple-silicon simulator) target.
    public static let linkReleaseFrameworkIosSimulatorArm64 = GradleTask(
        name: "linkReleaseFrameworkIosSimulatorArm64")

    /// `linkDebugFrameworkIosX64` — Link the debug-configuration KMP iOS framework for the
    /// `iosX64` (Intel simulator) target.
    public static let linkDebugFrameworkIosX64 = GradleTask(name: "linkDebugFrameworkIosX64")

    /// `linkReleaseFrameworkIosX64` — Link the release-configuration KMP iOS framework for
    /// the `iosX64` (Intel simulator) target.
    public static let linkReleaseFrameworkIosX64 = GradleTask(name: "linkReleaseFrameworkIosX64")

    /// `embedAndSignAppleFrameworkForXcode` — The task invoked by the Xcode "Run Script"
    /// build phase that the KMP Gradle plugin installs. Links and embeds the correct framework
    /// configuration/architecture based on Xcode environment variables.
    public static let embedAndSignAppleFrameworkForXcode = GradleTask(
        name: "embedAndSignAppleFrameworkForXcode")

    /// `iosSimulatorArm64Test` — Run KMP common/iOS-target tests on the Apple-silicon simulator.
    public static let iosSimulatorArm64Test = GradleTask(name: "iosSimulatorArm64Test")

    /// `iosArm64Test` — Run KMP common/iOS-target tests on an `iosArm64` device.
    public static let iosArm64Test = GradleTask(name: "iosArm64Test")

    /// `iosX64Test` — Run KMP common/iOS-target tests on the Intel simulator.
    public static let iosX64Test = GradleTask(name: "iosX64Test")

    /// Builds a KMP iOS framework link task such as `linkReleaseFrameworkIosSimulatorArm64`.
    ///
    /// - Parameters:
    ///   - configuration: Kotlin build configuration (e.g. `"Debug"`, `"Release"`).
    ///   - target: KMP iOS target name (e.g. `"IosArm64"`, `"IosSimulatorArm64"`, `"IosX64"`).
    public static func linkFramework(configuration: String, target: String) -> GradleTask {
        GradleTask(name: "link\(uppercasingFirst(configuration))Framework\(uppercasingFirst(target))")
    }

    /// Returns this task qualified with a Gradle module path.
    ///
    /// `GradleTask.bundleRelease.qualified(module: "app")` produces
    /// `:app:bundleRelease`. If `module` is already colon-prefixed, the leading colon is
    /// preserved and only a trailing separator is normalized.
    ///
    /// - Parameter module: Gradle module path, such as `"app"`, `"androidApp"`, or `":shared"`.
    /// - Returns: A module-qualified Gradle task.
    public func qualified(module: String) -> GradleTask {
        let trimmedModule = module.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModule.isEmpty else { return self }

        let normalizedModule = trimmedModule.hasPrefix(":") ? trimmedModule : ":\(trimmedModule)"
        let separator = normalizedModule.hasSuffix(":") ? "" : ":"
        return GradleTask(name: "\(normalizedModule)\(separator)\(name)", options: options)
    }

    /// Returns this task with `--tests <pattern>` appended for each pattern, restricting a JVM
    /// test task (e.g. `testDebugUnitTest`) to matching test classes or methods.
    ///
    /// ```swift
    /// GradleTask.unitTest(variant: "debug")
    ///     .qualified(module: "app")
    ///     .filteringTests(["com.example.FooTest.testBar"])
    /// // → :app:testDebugUnitTest --tests com.example.FooTest.testBar
    /// ```
    ///
    /// - Parameter patterns: Gradle test filter patterns. An empty array returns the task unchanged.
    public func filteringTests(_ patterns: [String]) -> GradleTask {
        guard !patterns.isEmpty else { return self }
        return appendingOptions(patterns.flatMap { ["--tests", $0] })
    }

    /// Returns this task with additional task-level options appended after its name.
    public func appendingOptions(_ values: [String]) -> GradleTask {
        GradleTask(name: name, options: options + values)
    }

    // MARK: - Custom

    /// Arbitrary custom task name.
    public static func custom(_ name: String) -> GradleTask {
        GradleTask(name: name)
    }

    // MARK: - Init

    /// Creates a `GradleTask` with the given task name and optional task-level options.
    public init(name: String, options: [String] = []) {
        self.name = name
        self.options = options
    }

    // MARK: - Private

    private static func uppercasingFirst(_ value: String) -> String {
        value.prefix(1).uppercased() + value.dropFirst()
    }
}
