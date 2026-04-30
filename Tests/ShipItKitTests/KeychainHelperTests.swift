import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("KeychainHelper")
struct KeychainHelperTests {

    // MARK: - createTemporaryKeychain

    @Test("createTemporaryKeychain issues create, settings, search-list, and unlock commands")
    func createTemporaryKeychainCommandSequence() async throws {
        nonisolated(unsafe) var capturedArgs: [[String]] = []
        let executor = MockExecutor { command, _ in
            capturedArgs.append(command.arguments)
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        try await KeychainHelper().createTemporaryKeychain(
            name: "test.keychain", password: "s3cret", context: context
        )

        #expect(capturedArgs.contains(where: { $0.first == "create-keychain" }), "Should create keychain")
        #expect(capturedArgs.contains(where: { $0.first == "set-keychain-settings" }), "Should configure settings")
        #expect(capturedArgs.contains(where: { $0.first == "list-keychains" }), "Should add to search list")
        #expect(capturedArgs.contains(where: { $0.first == "unlock-keychain" }), "Should unlock")
    }

    @Test("createTemporaryKeychain embeds name and password in create-keychain call")
    func createTemporaryKeychainUsesProvidedCredentials() async throws {
        nonisolated(unsafe) var createArgs: [String] = []
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "create-keychain" { createArgs = command.arguments }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        try await KeychainHelper().createTemporaryKeychain(
            name: "build.keychain", password: "hunter2", context: context
        )

        #expect(createArgs.contains("build.keychain"))
        #expect(createArgs.contains("hunter2"))
    }

    @Test("createTemporaryKeychain uses the default keychain name when none is given")
    func createTemporaryKeychainDefaultName() async throws {
        nonisolated(unsafe) var createArgs: [String] = []
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "create-keychain" { createArgs = command.arguments }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        try await KeychainHelper().createTemporaryKeychain(
            password: "pass", context: ActionContext.mock(executor: executor)
        )

        #expect(createArgs.contains(KeychainHelper.temporaryKeychainName))
    }

    @Test("createTemporaryKeychain throws keychainError when create-keychain fails")
    func createTemporaryKeychainThrowsOnCreateFailure() async throws {
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "create-keychain" {
                return ShellOutput(stdout: "", stderr: "security: keychain already exists", exitCode: 1)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        do {
            try await KeychainHelper().createTemporaryKeychain(password: "pass", context: context)
            Issue.record("Expected keychainError to be thrown")
        } catch ShipItError.keychainError {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    @Test("createTemporaryKeychain succeeds when set-keychain-settings fails (non-fatal)")
    func createTemporaryKeychainToleratesSettingsFailure() async throws {
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "set-keychain-settings" {
                return ShellOutput(stdout: "", stderr: "error", exitCode: 1)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(executor: executor)

        await #expect(throws: Never.self) {
            try await KeychainHelper().createTemporaryKeychain(password: "pass", context: context)
        }
    }

    @Test("createTemporaryKeychain succeeds when list-keychains fails (non-fatal)")
    func createTemporaryKeychainToleratesSearchListFailure() async throws {
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "list-keychains" {
                return ShellOutput(stdout: "", stderr: "error", exitCode: 1)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        await #expect(throws: Never.self) {
            try await KeychainHelper().createTemporaryKeychain(
                password: "pass", context: ActionContext.mock(executor: executor)
            )
        }
    }

    // MARK: - installCertificate

    @Test("installCertificate passes p12 path, keychain, password, and codesign ACLs to security import")
    func installCertificateCommandShape() async throws {
        nonisolated(unsafe) var importArgs: [String] = []
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "import" { importArgs = command.arguments }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        try await KeychainHelper().installCertificate(
            p12Path: "/tmp/Dist.p12",
            password: "p12pass",
            keychainName: "ci.keychain",
            context: ActionContext.mock(executor: executor)
        )

        #expect(importArgs.contains("/tmp/Dist.p12"), "Should pass p12 path")
        #expect(importArgs.contains("-k"), "Should specify keychain flag")
        #expect(importArgs.contains("ci.keychain"), "Should use provided keychain name")
        #expect(importArgs.contains("-P"), "Should specify password flag")
        #expect(importArgs.contains("p12pass"), "Should pass p12 password")
        #expect(importArgs.contains("/usr/bin/codesign"), "Should allow codesign access")
        #expect(importArgs.contains("/usr/bin/security"), "Should allow security access")
    }

    @Test("installCertificate grants codesign access via set-key-partition-list")
    func installCertificateSetsPartitionList() async throws {
        nonisolated(unsafe) var partitionArgs: [String] = []
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "set-key-partition-list" {
                partitionArgs = command.arguments
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        try await KeychainHelper().installCertificate(
            p12Path: "/tmp/cert.p12", password: "pass", context: ActionContext.mock(executor: executor)
        )

        #expect(partitionArgs.contains("apple-tool:,apple:"), "Should allow Apple tools access")
    }

    @Test("installCertificate uses the default keychain name when none is given")
    func installCertificateDefaultKeychainName() async throws {
        nonisolated(unsafe) var importArgs: [String] = []
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "import" { importArgs = command.arguments }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        try await KeychainHelper().installCertificate(
            p12Path: "/tmp/cert.p12", password: "pass",
            context: ActionContext.mock(executor: executor)
        )

        #expect(importArgs.contains(KeychainHelper.temporaryKeychainName))
    }

    @Test("installCertificate throws keychainError when security import fails")
    func installCertificateThrowsOnImportFailure() async throws {
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "import" {
                return ShellOutput(stdout: "", stderr: "error: could not import", exitCode: 1)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        do {
            try await KeychainHelper().installCertificate(
                p12Path: "/tmp/cert.p12", password: "wrong",
                context: ActionContext.mock(executor: executor)
            )
            Issue.record("Expected keychainError to be thrown")
        } catch ShipItError.keychainError {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }

    @Test("installCertificate succeeds when set-key-partition-list fails (non-fatal)")
    func installCertificateToleratesPartitionListFailure() async throws {
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "set-key-partition-list" {
                return ShellOutput(stdout: "", stderr: "error", exitCode: 1)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        await #expect(throws: Never.self) {
            try await KeychainHelper().installCertificate(
                p12Path: "/tmp/cert.p12", password: "pass",
                context: ActionContext.mock(executor: executor)
            )
        }
    }

    // MARK: - cleanupTemporaryKeychain

    @Test("cleanupTemporaryKeychain deletes the temp keychain and restores the default search list")
    func cleanupTemporaryKeychainCommandSequence() async throws {
        nonisolated(unsafe) var capturedArgs: [[String]] = []
        let executor = MockExecutor { command, _ in
            capturedArgs.append(command.arguments)
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        try await KeychainHelper().cleanupTemporaryKeychain(context: ActionContext.mock(executor: executor))

        let deletesTemp = capturedArgs.contains(where: {
            $0.first == "delete-keychain" && $0.contains(KeychainHelper.temporaryKeychainName)
        })
        let restoresList = capturedArgs.contains(where: {
            $0.first == "list-keychains" && $0.contains("login.keychain-db")
        })

        #expect(deletesTemp, "Should delete the temporary keychain")
        #expect(restoresList, "Should restore default keychain search list")
    }

    @Test("cleanupTemporaryKeychain does not throw when the keychain does not exist")
    func cleanupTemporaryKeychainIsIdempotent() async throws {
        // All commands fail — simulates the keychain never having been created.
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "keychain does not exist", exitCode: 1)
        }

        await #expect(throws: Never.self) {
            try await KeychainHelper().cleanupTemporaryKeychain(
                context: ActionContext.mock(executor: executor)
            )
        }
    }

    // MARK: - unlockKeychain

    @Test("unlockKeychain issues security unlock-keychain with name and password")
    func unlockKeychainCommandShape() async throws {
        nonisolated(unsafe) var unlockArgs: [String] = []
        let executor = MockExecutor { command, _ in
            if command.arguments.first == "unlock-keychain" { unlockArgs = command.arguments }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        try await KeychainHelper().unlockKeychain(
            name: "myapp.keychain", password: "hunter2",
            context: ActionContext.mock(executor: executor)
        )

        #expect(unlockArgs.contains("-p"))
        #expect(unlockArgs.contains("hunter2"))
        #expect(unlockArgs.contains("myapp.keychain"))
    }

    @Test("unlockKeychain throws keychainError when security unlock-keychain fails")
    func unlockKeychainThrowsOnFailure() async throws {
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "error: could not unlock keychain", exitCode: 1)
        }

        do {
            try await KeychainHelper().unlockKeychain(
                name: "test.keychain", password: "wrong",
                context: ActionContext.mock(executor: executor)
            )
            Issue.record("Expected keychainError to be thrown")
        } catch ShipItError.keychainError {
            // success
        } catch {
            Issue.record("Wrong error type thrown: \(error)")
        }
    }
}
