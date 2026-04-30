import Foundation
import Testing

/// Integration tests for Google Play API calls.
///
/// These tests target `com.shipitswifty.integration` exclusively — `assertIntegrationScope()`
/// is called in every test as a hard guard before any API call is made.
///
/// The service account used here is **scoped to com.shipitswifty.integration only** in the
/// Google Play Console. Even if credentials leak, they cannot reach any other app.
///
/// **Requirements:**
/// - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` or `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH`
///
/// See CONTRIBUTING.md for credential setup instructions.
@Suite("Google Play Integration", .requiresGooglePlayCredentials)
struct GooglePlayIntegrationTests {

    // MARK: - Play Store upload (dry-run)

    @Test("play-store --dry-run exits 0 with credentials present")
    func playStoreDryRunExitsZero() async throws {
        try assertIntegrationScope(shipfile: FixturePaths.androidReleaseShipfile)

        let result = try await CLI.run(
            "play-store",
            "--platform", "android",
            "--shipfile", FixturePaths.androidReleaseShipfile.path,
            "--dry-run",
            "--output", "json",
            environment: googlePlayEnvironment()
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
    }

    // MARK: - Helpers

    private func googlePlayEnvironment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var out: [String: String] = [:]
        ["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH"]
            .forEach { key in out[key] = env[key] }
        return out.compactMapValues { $0 }
    }
}
