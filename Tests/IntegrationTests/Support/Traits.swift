import Testing
import Foundation

// MARK: - CredentialTrait
//
// A custom trait that drives two behaviours depending on the environment:
//
//   Normal mode (default):
//     Missing credentials → test is **skipped** with an explanatory message.
//     This lets `swift test` pass cleanly on a machine without any secrets.
//
//   Strict mode (SHIPIT_INTEGRATION_STRICT=1):
//     Missing credentials → test **fails** immediately in prepare(for:).
//     Use this in CI jobs where every credential-gated test is expected to run.
//
// Implementation note: we wrap ConditionTrait and delegate to its prepare(for:) in
// non-strict mode so it handles the skip signal correctly. In strict mode we throw
// a plain Error instead, which Swift Testing records as a test failure.
//
// Usage:
//   @Test("my test", .requiresASCCredentials)
//   func myTest() async throws { ... }
//
// Run in strict mode:
//   SHIPIT_INTEGRATION_RUN_ENABLED=1 swift test --filter IntegrationTests

struct CredentialTrait: TestTrait, SuiteTrait {
    private let conditionMet: Bool
    private let message: String
    private let skipTrait: ConditionTrait

    init(conditionMet: Bool, message: String) {
        self.conditionMet = conditionMet
        self.message = message
        self.skipTrait = .enabled(if: conditionMet, Comment(rawValue: message))
    }

    private static var isStrictMode: Bool {
        ProcessInfo.processInfo.environment["SHIPIT_INTEGRATION_RUN_ENABLED"] == "1"
    }

    func prepare(for test: Test) async throws {
        if Self.isStrictMode {
            guard conditionMet else {
                throw CredentialMissingError(message: message)
            }
        } else {
            try await skipTrait.prepare(for: test)
        }
    }
}

private struct CredentialMissingError: Error, CustomStringConvertible {
    let message: String
    var description: String { "Missing required credential: \(message)" }
}

// MARK: - Credential traits

extension Trait where Self == CredentialTrait {

    /// Requires ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY (or ASC_PRIVATE_KEY_PATH).
    ///
    /// Use on any test that calls App Store Connect APIs.
    /// See CONTRIBUTING.md for how to set up your own credentials.
    static var requiresASCCredentials: CredentialTrait {
        let env = ProcessInfo.processInfo.environment
        let hasKey = env["ASC_KEY_ID"] != nil
        let hasIssuer = env["ASC_ISSUER_ID"] != nil
        let hasPrivateKey = env["ASC_PRIVATE_KEY"] != nil || env["ASC_PRIVATE_KEY_PATH"] != nil
        return CredentialTrait(
            conditionMet: hasKey && hasIssuer && hasPrivateKey,
            message: "ASC credentials not configured — set ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY. See CONTRIBUTING.md."
        )
    }

    /// Requires GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH.
    ///
    /// Use on any test that calls Google Play APIs.
    /// The service account is scoped to com.shipitswifty.integration only.
    static var requiresGooglePlayCredentials: CredentialTrait {
        let env = ProcessInfo.processInfo.environment
        let hasCredentials =
            env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"] != nil ||
            env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH"] != nil
        return CredentialTrait(
            conditionMet: hasCredentials,
            message: "Google Play credentials not configured — set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH. See CONTRIBUTING.md."
        )
    }

    /// Requires ANDROID_HOME or ANDROID_SDK_ROOT and a bootstrapped gradlew in the fixture.
    ///
    /// Use on any test that runs real Gradle builds.
    static var requiresAndroid: CredentialTrait {
        let env = ProcessInfo.processInfo.environment
        let hasSDK = env["ANDROID_HOME"] != nil || env["ANDROID_SDK_ROOT"] != nil
        let gradlew = FixturePaths.androidSample.appendingPathComponent("gradlew").path
        let hasGradlew = FileManager.default.fileExists(atPath: gradlew)
        return CredentialTrait(
            conditionMet: hasSDK && hasGradlew,
            message: "Android SDK not found or gradlew not bootstrapped — set ANDROID_HOME and run `gradle wrapper --gradle-version 8.7` in the android-sample fixture."
        )
    }

    /// Requires a local "Apple Development" code signing identity in the default keychain.
    ///
    /// Use on Layer 2 signing tests that install certificates and sign builds on a dev machine.
    /// Does NOT need any environment variables — it checks the local keychain directly.
    static var requiresSigningIdentity: CredentialTrait {
        let output = (try? shellOutput("security", "find-identity", "-v", "-p", "codesigning")) ?? ""
        return CredentialTrait(
            conditionMet: output.contains("Apple Development"),
            message: "No 'Apple Development' code signing identity found in the default keychain. Add one via Xcode Preferences > Accounts, or import a development certificate."
        )
    }

    /// Requires a P12 certificate and password for end-to-end CI signing round-trips.
    ///
    /// Set `SHIPIT_TEST_P12_BASE64` (base64-encoded .p12 file) and
    /// `SHIPIT_TEST_P12_PASSWORD` in CI secrets.
    static var requiresP12Credentials: CredentialTrait {
        let env = ProcessInfo.processInfo.environment
        let hasP12 = env["SHIPIT_TEST_P12_BASE64"] != nil
        let hasPassword = env["SHIPIT_TEST_P12_PASSWORD"] != nil
        return CredentialTrait(
            conditionMet: hasP12 && hasPassword,
            message: "P12 signing credentials not configured — set SHIPIT_TEST_P12_BASE64 and SHIPIT_TEST_P12_PASSWORD. See CONTRIBUTING.md."
        )
    }

    /// Requires a booted iOS simulator (used by tests that run `xcodebuild test`).
    ///
    /// Tests that only build or archive do NOT need this trait.
    static var requiresSimulator: CredentialTrait {
        let result = try? shellOutput("xcrun", "simctl", "list", "devices", "booted", "--json")
        let hasBooted = result?.contains("\"state\" : \"Booted\"") == true ||
                        result?.contains("\"state\":\"Booted\"") == true
        return CredentialTrait(
            conditionMet: hasBooted,
            message: "No booted iOS simulator — boot one with: xcrun simctl boot <device-uuid> && open -a Simulator"
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
