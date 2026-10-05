#if os(macOS)
import Foundation
import ShipItKit
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

            // One Kotlin/Native simulator task: its tests ran on an iOS simulator, through Gradle, in a KMP build.
            let report = try testReport(in: result)
            #expect(report.runner == .gradle)
            #expect(report.buildSystem == .kmp)
            #expect(report.destinations.map(\.platform) == [.ios])
            #expect(report.destinations.first?.kind == .simulator)
            #expect(report.destinations.first?.scope == "iosSimulatorArm64Test")
            #expect(report.summary.passed == 4)
            let cases = try #require(report.testCases)
            #expect(cases.count == 4)
            #expect(cases.allSatisfy { $0.destinationID == report.destinations.first?.id })
            #expect(
                cases.allSatisfy { if case .unsupported = $0.rerunSelector { true } else { false } },
                "Gradle's --tests filter cannot select Kotlin/Native tests, so a rerun must not be attempted")
            #expect(
                !cases.contains { $0.stableID.contains(tmpFixture.lastPathComponent) },
                "test IDs must not embed this machine's paths")
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

            // Android unit tests run on the host JVM but belong to Android, and are filterable by Gradle.
            let report = try testReport(in: result)
            #expect(report.runner == .gradle)
            #expect(report.buildSystem == .kmp)
            #expect(report.destinations.map(\.platform) == [.android])
            #expect(report.destinations.first?.kind == .host)
            #expect(report.destinations.first?.scope == "testReleaseUnitTest", "the variant the Shipfile builds")
            #expect(report.summary.passed == 6)
            #expect(report.testCases?.allSatisfy { if case .gradleTestFilter = $0.rerunSelector { true } else { false } } == true)
        }
    }

    /// The typed report from a `shipit test --output json` run.
    private func testReport(in result: CLIResult) throws -> TestRunReport {
        let object = try #require(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        let payload = try #require(object["payload"] as? [String: Any])
        let report = try #require(payload["report"], "no report in: \(result.stdout.prefix(400))")
        return try JSONDecoder().decode(TestRunReport.self, from: JSONSerialization.data(withJSONObject: report))
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
