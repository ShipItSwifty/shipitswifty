#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("Archive and Export Actions")
struct ArchiveExportActionTests {

    @Test("ArchiveAction enables provisioning updates for automatic signing")
    func archiveActionAutomaticSigning() async throws {
        nonisolated(unsafe) var capturedCommand: Command?
        let executor = MockExecutor { command, _ in
            capturedCommand = command
            return ShellOutput(stdout: "Archive Succeeded\n", stderr: "", exitCode: 0)
        }

        let baseContext = ActionContext.mock(executor: executor)
        let config = ResolvedConfig(
            appProject: "MockApp.xcodeproj",
            appScheme: "MockApp",
            automaticCodeSigning: true
        )
        let context = ActionContext(
            shell: baseContext.shell,
            logger: baseContext.logger,
            config: config,
            appStoreConnect: baseContext.appStoreConnect,
            platform: .ios
        )

        _ = try await ArchiveAction().run(with: .init(scheme: "MockApp"), context: context)

        #expect(capturedCommand?.arguments.contains("-allowProvisioningUpdates") == true)
    }

    @Test("ArchiveAction passes ASC API key flags for automatic signing in CI")
    func archiveActionPassesASCAuthKey() async throws {
        nonisolated(unsafe) var capturedCommand: Command?
        let executor = MockExecutor { command, _ in
            capturedCommand = command
            return ShellOutput(stdout: "Archive Succeeded\n", stderr: "", exitCode: 0)
        }

        let baseContext = ActionContext.mock(executor: executor)
        let config = ResolvedConfig(
            appProject: "MockApp.xcodeproj",
            appScheme: "MockApp",
            ascKeyID: "KEY123",
            ascIssuerID: "ISSUER456",
            ascPrivateKeyData: Data("key".utf8),
            automaticCodeSigning: true
        )
        let context = ActionContext(
            shell: baseContext.shell,
            logger: baseContext.logger,
            config: config,
            appStoreConnect: baseContext.appStoreConnect,
            platform: .ios
        )

        _ = try await ArchiveAction().run(with: .init(scheme: "MockApp"), context: context)

        let arguments = capturedCommand?.arguments ?? []
        #expect(arguments.contains("-authenticationKeyID"))
        #expect(arguments.contains("KEY123"))
        #expect(arguments.contains("-authenticationKeyIssuerID"))
        #expect(arguments.contains("ISSUER456"))
        #expect(arguments.contains("-authenticationKeyPath"))
        // Temp key file is cleaned up once the action returns.
        if let index = arguments.firstIndex(of: "-authenticationKeyPath"), index + 1 < arguments.count {
            #expect(!FileManager.default.fileExists(atPath: arguments[index + 1]))
        }
    }

