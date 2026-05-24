import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("TestAction — KMP")
struct TestActionKMPTests {

    #if os(macOS)
    @Test("KMP iOS tests dispatch to gradlew iosSimulatorArm64Test against the shared module")
    func kmpIOSTestsUseGradle() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "List of devices attached\nemulator-5554\tdevice\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .kmp
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .ios)

        let result = try await TestAction().run(
            with: TestAction.Options(),
            context: context
        )

        let captured = commands()
        let hasIosTest = captured.contains(where: { $0.contains(":shared:iosSimulatorArm64Test") })
        #expect(hasIosTest, "expected gradle iosSimulatorArm64Test invocation for KMP iOS tests")
        // Exit code 0 path with empty stdout produces a zero-failure result.
        #expect(result.failCount == 0)
        #expect(result.succeeded)
    }
    #endif

    @Test("KMP Android tests dispatch through the native gradle test path")
    func kmpAndroidUsesNativePath() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(
                stdout: "12 tests completed, 0 failed, 0 skipped\n",
                stderr: "",
                exitCode: 0
            )
        }

        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .kmp
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        _ = try await TestAction().run(
            with: TestAction.Options(module: "androidApp", buildVariant: "debug"),
            context: context
        )

        let captured = commands()
        let hasUnitTest = captured.contains(where: { $0.contains(":androidApp:testDebugUnitTest") })
        #expect(hasUnitTest, "KMP Android target should reuse the native unit-test path")
    }

    @Test("Android JVM tests default to the configured build variant")
    func androidTestsUseConfiguredBuildVariant() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(
                stdout: "12 tests completed, 0 failed, 0 skipped\n",
                stderr: "",
                exitCode: 0
            )
        }

        let config = ResolvedConfig(
            platform: .android,
            androidBuildVariant: "release"
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        _ = try await TestAction().run(
            with: TestAction.Options(module: "androidApp"),
            context: context
        )

        #expect(commands().contains { $0.contains(":androidApp:testReleaseUnitTest") })
    }

    @Test("Android instrumented tests default to the configured build variant")
    func androidInstrumentedTestsUseConfiguredBuildVariant() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "List of devices attached\nemulator-5554\tdevice\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            platform: .android,
            androidBuildVariant: "release"
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        _ = try await TestAction().run(
            with: TestAction.Options(
                kind: .instrumented,
                scope: .module,
                module: "androidApp",
                devices: TestDeviceConfig(strategy: .connected)
            ),
            context: context
        )

        #expect(commands().contains { $0.contains(":androidApp:connectedAndroidTest") })
    }

    #if os(macOS)
    @Test("KMP iOS tests use configured module and test task")
    func kmpIOSTestsUseConfiguredTask() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .kmp,
            kmpSharedModule: "coreShared",
            kmpTestTask: "iosX64Test"
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try await TestAction().run(with: TestAction.Options(), context: context)

        #expect(commands().contains { $0.contains(":coreShared:iosX64Test") })
    }
    #endif

    @Test("Custom task option overrides variant-based task selection")
    func customTaskOverridesVariantSelection() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(
                stdout: "5 tests completed, 0 failed, 0 skipped\n",
                stderr: "",
                exitCode: 0
            )
        }

        let config = ResolvedConfig(
            platform: .android,
            androidBuildVariant: "release"
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        _ = try await TestAction().run(
            with: TestAction.Options(module: "app", task: "testProdDebugUnitTest"),
            context: context
        )

        #expect(commands().contains { $0.contains(":app:testProdDebugUnitTest") })
    }

    @Test("Custom task with empty module runs root-level aggregate task")
    func customTaskWithEmptyModuleRunsRootLevel() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(
                stdout: "42 tests completed, 0 failed, 0 skipped\n",
                stderr: "",
                exitCode: 0
            )
        }

        let config = ResolvedConfig(
            platform: .android,
            androidModule: "app",
            androidBuildVariant: "release"
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        _ = try await TestAction().run(
            with: TestAction.Options(module: "", task: "testDebugUnitTest"),
            context: context
        )

        let captured = commands()
        // Should NOT have a module prefix — just the bare task name
        #expect(captured.contains { $0.contains("testDebugUnitTest") && !$0.contains(":app:") })
    }

    @Test("Custom task with explicit root scope runs root-level aggregate task")
    func customTaskWithExplicitRootScopeRunsRootLevel() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(
                stdout: "42 tests completed, 0 failed, 0 skipped\n",
                stderr: "",
                exitCode: 0
            )
        }

        let config = ResolvedConfig(
            platform: .android,
            androidModule: "app",
            androidBuildVariant: "release"
        )
        let context = makeTestActionContext(
            executor: executor, config: config, platform: .android)

        _ = try await TestAction().run(
            with: TestAction.Options(
                scope: .root,
                module: "app",
                task: "connectedAndroidTest"
            ),
            context: context
        )

        let captured = commands()
        #expect(captured.contains { $0.contains("connectedAndroidTest") && !$0.contains(":app:") })
    }
}
