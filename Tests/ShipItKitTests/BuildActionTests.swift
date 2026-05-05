import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

// MARK: - BuildAction Tests

#if os(macOS)
@Suite("BuildAction")
struct BuildActionTests {

    @Test("BuildAction invokes xcodebuild with correct scheme and configuration")
    func buildActionArgs() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = BuildAction.Options(scheme: "MyApp", configuration: .release)

        _ = try await BuildAction().run(with: options, context: context)

        #expect(commands().count > 0)
        let buildCommand = commands().first ?? ""
        #expect(buildCommand.contains("MyApp"))
        #expect(buildCommand.contains("Release"))
    }

    @Test("BuildAction throws ShipItError.buildFailed on non-zero exit code")
    func buildActionFailure() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "error: Build failed\n", exitCode: 65)
        }
        let context = ActionContext.mock(executor: executor)
        let options = BuildAction.Options(scheme: "MyApp", configuration: .release)

        await #expect {
            _ = try await BuildAction().run(with: options, context: context)
        } throws: { error in
            guard case ShipItError.buildFailed(let code, _) = error else { return false }
            return code == 65
        }
    }

    @Test("BuildAction throws invalidConfiguration when no scheme is set")
    func buildActionNoScheme() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let options = BuildAction.Options()  // No scheme

        // Override config to have no scheme
        let config = ResolvedConfig()  // No appScheme
        let contextNoScheme = makeTestActionContext(executor: executor, config: config, platform: .ios)

        await #expect {
            _ = try await BuildAction().run(with: options, context: contextNoScheme)
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }

    @Test("BuildAction counts warnings in output")
    func buildActionWarningCount() async throws {
        let warningOutput = """
            /MyApp/Sources/File.swift:10:5: warning: unused variable 'x'
            /MyApp/Sources/Other.swift:20:3: warning: deprecated API usage
            Build Succeeded
            """
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: warningOutput, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)
        let options = BuildAction.Options(scheme: "MockApp", configuration: .release)

        let result = try await BuildAction().run(with: options, context: context)
        #expect(result.warnings == 2)
    }

    @Test("BuildAction enables provisioning updates for automatic signing")
    func buildActionAutomaticSigning() async throws {
        nonisolated(unsafe) var capturedCommand: Command?
        let executor = MockExecutor { command, _ in
            capturedCommand = command
            return ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(appScheme: "MockApp", automaticCodeSigning: true)
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try await BuildAction().run(with: .init(scheme: "MockApp"), context: context)

        #expect(capturedCommand?.arguments.contains("-allowProvisioningUpdates") == true)
    }
}
#endif

// MARK: - BuildAction Options Tests

@Suite("BuildAction.Options")
struct BuildActionOptionsTests {

    @Test("Options can be encoded and decoded")
    func optionsCodable() throws {
        let options = BuildAction.Options(
            scheme: "TestApp",
            configuration: .debug,
            clean: true
        )

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(BuildAction.Options.self, from: data)

        #expect(decoded.scheme == "TestApp")
        #expect(decoded.configuration == .some(.debug))
        #expect(decoded.clean == true)
    }
}
