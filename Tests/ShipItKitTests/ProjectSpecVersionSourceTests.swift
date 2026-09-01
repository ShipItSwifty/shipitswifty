#if os(macOS)
import AppStoreConnectKit
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("ProjectSpecVersionSource")
struct ProjectSpecVersionSourceTests {

    /// Helper: creates a temporary project.yml with the given content, returns the
    /// file path. The file is deleted when the closure completes.
    private func withTempSpec(
        content: String,
        fileName: String = "project.yml",
        body: (String) throws -> Void
    ) throws {
        let dir = NSTemporaryDirectory() + "ShipItTests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/" + fileName
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: dir)
        }
        try body(path)
    }

    /// Helper: makes a context configured for project_spec versioning with the given spec path.
    private func makeContext(
        specPath: String,
        buildKey: String = "CURRENT_PROJECT_VERSION",
        marketingKey: String = "MARKETING_VERSION"
    ) -> ActionContext {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "MockApp",
            versioningSource: "project_spec",
            versioningSpecPath: specPath,
            versioningBuildKey: buildKey,
            versioningMarketingKey: marketingKey
        )
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
        return ActionContext(
            shell: ShellContext(executor: executor),
            logger: .forType(subsystem: "ShipItSwiftyTests", ProjectSpecVersionSource.self),
            config: config,
            appStoreConnect: ascClient
        )
    }

    // MARK: - Read tests

    @Test("readVersion extracts quoted marketing version from YAML")
    func readVersionQuoted() throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: "1.2.3"
              CURRENT_PROJECT_VERSION: "42"
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            let version = try source.readVersion()
            #expect(version == "1.2.3")
        }
    }

    @Test("readVersion extracts unquoted marketing version from YAML")
    func readVersionUnquoted() throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: 2.0.0
              CURRENT_PROJECT_VERSION: 10
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            let version = try source.readVersion()
            #expect(version == "2.0.0")
        }
    }

    @Test("readBuildNumber extracts build number from YAML")
    func readBuildNumber() throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "99"
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            let build = try source.readBuildNumber()
            #expect(build == "99")
        }
    }

    @Test("readVersion works with custom key names")
    func readVersionCustomKeys() throws {
        let yaml = """
            name: MyApp
            settings:
              MY_VERSION: "3.5.1"
              MY_BUILD: "77"
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path, buildKey: "MY_BUILD", marketingKey: "MY_VERSION")
            let source = ProjectSpecVersionSource(context: context)
            let version = try source.readVersion()
            let build = try source.readBuildNumber()
            #expect(version == "3.5.1")
            #expect(build == "77")
        }
    }

    @Test("readVersion throws when key is missing from spec")
    func readVersionThrowsWhenKeyMissing() throws {
        let yaml = """
            name: MyApp
            settings:
              CURRENT_PROJECT_VERSION: "42"
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            #expect(throws: ShipItError.self) {
                _ = try source.readVersion()
            }
        }
    }

    @Test("readBuildNumber throws when build key is missing from spec")
    func readBuildNumberThrowsWhenKeyMissing() throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: "1.0.0"
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            #expect(throws: ShipItError.self) {
                _ = try source.readBuildNumber()
            }
        }
    }

    @Test("readVersion throws when spec file does not exist")
    func readVersionThrowsWhenFileNotFound() throws {
        let context = makeContext(specPath: "/nonexistent/path/project.yml")
        let source = ProjectSpecVersionSource(context: context)
        #expect(throws: ShipItError.self) {
            _ = try source.readVersion()
        }
    }

    // MARK: - Write tests

    @Test("writeVersion updates quoted value preserving formatting")
    func writeVersionQuoted() throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: "1.2.3"
              CURRENT_PROJECT_VERSION: "42"
            targets:
              MyApp:
                type: application
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            try source.writeVersion("2.0.0")

            // Read back and verify
            let updated = try String(contentsOfFile: path, encoding: .utf8)
            #expect(updated.contains("MARKETING_VERSION: \"2.0.0\""))
            // Build number should be untouched
            #expect(updated.contains("CURRENT_PROJECT_VERSION: \"42\""))
            // Other content preserved
            #expect(updated.contains("name: MyApp"))
            #expect(updated.contains("targets:"))
        }
    }

    @Test("writeVersion updates unquoted value without adding quotes")
    func writeVersionUnquoted() throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: 1.2.3
              CURRENT_PROJECT_VERSION: 42
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            try source.writeVersion("2.0.0")

            let updated = try String(contentsOfFile: path, encoding: .utf8)
            #expect(updated.contains("MARKETING_VERSION: 2.0.0"))
            // Should NOT have added quotes
            #expect(!updated.contains("MARKETING_VERSION: \"2.0.0\""))
        }
    }

    @Test("writeBuildNumber updates build number preserving indentation")
    func writeBuildNumber() throws {
        let yaml = """
            name: MyApp
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "5"
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            try source.writeBuildNumber("6")

            let updated = try String(contentsOfFile: path, encoding: .utf8)
            #expect(updated.contains("CURRENT_PROJECT_VERSION: \"6\""))
            // Marketing version untouched
            #expect(updated.contains("MARKETING_VERSION: \"1.0.0\""))
        }
    }

    @Test("writeVersion preserves indentation of deeply nested keys")
    func writeVersionPreservesDeepIndentation() throws {
        let yaml = """
            name: MyApp
            settings:
              base:
                MARKETING_VERSION: "1.0.0"
            """

        // Note: the current implementation matches any line with the key prefix,
        // so this tests that the original indentation is preserved in the replacement.
        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            try source.writeVersion("3.0.0")

            let updated = try String(contentsOfFile: path, encoding: .utf8)
            // Should preserve the 4-space indent
            #expect(updated.contains("    MARKETING_VERSION: \"3.0.0\""))
        }
    }

    @Test("writeVersion throws when key not found in spec")
    func writeVersionThrowsWhenKeyNotFound() throws {
        let yaml = """
            name: MyApp
            settings:
              CURRENT_PROJECT_VERSION: "42"
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)
            #expect(throws: ShipItError.self) {
                try source.writeVersion("2.0.0")
            }
        }
    }

    @Test("readVersion then writeVersion round-trips correctly")
    func roundTrip() throws {
        let yaml = """
            name: MyApp
            # Project settings
            settings:
              MARKETING_VERSION: "1.0.0"
              CURRENT_PROJECT_VERSION: "1"
            """

        try withTempSpec(content: yaml) { path in
            let context = makeContext(specPath: path)
            let source = ProjectSpecVersionSource(context: context)

            let original = try source.readVersion()
            #expect(original == "1.0.0")

            try source.writeVersion("1.1.0")
            try source.writeBuildNumber("2")

            let newVersion = try source.readVersion()
            let newBuild = try source.readBuildNumber()
            #expect(newVersion == "1.1.0")
            #expect(newBuild == "2")

            // Verify comment is preserved
            let updated = try String(contentsOfFile: path, encoding: .utf8)
            #expect(updated.contains("# Project settings"))
        }
    }

    // MARK: - Spec path fallback

    @Test("uses projectGenerationSpecPath when versioningSpecPath is nil")
    func fallsBackToProjectGenerationSpecPath() throws {
        let yaml = """
            settings:
              MARKETING_VERSION: "4.0.0"
              CURRENT_PROJECT_VERSION: "1"
            """

        try withTempSpec(content: yaml) { path in
            let executor = MockExecutor { _, _ in
                ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            let config = ResolvedConfig(
                appScheme: "MockApp",
                versioningSource: "project_spec",
                versioningSpecPath: nil,
                projectGenerationSpecPath: path
            )
            let dummyKeyData = Data(
                "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                    .utf8)
            let ascClient = AppStoreConnectClient(keyID: "K", issuerID: "I", privateKeyData: dummyKeyData)
            let context = ActionContext(
                shell: ShellContext(executor: executor),
                logger: .forType(subsystem: "ShipItSwiftyTests", ProjectSpecVersionSource.self),
                config: config,
                appStoreConnect: ascClient
            )

            let source = ProjectSpecVersionSource(context: context)
            let version = try source.readVersion()
            #expect(version == "4.0.0")
        }
    }
}
#endif
