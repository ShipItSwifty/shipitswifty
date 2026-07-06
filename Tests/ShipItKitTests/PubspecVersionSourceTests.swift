import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("PubspecVersionSource via VersionBumper")
struct PubspecVersionSourceTests {

    /// Builds a context configured to use the `pubspec` source pointing at `path`.
    private func makeContext(path: String, platform: Platform = .ios) -> ActionContext {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "pubspec",
            versioningSpecPath: path
        )
        return makeTestActionContext(executor: executor, config: config, platform: platform)
    }

    @Test("Reads marketing version and build number from version: X.Y.Z+B")
    func readsVersionAndBuild() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pubspecURL = dir.appendingPathComponent("pubspec.yaml")
        try """
        name: demo_app
        description: A Flutter demo.
        version: 1.2.3+45
        environment:
          sdk: ^3.5.0
        """.write(to: pubspecURL, atomically: true, encoding: .utf8)

        let bumper = VersionBumper(context: makeContext(path: pubspecURL.path))
        let version = try await bumper.readVersion()
        let build = try await bumper.readBuildNumber()

        #expect(version == "1.2.3")
        #expect(build == "45")
    }

    @Test("Build number reads as 0 when the +build suffix is absent")
    func missingBuildSuffixReadsAsZero() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pubspecURL = dir.appendingPathComponent("pubspec.yaml")
        try """
        name: demo_app
        version: 2.0.0
        """.write(to: pubspecURL, atomically: true, encoding: .utf8)

        let bumper = VersionBumper(context: makeContext(path: pubspecURL.path))
        #expect(try await bumper.readVersion() == "2.0.0")
        #expect(try await bumper.readBuildNumber() == "0")
    }

    @Test("Quoted version values parse and inline comments are preserved on write")
    func quotedValueAndInlineComment() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pubspecURL = dir.appendingPathComponent("pubspec.yaml")
        try """
        name: demo_app
        version: "1.0.0+7"  # bumped by CI
        """.write(to: pubspecURL, atomically: true, encoding: .utf8)

        let context = makeContext(path: pubspecURL.path)
        #expect(try await VersionBumper(context: context).readVersion() == "1.0.0")

        _ = try await VersionBumper(context: context)
            .bump(options: VersionAction.Options(bump: .build))

        let written = try String(contentsOf: pubspecURL, encoding: .utf8)
        #expect(written.contains("version: 1.0.0+8"))
        #expect(written.contains("# bumped by CI"))
    }

    @Test("Bumping the build number rewrites only the top-level version line")
    func bumpsBuildNumber() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pubspecURL = dir.appendingPathComponent("pubspec.yaml")
        try """
        name: demo_app
        # The version below drives both stores.
        version: 2.0.0+7

        dependencies:
          flutter:
            sdk: flutter
          some_hosted_package:
            hosted: https://example.dev
            version: ^9.9.9
        """.write(to: pubspecURL, atomically: true, encoding: .utf8)

        let result = try await VersionBumper(context: makeContext(path: pubspecURL.path))
            .bump(options: VersionAction.Options(bump: .build))

        #expect(result.buildNumber == "8")
        #expect(result.version == "2.0.0")

        let written = try String(contentsOf: pubspecURL, encoding: .utf8)
        #expect(written.contains("version: 2.0.0+8"))
        #expect(written.contains("# The version below drives both stores."))
        // The nested dependency `version:` key must be untouched.
        #expect(written.contains("version: ^9.9.9"))
    }

    @Test("Setting an explicit version and build writes a combined version: value")
    func setsExplicitVersion() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pubspecURL = dir.appendingPathComponent("pubspec.yaml")
        try """
        name: demo_app
        version: 1.0.0+1
        """.write(to: pubspecURL, atomically: true, encoding: .utf8)

        _ = try await VersionBumper(context: makeContext(path: pubspecURL.path)).bump(
            options: VersionAction.Options(
                bump: .set, version: "3.4.5", buildNumber: "99"
            ))

        let written = try String(contentsOf: pubspecURL, encoding: .utf8)
        #expect(written.contains("version: 3.4.5+99"))
    }

    @Test("Falls back to pubspec.yaml at the project root when spec_path is unset")
    func defaultsToPubspecAtRoot() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(versioningSource: "pubspec")
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        // No pubspec.yaml exists in the test working directory — the error message
        // should point at the default path so users know what to configure.
        await #expect {
            _ = try await VersionBumper(context: context).readVersion()
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("pubspec.yaml")
        }
    }

    @Test("Missing top-level version key throws an actionable invalidConfiguration error")
    func missingVersionKeyThrows() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pubspecURL = dir.appendingPathComponent("pubspec.yaml")
        try """
        name: demo_app
        dependencies:
          some_hosted_package:
            version: ^1.0.0
        """.write(to: pubspecURL, atomically: true, encoding: .utf8)

        await #expect {
            _ = try await VersionBumper(context: makeContext(path: pubspecURL.path)).readVersion()
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("version:")
        }
    }
}
