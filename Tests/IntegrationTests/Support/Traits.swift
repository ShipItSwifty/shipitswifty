import Testing
import Foundation

// MARK: - Credential traits
//
// Tests decorated with these traits skip gracefully when the required environment
// variables are absent (local dev without credentials) and run automatically when
// they are present (CI with secrets injected, or a contributor's own accounts).

extension Trait where Self == ConditionTrait {

    /// Requires ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY (or ASC_PRIVATE_KEY_PATH).
    ///
    /// Use on any test that calls App Store Connect APIs.
    /// See CONTRIBUTING.md for how to set up your own credentials.
    static var requiresASCCredentials: ConditionTrait {
        let env = ProcessInfo.processInfo.environment
        let hasKey = env["ASC_KEY_ID"] != nil
        let hasIssuer = env["ASC_ISSUER_ID"] != nil
        let hasPrivateKey = env["ASC_PRIVATE_KEY"] != nil || env["ASC_PRIVATE_KEY_PATH"] != nil
        return .enabled(
            if: hasKey && hasIssuer && hasPrivateKey,
            "ASC credentials not configured — set ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY. See CONTRIBUTING.md."
        )
    }

    /// Requires GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH.
    ///
    /// Use on any test that calls Google Play APIs.
    /// The service account is scoped to com.shipitswifty.integration only.
    static var requiresGooglePlayCredentials: ConditionTrait {
        let env = ProcessInfo.processInfo.environment
        let hasCredentials =
            env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"] != nil ||
            env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH"] != nil
        return .enabled(
            if: hasCredentials,
            "Google Play credentials not configured — set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH. See CONTRIBUTING.md."
        )
    }

    /// Requires ANDROID_HOME or ANDROID_SDK_ROOT and a bootstrapped gradlew in the fixture.
    ///
    /// Use on any test that runs real Gradle builds.
    static var requiresAndroid: ConditionTrait {
        let env = ProcessInfo.processInfo.environment
        let hasSDK = env["ANDROID_HOME"] != nil || env["ANDROID_SDK_ROOT"] != nil
        let gradlew = FixturePaths.androidSample.appendingPathComponent("gradlew").path
        let hasGradlew = FileManager.default.fileExists(atPath: gradlew)
        return .enabled(
            if: hasSDK && hasGradlew,
            "Android SDK not found or gradlew not bootstrapped — set ANDROID_HOME and run `gradle wrapper --gradle-version 8.7` in the android-sample fixture."
        )
    }

    /// Requires a path to a signed iOS archive for end-to-end upload-readiness validation.
    static var requiresSignedArchive: ConditionTrait {
        let env = ProcessInfo.processInfo.environment
        let archivePath = env["SHIPIT_SIGNED_ARCHIVE_PATH"]
        let exists = archivePath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        return .enabled(
            if: exists,
            "Signed archive not configured — set SHIPIT_SIGNED_ARCHIVE_PATH to a signed .xcarchive for com.shipitswifty.integration."
        )
    }

    /// Requires a local "Apple Development" code signing identity in the default keychain.
    ///
    /// Use on Layer 2 signing tests that install certificates and sign builds on a dev machine.
    /// Does NOT need any environment variables — it checks the local keychain directly.
    static var requiresSigningIdentity: ConditionTrait {
        let output = (try? shellOutput("security", "find-identity", "-v", "-p", "codesigning")) ?? ""
        let hasIdentity = output.contains("Apple Development")
        return .enabled(
            if: hasIdentity,
            "No 'Apple Development' code signing identity found in the default keychain. Add one via Xcode Preferences > Accounts, or import a development certificate."
        )
    }

    /// Requires a P12 certificate and password for end-to-end CI signing round-trips.
    ///
    /// Set `SHIPIT_TEST_P12_BASE64` (base64-encoded .p12 file) and
    /// `SHIPIT_TEST_P12_PASSWORD` in CI secrets.
    static var requiresP12Credentials: ConditionTrait {
        let env = ProcessInfo.processInfo.environment
        let hasP12 = env["SHIPIT_TEST_P12_BASE64"] != nil
        let hasPassword = env["SHIPIT_TEST_P12_PASSWORD"] != nil
        return .enabled(
            if: hasP12 && hasPassword,
            "P12 signing credentials not configured — set SHIPIT_TEST_P12_BASE64 and SHIPIT_TEST_P12_PASSWORD. See CONTRIBUTING.md."
        )
    }

    /// Requires a booted iOS simulator (used by tests that run `xcodebuild test`).
    ///
    /// Tests that only build or archive do NOT need this trait.
    static var requiresSimulator: ConditionTrait {
        // Check if any simulator is booted by inspecting xcrun simctl output
        let result = try? shellOutput("xcrun", "simctl", "list", "devices", "booted", "--json")
        let hasBooted = result?.contains("\"state\" : \"Booted\"") == true ||
                        result?.contains("\"state\":\"Booted\"") == true
        return .enabled(
            if: hasBooted,
            "No booted iOS simulator — boot one with: xcrun simctl boot <device-uuid> && open -a Simulator"
        )
    }
}

// MARK: - Helpers

/// Synchronously runs a command and returns stdout. Used only during trait evaluation.
private func shellOutput(_ command: String, _ arguments: String...) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}
