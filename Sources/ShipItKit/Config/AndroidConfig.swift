import Foundation

/// Android-specific configuration for the `android:` Shipfile block.
///
/// When `platform` resolves to `.android`, the `ConfigResolver` merges this block
/// on top of shared Shipfile defaults.
///
/// ## Shipfile.yml Example
/// ```yaml
/// android:
///   module: app
///   package_name: com.example.myapp
///   build_type: aab
/// ```
public struct AndroidConfig: Codable, Sendable {

    /// Build system that produces the Android artifact. Defaults to ``BuildSystem/native``.
    /// Set to `.flutter`, `.reactNative`, or `.kmp` when the same source tree drives the
    /// Android target via a cross-platform tool.
    public var buildSystem: BuildSystem?

    /// Gradle module name (e.g. `app`). Defaults to `"app"`.
    public var module: String?

    /// Default scope for Android Gradle test tasks.
    ///
    /// - `module`: Qualify tasks with `module`, e.g. `:app:testDebugUnitTest`.
    /// - `root`: Run tasks from the Gradle root, e.g. `testDebugUnitTest`.
    public var scope: GradleTaskScope?

    /// Default test kind for Android test steps.
    public var testKind: TestKind?

    /// Default device configuration for Android instrumented tests.
    public var testDevices: TestDeviceConfig?

    /// Build variant (e.g. `release`, `debug`). Defaults to `"release"`.
    public var buildVariant: String?

    /// Output artifact type. Defaults to `.aab` for Play Store compatibility.
    public var buildType: AndroidBuildType?

    /// Path to the `gradlew` wrapper script. Auto-detected in the project root if nil.
    public var gradlewPath: String?

    /// Directory containing the Gradle root project. Defaults to the Shipfile directory.
    public var gradleProjectDir: String?

    /// Path to the Android keystore (`.jks` / `.keystore`) file.
    public var keystorePath: String?

    /// Signing key alias within the keystore.
    public var keystoreAlias: String?

    /// Android application package name (e.g. `com.example.myapp`).
    public var packageName: String?

    /// Staged rollout fraction (0.0–1.0). `nil` means full rollout (`completed` status).
    public var rolloutFraction: Double?

    /// Additional Gradle `-P` properties passed verbatim to every `gradlew` invocation.
    public var gradleProperties: [String: String]?

    /// Product flavor name (e.g. `free`, `paid`). Combined with `buildVariant` for task names.
    public var flavor: String?

    /// Additional Gradle flags such as `--no-daemon`, `--parallel`, `--configuration-cache`.
    public var gradleFlags: [String]?

    enum CodingKeys: String, CodingKey {
        case buildSystem = "build_system"
        case module
        case scope
        case testKind = "test_kind"
        case testDevices = "test_devices"
        case buildVariant = "build_variant"
        case buildType = "build_type"
        case gradlewPath = "gradlew_path"
        case gradleProjectDir = "gradle_project_dir"
        case keystorePath = "keystore_path"
        case keystoreAlias = "keystore_alias"
        case packageName = "package_name"
        case rolloutFraction = "rollout_fraction"
        case gradleProperties = "gradle_properties"
        case flavor
        case gradleFlags = "gradle_flags"
    }

    /// Creates an `AndroidConfig`.
    public init(
        buildSystem: BuildSystem? = nil,
        module: String? = nil,
        scope: GradleTaskScope? = nil,
        testKind: TestKind? = nil,
        testDevices: TestDeviceConfig? = nil,
        buildVariant: String? = nil,
        buildType: AndroidBuildType? = nil,
        gradlewPath: String? = nil,
        gradleProjectDir: String? = nil,
        keystorePath: String? = nil,
        keystoreAlias: String? = nil,
        packageName: String? = nil,
        rolloutFraction: Double? = nil,
        gradleProperties: [String: String]? = nil,
        flavor: String? = nil,
        gradleFlags: [String]? = nil
    ) {
        self.buildSystem = buildSystem
        self.module = module
        self.scope = scope
        self.testKind = testKind
        self.testDevices = testDevices
        self.buildVariant = buildVariant
        self.buildType = buildType
        self.gradlewPath = gradlewPath
        self.gradleProjectDir = gradleProjectDir
        self.keystorePath = keystorePath
        self.keystoreAlias = keystoreAlias
        self.packageName = packageName
        self.rolloutFraction = rolloutFraction
        self.gradleProperties = gradleProperties
        self.flavor = flavor
        self.gradleFlags = gradleFlags
    }
}

/// The type of Android build artifact to produce.
public enum AndroidBuildType: String, Codable, Sendable, CaseIterable {
    /// Android App Bundle — required by Google Play for new app uploads (since Aug 2021).
    case aab
    /// Android Package — for direct distribution (sideloading, Firebase App Distribution, etc.).
    case apk
}

/// iOS-specific Shipfile overrides for the `ios:` block.
///
/// When present, these values are merged on top of the shared root config when the platform
/// resolves to `.ios`. This lets you share a single Shipfile across an iOS+Android project.
///
/// ## Shipfile.yml Example
/// ```yaml
/// ios:
///   scheme: MyiOSApp
/// android:
///   module: app
/// ```
public struct IOSConfig: Codable, Sendable {
    /// Build system that produces the iOS artifact. Defaults to ``BuildSystem/native``.
    /// Set to `.flutter`, `.reactNative`, or `.kmp` when the iOS app is wrapped by a
    /// cross-platform tool.
    public var buildSystem: BuildSystem?
    /// KMP module containing shared iOS framework tasks. Defaults to `shared`.
    public var kmpSharedModule: String?
    /// KMP iOS framework target used for local builds. Defaults to `IosSimulatorArm64`.
    public var kmpBuildTarget: String?
    /// KMP iOS framework target used for archives. Defaults to `IosArm64`.
    public var kmpArchiveTarget: String?
    /// KMP iOS test Gradle task. Defaults to `iosSimulatorArm64Test`.
    public var kmpTestTask: String?
    /// iOS-specific Xcode scheme override.
    public var scheme: String?
    /// iOS-specific Xcode workspace override.
    public var workspace: String?
    /// iOS-specific Xcode project override.
    public var project: String?

    enum CodingKeys: String, CodingKey {
        case buildSystem = "build_system"
        case kmpSharedModule = "kmp_shared_module"
        case kmpBuildTarget = "kmp_build_target"
        case kmpArchiveTarget = "kmp_archive_target"
        case kmpTestTask = "kmp_test_task"
        case scheme
        case workspace
        case project
    }

    /// Creates an `IOSConfig`.
    public init(
        buildSystem: BuildSystem? = nil,
        kmpSharedModule: String? = nil,
        kmpBuildTarget: String? = nil,
        kmpArchiveTarget: String? = nil,
        kmpTestTask: String? = nil,
        scheme: String? = nil,
        workspace: String? = nil,
        project: String? = nil
    ) {
        self.buildSystem = buildSystem
        self.kmpSharedModule = kmpSharedModule
        self.kmpBuildTarget = kmpBuildTarget
        self.kmpArchiveTarget = kmpArchiveTarget
        self.kmpTestTask = kmpTestTask
        self.scheme = scheme
        self.workspace = workspace
        self.project = project
    }
}
