import Foundation
import Testing

@Suite("Flutter Fixture Integration", .serialized)
struct FlutterFixtureIntegrationTests {

    private let fixtureDir = FixturePaths.flutterSample

    @Test("build compiles Flutter iOS via flutter build ios")
    func buildIOS() async throws {
        try assertFlutterFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeFlutterEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalFlutterProject(at: tmpFixture)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }
            let result = try await CLI.run(
                "build",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "Flutter iOS build failed:\n\(result.output)")
        }
    }

    @Test("archive produces Flutter iOS IPA output")
    func archiveIOS() async throws {
        try assertFlutterFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeFlutterEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalFlutterProject(at: tmpFixture)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }
            let result = try await CLI.run(
                "archive",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "Flutter iOS archive failed:\n\(result.output)")

            let ipaDirectory = tmpFixture.appendingPathComponent("build/ios/ipa")
            #expect(FileManager.default.fileExists(atPath: ipaDirectory.path), "Expected Flutter IPA output under \(ipaDirectory.path)")
        }
    }

    @Test("build produces Flutter Android APK output")
    func buildAndroid() async throws {
        try assertFlutterFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeFlutterEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalFlutterProject(at: tmpFixture)
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
            #expect(result.exitCode == 0, "Flutter Android build failed:\n\(result.output)")

            let apkPath = tmpFixture.appendingPathComponent("build/app/outputs/flutter-apk/app-release.apk")
            #expect(FileManager.default.fileExists(atPath: apkPath.path), "Expected Flutter APK at \(apkPath.path)")
        }
    }

    @Test("archive produces Flutter Android AAB output")
    func archiveAndroid() async throws {
        try assertFlutterFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeFlutterEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalFlutterProject(at: tmpFixture)
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
            #expect(result.exitCode == 0, "Flutter Android archive failed:\n\(result.output)")

            let aabPath = tmpFixture.appendingPathComponent("build/app/outputs/bundle/release/app-release.aab")
            #expect(FileManager.default.fileExists(atPath: aabPath.path), "Expected Flutter AAB at \(aabPath.path)")

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
            #expect(validateResult.exitCode == 0, "Flutter AAB validation failed:\n\(validateResult.output)")
        }
    }

    @Test("test and lint dispatch through Flutter CLI")
    func testAndLint() async throws {
        try assertFlutterFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeFlutterEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "flutter-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalFlutterProject(at: tmpFixture)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let testResult = try await CLI.run(
                "test",
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(testResult.exitCode == 0, "Flutter tests failed:\n\(testResult.output)")
            #expect(testResult.stdout.contains("\"passCount\":3") || testResult.stdout.contains("\"passCount\" : 3"))

            let lintResult = try await CLI.run(
                "lint",
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(lintResult.exitCode == 0, "Flutter lint failed:\n\(lintResult.output)")
            #expect(lintResult.stdout.contains("\"issueCount\":0") || lintResult.stdout.contains("\"issueCount\" : 0"))
        }
    }
}
