import Foundation
import Testing
import SwiftyShell
@testable import ShipItKit

@Suite("SignAction")
struct SignActionTests {

    // MARK: - Platform guard

    @Test("run throws invalidConfiguration when platform is android")
    func runThrowsOnAndroidPlatform() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let base = ActionContext.mock(executor: executor)
        let context = ActionContext(
            shell: base.shell,
            logger: base.logger,
            config: ResolvedConfig(),
            appStoreConnect: base.appStoreConnect,
            platform: .android
        )

        do {
            _ = try await SignAction().run(with: .init(operation: .cleanup), context: context)
            Issue.record("Expected invalidConfiguration to be thrown")
        } catch ShipItError.invalidConfiguration {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    // MARK: - .cleanup

    @Test("cleanup issues delete-keychain and list-keychains")
    func cleanupCommandSequence() async throws {
        nonisolated(unsafe) var capturedArgs: [[String]] = []
        let executor = MockExecutor { command, _ in
            capturedArgs.append(command.arguments)
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let result = try await SignAction().run(
            with: .init(operation: .cleanup),
            context: ActionContext.mock(executor: executor)
        )

        #expect(result.operation == "cleanup")
        #expect(result.success == true)
        let deletesKeychain = capturedArgs.contains(where: { $0.first == "delete-keychain" })
        #expect(deletesKeychain, "Should issue delete-keychain")
        let restoresList = capturedArgs.contains(where: { $0.first == "list-keychains" })
        #expect(restoresList, "Should restore default search list via list-keychains")
    }

    @Test("cleanup succeeds even when delete-keychain fails (idempotent)")
    func cleanupIsIdempotent() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "keychain does not exist", exitCode: 1)
        }

