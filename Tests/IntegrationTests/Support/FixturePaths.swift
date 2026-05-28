import Foundation

/// Compile-time-resolved paths to integration test fixture files.
///
/// Uses `#filePath` so paths are always correct regardless of where `swift test`
/// is invoked from — no relative-path fragility.
enum FixturePaths {

    private static let fixturesRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Support/
        .deletingLastPathComponent()  // IntegrationTests/
        .appendingPathComponent("Fixtures")

    /// Minimal iOS Xcode project wired to `com.shipitswifty.integration`.
    static let iosSample: URL = fixturesRoot.appendingPathComponent("ios-sample")

    /// Minimal Android Gradle project wired to `com.shipitswifty.integration`.
    static let androidSample: URL = fixturesRoot.appendingPathComponent("android-sample")

    /// Minimal Flutter-shaped project used for cross-platform integration tests.
    static let flutterSample: URL = fixturesRoot.appendingPathComponent("flutter-sample")

    /// Minimal React Native-shaped project used for cross-platform integration tests.
    static let reactNativeSample: URL = fixturesRoot.appendingPathComponent("react-native-sample")

    /// Minimal KMP-shaped project used for cross-platform integration tests.
    static let kmpSample: URL = fixturesRoot.appendingPathComponent("kmp-sample")

    /// Full real Flutter app vendored in-repo for end-to-end tests.
    ///
    /// Source-only: `.dart_tool/`, `build/`, and the android Gradle caches are
    /// regenerated at test time via `flutter pub get` (see `bootstrapFlutter(in:)`).
    static let flutterApp: URL = fixturesRoot.appendingPathComponent("flutter-app")

    /// Full real React Native app (pinned to a stable RN release) vendored in-repo
    /// for end-to-end tests.
    ///
    /// Source-only: `node_modules/` and `ios/Pods/` are regenerated at test time via
    /// `npm install` / `pod install` (see `bootstrapReactNativeNode(in:)` /
    /// `bootstrapReactNativePods(in:)`).
    static let reactNativeApp: URL = fixturesRoot.appendingPathComponent("react-native-app")

    /// Pre-canned JaCoCo XML report with known coverage numbers.
    static let jacocoReport: URL = fixturesRoot.appendingPathComponent("jacoco-sample.xml")

    /// Shipfile pointing at the iOS fixture scheme.
    static let iosBetaShipfile: URL =
        fixturesRoot
        .appendingPathComponent("Shipfiles")
        .appendingPathComponent("ios-beta.yml")

    /// Shipfile pointing at the Android fixture module (release variant — archive/bundle).
    static let androidReleaseShipfile: URL =
        fixturesRoot
        .appendingPathComponent("Shipfiles")
        .appendingPathComponent("android-release.yml")

    /// Shipfile pointing at the Android fixture module (debug variant — build/test).
    static let androidDebugShipfile: URL =
        fixturesRoot
        .appendingPathComponent("Shipfiles")
        .appendingPathComponent("android-debug.yml")

    /// Minimal App Store metadata fixture used by precheck integration tests.
    static let metadata: URL = fixturesRoot.appendingPathComponent("metadata")
}
