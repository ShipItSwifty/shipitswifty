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
        let f = flavor.prefix(1).uppercased() + flavor.dropFirst()
        let v = variant.prefix(1).uppercased() + variant.dropFirst()
        return GradleTask(name: "assemble\(f)\(v)")
    }

    /// Builds a flavor+variant bundle task such as `bundleFreeRelease`.
    ///
    /// - Parameters:
    ///   - flavor: Product flavor (e.g. `"free"`, `"paid"`).
    ///   - variant: Build variant (e.g. `"release"`, `"debug"`).
    public static func bundle(flavor: String, variant: String) -> GradleTask {
        let f = flavor.prefix(1).uppercased() + flavor.dropFirst()
        let v = variant.prefix(1).uppercased() + variant.dropFirst()
        return GradleTask(name: "bundle\(f)\(v)")
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
        let cfg = configuration.prefix(1).uppercased() + configuration.dropFirst()
        let tgt = target.prefix(1).uppercased() + target.dropFirst()
        return GradleTask(name: "link\(cfg)Framework\(tgt)")
    }

    // MARK: - Custom

    /// Arbitrary custom task name.
    public static func custom(_ name: String) -> GradleTask {
        GradleTask(name: name)
    }

    // MARK: - Init

    /// Creates a `GradleTask` with the given task name.
    public init(name: String) {
        self.name = name
    }
}
