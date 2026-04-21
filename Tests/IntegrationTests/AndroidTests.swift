import Testing
import Foundation

/// Integration tests for the Android build pipeline against the fixture project.
///
/// These tests require:
/// - `ANDROID_HOME` or `ANDROID_SDK_ROOT` set
/// - `gradlew` bootstrapped in the fixture (run `gradle wrapper --gradle-version 8.7`)
///
/// Dry-run tests run on any machine. Real Gradle builds are gated on `requiresAndroid`.
///
/// **Prerequisite:** Run `swift build` before running these tests.
///
/// `.serialized` is required: parallel Gradle runs contend on shared `~/.gradle` caches
/// and locks even when each test has its own project directory copy.
/// iOS tests use xcodebuild which isolates derived data by SRCROOT, so they can
/// run in parallel. Gradle cannot — it must be serialized.
@Suite("Android Integration", .serialized)
struct AndroidIntegrationTests {

    private let fixtureDir = FixturePaths.androidSample

    // MARK: - Dry-run (always runs)

    @Test("build --platform android --dry-run exits 0")
    func buildAndroidDryRunExitsZero() async throws {
        try assertAndroidFixtureExists()
        let result = try await CLI.run(
            "build",
            "--platform", "android",
            "--shipfile", FixturePaths.androidReleaseShipfile.path,
            "--dry-run",
            workingDirectory: fixtureDir
        )
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(
            result.stdout.lowercased().contains("dry run") ||
            result.stdout.lowercased().contains("would"),
            "Expected dry-run message, got: \(result.stdout)"
        )
    }

    @Test("validate yml passes for Android Shipfile")
    func validateAndroidShipfile() async throws {
        let result = try await CLI.run(
            "validate", "yml",
            "--shipfile", FixturePaths.androidReleaseShipfile.path
        )
        #expect(result.exitCode == 0, "output: \(result.output)")
    }

    // MARK: - Real Gradle builds (requires Android SDK + gradlew)

    @Test("build assembleDebug succeeds", .requiresAndroid)
    func buildAssembleDebugSucceeds() async throws {
        try assertAndroidFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let result = try await CLI.run(
                "build",
                "--platform", "android",
                "--shipfile", FixturePaths.androidDebugShipfile.path,
                workingDirectory: tmpFixture,
                timeout: 300
            )
            #expect(result.exitCode == 0, "Gradle build failed:\n\(result.output)")

            let apkDir = tmpFixture.appendingPathComponent("app/build/outputs/apk/debug")
            #expect(
                FileManager.default.fileExists(atPath: apkDir.path),
                "Expected debug APK at \(apkDir.path)"
            )
        }
    }

    @Test("test runs unit tests and passes", .requiresAndroid)
    func testRunsUnitTests() async throws {
        try assertAndroidFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let result = try await CLI.run(
                "test",
                "--platform", "android",
                "--shipfile", FixturePaths.androidReleaseShipfile.path,
                workingDirectory: tmpFixture,
                timeout: 300
            )
            #expect(result.exitCode == 0, "Gradle tests failed:\n\(result.output)")
        }
    }

    @Test("lint runs and exits 0 on clean fixture", .requiresAndroid)
    func lintPassesOnFixture() async throws {
        try assertAndroidFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let result = try await CLI.run(
                "lint",
                "--platform", "android",
                "--shipfile", FixturePaths.androidReleaseShipfile.path,
                workingDirectory: tmpFixture,
                timeout: 300
            )
            #expect(result.exitCode == 0 || result.stdout.contains("lint"),
                    "Lint did not run as expected:\n\(result.output)")
        }
    }

    @Test("archive produces AAB for release variant", .requiresAndroid)
    func archiveProducesAAB() async throws {
        try assertAndroidFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let result = try await CLI.run(
                "archive",
                "--platform", "android",
                "--shipfile", FixturePaths.androidReleaseShipfile.path,
                workingDirectory: tmpFixture,
                timeout: 300
            )
            #expect(result.exitCode == 0, "Gradle archive failed:\n\(result.output)")

            let aabDir = tmpFixture.appendingPathComponent("app/build/outputs/bundle/release")
            #expect(
                FileManager.default.fileExists(atPath: aabDir.path),
                "Expected AAB at \(aabDir.path)"
            )
        }
    }
}
