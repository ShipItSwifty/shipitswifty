import Foundation
import SwiftyShell
import TestCommons
import Testing

@testable import ShipItKit

@Suite("TestAction — KMP")
struct TestActionKMPTests {

    #if os(macOS)
    @Test("KMP iOS tests dispatch to gradlew iosSimulatorArm64Test against the shared module")
    func kmpIOSTestsUseGradle() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let (executor, commands) = makeCaptureExecutor { _, _ in
            try Self.writeKMPReport(in: scratch.url, module: "shared", task: "iosSimulatorArm64Test")
            return ShellOutput(stdout: "List of devices attached\nemulator-5554\tdevice\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .kmp,
            gradleProjectDir: scratch.url.path
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
        #expect(result.failCount == 0)
        #expect(result.passCount == 1)
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
            ShellOutput(
                stdout: "List of devices attached\nemulator-5554\tdevice\n> Task :androidApp:connectedAndroidTest NO-SOURCE\n",
                stderr: "", exitCode: 0)
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
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let (executor, commands) = makeCaptureExecutor { _, _ in
            try Self.writeKMPReport(in: scratch.url, module: "coreShared", task: "iosX64Test")
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .kmp,
            kmpSharedModule: "coreShared",
            kmpTestTask: "iosX64Test",
            gradleProjectDir: scratch.url.path
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

    #if os(macOS)
    /// Writes the JUnit XML a real Kotlin/Native test task leaves behind.
    static func writeKMPReport(in root: URL, module: String, task: String) throws {
        let directory = root.appendingPathComponent("\(module)/build/test-results/\(task)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        <testsuite name="SharedTests" tests="1" failures="0" errors="0" skipped="0"><testcase classname="SharedTests" name="greets"/></testsuite>
        """.write(to: directory.appendingPathComponent("TEST-SharedTests.xml"), atomically: true, encoding: .utf8)
    }

    @Test("A KMP task that exits 0 but reports nothing is an execution failure with an error report")
    func kmpSilentSuccessFails() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let (executor, _) = makeCaptureExecutor { _, _ in ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0) }
        let reportPath = scratch.url.appendingPathComponent("report.json").path
        let context = makeTestActionContext(
            executor: executor, config: ResolvedConfig(platform: .ios, iosBuildSystem: .kmp, gradleProjectDir: scratch.url.path),
            platform: .ios)
        await #expect(throws: ShipItError.self) {
            _ = try await TestAction().run(with: .init(reportPath: reportPath), context: context)
        }
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
        #expect(report.summary.errored == 1)
    }

    @Test("Gradle NO-SOURCE is a legitimate empty KMP run")
    func kmpNoSourceIsNotAFailure() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let (executor, _) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "> Task :shared:iosSimulatorArm64Test NO-SOURCE\n", stderr: "", exitCode: 0)
        }
        let context = makeTestActionContext(
            executor: executor, config: ResolvedConfig(platform: .ios, iosBuildSystem: .kmp, gradleProjectDir: scratch.url.path),
            platform: .ios)
        let result = try await TestAction().run(with: .init(), context: context)
        #expect(result.passCount == 0)
        #expect(result.succeeded)
    }
    #endif
}
