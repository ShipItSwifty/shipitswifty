import Testing
@testable import ShipItKit

struct CommandFamilyTests {
    @Test func buildsAgvtoolCommands() {
        #expect(Agvtool().whatMarketingVersionTerse().command().arguments == [
            "agvtool", "what-marketing-version", "-terse"
        ])
        #expect(Agvtool().newVersionAll("42").command().arguments == [
            "agvtool", "new-version", "-all", "42"
        ])
    }

    @Test func buildsPlutilCommands() {
        #expect(Plutil().extractRaw(key: "CFBundleVersion", plistPath: "Info.plist").command().arguments == [
            "-extract", "CFBundleVersion", "raw", "Info.plist"
        ])
        #expect(Plutil().replaceString(key: "CFBundleVersion", value: "42", plistPath: "Info.plist").command().arguments == [
            "-replace", "CFBundleVersion", "-string", "42", "Info.plist"
        ])
    }

    @Test func buildsXccovCommand() {
        let command = Xccov().viewReportJSON(xcresultPath: "build/tests.xcresult").command()

        #expect(command.executableName == "xcrun")
        #expect(command.arguments == ["xccov", "view", "--report", "--json", "build/tests.xcresult"])
    }

    @Test func buildsAltoolCommand() {
        let command = Altool()
            .uploadApp(ipaPath: "App.ipa", platform: "ios", apiKey: "KEY", apiIssuer: "ISSUER")
            .command()

        #expect(command.executableName == "xcrun")
        #expect(command.arguments == [
            "altool",
            "--upload-app",
            "-f", "App.ipa",
            "-t", "ios",
            "--apiKey", "KEY",
            "--apiIssuer", "ISSUER",
            "--output-format", "json",
        ])
    }

    @Test func buildsFrameitAndWhichCommands() {
        #expect(Which().tool("frameit").command().arguments == ["frameit"])
        #expect(Frameit().render(screenshotsDirectory: "screens", outputDirectory: "framed").command().arguments == [
            "--path", "screens", "--output", "framed"
        ])
    }

    @Test func buildsBashScriptCommand() {
        let command = Bash().script("echo ok").command()

        #expect(command.executableName == "/bin/bash")
        #expect(command.arguments == ["-c", "echo ok"])
    }
}
