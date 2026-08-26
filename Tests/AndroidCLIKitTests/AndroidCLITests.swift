import AndroidCLIKit
import Testing

@Suite("AndroidCLI")
struct AndroidCLITests {
    @Test("global SDK and executable configuration precede subcommand")
    func configuration() {
        let command = AndroidCLI(executablePath: "/opt/android", sdkPath: "/opt/sdk")
            .describe(projectDirectory: "/tmp/project")
            .command()
        #expect(command.executableName == "/opt/android")
        #expect(command.arguments == ["--sdk=/opt/sdk", "describe", "--project_dir=/tmp/project"])
    }

    @Test("run builds deployment arguments")
    func run() {
        let command = AndroidCLI().run(
            apks: ["base.apk", "split.apk"], device: "emulator-5554", activity: ".MainActivity",
            type: .activity, installOptions: ["-g", "-d"], useDeltaInstall: true, debug: true
        ).command()
        #expect(
            command.arguments == [
                "run", "--apks=base.apk,split.apk", "--device=emulator-5554",
                "--activity=.MainActivity", "--type=ACTIVITY", "--install-options=-g,-d",
                "--use-delta-install", "--debug",
            ])
    }

    @Test(
        "all command families construct expected prefixes",
        arguments: [
            (AndroidCLI().listTemplates().command().arguments, ["create", "--list"]),
            (AndroidCLI().docsSearch("performance").command().arguments, ["docs", "search", "performance"]),
            (AndroidCLI().emulatorList(long: true).command().arguments, ["emulator", "list", "--long"]),
            (
                AndroidCLI().screenCapture(output: "screen.png", annotate: true).command().arguments,
                ["screen", "capture", "--annotate", "--output=screen.png"]
            ),
            (AndroidCLI().sdkRemove(packages: ["platforms/android-34"]).command().arguments, ["sdk", "remove", "platforms/android-34"]),
            (AndroidCLI().skillsFind("performance").command().arguments, ["skills", "find", "performance"]),
            (AndroidCLI().studioCheck().command().arguments, ["studio", "check"]),
            (AndroidCLI().update().command().arguments, ["update"]),
        ])
    func families(actual: [String], expected: [String]) {
        #expect(actual == expected)
    }

    @Test("layout parser tolerates unknown fields")
    func layoutParser() throws {
        let elements = try AndroidCLIOutputParser.layoutElements(
            from: """
                [{"text":"Run","resourceId":"run","center":"[1,2]","off-screen":false,"future":1}]
                """)
        #expect(elements == [.init(text: "Run", resourceId: "run", center: "[1,2]", offScreen: false)])
    }
}