        await #expect(throws: Never.self) {
            _ = try await SignAction().run(
                with: .init(operation: .cleanup),
                context: ActionContext.mock(executor: executor)
            )
        }
    }

    // MARK: - .sync

    @Test("sync throws invalidConfiguration when gitUrl is absent")
    func syncThrowsWithoutGitUrl() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let base = ActionContext.mock(executor: executor)
        let context = ActionContext(
            shell: base.shell,
            logger: base.logger,
            config: ResolvedConfig(),   // no codeSigningGitUrl
            appStoreConnect: base.appStoreConnect,
            platform: .ios
        )

        do {
            _ = try await SignAction().run(with: .init(operation: .sync), context: context)
            Issue.record("Expected invalidConfiguration to be thrown")
        } catch ShipItError.invalidConfiguration {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    @Test("sync issues git clone --depth 1 with the provided gitUrl")
    func syncIssuesShallowClone() async throws {
        nonisolated(unsafe) var cloneArgs: [String] = []
        let executor = MockExecutor { command, _ in
            // Command("git", "clone", ...) → arguments = ["clone", ...]
            if command.arguments.first == "clone" {
                cloneArgs = command.arguments
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        _ = try await SignAction().run(
            with: .init(operation: .sync, gitUrl: "git@github.com:team/certs.git"),
            context: ActionContext.mock(executor: executor)
        )

        #expect(!cloneArgs.isEmpty, "Should issue a git clone command")
        #expect(cloneArgs.contains("--depth"), "Should perform a shallow clone")
        #expect(cloneArgs.contains("1"), "Depth should be 1")
        #expect(cloneArgs.contains("git@github.com:team/certs.git"), "Should use provided URL")
    }

    @Test("sync in CI mode creates a temporary keychain after cloning")
    func syncCiModeCreatesTemporaryKeychain() async throws {
        nonisolated(unsafe) var capturedArgs: [[String]] = []
        let executor = MockExecutor { command, _ in
            capturedArgs.append(command.arguments)
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        _ = try await SignAction().run(
            with: .init(operation: .sync, ci: true, gitUrl: "git@github.com:team/certs.git"),
            context: ActionContext.mock(executor: executor)
        )

        // Command("git", "clone", ...) → arguments = ["clone", ...]
        let hasClone = capturedArgs.contains(where: { $0.first == "clone" })
        let hasCreateKeychain = capturedArgs.contains(where: { $0.first == "create-keychain" })

        #expect(hasClone, "Should clone the repository first")
        #expect(hasCreateKeychain, "CI mode should create a temporary keychain")

        // Clone should come before keychain creation
        let cloneIndex = capturedArgs.firstIndex(where: { $0.first == "clone" })
        let createIndex = capturedArgs.firstIndex(where: { $0.first == "create-keychain" })
        if let c = cloneIndex, let k = createIndex {
            #expect(c < k, "Clone should happen before keychain creation")
        }
    }

    @Test("sync returns success result")
    func syncReturnsSuccessResult() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }

        let result = try await SignAction().run(
            with: .init(operation: .sync, type: "appstore", gitUrl: "git@github.com:team/certs.git"),
            context: ActionContext.mock(executor: executor)
        )

        #expect(result.operation == "sync")
        #expect(result.success == true)
    }

    @Test("sync throws signingResourceNotFound when git clone fails")
    func syncThrowsWhenCloneFails() async throws {
        let executor = MockExecutor { command, _ in
            // Command("git", "clone", ...) → arguments = ["clone", ...]
            if command.arguments.first == "clone" {
                return ShellOutput(stdout: "", stderr: "fatal: repository not found", exitCode: 128)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        do {
            _ = try await SignAction().run(
                with: .init(operation: .sync, gitUrl: "git@github.com:team/certs.git"),
                context: ActionContext.mock(executor: executor)
            )
            Issue.record("Expected signingResourceNotFound to be thrown")
        } catch ShipItError.signingResourceNotFound {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    @Test("manual sync installs certificate and provisioning profile without cloning")
    func manualSyncInstallsConfiguredAssets() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let p12URL = tempDirectory.appendingPathComponent("distribution.p12")
        let profileURL = tempDirectory.appendingPathComponent("AppStore.mobileprovision")
        try Data("p12".utf8).write(to: p12URL)
        try Data("profile".utf8).write(to: profileURL)

        nonisolated(unsafe) var capturedArgs: [[String]] = []
        let executor = MockExecutor { command, _ in
            capturedArgs.append(command.arguments)
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let base = ActionContext.mock(executor: executor)
        let context = ActionContext(
            shell: base.shell,
            logger: base.logger,
            config: ResolvedConfig(
                codeSigningType: "manual",
                codeSigningP12Path: p12URL.path,
                codeSigningP12Password: "p12pass",
                codeSigningProvisioningProfilePath: profileURL.path
            ),
            appStoreConnect: base.appStoreConnect,
            platform: .ios
        )

        let result = try await SignAction().run(with: .init(operation: .sync), context: context)

        #expect(result.operation == "sync")
        #expect(result.success)
        #expect(!capturedArgs.contains(where: { $0.first == "clone" }), "Manual sync should not clone vault storage")
        #expect(capturedArgs.contains(where: { $0.first == "import" && $0.contains(p12URL.path) }))

        let installedProfile = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles/AppStore.mobileprovision")
        defer { try? FileManager.default.removeItem(at: installedProfile) }
        #expect(FileManager.default.fileExists(atPath: installedProfile.path))
    }

    @Test("manual sync writes base64 assets to temporary files before installing")
    func manualSyncInstallsBase64Assets() async throws {
        nonisolated(unsafe) var importArgs: [String] = []
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "import" {
                importArgs = command.arguments
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let base = ActionContext.mock(executor: executor)
        let context = ActionContext(
            shell: base.shell,
            logger: base.logger,
            config: ResolvedConfig(
                codeSigningType: "manual",
                codeSigningP12Data: Data("p12".utf8),
                codeSigningP12Password: "p12pass",
                codeSigningProvisioningProfileData: Data("profile".utf8)
            ),
            appStoreConnect: base.appStoreConnect,
            platform: .ios
        )

        let result = try await SignAction().run(with: .init(operation: .sync), context: context)

        #expect(result.success)
        let installedP12Path = try #require(importArgs.first(where: { $0.hasSuffix("certificate.p12") }))
        #expect(!FileManager.default.fileExists(atPath: installedP12Path), "Temporary decoded p12 should be cleaned up after install")

        let installedProfile = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles/profile.mobileprovision")
        defer { try? FileManager.default.removeItem(at: installedProfile) }
        let profileData = try Data(contentsOf: installedProfile)
        #expect(profileData == Data("profile".utf8))
    }

    // MARK: - .init

    @Test("init throws invalidConfiguration when gitUrl is absent")
    func initThrowsWithoutGitUrl() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let base = ActionContext.mock(executor: executor)
        let context = ActionContext(
            shell: base.shell,
            logger: base.logger,
            config: ResolvedConfig(),   // no codeSigningGitUrl
            appStoreConnect: base.appStoreConnect,
            platform: .ios
        )

        do {
            _ = try await SignAction().run(with: .init(operation: .`init`), context: context)
            Issue.record("Expected invalidConfiguration to be thrown")
        } catch ShipItError.invalidConfiguration {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    @Test("init issues git clone (or git init) for the provided gitUrl")
    func initIssuesGitOperation() async throws {
        nonisolated(unsafe) var capturedArgs: [[String]] = []
        let executor = MockExecutor { command, _ in
            capturedArgs.append(command.arguments)
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        _ = try await SignAction().run(
            with: .init(operation: .`init`, gitUrl: "git@github.com:team/certs.git"),
            context: ActionContext.mock(executor: executor)
        )

        // Command("git", "clone"/"init", ...) → arguments = ["clone"/"init", ...]
        let hasGitOp = capturedArgs.contains(where: { $0.first == "clone" || $0.first == "init" })
        #expect(hasGitOp, "Should issue a git operation for the repository URL")
    }

    // MARK: - .import

    @Test("import throws invalidConfiguration when p12Path is absent")
    func importThrowsWithoutP12Path() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        do {
            _ = try await SignAction().run(
                with: .init(
                    operation: .`import`,
                    gitUrl: "git@github.com:team/certs.git",
                    provisioningProfilePath: "/tmp/profile.mobileprovision"
                ),
                context: ActionContext.mock(executor: executor)
            )
            Issue.record("Expected invalidConfiguration to be thrown")
        } catch ShipItError.invalidConfiguration {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    @Test("import throws invalidConfiguration when provisioningProfilePath is absent")
    func importThrowsWithoutProfilePath() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        do {
            _ = try await SignAction().run(
                with: .init(
                    operation: .`import`,
                    gitUrl: "git@github.com:team/certs.git",
                    p12Path: "/tmp/cert.p12"
                ),
                context: ActionContext.mock(executor: executor)
            )
            Issue.record("Expected invalidConfiguration to be thrown")
        } catch ShipItError.invalidConfiguration {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    @Test("import throws invalidConfiguration when gitUrl is absent")
    func importThrowsWithoutGitUrl() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let base = ActionContext.mock(executor: executor)
        let context = ActionContext(
            shell: base.shell,
            logger: base.logger,
            config: ResolvedConfig(),   // no codeSigningGitUrl
            appStoreConnect: base.appStoreConnect,
            platform: .ios
        )

        do {
            _ = try await SignAction().run(
                with: .init(
                    operation: .`import`,
                    p12Path: "/tmp/cert.p12",
                    provisioningProfilePath: "/tmp/profile.mobileprovision"
                ),
                context: context
            )
            Issue.record("Expected invalidConfiguration to be thrown")
        } catch ShipItError.invalidConfiguration {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    @Test("import returns success when all required options are provided")
    func importSucceedsWithAllOptions() async throws {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }

        let result = try await SignAction().run(
            with: .init(
                operation: .`import`,
                gitUrl: "git@github.com:team/certs.git",
                p12Path: "/tmp/cert.p12",
                provisioningProfilePath: "/tmp/profile.mobileprovision"
            ),
            context: ActionContext.mock(executor: executor)
        )

        #expect(result.operation == "import")
        #expect(result.success == true)
    }
}
