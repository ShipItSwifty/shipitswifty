#if os(macOS)
import Foundation
import Testing

@testable import ShipItKit

struct CommandFamilyTests {
    @Test func buildsAgvtoolCommands() {
        #expect(
            Agvtool().whatMarketingVersionTerse().command().arguments == [
                "agvtool", "what-marketing-version", "-terse",
            ])
        #expect(
            Agvtool().newVersionAll("42").command().arguments == [
                "agvtool", "new-version", "-all", "42",
            ])
    }

    @Test func buildsPlutilCommands() {
        #expect(
            Plutil().lint("Info.plist", additionalPlistPaths: ["Settings.plist"]).command().arguments == [
                "-lint", "--", "Info.plist", "Settings.plist",
            ])
        #expect(
            Plutil().convert("Info.plist", to: .json, output: .standardOutput, prettyPrinted: true).command().arguments == [
                "-convert", "json", "-o", "-", "-r", "--", "Info.plist",
            ])
        #expect(
            Plutil().extract("Metadata", as: .xml, expectedType: .dictionary, from: "Info.plist").command().arguments == [
                "-extract", "Metadata", "xml1", "-expect", "dictionary", "--", "Info.plist",
            ])
        #expect(
            Plutil().extractRaw("CFBundleVersion", expectedType: .string, from: "Info.plist", omitTrailingNewline: true).command().arguments
                == [
                    "-extract", "CFBundleVersion", "raw", "-expect", "string", "-n", "--", "Info.plist",
                ])
        #expect(
            Plutil().insert(.integer(42), at: "Build", in: "Info.plist").command().arguments == [
                "-insert", "Build", "-integer", "42", "--", "Info.plist",
            ])
        #expect(
            Plutil().append(.string("beta"), toArrayAt: "Tags", in: "Info.plist").command().arguments == [
                "-insert", "Tags", "-string", "beta", "-append", "--", "Info.plist",
            ])
        #expect(
            Plutil().insertEmpty(.dictionary, at: "Metadata", in: "Info.plist").command().arguments == [
                "-insert", "Metadata", "-dictionary", "--", "Info.plist",
            ])
        #expect(
            Plutil().replace(.string("42"), at: "CFBundleVersion", in: "Info.plist").command().arguments == [
                "-replace", "CFBundleVersion", "-string", "42", "--", "Info.plist",
            ])
        #expect(
            Plutil().remove("Obsolete", from: "Info.plist").command().arguments == [
                "-remove", "Obsolete", "--", "Info.plist",
            ])
    }

    @Test func serializesTypedPlutilValues() {
        let date = Date(timeIntervalSince1970: 0)

        #expect(
            Plutil().replace(.bool(true), at: "Value", in: "Info.plist").command().arguments[2...3] == [
                "-bool", "YES",
            ])
        #expect(
            Plutil().replace(.float(1.5), at: "Value", in: "Info.plist").command().arguments[2...3] == [
                "-float", "1.5",
            ])
        #expect(
            Plutil().replace(.date(date), at: "Value", in: "Info.plist").command().arguments[2...3] == [
                "-date", "1970-01-01T00:00:00Z",
            ])
        #expect(
            Plutil().replace(.data(Data([0, 1, 2])), at: "Value", in: "Info.plist").command().arguments[2...3] == [
                "-data", "AAEC",
            ])
        #expect(
            Plutil().replace(.xml("<array/>"), at: "Value", in: "Info.plist").command().arguments[2...3] == [
                "-xml", "<array/>",
            ])
        #expect(
            Plutil().replace(.json("[1,2]"), at: "Value", in: "Info.plist").command().arguments[2...3] == [
                "-json", "[1,2]",
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
        #expect(
            command.arguments == [
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
        #expect(
            Frameit().render(screenshotsDirectory: "screens", outputDirectory: "framed").command().arguments == [
                "--path", "screens", "--output", "framed",
            ])
    }

    @Test func buildsBashScriptCommand() {
        let command = Bash().script("echo ok").command()

        #expect(command.executableName == "/bin/bash")
        #expect(command.arguments == ["-c", "echo ok"])
    }
}
#endif
