import Foundation
import Testing
import SwiftyShell
@testable import ShipItKit

/// Tests for `IPAUploadService`.
///
/// The new implementation delegates the actual binary transfer to
/// `xcrun altool --upload-app` rather than the ASC REST API (which does not
/// allow `POST /v1/builds`).  These tests mock both the shell executor and the
/// HTTP session so no real processes or network calls are made.
@Suite("IPAUploadService", .serialized)
struct IPAUploadServiceTests {

    // MARK: - Credential guard tests

    @Test("throws invalidConfiguration when ascKeyID is missing")
    func throwsMissingKeyID() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        let context = makeContext(keyID: nil, issuerID: "issuer", keyData: Data("pem".utf8))
        let client = makeClient(responses: [])

        await #expect {
            _ = try await IPAUploadService(client: client).uploadIPA(
                at: ipaURL, bundleID: "com.example.app", context: context
            )
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }

    @Test("throws invalidConfiguration when ascIssuerID is missing")
    func throwsMissingIssuerID() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        let context = makeContext(keyID: "KEY", issuerID: nil, keyData: Data("pem".utf8))
        let client = makeClient(responses: [])

        await #expect {
            _ = try await IPAUploadService(client: client).uploadIPA(
                at: ipaURL, bundleID: "com.example.app", context: context
            )
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }

    @Test("throws invalidConfiguration when ascPrivateKeyData is missing")
    func throwsMissingPrivateKey() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        let context = makeContext(keyID: "KEY", issuerID: "issuer", keyData: nil)
        let client = makeClient(responses: [])

        await #expect {
            _ = try await IPAUploadService(client: client).uploadIPA(
                at: ipaURL, bundleID: "com.example.app", context: context
            )
        } throws: { error in
            guard case ShipItError.invalidConfiguration = error else { return false }
            return true
        }
    }

    // MARK: - File guard

    @Test("throws uploadFailed when IPA file does not exist")
    func throwsWhenIPANotFound() async throws {
        let ipaURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).ipa")
        let context = makeContext()
        let client = makeClient(responses: [])

        await #expect {
            _ = try await IPAUploadService(client: client).uploadIPA(
                at: ipaURL, bundleID: "com.example.app", context: context
            )
        } throws: { error in
            guard case ShipItError.uploadFailed = error else { return false }
            return true
        }
    }

    // MARK: - altool invocation

    @Test("invokes xcrun altool with upload-app, apiKey, and apiIssuer flags")
    func altoolCommandFlags() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        nonisolated(unsafe) var capturedArgs: [String] = []

        let executor = MockExecutor { command, _ in
            // xcrun altool … → arguments = ["altool", "--upload-app", …]
            if command.arguments.first == "altool" {
                capturedArgs = command.arguments
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            // bash -c "unzip | plutil" → return a build version
            if command.arguments.first == "-c" {
                return ShellOutput(stdout: "42\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = makeContext(executor: executor)
        let client = makeMockSession { request in
            let path = request.url?.path ?? ""
            if path == "/v1/apps" {
                return .json(["data": [["id": "app-1", "attributes": ["bundleId": "com.example.app"]]]])
            }
            if path == "/v1/builds" {
                return .json(["data": [["id": "build-99", "attributes": ["version": "42"]]]])
            }
            return .error(statusCode: 404, body: "not found")
        }
        let ascClient = AppStoreConnectClient(
            keyID: "TESTKEY", issuerID: "test-issuer",
            privateKeyData: Data("placeholder".utf8),
            session: client, tokenProvider: { "test-token" }
        )

        _ = try await IPAUploadService(client: ascClient, pollMaxAttempts: 1, pollDelaySeconds: 0)
            .uploadIPA(at: ipaURL, bundleID: "com.example.app", context: context)

        #expect(capturedArgs.contains("--upload-app"))
        #expect(capturedArgs.contains("--apiKey"))
        #expect(capturedArgs.contains("TESTKEY"))
        #expect(capturedArgs.contains("--apiIssuer"))
        #expect(capturedArgs.contains("test-issuer-id"))
        #expect(capturedArgs.contains("-f"))
        #expect(capturedArgs.contains(ipaURL.path))
    }

    @Test("throws uploadFailed when altool exits with non-zero code")
    func throwsWhenAltoolFails() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        let executor = MockExecutor { command, _ in
            if command.arguments.first == "altool" {
                return ShellOutput(stdout: "", stderr: "invalid credentials", exitCode: 1)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = makeContext(executor: executor)
        let client = makeClient(responses: [])

        await #expect {
            _ = try await IPAUploadService(client: client).uploadIPA(
                at: ipaURL, bundleID: "com.example.app", context: context
            )
        } throws: { error in
            guard case ShipItError.uploadFailed = error else { return false }
            return true
        }
    }

    @Test("skips ASC lookup when resolveBuildID is false")
    func skipsBuildLookupWhenNotNeeded() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        nonisolated(unsafe) var extractedBuildVersion = false
        nonisolated(unsafe) var ascWasCalled = false

        let executor = MockExecutor { command, _ in
            if command.arguments.first == "-c" {
                extractedBuildVersion = true
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = makeContext(executor: executor)
        let session = makeMockSession { _ in
            ascWasCalled = true
            return .error(statusCode: 500, body: "unexpected request")
        }
        let client = AppStoreConnectClient(
            keyID: "TESTKEY", issuerID: "test-issuer",
            privateKeyData: Data("placeholder".utf8),
            session: session, tokenProvider: { "test-token" }
        )

        let result = try await IPAUploadService(client: client)
            .uploadIPA(
                at: ipaURL,
                bundleID: "com.example.app",
                context: context,
                resolveBuildID: false
            )

        #expect(result.appID == nil)
        #expect(result.buildID == nil)
        #expect(result.fileName == ipaURL.lastPathComponent)
        #expect(extractedBuildVersion == false)
        #expect(ascWasCalled == false)
    }

    // MARK: - Post-upload ASC resolution

    @Test("throws apiError(404) when app is not found in ASC")
    func throwsWhenAppNotFound() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        let executor = MockExecutor { command, _ in
            if command.arguments.first == "-c" {
                return ShellOutput(stdout: "99\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = makeContext(executor: executor)
        // Apps endpoint returns empty list
        let client = makeClient(responses: [.json(["data": []])])

        await #expect {
            _ = try await IPAUploadService(client: client, pollMaxAttempts: 1, pollDelaySeconds: 0)
                .uploadIPA(at: ipaURL, bundleID: "com.example.missing", context: context)
        } throws: { error in
            guard case ShipItError.apiError(let code, _) = error else { return false }
            return code == 404
        }
    }

    @Test("throws uploadFailed when build does not appear in ASC after polling")
    func throwsWhenBuildNeverAppears() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        let executor = MockExecutor { command, _ in
            if command.arguments.first == "-c" {
                return ShellOutput(stdout: "77\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = makeContext(executor: executor)
        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            if path == "/v1/apps" {
                return .json(["data": [["id": "app-1", "attributes": ["bundleId": "com.example.app"]]]])
            }
            // Builds endpoint always returns empty — simulates build not registered yet
            if path == "/v1/builds" {
                return .json(["data": []])
            }
            return .error(statusCode: 404, body: "not found")
        }
        let client = AppStoreConnectClient(
            keyID: "TESTKEY", issuerID: "test-issuer",
            privateKeyData: Data("placeholder".utf8),
            session: session, tokenProvider: { "test-token" }
        )

        // pollMaxAttempts: 2, pollDelaySeconds: 0 → fast failure without real sleep
        await #expect {
            _ = try await IPAUploadService(client: client, pollMaxAttempts: 2, pollDelaySeconds: 0)
                .uploadIPA(at: ipaURL, bundleID: "com.example.app", context: context)
        } throws: { error in
            guard case ShipItError.uploadFailed = error else { return false }
            return true
        }
    }

    @Test("returns build ID found in ASC after successful altool upload")
    func returnsResolvedBuildID() async throws {
        let ipaURL = try makeTempIPA()
        defer { try? FileManager.default.removeItem(at: ipaURL) }

        let executor = MockExecutor { command, _ in
            if command.arguments.first == "-c" {
                return ShellOutput(stdout: "123\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let context = makeContext(executor: executor)
        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            if path == "/v1/apps" {
                return .json(["data": [["id": "app-1", "attributes": ["bundleId": "com.example.app"]]]])
            }
            if path == "/v1/builds" {
                return .json(["data": [["id": "build-abc", "attributes": ["version": "123"]]]])
            }
            return .error(statusCode: 404, body: "not found")
        }
        let client = AppStoreConnectClient(
            keyID: "TESTKEY", issuerID: "test-issuer",
            privateKeyData: Data("placeholder".utf8),
            session: session, tokenProvider: { "test-token" }
        )

        let result = try await IPAUploadService(client: client, pollMaxAttempts: 1, pollDelaySeconds: 0)
            .uploadIPA(at: ipaURL, bundleID: "com.example.app", context: context)

        #expect(result.buildID == "build-abc")
        #expect(result.appID == "app-1")
        #expect(result.fileName == ipaURL.lastPathComponent)
    }

    // MARK: - Helpers

    private func makeTempIPA() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).ipa")
        try Data("ipa-placeholder".utf8).write(to: url)
        return url
    }

    /// Builds an `ActionContext` with the given credentials, defaulting to
    /// valid stub values so tests only need to override the field under test.
    private func makeContext(
        keyID: String? = "TESTKEY",
        issuerID: String? = "test-issuer-id",
        keyData: Data? = Data("-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n".utf8),
        executor: MockExecutor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    ) -> ActionContext {
        let base = ActionContext.mock(executor: executor)
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-ipa-upload-home-\(UUID().uuidString)", isDirectory: true)
        let shell = ShellContext(
            executor: executor,
            searchPaths: base.shell.searchPaths,
            environment: base.shell.environment.merging(["HOME": homeURL.path]) { _, new in new },
            workingDirectory: base.shell.workingDirectory,
            defaultTimeout: base.shell.defaultTimeout,
            defaultOutputLimit: base.shell.defaultOutputLimit
        )
        return ActionContext(
            shell: shell,
            logger: base.logger,
            config: ResolvedConfig(
                ascKeyID: keyID,
                ascIssuerID: issuerID,
                ascPrivateKeyData: keyData
            ),
            appStoreConnect: base.appStoreConnect,
            platform: .ios
        )
    }
}
