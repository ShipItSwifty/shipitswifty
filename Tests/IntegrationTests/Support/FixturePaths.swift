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

    /// Pre-canned JaCoCo XML report with known coverage numbers.
    static let jacocoReport: URL = fixturesRoot.appendingPathComponent("jacoco-sample.xml")

    /// Shipfile pointing at the iOS fixture scheme.
    static let iosBetaShipfile: URL = fixturesRoot
        .appendingPathComponent("Shipfiles")
        .appendingPathComponent("ios-beta.yml")

    /// Shipfile pointing at the Android fixture module (release variant — archive/bundle).
    static let androidReleaseShipfile: URL = fixturesRoot
        .appendingPathComponent("Shipfiles")
        .appendingPathComponent("android-release.yml")

    /// Shipfile pointing at the Android fixture module (debug variant — build/test).
    static let androidDebugShipfile: URL = fixturesRoot
        .appendingPathComponent("Shipfiles")
        .appendingPathComponent("android-debug.yml")
}
