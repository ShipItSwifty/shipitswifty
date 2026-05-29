import Foundation
import Testing

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
//     (The legacy name SHIPIT_INTEGRATION_RUN_ENABLED=1 is still accepted.)
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
//   SHIPIT_INTEGRATION_STRICT=1 swift test --filter IntegrationTests

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
        let env = ProcessInfo.processInfo.environment
        // `SHIPIT_INTEGRATION_STRICT` is canonical; `SHIPIT_INTEGRATION_RUN_ENABLED`
        // is the legacy name kept for back-compat with existing CI configs.
        return env["SHIPIT_INTEGRATION_STRICT"] == "1" || env["SHIPIT_INTEGRATION_RUN_ENABLED"] == "1"
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
            env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"] != nil || env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH"] != nil
        return CredentialTrait(
            conditionMet: hasCredentials,
            message:
                "Google Play credentials not configured — set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH. See CONTRIBUTING.md."
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
            message:
                "Android SDK not found or gradlew not bootstrapped — set ANDROID_HOME and run `gradle wrapper --gradle-version 8.7` in the android-sample fixture."
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
            message:
                "No 'Apple Development' code signing identity found in the default keychain. Add one via Xcode Preferences > Accounts, or import a development certificate."
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
            message:
                "P12 signing credentials not configured — set SHIPIT_TEST_P12_BASE64 and SHIPIT_TEST_P12_PASSWORD. See CONTRIBUTING.md."
        )
    }

    /// Requires a booted iOS simulator (used by tests that run `xcodebuild test`).
    ///
    /// Tests that only build or archive do NOT need this trait.
    static var requiresSimulator: CredentialTrait {
        let result = try? shellOutput("xcrun", "simctl", "list", "devices", "booted", "--json")
        let hasBooted = result?.contains("\"state\" : \"Booted\"") == true || result?.contains("\"state\":\"Booted\"") == true
        return CredentialTrait(
            conditionMet: hasBooted,
            message: "No booted iOS simulator — boot one with: xcrun simctl boot <device-uuid> && open -a Simulator"
        )
    }

    /// Requires `SHIPIT_EXTERNAL_FLUTTER_PROJECT` to point at a Flutter app checkout.
    ///
    /// Use on opt-in external validation tests that exercise ShipIt against a real
    /// open-source Flutter project outside the repository fixtures.
    static var requiresExternalFlutterProject: CredentialTrait {
        let env = ProcessInfo.processInfo.environment
        let path = env["SHIPIT_EXTERNAL_FLUTTER_PROJECT"]
        let exists = path.map { FileManager.default.fileExists(atPath: $0) } ?? false
        return CredentialTrait(
            conditionMet: exists,
            message:
                "External Flutter project not configured — set SHIPIT_EXTERNAL_FLUTTER_PROJECT to a local Flutter app checkout."
        )
    }

    /// Requires `SHIPIT_EXTERNAL_RN_PROJECT` to point at a React Native CLI app checkout.
    ///
    /// Use on opt-in external validation tests that exercise ShipIt against a real
    /// open-source React Native project outside the repository fixtures.
    static var requiresExternalReactNativeProject: CredentialTrait {
        let env = ProcessInfo.processInfo.environment
        let path = env["SHIPIT_EXTERNAL_RN_PROJECT"]
        let exists = path.map { FileManager.default.fileExists(atPath: $0) } ?? false
        return CredentialTrait(
            conditionMet: exists,
            message:
                "External React Native project not configured — set SHIPIT_EXTERNAL_RN_PROJECT to a local React Native app checkout."
        )
    }

    /// Requires `flutter` on PATH for real external Flutter validation tests.
    static var requiresFlutterToolchain: CredentialTrait {
        let flutter = (try? shellOutput("which", "flutter"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CredentialTrait(
            conditionMet: flutter?.isEmpty == false,
            message: "Flutter SDK not found on PATH — install Flutter and ensure `flutter` resolves in your shell."
        )
    }

    /// Requires CocoaPods (`pod`) on PATH for React Native iOS project setup.
    static var requiresCocoaPods: CredentialTrait {
        let pod = (try? shellOutput("which", "pod"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CredentialTrait(
            conditionMet: pod?.isEmpty == false,
            message: "CocoaPods not found on PATH — install CocoaPods to validate React Native iOS builds."
        )
    }

    /// Requires `node` and `npm` on PATH for React Native Jest/eslint tiers.
    static var requiresNode: CredentialTrait {
        let node = (try? shellOutput("which", "node"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let npm = (try? shellOutput("which", "npm"))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CredentialTrait(
            conditionMet: node?.isEmpty == false && npm?.isEmpty == false,
            message: "Node.js not found on PATH — install Node (>= 22.11) so `node` and `npm` resolve in your shell."
        )
    }
}

// MARK: - E2E tier gates
//
// The build and full e2e tiers run real, slow builds (and, for the full tier,
// code signing). They are **opt-in**: a plain `swift test --filter IntegrationTests`
// runs only the quick tier. Set the env flag to opt into a heavier tier.

extension Trait where Self == ConditionTrait {

    /// Gates the e2e **quick** tier (`shipit test` + `shipit lint` against real toolchains).
    /// Opt in with `SHIPIT_E2E=1`.
    ///
    /// Even the "quick" tier runs a full `npm install` / `flutter pub get` into a temp copy
    /// before invoking `shipit`, which is slow and hits the network. Gating it keeps a plain
    /// `swift test --filter IntegrationTests` fast instead of triggering installs implicitly
    /// on any machine that happens to have Node or Flutter on PATH. The heavier `SHIPIT_E2E_BUILD`
    /// / `SHIPIT_E2E_FULL` tiers imply the quick tier too.
    static var requiresE2EQuick: ConditionTrait {
        let env = ProcessInfo.processInfo.environment
        let enabled = env["SHIPIT_E2E"] == "1" || env["SHIPIT_E2E_BUILD"] == "1" || env["SHIPIT_E2E_FULL"] == "1"
        return .enabled(
            if: enabled,
            "e2e quick tier is opt-in — set SHIPIT_E2E=1 to run real Flutter/RN test + lint (regenerates deps)."
        )
    }

    /// Gates the e2e **build** tier (`shipit build`/`archive` against real toolchains).
    /// Opt in with `SHIPIT_E2E_BUILD=1`.
    static var requiresE2EBuild: ConditionTrait {
        .enabled(
            if: ProcessInfo.processInfo.environment["SHIPIT_E2E_BUILD"] == "1",
            "e2e build tier is opt-in — set SHIPIT_E2E_BUILD=1 to run real Flutter/RN builds."
        )
    }

    /// Gates the e2e **full** tier (archive, code signing, validate signing, downstream steps).
    /// Opt in with `SHIPIT_E2E_FULL=1`.
    static var requiresE2EFull: ConditionTrait {
        .enabled(
            if: ProcessInfo.processInfo.environment["SHIPIT_E2E_FULL"] == "1",
            "e2e full tier is opt-in — set SHIPIT_E2E_FULL=1 to run archive + code signing."
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
