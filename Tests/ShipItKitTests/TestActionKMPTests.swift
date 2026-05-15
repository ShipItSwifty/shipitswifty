import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("TestAction — KMP")
struct TestActionKMPTests {

    @Test("KMP iOS tests dispatch to gradlew iosSimulatorArm64Test against the shared module")
    func kmpIOSTestsUseGradle() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
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
        let hasIosTest = captured.contains(where: { $0.contains("iosSimulatorArm64Test") })
        #expect(hasIosTest, "expected gradle iosSimulatorArm64Test invocation for KMP iOS tests")
        // Exit code 0 path with empty stdout produces a zero-failure result.
        #expect(result.failCount == 0)
        #expect(result.succeeded)
    }

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
        let hasUnitTest = captured.contains(where: { $0.contains("testDebugUnitTest") })
        #expect(hasUnitTest, "KMP Android target should reuse the native unit-test path")
    }
}
