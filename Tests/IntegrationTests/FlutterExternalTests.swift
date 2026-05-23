import Foundation
import Testing

@Suite("Flutter External Integration", .serialized, .requiresExternalFlutterProject, .requiresFlutterToolchain)
struct FlutterExternalIntegrationTests {

    @Test("flutter validate yml passes for external shipfile")
    func validateShipfile() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.flutterProject,
            envKey: "SHIPIT_EXTERNAL_FLUTTER_PROJECT"
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-flutter",
            directory: project,
            contents: shipfileForExternalFlutterProject(at: project)
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

    @Test("flutter test succeeds for external project")
    func flutterTestsPass() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.flutterProject,
            envKey: "SHIPIT_EXTERNAL_FLUTTER_PROJECT"
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-flutter",
            directory: project,
            contents: shipfileForExternalFlutterProject(at: project)
        )
        defer { try? FileManager.default.removeItem(at: shipfile) }

        let result = try await CLI.run(
            "test",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 600
        )
        #expect(result.exitCode == 0, "flutter test failed:\n\(result.output)")
    }

    @Test("flutter analyze succeeds for external project")
    func flutterLintPasses() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.flutterProject,
            envKey: "SHIPIT_EXTERNAL_FLUTTER_PROJECT"
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-flutter",
            directory: project,
            contents: shipfileForExternalFlutterProject(at: project)
        )
        defer { try? FileManager.default.removeItem(at: shipfile) }

        let result = try await CLI.run(
            "lint",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 600
        )
        #expect(result.exitCode == 0, "flutter analyze failed:\n\(result.output)")
    }

    @Test("flutter Android archive produces AAB on external project", .requiresAndroid)
    func flutterAndroidArchiveProducesAAB() async throws {
        let project = try assertExternalProjectExists(
            ExternalProjectPaths.flutterProject,
            envKey: "SHIPIT_EXTERNAL_FLUTTER_PROJECT"
        )
        let shipfile = try makeTempShipfile(
            prefix: "external-flutter",
            directory: project,
            contents: shipfileForExternalFlutterProject(at: project)
        )
        defer { try? FileManager.default.removeItem(at: shipfile) }

        let result = try await CLI.run(
            "archive",
            "--platform", "android",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 1800
        )
        #expect(result.exitCode == 0, "flutter Android archive failed:\n\(result.output)")

        let aabPath = project.appendingPathComponent("build/app/outputs/bundle/release/app-release.aab")
        #expect(FileManager.default.fileExists(atPath: aabPath.path), "Expected Flutter AAB at \(aabPath.path)")

        let validateResult = try await CLI.run(
            "validate", "bundle",
            "--platform", "android",
            "--aab", aabPath.path,
            "--output", "json",
            "--shipfile", shipfile.path,
            workingDirectory: project,
            timeout: 600
        )
        #expect(validateResult.exitCode == 0, "flutter Android AAB validation failed:\n\(validateResult.output)")
    }
}
