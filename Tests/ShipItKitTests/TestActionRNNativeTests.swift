import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("TestAction — React Native native test bypass")
struct TestActionRNNativeTests {

    // MARK: - iOS bypass

    #if os(macOS)
    @Test("RN iOS: explicit scheme bypasses Jest and dispatches to xcodebuild")
    func rnIOSWithSchemeDispatchesToXcodebuild() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNNativeIOSTest")

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "MyApp",
            platform: .ios,
            iosBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try? await TestAction().run(
            with: TestAction.Options(scheme: "MyApp"),
            context: context
        )

        let captured = commands()
        // xcodebuild must be invoked — not the JS package manager
        #expect(captured.contains { $0.contains("xcodebuild") })
        #expect(!captured.contains { $0.contains("npm") || $0.contains("yarn") })
    }

    @Test("RN iOS: explicit destinations bypasses Jest and dispatches to xcodebuild")
    func rnIOSWithDestinationsBypassesJest() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNNativeIOSDestTest")

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            appScheme: "MyApp",
            platform: .ios,
            iosBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try? await TestAction().run(
            with: TestAction.Options(destinations: ["platform=iOS Simulator,name=iPhone 15"]),
            context: context
        )

        let captured = commands()
        #expect(captured.contains { $0.contains("xcodebuild") })
    }

    @Test("RN iOS: no native options runs Jest")
    func rnIOSWithoutNativeOptionsRunsJest() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNJestFallback")
        let packageJSON = """
            {"name": "my-app", "scripts": {"test": "jest"}}
            """
        try packageJSON.write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("node_modules"),
            withIntermediateDirectories: false
        )

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .ios,
            iosBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try? await TestAction().run(with: TestAction.Options(), context: context)

        let captured = commands()
        let testCommands = captured.filter { $0.contains("run") && $0.contains("test") }
        #expect(testCommands.count == 1)
        #expect(testCommands[0].contains("--json"))
        #expect(testCommands[0].contains("--outputFile"))
        #expect(!captured.contains { $0.contains("xcodebuild") })
    }
    #endif

    // MARK: - Android bypass

    @Test("RN Android: explicit kind bypasses Jest and dispatches to Gradle")
    func rnAndroidWithKindDispatchesToGradle() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNNativeAndroidTest")
        // Create android/gradlew so reactNativeAndroidContext patches the dir
        let androidDir = tempDir.appendingPathComponent("android")
        try FileManager.default.createDirectory(at: androidDir, withIntermediateDirectories: true)
        let gradlewPath = androidDir.appendingPathComponent("gradlew")
        try "#!/bin/sh\nexec gradle \"$@\"\n".write(to: gradlewPath, atomically: true, encoding: .utf8)

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "1 test completed\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        _ = try? await TestAction().run(
            with: TestAction.Options(kind: .unit),
            context: context
        )

        let captured = commands()
        // Gradle (gradlew) must be invoked — not the JS package manager
        #expect(captured.contains { $0.contains("gradlew") || $0.contains("gradle") })
        #expect(!captured.contains { $0.contains("npm") || $0.contains("yarn") })
    }

    @Test("RN Android: no kind runs Jest")
    func rnAndroidWithoutKindRunsJest() async throws {
        let tempDir = try makeTempDirectory(prefix: "RNAndroidJestFallback")
        let packageJSON = """
            {"name": "my-app", "scripts": {"test": "jest"}}
            """
        try packageJSON.write(
            to: tempDir.appendingPathComponent("package.json"),
            atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("node_modules"),
            withIntermediateDirectories: false
        )

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidBuildSystem: .reactNative,
            projectRoot: tempDir.path
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        _ = try? await TestAction().run(with: TestAction.Options(), context: context)

        let captured = commands()
        let testCommands = captured.filter { $0.contains("run") && $0.contains("test") }
        #expect(testCommands.count == 1)
        #expect(testCommands[0].contains("--json"))
        #expect(testCommands[0].contains("--outputFile"))
        #expect(!captured.contains { $0.contains("gradlew") })
    }

    // MARK: - ActionContext.withGradleProjectDir

    @Test("withGradleProjectDir returns context with updated gradleProjectDir")
    func withGradleProjectDirUpdatesConfig() async throws {
        let (executor, _) = makeCaptureExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let config = ResolvedConfig(platform: .android, projectRoot: "/project")
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        let updated = context.withGradleProjectDir("/project/android")

        #expect(updated.config.gradleProjectDir == "/project/android")
        #expect(context.config.gradleProjectDir == "/project")  // original unchanged
    }
}
