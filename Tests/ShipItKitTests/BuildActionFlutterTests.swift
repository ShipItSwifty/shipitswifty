import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("BuildAction — Flutter")
struct BuildActionFlutterTests {

    @Test("Flutter iOS build runs flutter build ios (not ipa)")
    func flutterIOSBuildRunsFlutterBuildIOS() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "✓ Built build/ios/Runner.app\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "Runner",
            platform: .ios,
            iosBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        #if os(macOS)
        _ = try await BuildAction().run(with: BuildAction.Options(), context: context)
        let captured = commands()
        #expect(captured.contains { $0.contains("flutter") && $0.contains("build") && $0.contains("ios") })
        // BuildAction should NOT run `flutter build ipa` — that's ArchiveAction's job
        #expect(!captured.contains { $0.contains("ipa") })
        #else
        await #expect {
            _ = try await BuildAction().run(with: BuildAction.Options(), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
        #endif
    }

    @Test("Flutter Android build runs flutter build apk")
    func flutterAndroidBuildRunsAPK() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "✓ Built build/app/outputs/flutter-apk/app-release.apk\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        let result = try await BuildAction().run(with: BuildAction.Options(), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("flutter") && $0.contains("apk") })
        #expect(result.apkPath == "build/app/outputs/flutter-apk/app-release.apk")
    }

    @Test("Flutter build failure throws buildFailed")
    func flutterBuildFailureThrows() async throws {
        let executor = MockExecutor { _, _ in
            throw ShellError.exitFailure(command: "flutter", output: ShellOutput(stdout: "", stderr: "Error: pubspec.yaml not found", exitCode: 1))
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .flutter
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        await #expect {
            _ = try await BuildAction().run(with: BuildAction.Options(), context: context)
        } throws: { error in
            guard case ShipItError.buildFailed = error else { return false }
            return true
        }
    }

    @Test("React Native Android build runs npx react-native build-android")
    func rnAndroidBuildRunsRNCLI() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .reactNative
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        let result = try await BuildAction().run(
            with: BuildAction.Options(buildVariant: "release"),
            context: context
        )

        let captured = commands()
        #expect(captured.contains { $0.contains("npx") && $0.contains("react-native") && $0.contains("build-android") })
        #expect(result.apkPath == "android/app/build/outputs/apk/release/app-release.apk")
    }

    #if os(macOS)
    @Test("React Native iOS build runs npx react-native build-ios")
    func rnIOSBuildRunsRNCLI() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "MyApp",
            platform: .ios,
            iosBuildSystem: .reactNative
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try await BuildAction().run(with: BuildAction.Options(scheme: "MyApp"), context: context)

        let captured = commands()
        #expect(captured.contains { $0.contains("npx") && $0.contains("react-native") && $0.contains("build-ios") })
    }
    #endif
}
