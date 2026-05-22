import Foundation
import Testing

@Suite("React Native Fixture Integration", .serialized)
struct ReactNativeFixtureIntegrationTests {

    private let fixtureDir = FixturePaths.reactNativeSample

    @Test("test and lint run from React Native project root")
    func testAndLint() async throws {
        try assertReactNativeFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeReactNativeEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "rn-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalReactNativeProject(at: tmpFixture)
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
            #expect(testResult.exitCode == 0, "React Native tests failed:\n\(testResult.output)")
            #expect(testResult.stdout.contains("\"passCount\":5") || testResult.stdout.contains("\"passCount\" : 5"))

            let lintResult = try await CLI.run(
                "lint",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(lintResult.exitCode == 0, "React Native lint failed:\n\(lintResult.output)")
        }
    }

    @Test("build compiles React Native iOS via npx react-native build-ios")
    func buildIOS() async throws {
        try assertReactNativeFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeReactNativeEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "rn-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalReactNativeProject(at: tmpFixture)
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }
            let result = try await CLI.run(
                "build",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "React Native iOS build failed:\n\(result.output)")
        }
    }

    @Test("archive uses xcodebuild for React Native iOS")
    func archiveIOS() async throws {
        try assertReactNativeFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeReactNativeEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "rn-ios",
                directory: tmpFixture,
                contents: reactNativeIOSArchiveShipfile
            )
            defer { try? FileManager.default.removeItem(at: shipfile) }

            let archivePath = tmpFixture.appendingPathComponent("build/HelloWorld.xcarchive")
            let result = try await CLI.run(
                "archive",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(result.exitCode == 0, "React Native iOS archive failed:\n\(result.output)")
            #expect(FileManager.default.fileExists(atPath: archivePath.path), "Expected React Native archive at \(archivePath.path)")

            let validateArchiveResult = try await CLI.run(
                "validate", "archive",
                "--archive-path", archivePath.path,
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(validateArchiveResult.exitCode == 0, "React Native archive validation failed:\n\(validateArchiveResult.output)")

            let exportDirectory = tmpFixture.appendingPathComponent("build/export")
            let exportResult = try await CLI.run(
                "export",
                "--archive", archivePath.path,
                "--output-directory", exportDirectory.path,
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(exportResult.exitCode == 0, "React Native export failed:\n\(exportResult.output)")

            let ipaPath = exportDirectory.appendingPathComponent("HelloWorld.ipa")
            #expect(FileManager.default.fileExists(atPath: ipaPath.path), "Expected exported IPA at \(ipaPath.path)")

            let validateIPAResult = try await CLI.run(
                "validate", "archive",
                "--ipa", ipaPath.path,
                "--output", "json",
                "--shipfile", shipfile.path,
                workingDirectory: tmpFixture,
                environment: environment,
                timeout: 300
            )
            #expect(validateIPAResult.exitCode == 0, "React Native IPA validation failed:\n\(validateIPAResult.output)")
        }
    }

    @Test("build produces React Native Android APK output")
    func buildAndroid() async throws {
        try assertReactNativeFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeReactNativeEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "rn-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalReactNativeProject(at: tmpFixture)
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
            #expect(result.exitCode == 0, "React Native Android build failed:\n\(result.output)")

            let apkPath = tmpFixture.appendingPathComponent("android/app/build/outputs/apk/release/app-release.apk")
            #expect(FileManager.default.fileExists(atPath: apkPath.path), "Expected React Native APK at \(apkPath.path)")
        }
    }

    @Test("archive produces React Native Android AAB output")
    func archiveAndroid() async throws {
        try assertReactNativeFixtureExists()
        try await withFixtureCopy(of: fixtureDir) { tmpFixture in
            let environment = try makeFakeReactNativeEnvironment(in: tmpFixture)
            let shipfile = try makeTempShipfile(
                prefix: "rn-fixture",
                directory: tmpFixture,
                contents: shipfileForExternalReactNativeProject(at: tmpFixture)
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
            #expect(result.exitCode == 0, "React Native Android archive failed:\n\(result.output)")

            let aabPath = tmpFixture.appendingPathComponent("android/app/build/outputs/bundle/release/app-release.aab")
            #expect(FileManager.default.fileExists(atPath: aabPath.path), "Expected React Native AAB at \(aabPath.path)")

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
            #expect(validateResult.exitCode == 0, "React Native AAB validation failed:\n\(validateResult.output)")
        }
    }
}

private let reactNativeIOSArchiveShipfile = """
app:
  project: ios/HelloWorld.xcodeproj
  scheme: HelloWorld

ios:
  build_system: react_native
"""
