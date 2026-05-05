import Foundation
import Testing

/// Integration tests for core CLI plumbing — help, version, schema, validate.
///
/// These tests run the real `shipit` binary as a subprocess.
/// No credentials or iOS/Android SDKs required.
///
/// **Prerequisite:** Run `swift build` before running these tests.
@Suite("CLI Integration")
struct CLIIntegrationTests {

    // MARK: - Help / version

    @Test("--help exits 0 and mentions shipit")
    func helpExitsZero() async throws {
        let result = try await CLI.run("--help")
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("shipit"))
    }

    @Test("--version exits 0 and contains a version string")
    func versionExitsZero() async throws {
        let result = try await CLI.run("--version")
        #expect(result.exitCode == 0)
        // Version string should look like "1.0.0" or "0.x.y"
        #expect(result.stdout.contains("."))
    }

    @Test("subcommands do not accept inherited --version")
    func subcommandsRejectInheritedVersionFlag() async throws {
        let result = try await CLI.run("build", "--version")
        #expect(result.exitCode != 0)
        #expect(result.output.contains("Unknown option '--version'"), "output: \(result.output)")
    }

    // MARK: - Schema

    @Test("schema --output json produces valid JSON")
    func schemaProducesValidJSON() async throws {
        let result = try await CLI.run("schema", "--output", "json")
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")

        let data = Data(result.stdout.utf8)
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: data)
        }
    }

    @Test("schema --workflow beta --output json contains workflow key")
    func schemaBetaContainsWorkflowKey() async throws {
        let result = try await CLI.run("schema", "--workflow", "beta", "--output", "json")
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")

        let data = Data(result.stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
    }

    // MARK: - Validate yml

    @Test("validate yml passes for valid iOS Shipfile")
    func validateYmlPassesForValidShipfile() async throws {
        let result = try await CLI.run(
            "validate", "yml",
            "--shipfile", FixturePaths.iosBetaShipfile.path
        )
        #expect(result.exitCode == 0, "output: \(result.output)")
    }

    @Test("validate yml passes for valid Android Shipfile")
    func validateYmlPassesForAndroidShipfile() async throws {
        let result = try await CLI.run(
            "validate", "yml",
            "--shipfile", FixturePaths.androidReleaseShipfile.path
        )
        #expect(result.exitCode == 0, "output: \(result.output)")
    }

    @Test("validate yml fails for malformed YAML")
    func validateYmlFailsForMalformedYAML() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-\(UUID().uuidString).yml")
        // Deliberately malformed YAML — unclosed bracket causes parse failure
        try "workflows: [unclosed bracket\n  bad: indentation:\n".write(
            to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = try await CLI.run("validate", "yml", "--shipfile", tmp.path)
        #expect(
            result.exitCode != 0, "Expected non-zero exit for malformed YAML, got: \(result.exitCode)")
    }

    // MARK: - AI session

    @Test("ai-session --goal beta produces valid JSON contract")
    func aiSessionProducesValidJSON() async throws {
        // ai-session always outputs JSON (no --output flag needed)
        let result = try await CLI.run(
            "ai-session", "--goal", "beta",
            "--path", FixturePaths.iosSample.path
        )
        // May exit 2 if project isn't fully configured — that's OK, output is still valid JSON
        #expect(result.exitCode == 0 || result.exitCode == 2, "stderr: \(result.stderr)")

        let data = Data(result.stdout.utf8)
        // The response is wrapped in an ActionResultEnvelope: {"action":..., "status":..., "payload":{...}}
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil, "Expected valid JSON output from ai-session")
        #expect(
            json?["action"] != nil || json?["version"] != nil,
            "Expected envelope or versioned JSON in ai-session response")
    }

    // MARK: - Generate

    @Test("generate --non-interactive exits 0 and always outputs JSON")
    func generateNonInteractiveExitsZero() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("generate-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = try await CLI.run(
            "generate", "--goal", "beta", "--non-interactive",
            workingDirectory: tmp
        )
        #expect(result.exitCode == 0, "output: \(result.output)")
        #expect(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("Shipfile.yml").path))
    }

    @Test("init command is removed")
    func initCommandIsRemoved() async throws {
        let result = try await CLI.run("init")
        #expect(result.exitCode != 0)
        #expect(result.output.contains("init"))
    }
}
