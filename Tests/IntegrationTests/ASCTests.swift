import Testing
import Foundation

/// Integration tests for App Store Connect API calls.
///
/// These tests target `com.shipitswifty.integration` exclusively — `assertIntegrationScope()`
/// is called in every test as a hard guard before any API call is made.
///
/// **Requirements:**
/// - `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (or `ASC_PRIVATE_KEY_PATH`)
/// - Credentials must belong to the **dedicated integration Apple Developer account**
///   (not a personal or production account). Ask a maintainer for access.
///
/// See CONTRIBUTING.md for credential setup instructions.
@Suite("ASC Integration", .requiresASCCredentials)
struct ASCIntegrationTests {

    // MARK: - Validate metadata (precheck)

    @Test("validate metadata runs precheck against integration app")
    func validateMetadataRunsPrecheck() async throws {
        try assertIntegrationScope(shipfile: FixturePaths.iosBetaShipfile)

        let result = try await CLI.run(
            "validate", "metadata",
            "--shipfile", FixturePaths.iosBetaShipfile.path,
            "--output", "json",
            environment: ascEnvironment()
        )
        // Precheck may warn but should not crash
        #expect(result.exitCode == 0 || result.exitCode == 1,
                "Unexpected exit code \(result.exitCode):\n\(result.stderr)")
        // Must not error on authentication
        #expect(!result.stderr.contains("401"), "Auth failure: \(result.stderr)")
        #expect(!result.stderr.contains("403"), "Permission failure: \(result.stderr)")
    }

    // MARK: - TestFlight upload (dry-run)

    @Test("testflight --dry-run exits 0 with credentials present")
    func testFlightDryRunExitsZero() async throws {
        try assertIntegrationScope(shipfile: FixturePaths.iosBetaShipfile)

        let result = try await CLI.run(
            "testflight",
            "--shipfile", FixturePaths.iosBetaShipfile.path,
            "--dry-run",
            "--output", "json",
            environment: ascEnvironment()
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
    }

    // MARK: - Helpers

    private func ascEnvironment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var out: [String: String] = [:]
        ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY", "ASC_PRIVATE_KEY_PATH"]
            .forEach { key in out[key] = env[key] }
        return out.compactMapValues { $0 }
    }
}
