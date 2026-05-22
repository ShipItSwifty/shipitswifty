import Foundation
import Testing

@Suite("React Native External Integration", .serialized, .requiresExternalReactNativeProject)
struct ReactNativeExternalIntegrationTests {

    @Test("react native validate yml passes for external shipfile")
    func validateShipfile() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.reactNativeProject,
            envKey: "SHIPIT_EXTERNAL_RN_PROJECT"
        )
        try #require(
            externalProjectHasNodeModules(project),
            "External React Native project must have dependencies installed before validation. Run the project's package-manager install first."
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-rn",
            directory: project,
            contents: shipfileForExternalReactNativeProject(at: project)
        )
        defer { try? FileManager.default.removeItem(at: shipfile) }

        let result = try await CLI.run(
            "validate", "yml",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 180
        )
        #expect(result.exitCode == 0, "output: \(result.output)")
    }

    @Test("react native test succeeds for external project")
    func reactNativeTestsPass() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.reactNativeProject,
            envKey: "SHIPIT_EXTERNAL_RN_PROJECT"
        )
        try #require(
            externalProjectHasNodeModules(project),
            "External React Native project must have dependencies installed before validation. Run the project's package-manager install first."
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-rn",
            directory: project,
            contents: shipfileForExternalReactNativeProject(at: project)
        )
        defer { try? FileManager.default.removeItem(at: shipfile) }

        let result = try await CLI.run(
            "test",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 1200
        )
        #expect(result.exitCode == 0, "react native test failed:\n\(result.output)")
    }

    @Test("react native lint succeeds for external project")
    func reactNativeLintPasses() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.reactNativeProject,
            envKey: "SHIPIT_EXTERNAL_RN_PROJECT"
        )
        try #require(
            externalProjectHasNodeModules(project),
            "External React Native project must have dependencies installed before validation. Run the project's package-manager install first."
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-rn",
            directory: project,
            contents: shipfileForExternalReactNativeProject(at: project)
        )
        defer { try? FileManager.default.removeItem(at: shipfile) }

        let result = try await CLI.run(
            "lint",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 1200
        )
        #expect(result.exitCode == 0, "react native lint failed:\n\(result.output)")
    }

    @Test("react native Android archive produces AAB on external project", .requiresAndroid)
    func reactNativeAndroidArchiveProducesAAB() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.reactNativeProject,
            envKey: "SHIPIT_EXTERNAL_RN_PROJECT"
        )
        try #require(
            externalProjectHasNodeModules(project),
            "External React Native project must have dependencies installed before validation. Run the project's package-manager install first."
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-rn",
            directory: project,
            contents: shipfileForExternalReactNativeProject(at: project)
        )
        defer { try? FileManager.default.removeItem(at: shipfile) }

        let result = try await CLI.run(
            "archive",
            "--platform", "android",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 1800
        )
        #expect(result.exitCode == 0, "react native Android archive failed:\n\(result.output)")

        let aabDir = project.appendingPathComponent("android/app/build/outputs/bundle")
        #expect(FileManager.default.fileExists(atPath: aabDir.path), "Expected React Native AAB output under \(aabDir.path)")
    }

    @Test("react native iOS build succeeds for external project", .requiresCocoaPods)
    func reactNativeIOSBuildPasses() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.reactNativeProject,
            envKey: "SHIPIT_EXTERNAL_RN_PROJECT"
        )
        try #require(
            externalProjectHasNodeModules(project),
            "External React Native project must have dependencies installed before validation. Run the project's package-manager install first."
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-rn",
            directory: project,
            contents: shipfileForExternalReactNativeProject(at: project)
        )
        defer { try? FileManager.default.removeItem(at: shipfile) }

        let result = try await CLI.run(
            "build",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 1800
        )
        #expect(result.exitCode == 0, "react native iOS build failed:\n\(result.output)")
    }
}
