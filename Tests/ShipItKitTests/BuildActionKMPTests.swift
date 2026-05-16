import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

#if os(macOS)
@Suite("BuildAction — KMP")
struct BuildActionKMPTests {

    @Test("KMP iOS build links the shared framework via Gradle before xcodebuild")
    func kmpIOSLinksFrameworkBeforeXcodebuild() async throws {
        let (executor, commands) = makeCaptureExecutor { command, _ in
            // Both gradlew and xcodebuild succeed.
            return ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "iosApp",
            platform: .ios,
            iosBuildSystem: .kmp
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .ios)

        _ = try await BuildAction().run(
            with: BuildAction.Options(scheme: "iosApp", configuration: .release),
            context: context
        )

        let captured = commands()
        let gradleIndex = captured.firstIndex(where: {
            $0.contains("linkReleaseFramework") || $0.contains("gradle")
                || $0.contains("./gradlew")
        })
        let xcodeIndex = captured.firstIndex(where: { $0.contains("xcodebuild") })

        #expect(gradleIndex != nil, "expected a gradle link invocation before xcodebuild")
        #expect(xcodeIndex != nil, "expected an xcodebuild invocation")
        if let g = gradleIndex, let x = xcodeIndex {
            #expect(g < x, "gradle link must run before xcodebuild for the KMP iOS path")
        }
    }

    @Test("KMP iOS build links the Debug framework when options.configuration is .debug")
    func kmpIOSLinksDebugFrameworkForDebugBuild() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }

        // Resolved config defaults to Release; the action options override to Debug.
        // The pre-link must follow the option, not the resolved default.
        let config = ResolvedConfig(
            appScheme: "iosApp",
            buildConfiguration: "Release",
            platform: .ios,
            iosBuildSystem: .kmp
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .ios)

        _ = try await BuildAction().run(
            with: BuildAction.Options(scheme: "iosApp", configuration: .debug),
            context: context
        )

        let captured = commands()
        let hasDebugLink = captured.contains(where: {
            $0.contains("linkDebugFrameworkIosSimulatorArm64")
        })
        let hasReleaseLink = captured.contains(where: {
            $0.contains("linkReleaseFrameworkIosSimulatorArm64")
        })
        #expect(hasDebugLink, "expected linkDebug… task for a Debug build override")
        #expect(!hasReleaseLink, "must not run the Release link task when Debug was requested")
    }

    @Test("KMP iOS build uses configured shared module and target")
    func kmpIOSUsesConfiguredModuleAndTarget() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "iosApp",
            platform: .ios,
            iosBuildSystem: .kmp,
            kmpSharedModule: "coreShared",
            kmpBuildTarget: "IosX64"
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try await BuildAction().run(
            with: BuildAction.Options(scheme: "iosApp", configuration: .debug),
            context: context
        )

        let captured = commands()
        #expect(captured.contains { $0.contains(":coreShared:linkDebugFrameworkIosX64") })
    }

    @Test("KMP Android build uses the native gradle assemble path")
    func kmpAndroidUsesNativeGradlePath() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .kmp
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        _ = try await BuildAction().run(
            with: BuildAction.Options(module: "androidApp", buildVariant: "release"),
            context: context
        )

        let captured = commands()
        let hasAssemble = captured.contains(where: { $0.contains(":androidApp:assembleRelease") })
        #expect(hasAssemble, "expected module-qualified gradle assembleRelease for KMP Android target")
    }

    @Test("Flutter iOS build succeeds via flutter build ios")
    func flutterSucceeds() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "✓ Built build/ios/Runner.app\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "Runner",
            platform: .ios,
            iosBuildSystem: .flutter
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .ios)

        #if os(macOS)
        let result = try await BuildAction().run(
            with: BuildAction.Options(scheme: "Runner"),
            context: context
        )
        #expect(result.exitCode == 0)
        #else
        // Flutter iOS requires macOS — verify graceful error on Linux
        await #expect {
            _ = try await BuildAction().run(
                with: BuildAction.Options(scheme: "Runner"),
                context: context
            )
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
        #endif
    }

    @Test("React Native Android build succeeds via npx react-native build-android")
    func reactNativeSucceeds() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .reactNative
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        let result = try await BuildAction().run(
            with: BuildAction.Options(module: "app"),
            context: context
        )
        #expect(result.exitCode == 0)
    }
}
#endif
