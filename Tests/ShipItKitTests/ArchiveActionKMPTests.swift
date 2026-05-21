import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

#if os(macOS)
@Suite("ArchiveAction — KMP")
struct ArchiveActionKMPTests {

    @Test("KMP iOS archive links archive target before xcodebuild archive")
    func kmpIOSArchiveLinksArchiveTarget() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Archive Succeeded\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "iosApp",
            platform: .ios,
            iosBuildSystem: .kmp,
            kmpSharedModule: "sharedCore",
            kmpArchiveTarget: "IosArm64"
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try await ArchiveAction().run(
            with: ArchiveAction.Options(scheme: "iosApp", configuration: "Release"),
            context: context
        )

        let captured = commands()
        let gradleIndex = try #require(captured.firstIndex { $0.contains(":sharedCore:linkReleaseFrameworkIosArm64") })
        let archiveIndex = try #require(captured.firstIndex { $0.contains("xcodebuild") && $0.contains("archive") })
        #expect(gradleIndex < archiveIndex)
    }

    @Test("KMP Android archive uses module-qualified bundle task")
    func kmpAndroidArchiveUsesModuleQualifiedTask() async throws {
        // Create the expected AAB file so post-archive verification passes
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-kmp-\(UUID().uuidString)", isDirectory: true)
        let aabDir = tmpDir.appendingPathComponent("androidApp/build/outputs/bundle/release", isDirectory: true)
        try FileManager.default.createDirectory(at: aabDir, withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: aabDir.appendingPathComponent("androidApp-release.aab"))
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(platform: .android, androidBuildSystem: .kmp)
        let shell = ShellContext(executor: executor, workingDirectory: tmpDir.path)
        let context = makeTestActionContext(shell: shell, config: config, platform: .android)

        _ = try await ArchiveAction().run(
            with: ArchiveAction.Options(module: "androidApp", buildVariant: "release"),
            context: context
        )

        #expect(commands().contains { $0.contains(":androidApp:bundleRelease") })
    }
}
#endif
