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
