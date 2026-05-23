#if os(macOS)
import Foundation
import Testing

@Suite("KMP Fixture Integration", .serialized)
struct KMPFixtureIntegrationTests {

    private let fixtureDir = FixturePaths.kmpSample

    @Test("build compiles KMP iOS via gradlew link plus xcodebuild")
    func buildIOS() async throws {
        try assertKMPFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeKMPEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "kmp-fixture",
                directory: tmpFixture,
                contents: kmpFixtureShipfile
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "build",
                "--platform", "ios",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "KMP iOS build failed:\n\(result.output)")
        }
    }

    @Test("archive produces KMP iOS xcarchive and validates it")
    func archiveIOS() async throws {
        try assertKMPFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeKMPEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "kmp-fixture",
                directory: tmpFixture,
                contents: kmpFixtureShipfile
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let archivePath = tmpFixture.appendingPathComponent("build/iosApp.xcarchive")
            let archiveResult = try await CLI.run(
                "archive",
                "--platform", "ios",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(archiveResult.exitCode == 0, "KMP iOS archive failed:\n\(archiveResult.output)")
            #expect(FileManager.default.fileExists(atPath: archivePath.path), "Expected KMP archive at \(archivePath.path)")

            let validateArchiveResult = try await CLI.run(
                "validate", "archive",
                "--platform", "ios",
                "--archive-path", archivePath.path,
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(validateArchiveResult.exitCode == 0, "KMP archive validation failed:\n\(validateArchiveResult.output)")

            let exportDirectory = tmpFixture.appendingPathComponent("build/export")
            let exportResult = try await CLI.run(
                "export",
                "--platform", "ios",
                "--archive", archivePath.path,
                "--output-directory", exportDirectory.path,
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(exportResult.exitCode == 0, "KMP export failed:\n\(exportResult.output)")

            let ipaPath = exportDirectory.appendingPathComponent("HelloWorld.ipa")
            #expect(FileManager.default.fileExists(atPath: ipaPath.path), "Expected exported IPA at \(ipaPath.path)")

            let validateIPAResult = try await CLI.run(
                "validate", "archive",
                "--platform", "ios",
                "--ipa", ipaPath.path,
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(validateIPAResult.exitCode == 0, "KMP IPA validation failed:\n\(validateIPAResult.output)")
        }
    }

    @Test("test dispatches KMP iOS tests through gradlew")
    func testIOS() async throws {
        try assertKMPFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeKMPEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "kmp-fixture",
                directory: tmpFixture,
                contents: kmpFixtureShipfile
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "test",
                "--platform", "ios",
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "KMP iOS tests failed:\n\(result.output)")
        }
    }

    @Test("build produces KMP Android APK output")
    func buildAndroid() async throws {
        try assertKMPFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeKMPEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "kmp-fixture",
                directory: tmpFixture,
                contents: kmpFixtureShipfile
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "build",
                "--platform", "android",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "KMP Android build failed:\n\(result.output)")

            let apkPath = tmpFixture.appendingPathComponent("androidApp/build/outputs/apk/release/androidApp-release.apk")
            #expect(FileManager.default.fileExists(atPath: apkPath.path), "Expected KMP APK at \(apkPath.path)")
        }
    }

    @Test("archive produces KMP Android AAB output and validates it")
    func archiveAndroid() async throws {
        try assertKMPFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeKMPEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "kmp-fixture",
                directory: tmpFixture,
                contents: kmpFixtureShipfile
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "archive",
                "--platform", "android",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "KMP Android archive failed:\n\(result.output)")

            let aabPath = tmpFixture.appendingPathComponent("androidApp/build/outputs/bundle/release/androidApp-release.aab")
            #expect(FileManager.default.fileExists(atPath: aabPath.path), "Expected KMP AAB at \(aabPath.path)")

            let validateResult = try await CLI.run(
                "validate", "bundle",
                "--platform", "android",
                "--aab", aabPath.path,
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(validateResult.exitCode == 0, "KMP AAB validation failed:\n\(validateResult.output)")
        }
    }

    @Test("test dispatches KMP Android unit tests through gradlew")
    func testAndroid() async throws {
        try assertKMPFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeKMPEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "kmp-fixture",
                directory: tmpFixture,
                contents: kmpFixtureShipfile
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let result = try await CLI.run(
                "test",
                "--platform", "android",
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "KMP Android tests failed:\n\(result.output)")
        }
    }
}

private let kmpFixtureShipfile = """
    app:
      scheme: iosApp
      project: iosApp/iosApp.xcodeproj

    ios:
      build_system: kmp
      kmp_shared_module: shared
      kmp_build_target: IosSimulatorArm64
      kmp_archive_target: IosArm64
      kmp_test_task: iosSimulatorArm64Test

    android:
      build_system: kmp
      module: androidApp
    """
#endif
