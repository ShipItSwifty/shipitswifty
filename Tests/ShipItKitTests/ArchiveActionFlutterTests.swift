import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("ArchiveAction — Flutter and React Native")
struct ArchiveActionFlutterTests {

    @Test("Flutter Android archive runs flutter build appbundle and returns AAB path")
    func flutterAndroidArchive() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "✓ Built build/app/outputs/bundle/release/app-release.aab\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        let result = try await ArchiveAction().run(with: ArchiveAction.Options(), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("flutter") && $0.contains("appbundle") })
        #expect(result.aabPath == "build/app/outputs/bundle/release/app-release.aab")
        #expect(result.archivePath == nil)
        #expect(result.ipaPath == nil)
    }

    @Test("Flutter Android archive returns flavor-aware AAB path")
    func flutterAndroidArchiveUsesFlavorPath() async throws {
        let (executor, _) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "✓ Built app-free-release.aab\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        let result = try await ArchiveAction().run(
            with: ArchiveAction.Options(flavor: "free"),
            context: context
        )

        #expect(result.aabPath == "build/app/outputs/bundle/freeRelease/app-free-release.aab")
    }

    @Test("Flutter iOS archive runs flutter build ipa and returns IPA directory path")
    func flutterIOSArchive() async throws {
        #if os(macOS)
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "✓ Built build/ios/ipa/Runner.ipa\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "Runner",
            platform: .ios,
            iosBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        let result = try await ArchiveAction().run(with: ArchiveAction.Options(), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("flutter") && $0.contains("ipa") })
        #expect(result.ipaPath == "build/ios/ipa")
        #expect(result.archivePath == nil)
        #expect(result.aabPath == nil)
        #else
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let config = ResolvedConfig(platform: .ios, iosBuildSystem: .flutter)
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)
        await #expect {
            _ = try await ArchiveAction().run(with: ArchiveAction.Options(), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
        #endif
    }

    @Test("React Native Android archive runs npx react-native build-android and returns AAB path")
    func rnAndroidArchive() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .reactNative,
            androidBuildVariant: "release"
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        let result = try await ArchiveAction().run(with: ArchiveAction.Options(), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("npx") && $0.contains("react-native") && $0.contains("build-android") })
        #expect(captured.contains { $0.contains("--tasks bundleRelease") })
        #expect(result.aabPath == "android/app/build/outputs/bundle/release/app-release.aab")
    }

    #if os(macOS)
    @Test("React Native iOS archive uses xcodebuild archive")
    func rnIOSArchiveUsesXcodebuild() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "** ARCHIVE SUCCEEDED **\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "MyApp",
            platform: .ios,
            iosBuildSystem: .reactNative
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        let result = try await ArchiveAction().run(with: ArchiveAction.Options(scheme: "MyApp"), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("xcodebuild") && $0.contains("archive") })
        #expect(result.archivePath != nil)
        #expect(result.ipaPath == nil)
    }
    #endif
}
