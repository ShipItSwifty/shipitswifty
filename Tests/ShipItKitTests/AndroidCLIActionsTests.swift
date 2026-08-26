import SwiftyShell
import Synchronization
import Testing

@testable import ShipItKit

@Suite("AndroidCLI workflow actions")
struct AndroidCLIActionsTests {
    @Test("disabled configuration fails explicitly")
    func disabled() async {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = ActionContext.mock(executor: executor, platform: .android)
        await #expect(throws: ShipItError.self) {
            try await AndroidInfoAction().run(with: .init(operation: "info"), context: context)
        }
    }

    @Test("mutating operation requires explicit authorization")
    func mutationGuard() async {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let context = enabledContext(executor: executor)
        await #expect(throws: ShipItError.self) {
            try await AndroidSDKAction().run(
                with: .init(operation: "install", arguments: ["platforms/android-36"]),
                context: context
            )
        }
    }

    @Test("enabled action validates version then executes family command")
    func executes() async throws {
        let captured = Mutex<[[String]]>([])
        let executor = MockExecutor { command, _ in
            captured.withLock { $0.append(command.arguments) }
            if command.arguments.contains("--version") {
                return ShellOutput(stdout: "1.0.15985488\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "android-cli\n", stderr: "", exitCode: 0)
        }
        let result = try await AndroidSkillsAction().run(
            with: .init(operation: "list", arguments: ["--long"]),
            context: enabledContext(executor: executor)
        )
        #expect(result.command == ["skills", "list", "--long"])
        #expect(result.stdout == "android-cli\n")
        #expect(captured.withLock { $0 }.count == 2)
    }

    @Test(
        "create operations map to AndroidCLI's asymmetric command syntax",
        arguments: [
            ("create", ["create", "--template", "compose-app"]),
            ("list", ["create", "--list", "--json"]),
        ])
    func createCommandShape(operation: String, expected: [String]) async throws {
        let executor = MockExecutor { command, _ in
            if command.arguments.contains("--version") {
                return ShellOutput(stdout: "1.0.15985488\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let arguments = operation == "create" ? ["--template", "compose-app"] : ["--json"]
        let result = try await AndroidCreateAction().run(
            with: .init(operation: operation, arguments: arguments, allowMutation: operation == "create"),
            context: enabledContext(executor: executor)
        )
        #expect(result.command == expected)
    }

    @Test("unsupported operation is rejected before shell execution")
    func invalidOperation() async {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        await #expect(throws: ShipItError.self) {
            try await AndroidEmulatorAction().run(
                with: .init(operation: "teleport"),
                context: enabledContext(executor: executor)
            )
        }
    }

    @Test(
        "version parsing tolerates prefixed version strings",
        arguments: [
            ("1.0.15985488", true),
            ("Android CLI, version 1.2.0", true),
            ("android-cli v1.2.0", true),
            ("0.9.0", false),
            ("not a version", false),
        ])
    func versionParsingHandlesRealisticOutput(output: String, expectedSupported: Bool) {
        #expect(AndroidCLIVersionGate.supports(output) == expectedSupported)
    }

    private func enabledContext(executor: MockExecutor) -> ActionContext {
        ActionContext.mock(
            executor: executor,
            platform: .android,
            config: ResolvedConfig(
                platform: .android,
                androidCLI: AndroidCLIConfig(enabled: true, executablePath: "android", sdkPath: "/opt/sdk")
            )
        )
    }
}
