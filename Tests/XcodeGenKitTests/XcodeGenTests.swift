#if os(macOS)
import Foundation
import SwiftyShell
import Synchronization
import Testing

@testable import XcodeGenKit

@Suite("XcodeGen")
struct XcodeGenTests {

    @Test("XcodeGen builds generate command with spec option")
    func generateWithSpec() {
        let command = XcodeGen()
            .generate()
            .spec("project.yml")
            .command()

        #expect(command.executableName == "xcodegen")
        #expect(command.arguments == ["generate", "--spec", "project.yml"])
    }

    @Test("XcodeGen builds generate command with project directory")
    func generateWithProjectDir() {
        let command = XcodeGen()
            .generate()
            .projectDirectory("./MyApp")
            .command()

        #expect(command.arguments == ["generate", "--project", "./MyApp"])
    }

    @Test("XcodeGen builds dump command")
    func dumpCommand() {
        let command = XcodeGen()
            .dump()
            .option(.type("resolved"))
            .command()

        #expect(command.arguments == ["dump", "--type", "resolved"])
    }

    @Test("XcodeGen noCache and quiet options")
    func noCacheAndQuiet() {
        let command = XcodeGen()
            .generate()
            .noCache()
            .quiet()
            .command()

        #expect(command.arguments == ["generate", "--no-cache", "--quiet"])
    }

    @Test("XcodeGen custom option")
    func customOption() {
        let command = XcodeGen()
            .generate()
            .option(.custom("--custom-flag", values: "value"))
            .command()

        #expect(command.arguments == ["generate", "--custom-flag", "value"])
    }

    @Test("XcodeGen runs and returns output via mock executor")
    func runsViaMockExecutor() async throws {
        let captured = Mutex<[String]>([])
        let executor = MockExecutor { command, _ in
            captured.withLock { $0.append(command.description) }
            return ShellOutput(stdout: "Generated project\n", stderr: "", exitCode: 0)
        }
        let context = ShellContext(executor: executor)
        let output = try await XcodeGen(context: context)
            .generate()
            .spec("project.yml")
            .run()

        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("Generated project"))
        let cmds = captured.withLock { $0 }
        #expect(cmds.count == 1)
        #expect(cmds.first?.contains("xcodegen") == true)
    }

    @Test("XcodeGenOption spec creates correct arguments")
    func specOption() {
        let option = XcodeGenOption.spec("custom.yml")
        #expect(option.arguments == ["--spec", "custom.yml"])
    }

    @Test("XcodeGenOption noEnv creates correct argument")
    func noEnvOption() {
        let option = XcodeGenOption.noEnv
        #expect(option.arguments == ["--no-env"])
    }
}
#endif
