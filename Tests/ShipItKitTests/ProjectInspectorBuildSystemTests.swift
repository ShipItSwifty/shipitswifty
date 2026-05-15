import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("ProjectInspector — BuildSystem detection")
struct ProjectInspectorBuildSystemTests {

    @Test("Detects KMP via build.gradle.kts using kotlin(\"multiplatform\")")
    func detectsKMP() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        plugins {
            kotlin("multiplatform") version "1.9.0"
        }
        """.write(
            to: dir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let inspection = try await ProjectInspector(
            rootPath: dir.path,
            shell: ShellContext(executor: executor)
        ).inspect()

        #expect(inspection.detectedBuildSystem == .kmp)
        #expect(inspection.buildSystemFiles.contains("build.gradle.kts"))
    }

    @Test("Detects Flutter via pubspec.yaml with a flutter: key")
    func detectsFlutter() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        name: demo
        flutter:
          uses-material-design: true
        """.write(
            to: dir.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let inspection = try await ProjectInspector(
            rootPath: dir.path,
            shell: ShellContext(executor: executor)
        ).inspect()

        #expect(inspection.detectedBuildSystem == .flutter)
        #expect(inspection.buildSystemFiles.contains("pubspec.yaml"))
    }

    @Test("Detects React Native via package.json")
    func detectsReactNative() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        {
          "name": "demo",
          "dependencies": {
            "react-native": "0.74.0"
          }
        }
        """.write(
            to: dir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let inspection = try await ProjectInspector(
            rootPath: dir.path,
            shell: ShellContext(executor: executor)
        ).inspect()

        #expect(inspection.detectedBuildSystem == .reactNative)
        #expect(inspection.buildSystemFiles.contains("package.json"))
    }

    @Test("Returns nil for a vanilla native project")
    func nativeProjectHasNilBuildSystem() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let inspection = try await ProjectInspector(
            rootPath: dir.path,
            shell: ShellContext(executor: executor)
        ).inspect()

        #expect(inspection.detectedBuildSystem == nil)
        #expect(inspection.buildSystemFiles.isEmpty)
    }
}
