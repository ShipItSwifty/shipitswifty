import Testing

@testable import GradleKit

@Suite("GradleKit — task helpers, flags, bundletool, emulator")
struct GradleKitHelpersTests {

    // MARK: - Variant task names

    @Test(
        "variantTask upper-cases only the first character of each segment",
        arguments: [
            (GradleTask.variantTask(prefix: "assemble", variant: "release"), "assembleRelease"),
            (GradleTask.variantTask(prefix: "bundle", variant: "stagingRelease"), "bundleStagingRelease"),
            (GradleTask.variantTask(prefix: "bundle", flavor: "free", variant: "release"), "bundleFreeRelease"),
            (GradleTask.variantTask(prefix: "bundle", flavor: "freeTier", variant: "release"), "bundleFreeTierRelease"),
            (GradleTask.variantTask(prefix: "assemble", flavor: "", variant: "debug"), "assembleDebug"),
            (GradleTask.variantTask(prefix: "test", variant: "debug", suffix: "UnitTest"), "testDebugUnitTest"),
        ]
    )
    func variantTaskNames(task: GradleTask, expected: String) {
        #expect(task.name == expected)
    }

    @Test("Variant factories match AGP task names")
    func variantFactories() {
        #expect(GradleTask.assemble(variant: "prodRelease").name == "assembleProdRelease")
        #expect(GradleTask.bundle(variant: "release") == .bundleRelease)
        #expect(GradleTask.lint(variant: "debug") == .lintDebug)
        #expect(GradleTask.unitTest(variant: "debug") == .testDebugUnitTest)
        #expect(GradleTask.connectedAndroidTest(variant: "debug") == .connectedDebugAndroidTest)
        #expect(GradleTask.managedDeviceAndroidTest(device: "pixel6Api34", variant: "debug").name == "pixel6Api34DebugAndroidTest")
    }

    @Test("Flavored factories keep their existing output")
    func flavoredFactories() {
        #expect(GradleTask.assemble(flavor: "paid", variant: "debug").name == "assemblePaidDebug")
        #expect(GradleTask.bundle(flavor: "free", variant: "release").name == "bundleFreeRelease")
        #expect(GradleTask.linkFramework(configuration: "release", target: "iosArm64") == .linkReleaseFrameworkIosArm64)
    }

    // MARK: - Task options

    @Test("filteringTests appends a --tests pair per pattern")
    func filteringTests() {
        let task = GradleTask.testDebugUnitTest.filteringTests(["com.example.A.one", "com.example.B"])
        #expect(task.name == "testDebugUnitTest")
        #expect(task.arguments == ["testDebugUnitTest", "--tests", "com.example.A.one", "--tests", "com.example.B"])
    }

    @Test("filteringTests with no patterns leaves the task unchanged")
    func filteringTestsEmpty() {
        #expect(GradleTask.testDebugUnitTest.filteringTests([]) == .testDebugUnitTest)
    }

    @Test("qualified(module:) preserves task options")
    func qualifiedPreservesOptions() {
        let task = GradleTask.testDebugUnitTest
            .filteringTests(["com.example.A"])
            .qualified(module: "app")
        #expect(task.arguments == [":app:testDebugUnitTest", "--tests", "com.example.A"])
    }

    @Test("Gradle emits task options after their task and after global flags")
    func gradleCommandOrdersTaskOptions() throws {
        let args = Gradle()
            .flag(.noDaemon)
            .task(.clean)
            .task(GradleTask.unitTest(variant: "debug").filteringTests(["com.example.A"]))
            .command()
            .arguments

        let flagIndex = try #require(args.firstIndex(of: "--no-daemon"))
        let cleanIndex = try #require(args.firstIndex(of: "clean"))
        let taskIndex = try #require(args.firstIndex(of: "testDebugUnitTest"))
        #expect(flagIndex < cleanIndex)
        #expect(cleanIndex < taskIndex)
        #expect(Array(args[(taskIndex + 1)...]) == ["--tests", "com.example.A"])
    }

