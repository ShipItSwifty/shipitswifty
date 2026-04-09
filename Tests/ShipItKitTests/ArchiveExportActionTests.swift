import Foundation
import Testing
import SwiftyShell
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
               plistIndex + 1 < command.arguments.count {
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

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
