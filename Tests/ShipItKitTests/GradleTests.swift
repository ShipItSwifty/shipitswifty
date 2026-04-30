import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

// MARK: - Gradle command builder tests

@Suite("Gradle")
struct GradleTests {

    @Test("Gradle builds command with a single task")
    func singleTask() {
        let command = Gradle()
            .task(.assembleRelease)
            .command()

        // executable is "gradle" when ./gradlew doesn't exist on disk (test environment)
        let exec = command.executableName
        #expect(exec == "gradle" || exec == "./gradlew")
        #expect(command.arguments.contains("assembleRelease"))
    }

    @Test("Gradle builds command with multiple tasks")
    func multipleTasks() {
        let command = Gradle()
            .task(.clean)
            .task(.bundleRelease)
            .command()

        let args = command.arguments
        #expect(args.contains("clean"))
        #expect(args.contains("bundleRelease"))
        // clean should come before bundleRelease
        let cleanIndex = args.firstIndex(of: "clean")
        let bundleIndex = args.firstIndex(of: "bundleRelease")
        #expect(cleanIndex != nil && bundleIndex != nil)
        if let ci = cleanIndex, let bi = bundleIndex {
            #expect(ci < bi)
        }
    }

    @Test("Gradle appends --no-daemon flag")
    func noDaemonFlag() {
        let command = Gradle()
            .task(.assembleRelease)
            .flag(.noDaemon)
            .command()

        #expect(command.arguments.contains("--no-daemon"))
    }

    @Test("Gradle appends --build-cache flag")
    func buildCacheFlag() {
        let command = Gradle()
            .task(.assembleRelease)
            .flag(.buildCache)
            .command()

        #expect(command.arguments.contains("--build-cache"))
    }

    @Test("Gradle appends -P property")
    func property() {
        let command = Gradle()
            .task(.assembleRelease)
            .property(.init(key: "versionCode", value: "42"))
            .command()

        #expect(command.arguments.contains("-PversionCode=42"))
    }

    @Test("Gradle uses custom gradlew path when set")
    func customGradlewPath() {
        let command = Gradle()
            .settingGradlewPath("/opt/project/gradlew")
            .task(.assembleRelease)
            .command()

        #expect(command.executableName == "/opt/project/gradlew")
    }

    @Test("Gradle resolves gradlew from project directory")
    func projectDir() {
        // projectDir affects gradlew resolution, not argument list
        let gradle = Gradle()
            .projectDir("./android")
            .task(.assembleDebug)
        let command = gradle.command()

        // task should still be in args
        #expect(command.arguments.contains("assembleDebug"))
        // executable should look in ./android/gradlew first (may fall back to gradle when not on disk)
        let exec = command.executableName
        #expect(exec == "./android/gradlew" || exec == "gradle")
    }

    @Test("Gradle runs and returns output via mock executor")
    func runsViaMockExecutor() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL in 2s\n", stderr: "", exitCode: 0)
        }
        let context = ShellContext(executor: executor)
        let output = try await Gradle(context: context)
            .task(.assembleRelease)
            .run()

        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("BUILD SUCCESSFUL"))
        #expect(commands().count == 1)
        #expect(commands().first?.contains("assembleRelease") == true)
    }

    @Test("GradleTask flavor+variant assemble generates correct task name")
    func flavorAssembleTask() {
        let task = GradleTask.assemble(flavor: "free", variant: "release")
        #expect(task.name == "assembleFreeRelease")
    }

    @Test("GradleTask flavor+variant bundle generates correct task name")
    func flavorBundleTask() {
        let task = GradleTask.bundle(flavor: "paid", variant: "debug")
        #expect(task.name == "bundlePaidDebug")
    }
}

// MARK: - Adb command builder tests

@Suite("Adb")
struct AdbTests {

    @Test("Adb builds install command")
    func installCommand() {
        let command = Adb()
            .install(apk: "app-release.apk", replace: true)
            .command()

        #expect(command.executableName == "adb")
        #expect(command.arguments.contains("install"))
        #expect(command.arguments.contains("-r"))
        #expect(command.arguments.contains("app-release.apk"))
    }

    @Test("Adb builds shell command")
    func shellCommand() {
        let command = Adb()
            .shell("am start -n com.example/.MainActivity")
            .command()

        let args = command.arguments
        #expect(args.contains("shell"))
        #expect(args.contains("am start -n com.example/.MainActivity"))
    }

    @Test("Adb devices command uses 'adb' executable")
    func devicesCommand() {
        let cmd = Adb().devices().command()
        #expect(cmd.executableName == "adb")
        #expect(cmd.arguments.contains("devices"))
    }
}

// MARK: - Bundletool command builder tests

@Suite("Bundletool")
struct BundletoolTests {

    @Test("Bundletool validate(bundle:) produces correct arguments")
    func validateBundle() {
        let command = Bundletool()
            .validate(bundle: "./app-release.aab")
            .command()

        let args = command.arguments
        #expect(command.executableName == "bundletool")
        #expect(args.contains("validate"))
        #expect(args.contains("--bundle=./app-release.aab"))
    }

    @Test("Bundletool buildApks produces correct arguments")
    func buildApks() {
        let command = Bundletool()
            .buildApks(bundle: "app-release.aab", output: "app.apks")
            .command()

        let args = command.arguments
        #expect(args.contains("build-apks"))
        #expect(args.contains("--bundle=app-release.aab"))
        #expect(args.contains("--output=app.apks"))
    }
}

// MARK: - Android BuildAction tests

@Suite("BuildAction (Android)")
struct AndroidBuildActionTests {

    @Test("BuildAction on Android runs gradlew assembleRelease")
    func androidBuild() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(platform: .android)
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: ActionContext.mock(executor: executor).logger,
            config: config,
            appStoreConnect: ActionContext.mock(executor: executor).appStoreConnect,
            platform: .android
        )
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
        let context = ActionContext(
            shell: ShellContext(executor: executor),
            logger: ActionContext.mock(executor: executor).logger,
            config: config,
            appStoreConnect: ActionContext.mock(executor: executor).appStoreConnect,
            platform: .android
        )
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