    @Test("ExportAction enables provisioning updates and automatic signing style")
    func exportActionAutomaticSigning() async throws {
        nonisolated(unsafe) var capturedCommand: Command?
        nonisolated(unsafe) var plistContents: String?

        let exportDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try Data().write(to: exportDirectory.appendingPathComponent("MockApp.ipa"))

        let archiveDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: archiveDirectory) }
        let archivePath = archiveDirectory.appendingPathComponent("MockApp.xcarchive").path
        FileManager.default.createFile(atPath: archivePath, contents: Data())

        let executor = MockExecutor { command, _ in
            capturedCommand = command
            if let plistIndex = command.arguments.firstIndex(of: "-exportOptionsPlist"),
                plistIndex + 1 < command.arguments.count
            {
                plistContents = try String(
                    contentsOfFile: command.arguments[plistIndex + 1],
                    encoding: .utf8
                )
            }
            return ShellOutput(stdout: "Export Succeeded\n", stderr: "", exitCode: 0)
        }

        let baseContext = ActionContext.mock(executor: executor)
        let config = ResolvedConfig(
            teamID: "TEAM12345",
            archiveOutputPath: archivePath,
            exportOutputDirectory: exportDirectory.path,
            automaticCodeSigning: true
        )
        let context = ActionContext(
            shell: baseContext.shell,
            logger: baseContext.logger,
            config: config,
            appStoreConnect: baseContext.appStoreConnect,
            platform: .ios
        )

        let result = try await ExportAction().run(with: .init(), context: context)

        #expect(result.ipaPath.hasSuffix("MockApp.ipa"))
        #expect(capturedCommand?.arguments.contains("-allowProvisioningUpdates") == true)

        guard let plistContents else {
            Issue.record("Expected export options plist contents to be captured")
            return
        }

        #expect(plistContents.contains("<key>signingStyle</key>"))
        #expect(plistContents.contains("<string>automatic</string>"))
        #expect(plistContents.contains("<key>teamID</key>"))
    }

    @Test("ExportAction passes ASC API key flags for automatic signing in CI")
    func exportActionPassesASCAuthKey() async throws {
        nonisolated(unsafe) var capturedCommand: Command?

        let exportDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try Data().write(to: exportDirectory.appendingPathComponent("MockApp.ipa"))

        let archiveDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: archiveDirectory) }
        let archivePath = archiveDirectory.appendingPathComponent("MockApp.xcarchive").path
        FileManager.default.createFile(atPath: archivePath, contents: Data())

        let executor = MockExecutor { command, _ in
            capturedCommand = command
            return ShellOutput(stdout: "Export Succeeded\n", stderr: "", exitCode: 0)
        }

        let baseContext = ActionContext.mock(executor: executor)
        let config = ResolvedConfig(
            teamID: "TEAM12345",
            ascKeyID: "KEY123",
            ascIssuerID: "ISSUER456",
            ascPrivateKeyData: Data("key".utf8),
            archiveOutputPath: archivePath,
            exportOutputDirectory: exportDirectory.path,
            automaticCodeSigning: true
        )
        let context = ActionContext(
            shell: baseContext.shell,
            logger: baseContext.logger,
            config: config,
            appStoreConnect: baseContext.appStoreConnect,
            platform: .ios
        )

        _ = try await ExportAction().run(with: .init(), context: context)

        let arguments = capturedCommand?.arguments ?? []
        #expect(arguments.contains("-authenticationKeyID"))
        #expect(arguments.contains("KEY123"))
        #expect(arguments.contains("-authenticationKeyIssuerID"))
        #expect(arguments.contains("ISSUER456"))
        #expect(arguments.contains("-authenticationKeyPath"))
        if let index = arguments.firstIndex(of: "-authenticationKeyPath"), index + 1 < arguments.count {
            #expect(!FileManager.default.fileExists(atPath: arguments[index + 1]))
        }
    }

    @Test("ExportAction does not pass -allowProvisioningUpdates for manual signing")
    func exportActionManualSigning() async throws {
        nonisolated(unsafe) var capturedCommand: Command?

        let exportDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try Data().write(to: exportDirectory.appendingPathComponent("MockApp.ipa"))

        let archiveDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: archiveDirectory) }
        let archivePath = archiveDirectory.appendingPathComponent("MockApp.xcarchive").path
        FileManager.default.createFile(atPath: archivePath, contents: Data())

        let executor = MockExecutor { command, _ in
            capturedCommand = command
            return ShellOutput(stdout: "Export Succeeded\n", stderr: "", exitCode: 0)
        }

        let baseContext = ActionContext.mock(executor: executor)
        let config = ResolvedConfig(
            teamID: "TEAM12345",
            archiveOutputPath: archivePath,
            exportOutputDirectory: exportDirectory.path,
            automaticCodeSigning: false
        )
        let context = ActionContext(
            shell: baseContext.shell,
            logger: baseContext.logger,
            config: config,
            appStoreConnect: baseContext.appStoreConnect,
            platform: .ios
        )

        _ = try await ExportAction().run(with: .init(), context: context)

        #expect(
            capturedCommand?.arguments.contains("-allowProvisioningUpdates") != true,
            "Manual signing should NOT pass -allowProvisioningUpdates")
    }

    @Test("ExportAction omits teamID key from plist when teamID is not configured")
    func exportActionNoTeamID() async throws {
        nonisolated(unsafe) var plistContents: String?

        let exportDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try Data().write(to: exportDirectory.appendingPathComponent("MockApp.ipa"))

        let archiveDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: archiveDirectory) }
        let archivePath = archiveDirectory.appendingPathComponent("MockApp.xcarchive").path
        FileManager.default.createFile(atPath: archivePath, contents: Data())

        let executor = MockExecutor { command, _ in
            if let plistIndex = command.arguments.firstIndex(of: "-exportOptionsPlist"),
                plistIndex + 1 < command.arguments.count
            {
                plistContents = try String(
                    contentsOfFile: command.arguments[plistIndex + 1],
                    encoding: .utf8
                )
            }
            return ShellOutput(stdout: "Export Succeeded\n", stderr: "", exitCode: 0)
        }

        let baseContext = ActionContext.mock(executor: executor)
        let config = ResolvedConfig(
            archiveOutputPath: archivePath,
            exportOutputDirectory: exportDirectory.path
                // teamID intentionally omitted
        )
        let context = ActionContext(
            shell: baseContext.shell,
            logger: baseContext.logger,
            config: config,
            appStoreConnect: baseContext.appStoreConnect,
            platform: .ios
        )

        _ = try await ExportAction().run(with: .init(), context: context)

        guard let plistContents else {
            Issue.record("Expected export options plist contents to be captured")
            return
        }

        #expect(!plistContents.contains("<key>teamID</key>"), "Should omit teamID when not configured")
    }

    @Test("ExportAction writes the export method to the options plist")
    func exportActionWritesMethodToPlist() async throws {
        nonisolated(unsafe) var plistContents: String?

        let exportDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try Data().write(to: exportDirectory.appendingPathComponent("MockApp.ipa"))

        let archiveDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: archiveDirectory) }
        let archivePath = archiveDirectory.appendingPathComponent("MockApp.xcarchive").path
        FileManager.default.createFile(atPath: archivePath, contents: Data())

        let executor = MockExecutor { command, _ in
            if let plistIndex = command.arguments.firstIndex(of: "-exportOptionsPlist"),
                plistIndex + 1 < command.arguments.count
            {
                plistContents = try String(
                    contentsOfFile: command.arguments[plistIndex + 1],
                    encoding: .utf8
                )
            }
            return ShellOutput(stdout: "Export Succeeded\n", stderr: "", exitCode: 0)
        }

        let baseContext = ActionContext.mock(executor: executor)
        let config = ResolvedConfig(
            archiveExportMethod: "ad-hoc",
            archiveOutputPath: archivePath,
            exportOutputDirectory: exportDirectory.path
        )
        let context = ActionContext(
            shell: baseContext.shell,
            logger: baseContext.logger,
            config: config,
            appStoreConnect: baseContext.appStoreConnect,
            platform: .ios
        )

        _ = try await ExportAction().run(with: .init(), context: context)

        guard let plistContents else {
            Issue.record("Expected export options plist contents to be captured")
            return
        }

        #expect(plistContents.contains("<key>method</key>"), "Plist should contain method key")
        #expect(plistContents.contains("<string>ad-hoc</string>"), "Plist should contain ad-hoc export method")
    }

    @Test("ArchiveAction uses full Android build variant in Gradle task")
    func archiveActionUsesFullAndroidVariantTask() async throws {
        let tmpDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let aabPath = tmpDir.appendingPathComponent("app/build/outputs/bundle/prodRelease/app-prod-release.aab")
        try FileManager.default.createDirectory(at: aabPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("aab".utf8).write(to: aabPath)

        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL\n", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            androidModule: "app",
            androidBuildVariant: "prodRelease",
            gradleProjectDir: tmpDir.path
        )
        let shell = ShellContext(executor: executor, workingDirectory: tmpDir.path)
        let context = makeTestActionContext(shell: shell, config: config, platform: .android)

        _ = try await ArchiveAction().run(with: .init(), context: context)

        #expect(commands().contains { $0.contains(":app:bundleProdRelease") })
    }

    @Test("ExportAction throws for Flutter iOS build system")
    func exportActionThrowsForFlutter() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let config = ResolvedConfig(iosBuildSystem: .flutter)
        let context = ActionContext(
            shell: ActionContext.mock(executor: executor).shell,
            logger: ActionContext.mock(executor: executor).logger,
            config: config,
            appStoreConnect: ActionContext.mock(executor: executor).appStoreConnect,
            platform: .ios
        )

        await #expect {
            _ = try await ExportAction().run(with: .init(), context: context)
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("Flutter") && reason.contains("export")
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