    // MARK: - Flags

    @Test("New global flags emit the expected arguments")
    func newFlags() {
        #expect(GradleFlag.continueAfterFailure.arguments == ["--continue"])
        #expect(GradleFlag.rerunTasks.arguments == ["--rerun-tasks"])
        #expect(GradleFlag.refreshDependencies.arguments == ["--refresh-dependencies"])
        #expect(GradleFlag.noConfigurationCache.arguments == ["--no-configuration-cache"])
        #expect(GradleFlag.quiet.arguments == ["--quiet"])
        #expect(GradleFlag.maxWorkers(2).arguments == ["--max-workers=2"])
        #expect(GradleFlag.excludeTask(.lint).arguments == ["-x", "lint"])
    }

    // MARK: - Bundletool

    @Test("Bundletool signing overload uses file password sources, mode, and overwrite")
    func bundletoolSigning() {
        let args = Bundletool(jarPath: "/opt/bundletool.jar")
            .buildApks(
                bundle: "app.aab",
                output: "app.apks",
                signing: .init(keystorePath: "release.jks", keystorePassword: .file("/secrets/ks"), keyAlias: "upload"),
                mode: .universal,
                overwrite: true
            )
            .command()
            .arguments
        #expect(
            args == [
                "-jar", "/opt/bundletool.jar", "build-apks", "--bundle=app.aab", "--output=app.apks", "--ks=release.jks",
                "--ks-pass=file:/secrets/ks", "--ks-key-alias=upload", "--mode=universal", "--overwrite",
            ])
    }

    @Test("Bundletool string passwords keep the pass: prefix and install-apks can target a device")
    func bundletoolLegacyPasswordsAndDeviceID() {
        let build = Bundletool(jarPath: "b.jar")
            .buildApks(bundle: "a.aab", output: "a.apks", keystorePath: "k.jks", keystorePassword: "pw", keyAlias: "k", keyPassword: "kp")
            .command()
            .arguments
        #expect(build.contains("--ks-pass=pass:pw"))
        #expect(build.contains("--key-pass=pass:kp"))

        let install = Bundletool(jarPath: "b.jar").installApks(apks: "a.apks", deviceID: "emulator-5554").command().arguments
        #expect(install.suffix(3) == ["install-apks", "--apks=a.apks", "--device-id=emulator-5554"])
    }

    // MARK: - Emulator

    @Test("Emulator start emits boot options in order")
    func emulatorStartOptions() {
        let args = Emulator(executablePath: "emulator")
            .start(
                avd: "Pixel_7", headless: true, gpu: "swiftshader_indirect", noSnapshot: true, wipeData: true, readOnly: true, port: 5560
            )
            .command()
            .arguments
        #expect(
            args == [
                "-avd", "Pixel_7", "-no-window", "-no-audio", "-no-boot-anim", "-gpu", "swiftshader_indirect",
                "-no-snapshot", "-wipe-data", "-read-only", "-port", "5560",
            ])
    }

    @Test("Emulator resolves the SDK binary from ANDROID_HOME, then ANDROID_SDK_ROOT, then PATH")
    func emulatorExecutableResolution() {
        let existing: Set<String> = ["/sdk-root/emulator/emulator"]
        let exists: (String) -> Bool = { existing.contains($0) }

        #expect(
            Emulator.resolveExecutable(environment: ["ANDROID_SDK_ROOT": "/sdk-root"], fileExists: exists) == "/sdk-root/emulator/emulator")
        #expect(
            Emulator.resolveExecutable(environment: ["ANDROID_HOME": "/missing", "ANDROID_SDK_ROOT": "/sdk-root"], fileExists: exists)
                == "/sdk-root/emulator/emulator")
        #expect(Emulator.resolveExecutable(environment: [:], fileExists: exists) == "emulator")
        #expect(Emulator(executablePath: "/custom/emulator").list().command().executableName == "/custom/emulator")
    }
}
