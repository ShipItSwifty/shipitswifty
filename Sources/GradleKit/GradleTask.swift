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
