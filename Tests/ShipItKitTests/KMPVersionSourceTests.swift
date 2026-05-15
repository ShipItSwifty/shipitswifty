import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

#if os(macOS)
@Suite("KMPVersionSource via VersionBumper")
struct KMPVersionSourceTests {

    @Test("Reads versionName and versionCode from gradle.properties")
    func readsVersionAndBuild() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let propertiesURL = dir.appendingPathComponent("gradle.properties")
        try """
            # Project properties
            kotlin.code.style=official
            versionName=1.2.3
            versionCode=42
            """.write(to: propertiesURL, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "kmp",
            versioningSpecPath: propertiesURL.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .ios)

        let bumper = VersionBumper(context: context)
        let version = try await bumper.readVersion()
        let build = try await bumper.readBuildNumber()

        #expect(version == "1.2.3")
        #expect(build == "42")
    }

    @Test("Bumping the build number rewrites only the versionCode line")
    func bumpsBuildNumber() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let propertiesURL = dir.appendingPathComponent("gradle.properties")
        try """
            # Comment that must be preserved
            org.gradle.jvmargs=-Xmx2g
            versionName=2.0.0
            versionCode=7
            kotlin.mpp.enableCInteropCommonization=true
            """.write(to: propertiesURL, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "kmp",
            versioningSpecPath: propertiesURL.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        let result = try await VersionBumper(context: context)
            .bump(options: VersionAction.Options(bump: .build))

        #expect(result.buildNumber == "8")
        #expect(result.version == "2.0.0")

        let written = try String(contentsOf: propertiesURL, encoding: .utf8)
        #expect(written.contains("versionCode=8"))
        #expect(written.contains("versionName=2.0.0"))
        #expect(written.contains("# Comment that must be preserved"))
        #expect(written.contains("org.gradle.jvmargs=-Xmx2g"))
        #expect(written.contains("kotlin.mpp.enableCInteropCommonization=true"))
    }

    @Test("Setting an explicit version writes both keys")
    func setsExplicitVersion() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let propertiesURL = dir.appendingPathComponent("gradle.properties")
        try """
            versionName=1.0.0
            versionCode=1
            """.write(to: propertiesURL, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "kmp",
            versioningSpecPath: propertiesURL.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .ios)

        _ = try await VersionBumper(context: context).bump(
            options: VersionAction.Options(
                bump: .set, version: "3.4.5", buildNumber: "99"
            ))

        let written = try String(contentsOf: propertiesURL, encoding: .utf8)
        #expect(written.contains("versionName=3.4.5"))
        #expect(written.contains("versionCode=99"))
    }

    @Test("Missing key throws an actionable invalidConfiguration error")
    func missingKeyThrows() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let propertiesURL = dir.appendingPathComponent("gradle.properties")
        try """
            # versionName intentionally omitted
            versionCode=1
            """.write(to: propertiesURL, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "kmp",
            versioningSpecPath: propertiesURL.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .ios)

        await #expect {
            _ = try await VersionBumper(context: context).readVersion()
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }
}
#endif
