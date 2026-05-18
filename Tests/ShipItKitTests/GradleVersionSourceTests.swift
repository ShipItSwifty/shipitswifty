import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

#if os(macOS)
@Suite("GradleVersionSource via VersionBumper")
struct GradleVersionSourceTests {

    @Test("Reads versionName and versionCode from build.gradle.kts (Kotlin DSL)")
    func readsKotlinDSL() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appDir = dir.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let gradleFile = appDir.appendingPathComponent("build.gradle.kts")
        try """
        plugins {
            id("com.android.application")
        }

        android {
            defaultConfig {
                applicationId = "com.example.app"
                versionCode = 42
                versionName = "1.2.3"
            }
        }
        """.write(to: gradleFile, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "gradle",
            versioningSpecPath: gradleFile.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        let bumper = VersionBumper(context: context)
        let version = try await bumper.readVersion()
        let build = try await bumper.readBuildNumber()

        #expect(version == "1.2.3")
        #expect(build == "42")
    }

    @Test("Reads versionName and versionCode from build.gradle (Groovy DSL)")
    func readsGroovyDSL() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appDir = dir.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let gradleFile = appDir.appendingPathComponent("build.gradle")
        try """
        android {
            defaultConfig {
                applicationId "com.example.app"
                versionCode 10
                versionName "2.0.1"
            }
        }
        """.write(to: gradleFile, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "gradle",
            versioningSpecPath: gradleFile.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        let bumper = VersionBumper(context: context)
        let version = try await bumper.readVersion()
        let build = try await bumper.readBuildNumber()

        #expect(version == "2.0.1")
        #expect(build == "10")
    }

    @Test("Bumping the build number rewrites only versionCode")
    func bumpsBuildNumber() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appDir = dir.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let gradleFile = appDir.appendingPathComponent("build.gradle.kts")
        try """
        android {
            defaultConfig {
                applicationId = "com.example.app"
                versionCode = 7
                versionName = "2.0.0"
                testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
            }
        }
        """.write(to: gradleFile, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "gradle",
            versioningSpecPath: gradleFile.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        let result = try await VersionBumper(context: context)
            .bump(options: VersionAction.Options(bump: .build))

        #expect(result.buildNumber == "8")
        #expect(result.version == "2.0.0")

        let written = try String(contentsOf: gradleFile, encoding: .utf8)
        #expect(written.contains("versionCode = 8"))
        #expect(written.contains("versionName = \"2.0.0\""))
        #expect(written.contains("testInstrumentationRunner"))
    }

    @Test("Setting an explicit version writes both values")
    func setsExplicitVersion() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appDir = dir.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let gradleFile = appDir.appendingPathComponent("build.gradle.kts")
        try """
        android {
            defaultConfig {
                versionCode = 1
                versionName = "1.0.0"
            }
        }
        """.write(to: gradleFile, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "gradle",
            versioningSpecPath: gradleFile.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        _ = try await VersionBumper(context: context).bump(
            options: VersionAction.Options(
                bump: .set, version: "3.4.5", buildNumber: "99"
            ))

        let written = try String(contentsOf: gradleFile, encoding: .utf8)
        #expect(written.contains("versionCode = 99"))
        #expect(written.contains("versionName = \"3.4.5\""))
    }

    @Test("Missing versionName throws invalidConfiguration")
    func missingVersionNameThrows() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appDir = dir.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let gradleFile = appDir.appendingPathComponent("build.gradle.kts")
        try """
        android {
            defaultConfig {
                versionCode = 1
            }
        }
        """.write(to: gradleFile, atomically: true, encoding: .utf8)

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            versioningSource: "gradle",
            versioningSpecPath: gradleFile.path
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        await #expect {
            _ = try await VersionBumper(context: context).readVersion()
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }
}
#endif
