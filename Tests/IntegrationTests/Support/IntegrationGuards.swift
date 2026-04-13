import Testing
import Foundation

// MARK: - Bundle ID guard

/// The single bundle ID authorised for all integration testing.
///
/// Every credentialed test MUST call `assertIntegrationScope()` before making
/// any App Store Connect or Google Play API call. This ensures that even if
/// credentials are leaked, they cannot be used to modify any production app.
let integrationBundleID = "com.shipitswifty.integration"

/// Asserts that the active bundle ID matches the designated integration test app.
///
/// Call this at the top of every credentialed test:
/// ```swift
/// @Test(.requiresASCCredentials)
/// func testFlightUpload() async throws {
///     try assertIntegrationScope(shipfile: FixturePaths.iosBetaShipfile)
///     // ... rest of test
/// }
/// ```
func assertIntegrationScope(bundleID: String) throws {
    #expect(bundleID == integrationBundleID,
        "Integration tests may only target '\(integrationBundleID)' — got '\(bundleID)'. This guard prevents leaked credentials from touching production apps.")
    guard bundleID == integrationBundleID else {
        throw IntegrationScopeError.wrongBundleID(expected: integrationBundleID, got: bundleID)
    }
}

/// Extracts the bundle ID from a fixture Shipfile and verifies it targets the integration app.
func assertIntegrationScope(shipfile: URL) throws {
    let contents = try String(contentsOf: shipfile, encoding: .utf8)
    let pattern = #"(?m)^\s*bundle_id:\s*([^\s#]+)\s*$"#
    guard
        let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)),
        let bundleRange = Range(match.range(at: 1), in: contents)
    else {
        throw IntegrationScopeError.fixtureMissing(
            "Could not extract bundle_id from Shipfile at \(shipfile.path)."
        )
    }

    try assertIntegrationScope(bundleID: String(contents[bundleRange]))
}

// MARK: - Fixture validation

/// Asserts the iOS fixture project exists on disk.
func assertIOSFixtureExists() throws {
    let projectPath = FixturePaths.iosSample
        .appendingPathComponent("ios-sample.xcodeproj")
        .path
    guard FileManager.default.fileExists(atPath: projectPath) else {
        throw IntegrationScopeError.fixtureMissing(
            "iOS fixture project not found at \(projectPath) — ensure Tests/IntegrationTests/Fixtures/ios-sample/ is present.")
    }
}

/// Asserts the Android fixture project exists and gradlew is present.
func assertAndroidFixtureExists() throws {
    let gradlewPath = FixturePaths.androidSample
        .appendingPathComponent("gradlew")
        .path
    guard FileManager.default.fileExists(atPath: gradlewPath) else {
        throw IntegrationScopeError.fixtureMissing(
            "Android fixture gradlew not found at \(gradlewPath) — run `gradle wrapper --gradle-version 8.7` in the android-sample fixture.")
    }
}

// MARK: - Error types

enum IntegrationScopeError: Error, CustomStringConvertible, Sendable {
    case wrongBundleID(expected: String, got: String)
    case fixtureMissing(String)

    var description: String {
        switch self {
        case .wrongBundleID(let expected, let got):
            return "Integration scope violation: expected '\(expected)' but got '\(got)'"
        case .fixtureMissing(let message):
            return message
        }
    }
}
