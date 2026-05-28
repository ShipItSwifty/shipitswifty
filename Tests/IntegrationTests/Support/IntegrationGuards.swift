import Foundation
import Testing

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
    #expect(
        bundleID == integrationBundleID,
        "Integration tests may only target '\(integrationBundleID)' — got '\(bundleID)'. This guard prevents leaked credentials from touching production apps."
    )
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
            "Android fixture gradlew not found at \(gradlewPath) — run `gradle wrapper --gradle-version 8.7` in the android-sample fixture."
        )
    }
}

/// Asserts the Flutter fixture project exists on disk.
func assertFlutterFixtureExists() throws {
    let pubspecPath = FixturePaths.flutterSample
        .appendingPathComponent("pubspec.yaml")
        .path
    guard FileManager.default.fileExists(atPath: pubspecPath) else {
        throw IntegrationScopeError.fixtureMissing(
            "Flutter fixture pubspec not found at \(pubspecPath) — ensure Tests/IntegrationTests/Fixtures/flutter-sample/ is present."
        )
    }
}

/// Asserts the React Native fixture project exists on disk.
func assertReactNativeFixtureExists() throws {
    let packageJSONPath = FixturePaths.reactNativeSample
        .appendingPathComponent("package.json")
        .path
    guard FileManager.default.fileExists(atPath: packageJSONPath) else {
        throw IntegrationScopeError.fixtureMissing(
            "React Native fixture package.json not found at \(packageJSONPath) — ensure Tests/IntegrationTests/Fixtures/react-native-sample/ is present."
        )
    }
}

/// Asserts the full Flutter app fixture exists on disk.
func assertFlutterAppFixtureExists() throws {
    let pubspecPath = FixturePaths.flutterApp
        .appendingPathComponent("pubspec.yaml")
        .path
    guard FileManager.default.fileExists(atPath: pubspecPath) else {
        throw IntegrationScopeError.fixtureMissing(
            "Flutter app fixture pubspec not found at \(pubspecPath) — ensure Tests/IntegrationTests/Fixtures/flutter-app/ is present."
        )
    }
}

/// Asserts the full React Native app fixture exists on disk.
func assertReactNativeAppFixtureExists() throws {
    let packageJSONPath = FixturePaths.reactNativeApp
        .appendingPathComponent("package.json")
        .path
    guard FileManager.default.fileExists(atPath: packageJSONPath) else {
        throw IntegrationScopeError.fixtureMissing(
            "React Native app fixture package.json not found at \(packageJSONPath) — ensure Tests/IntegrationTests/Fixtures/react-native-app/ is present."
        )
    }
}

/// Asserts the KMP fixture project exists on disk.
func assertKMPFixtureExists() throws {
    let gradleFilePath = FixturePaths.kmpSample
        .appendingPathComponent("build.gradle.kts")
        .path
    guard FileManager.default.fileExists(atPath: gradleFilePath) else {
        throw IntegrationScopeError.fixtureMissing(
            "KMP fixture build.gradle.kts not found at \(gradleFilePath) — ensure Tests/IntegrationTests/Fixtures/kmp-sample/ is present."
        )
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
