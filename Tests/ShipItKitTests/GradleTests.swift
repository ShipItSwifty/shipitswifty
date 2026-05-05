import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

// MARK: - Android BuildAction tests

@Suite("BuildAction (Android)")
struct AndroidBuildActionTests {

    @Test("BuildAction on Android runs gradlew assembleRelease")
    func androidBuild() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(platform: .android)
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)
        let options = BuildAction.Options()

        _ = try await BuildAction().run(with: options, context: context)

        let cmds = commands()
        #expect(cmds.count > 0)
        let buildCmd = cmds.first ?? ""
        #expect(buildCmd.lowercased().contains("gradlew") || buildCmd.lowercased().contains("gradle"))
        #expect(buildCmd.lowercased().contains("assemble"))
    }
}

// MARK: - Android ArchiveAction tests

@Suite("ArchiveAction (Android)")
struct AndroidArchiveActionTests {

    @Test("ArchiveAction on Android runs gradlew bundleRelease")
    func androidArchive() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(platform: .android)
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)
        let options = ArchiveAction.Options()

        _ = try await ArchiveAction().run(with: options, context: context)

        let cmds = commands()
        #expect(cmds.count > 0)
        let archiveCmd = cmds.first ?? ""
        #expect(archiveCmd.lowercased().contains("gradlew") || archiveCmd.lowercased().contains("gradle"))
        #expect(archiveCmd.lowercased().contains("bundle"))
    }
}

// MARK: - iOS-only platform guard tests

#if os(macOS)
@Suite("Platform guards")
struct PlatformGuardTests {

    @Test("ExportAction throws on Android platform")
    func exportAndroidGuard() async throws {
        let context = makeAndroidContext()
        await #expect {
            _ = try await ExportAction().run(with: .init(), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("iOS platform")
        }
    }

    @Test("TestFlightAction throws on Android platform")
    func testFlightAndroidGuard() async throws {
        let context = makeAndroidContext()
        await #expect {
            _ = try await TestFlightAction().run(with: .init(), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("iOS platform")
        }
    }

    @Test("UploadAction throws on Android platform")
    func uploadAndroidGuard() async throws {
        let context = makeAndroidContext()
        await #expect {
            _ = try await UploadAction().run(with: .init(), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("iOS platform")
        }
    }

    @Test("SignAction throws on Android platform")
    func signAndroidGuard() async throws {
        let context = makeAndroidContext()
        await #expect {
            _ = try await SignAction().run(with: .init(operation: .sync), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("iOS platform")
        }
    }

    @Test("DsymAction throws on Android platform")
    func dsymAndroidGuard() async throws {
        let context = makeAndroidContext()
        await #expect {
            _ = try await DsymAction().run(with: .init(operation: .download), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("iOS platform")
        }
    }

    // MARK: - Helpers

    private func makeAndroidContext() -> ActionContext {
        let base = ActionContext.mock(
            executor: MockExecutor { _, _ in
                ShellOutput(stdout: "", stderr: "", exitCode: 0)
            })
        return ActionContext(
            shell: base.shell,
            logger: base.logger,
            config: ResolvedConfig(platform: .android),
            appStoreConnect: base.appStoreConnect,
            platform: .android
        )
    }
}
#endif

// MARK: - ProjectInspector Android detection tests

@Suite("ProjectInspector (Android detection)")
struct ProjectInspectorAndroidTests {

    @Test("detectedPlatform is .android when gradlew is present")
    func detectsAndroid() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a gradlew file
        FileManager.default.createFile(atPath: dir.appendingPathComponent("gradlew").path, contents: nil)

        let inspector = ProjectInspector(rootPath: dir.path)
        let inspection = try await inspector.inspect()

        #expect(inspection.detectedPlatform == .android)
        #expect(inspection.gradleFiles.contains("gradlew"))
    }

    @Test("detectedPlatform is .ios when no gradle files are present")
    func detectsiOS() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // No gradle files — should default to .ios
        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("README.md").path,
            contents: nil
        )

        let inspector = ProjectInspector(rootPath: dir.path)
        let inspection = try await inspector.inspect()

        #expect(inspection.detectedPlatform == .ios)
        #expect(inspection.gradleFiles.isEmpty)
    }

    @Test("detectedPlatform defaults to .ios when no project files are present")
    func defaultsiOS() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let inspector = ProjectInspector(rootPath: dir.path)
        let inspection = try await inspector.inspect()

        #expect(inspection.detectedPlatform == .ios)
    }
}
