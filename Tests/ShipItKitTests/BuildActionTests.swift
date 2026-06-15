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

    @Test("BuildAction keeps Gradle properties when clean is enabled")
    func buildActionCleanPreservesGradleProperties() async throws {
        nonisolated(unsafe) var capturedCommand: Command?
        let executor = MockExecutor { command, _ in
            capturedCommand = command
            return ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            platform: .android,
            androidModule: "app",
            androidBuildVariant: "release",
            androidGradleProperties: ["ci": "true"]
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        _ = try await BuildAction().run(
            with: .init(clean: true, gradleProperties: ["versionCode": "42"]),
            context: context
        )

        let arguments = capturedCommand?.arguments ?? []
        #expect(arguments.contains("clean"))
        #expect(arguments.contains(where: { $0 == "-Pci=true" }))
        #expect(arguments.contains(where: { $0 == "-PversionCode=42" }))
    }

    @Test("BuildAction uses full Android build variant in Gradle task")
    func buildActionUsesFullAndroidVariantTask() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidModule: "app",
            androidBuildVariant: "prodRelease"
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        _ = try await BuildAction().run(with: .init(), context: context)

        #expect(commands().contains { $0.contains(":app:assembleProdRelease") })
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

    @Test("BuildAction passes ASC API key flags for automatic signing in CI")
    func buildActionPassesASCAuthKey() async throws {
        nonisolated(unsafe) var capturedCommand: Command?
        nonisolated(unsafe) var keyPathExistedDuringRun = false
        nonisolated(unsafe) var keyContents: Data?
        let executor = MockExecutor { command, _ in
            capturedCommand = command
            if let index = command.arguments.firstIndex(of: "-authenticationKeyPath"),
                index + 1 < command.arguments.count
            {
                let path = command.arguments[index + 1]
                keyPathExistedDuringRun = FileManager.default.fileExists(atPath: path)
                keyContents = FileManager.default.contents(atPath: path)
            }
            return ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }

        let pemData = Data("-----BEGIN PRIVATE KEY-----\nMOCK\n-----END PRIVATE KEY-----".utf8)
        let config = ResolvedConfig(
            appScheme: "MockApp",
            ascKeyID: "KEY123",
            ascIssuerID: "ISSUER456",
            ascPrivateKeyData: pemData,
            automaticCodeSigning: true
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try await BuildAction().run(with: .init(scheme: "MockApp"), context: context)

        let arguments = capturedCommand?.arguments ?? []
        #expect(arguments.contains("-authenticationKeyID"))
        #expect(arguments.contains("KEY123"))
        #expect(arguments.contains("-authenticationKeyIssuerID"))
        #expect(arguments.contains("ISSUER456"))
        #expect(arguments.contains("-authenticationKeyPath"))
        #expect(keyPathExistedDuringRun, "Temp .p8 key file should exist during the xcodebuild run")
        #expect(keyContents == pemData, "Temp .p8 file should contain the resolved private key")

        // The temporary key file must be cleaned up once the action returns.
        if let index = arguments.firstIndex(of: "-authenticationKeyPath"), index + 1 < arguments.count {
            #expect(!FileManager.default.fileExists(atPath: arguments[index + 1]), "Temp key file should be removed after run")
        }
    }

    @Test("BuildAction omits ASC API key flags when credentials are absent")
    func buildActionOmitsASCAuthKeyWithoutCredentials() async throws {
        nonisolated(unsafe) var capturedCommand: Command?
        let executor = MockExecutor { command, _ in
            capturedCommand = command
            return ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(appScheme: "MockApp", automaticCodeSigning: true)
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try await BuildAction().run(with: .init(scheme: "MockApp"), context: context)

        let arguments = capturedCommand?.arguments ?? []
        #expect(arguments.contains("-allowProvisioningUpdates"))
        #expect(!arguments.contains("-authenticationKeyPath"), "No ASC key flags without credentials")
    }

    @Test("BuildAction omits ASC API key flags for manual signing")
    func buildActionOmitsASCAuthKeyForManualSigning() async throws {
        nonisolated(unsafe) var capturedCommand: Command?
        let executor = MockExecutor { command, _ in
            capturedCommand = command
            return ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
        }

        let config = ResolvedConfig(
            appScheme: "MockApp",
            ascKeyID: "KEY123",
            ascIssuerID: "ISSUER456",
            ascPrivateKeyData: Data("key".utf8),
            automaticCodeSigning: false
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .ios)

        _ = try await BuildAction().run(with: .init(scheme: "MockApp"), context: context)

        let arguments = capturedCommand?.arguments ?? []
        #expect(!arguments.contains("-authenticationKeyPath"), "Manual signing should not pass ASC key flags")
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
