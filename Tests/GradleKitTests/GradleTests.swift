import Foundation
import SwiftyShell
import Synchronization
import Testing

@testable import GradleKit

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
        let captured = Mutex<[String]>([])
        let executor = MockExecutor { command, _ in
            captured.withLock { $0.append(command.description) }
            return ShellOutput(stdout: "BUILD SUCCESSFUL in 2s\n", stderr: "", exitCode: 0)
        }
        let context = ShellContext(executor: executor)
        let output = try await Gradle(context: context)
            .task(.assembleRelease)
            .run()

        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("BUILD SUCCESSFUL"))
        let cmds = captured.withLock { $0 }
        #expect(cmds.count == 1)
        #expect(cmds.first?.contains("assembleRelease") == true)
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

    @Test("Adb raw arguments preserve serial prefix")
    func rawArgumentsCommand() {
        let command = Adb()
            .serial("emulator-5554")
            .rawArguments(["version"])
            .command()

        #expect(command.executableName == "adb")
        #expect(command.arguments == ["-s", "emulator-5554", "version"])
    }

    @Test("Adb serial targets a specific device")
    func serialCommand() {
        let command = Adb()
            .serial("R5CT2074MZ")
            .devices()
            .command()

        #expect(command.arguments == ["-s", "R5CT2074MZ", "devices"])
    }

    @Test("Adb nil serial produces no prefix")
    func nilSerialCommand() {
        let command = Adb()
            .serial("emulator-5554")
            .serial(nil)
            .devices()
            .command()

        #expect(command.arguments == ["devices"])
    }

    @Test("Adb start-server command")
    func startServerCommand() {
        let command = Adb().startServer().command()
        #expect(command.arguments == ["start-server"])
    }

    @Test("Adb kill-server command")
    func killServerCommand() {
        let command = Adb().killServer().command()
        #expect(command.arguments == ["kill-server"])
    }

    @Test("Adb devices long format")
    func devicesLongCommand() {
        let command = Adb().devices(long: true).command()
        #expect(command.arguments == ["devices", "-l"])
    }

    @Test("Adb wait-for-device command")
    func waitForDeviceCommand() {
        let command = Adb().waitForDevice().command()
        #expect(command.arguments == ["wait-for-device"])
    }

    @Test("Adb uninstall command")
    func uninstallCommand() {
        let command = Adb().uninstall(package: "com.example.app").command()
        #expect(command.arguments == ["uninstall", "com.example.app"])
    }

    @Test("Adb am force-stop command")
    func amForceStopCommand() {
        let command = Adb().amForceStop(package: "com.example.app").command()
        #expect(command.arguments == ["shell", "am", "force-stop", "com.example.app"])
    }

    @Test("Adb am start activity with extras")
    func amStartActivityExtras() {
        let command = Adb()
            .amStartActivity(
                component: "com.example/.MainActivity",
                extras: ["key1": "val1", "key2": "val2"]
            )
            .command()

        #expect(
            command.arguments == [
                "shell", "am", "start", "-n", "com.example/.MainActivity",
                "--es", "key1", "val1",
                "--es", "key2", "val2",
            ])
    }

    @Test("Adb am start activity with ordered arguments")
    func amStartActivityArguments() {
        let command = Adb()
            .amStartActivity(component: "com.example/.Main", arguments: ["a", "b"])
            .command()

        #expect(
            command.arguments == [
                "shell", "am", "start", "-n", "com.example/.Main",
                "--es", "arg", "a",
                "--es", "arg", "b",
            ])
    }

    @Test("Adb am start VIEW URL")
    func amStartViewURL() {
        let command = Adb().amStartViewURL("https://example.com").command()
        #expect(
            command.arguments == [
                "shell", "am", "start",
                "-a", "android.intent.action.VIEW",
                "-d", "https://example.com",
            ])
    }

    @Test("Adb pm list packages")
    func pmListPackages() {
        let command = Adb().pmListPackages().command()
        #expect(command.arguments == ["shell", "pm", "list", "packages"])
    }

    @Test("Adb pm grant permission")
    func pmGrantPermission() {
        let command = Adb()
            .pmGrantPermission(package: "com.example", permission: "android.permission.CAMERA")
            .command()
        #expect(
            command.arguments == [
                "shell", "pm", "grant", "com.example", "android.permission.CAMERA",
            ])
    }

    @Test("Adb pm revoke permission")
    func pmRevokePermission() {
        let command = Adb()
            .pmRevokePermission(package: "com.example", permission: "android.permission.CAMERA")
            .command()
        #expect(
            command.arguments == [
                "shell", "pm", "revoke", "com.example", "android.permission.CAMERA",
            ])
    }

    @Test("Adb resolve launchable activity")
    func resolveLaunchableActivity() {
        let command = Adb().resolveLaunchableActivity(package: "com.example").command()
        #expect(
            command.arguments == [
                "shell", "cmd", "package", "resolve-activity", "--brief", "com.example",
            ])
    }

    @Test("Adb screencap command")
    func screencapCommand() {
        let command = Adb().screencap(remotePath: "/sdcard/screen.png").command()
        #expect(command.arguments == ["shell", "screencap", "-p", "/sdcard/screen.png"])
    }

    @Test("Adb screenrecord command")
    func screenrecordCommand() {
        let command = Adb().screenrecord(remotePath: "/sdcard/demo.mp4").command()
        #expect(command.arguments == ["shell", "screenrecord", "/sdcard/demo.mp4"])
    }

    @Test("Adb shell pkill command")
    func shellPkillCommand() {
        let command = Adb().shellPkill(process: "screenrecord").command()
        #expect(command.arguments == ["shell", "pkill", "-INT", "screenrecord"])
    }

    @Test("Adb input keyevent command")
    func inputKeyeventCommand() {
        let command = Adb().inputKeyevent("KEYCODE_HOME").command()
        #expect(command.arguments == ["shell", "input", "keyevent", "KEYCODE_HOME"])
    }

    @Test("Adb uimode night command")
    func cmdUimodeNightCommand() {
        let command = Adb().cmdUimodeNight(.yes).command()
        #expect(command.arguments == ["shell", "cmd", "uimode", "night", "yes"])
    }

    @Test("Adb forward TCP command")
    func forwardTCPCommand() {
        let command = Adb().forwardTCP(localPort: 8080, remotePort: 3000).command()
        #expect(command.arguments == ["forward", "tcp:8080", "tcp:3000"])
    }

    @Test("Adb remove forward TCP command")
    func removeForwardTCPCommand() {
        let command = Adb().removeForwardTCP(localPort: 8080).command()
        #expect(command.arguments == ["forward", "--remove", "tcp:8080"])
    }

    @Test("Adb push command")
    func pushCommand() {
        let command = Adb().push(local: "./file.txt", remote: "/sdcard/file.txt").command()
        #expect(command.arguments == ["push", "./file.txt", "/sdcard/file.txt"])
    }

    @Test("Adb pull command")
    func pullCommand() {
        let command = Adb().pull(remote: "/sdcard/file.txt", local: "./file.txt").command()
        #expect(command.arguments == ["pull", "/sdcard/file.txt", "./file.txt"])
    }

    @Test("Adb logcat with filters")
    func logcatCommand() {
        let command = Adb().logcat(filters: ["*:E"]).command()
        #expect(command.arguments == ["logcat", "*:E"])
    }

    @Test("Adb emu kill command")
    func emuKillCommand() {
        let command = Adb().emuKill().command()
        #expect(command.arguments == ["emu", "kill"])
    }

    @Test("Adb emu geo fix command")
    func emuGeoFixCommand() {
        let command = Adb().emuGeoFix(longitude: -122.084, latitude: 37.422).command()
        #expect(command.arguments == ["emu", "geo", "fix", "-122.084", "37.422"])
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
