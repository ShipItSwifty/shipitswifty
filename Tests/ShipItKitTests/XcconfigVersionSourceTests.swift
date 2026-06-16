import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("XcconfigVersionSource via VersionBumper")
struct XcconfigVersionSourceTests {

    /// Builds a context configured to use the `xcconfig` source pointing at `path`,
    /// with the Lagos-style custom key names.
    private func makeContext(
        path: String,
        marketingKey: String = "JOT_MARKETING_VERSION",
        buildKey: String = "JOT_BUILD_NUMBER"
    ) -> ActionContext {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "xcconfig",
            versioningSpecPath: path,
            versioningBuildKey: buildKey,
            versioningMarketingKey: marketingKey
        )
        return makeTestActionContext(executor: executor, config: config, platform: .ios)
    }

    private func writeTempXcconfig(_ content: String) throws -> URL {
        let dir = try makeTempDirectory()
        let configDir = dir.appendingPathComponent("Config")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let file = configDir.appendingPathComponent("Version.xcconfig")
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test("Reads custom marketing version and build number keys")
    func readsCustomKeys() async throws {
        let file = try writeTempXcconfig(
            """
            JOT_MARKETING_VERSION = 1.0.0
            JOT_BUILD_NUMBER = 1
            """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let bumper = VersionBumper(context: makeContext(path: file.path))
        #expect(try await bumper.readVersion() == "1.0.0")
        #expect(try await bumper.readBuildNumber() == "1")
    }

    @Test("Bumping the build number rewrites only the build key")
    func bumpsBuildNumber() async throws {
        let file = try writeTempXcconfig(
            """
            // Single source of truth for app version.
            JOT_MARKETING_VERSION = 2.3.1
            JOT_BUILD_NUMBER = 7
            """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let result = try await VersionBumper(context: makeContext(path: file.path))
            .bump(options: VersionAction.Options(bump: .build))

        #expect(result.buildNumber == "8")
        #expect(result.version == "2.3.1")

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("JOT_BUILD_NUMBER = 8"))
        #expect(written.contains("JOT_MARKETING_VERSION = 2.3.1"))
        // Comment line preserved.
        #expect(written.contains("// Single source of truth for app version."))
    }

    @Test("Bumping the marketing version rewrites only the marketing key")
    func bumpsMarketingVersion() async throws {
        let file = try writeTempXcconfig(
            """
            JOT_MARKETING_VERSION = 1.4.9
            JOT_BUILD_NUMBER = 12
            """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let result = try await VersionBumper(context: makeContext(path: file.path))
            .bump(options: VersionAction.Options(bump: .minor))

        #expect(result.version == "1.5.0")
        #expect(result.buildNumber == "12")

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("JOT_MARKETING_VERSION = 1.5.0"))
        #expect(written.contains("JOT_BUILD_NUMBER = 12"))
    }

    @Test("Setting explicit values writes both keys")
    func setsExplicitValues() async throws {
        let file = try writeTempXcconfig(
            """
            JOT_MARKETING_VERSION = 1.0.0
            JOT_BUILD_NUMBER = 1
            """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        _ = try await VersionBumper(context: makeContext(path: file.path)).bump(
            options: VersionAction.Options(bump: .set, version: "9.8.7", buildNumber: "42"))

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("JOT_MARKETING_VERSION = 9.8.7"))
        #expect(written.contains("JOT_BUILD_NUMBER = 42"))
    }

    @Test("Indentation and inline comments are preserved/handled")
    func preservesIndentAndStripsComment() async throws {
        let file = try writeTempXcconfig(
            """
            #include "Shared.xcconfig"
                JOT_MARKETING_VERSION = 3.0.0 // marketing
                JOT_BUILD_NUMBER = 5
            """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let bumper = VersionBumper(context: makeContext(path: file.path))
        // Inline comment stripped on read.
        #expect(try await bumper.readVersion() == "3.0.0")

        _ = try await bumper.bump(options: VersionAction.Options(bump: .patch))
        let written = try String(contentsOf: file, encoding: .utf8)
        // Leading indentation preserved.
        #expect(written.contains("    JOT_MARKETING_VERSION = 3.0.1"))
        // #include directive untouched.
        #expect(written.contains("#include \"Shared.xcconfig\""))
    }

    @Test("A key sharing a prefix is not matched")
    func prefixCollisionGuard() async throws {
        let file = try writeTempXcconfig(
            """
            JOT_MARKETING_VERSION = 1.0.0
            JOT_BUILD_NUMBER_SUFFIX = beta
            JOT_BUILD_NUMBER = 3
            """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let bumper = VersionBumper(context: makeContext(path: file.path))
        #expect(try await bumper.readBuildNumber() == "3")

        _ = try await bumper.bump(options: VersionAction.Options(bump: .build))
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("JOT_BUILD_NUMBER = 4"))
        // Decoy key untouched.
        #expect(written.contains("JOT_BUILD_NUMBER_SUFFIX = beta"))
    }

    @Test("Missing key throws invalidConfiguration")
    func missingKeyThrows() async throws {
        let file = try writeTempXcconfig("JOT_BUILD_NUMBER = 1")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let bumper = VersionBumper(context: makeContext(path: file.path))
        await #expect {
            _ = try await bumper.readVersion()
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }

    @Test("Missing spec_path throws invalidConfiguration")
    func missingSpecPathThrows() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let config = ResolvedConfig(versioningSource: "xcconfig", versioningSpecPath: nil)
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        await #expect {
            _ = try await VersionBumper(context: context).readVersion()
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }
}
