#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("TestFlightAction", .serialized)
struct TestFlightActionTests {

    @Test("distributes uploaded build using app beta groups and 204 relationship response")
    func distributesBuildToRequestedGroups() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Example.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        nonisolated(unsafe) var betaGroupQuery: [String: String] = [:]

        let executor = MockExecutor { command, _ in
            // xcrun altool --upload-app → success
            if command.arguments.first == "altool" {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            // Typed plutil pipeline stage returns build version "1".
            if command.executableName == "plutil" {
                return ShellOutput(stdout: "1\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

            // App lookup
            if path == "/v1/apps", query["filter[bundleId]"] == "com.example.app" {
                return .json([
                    "data": [
                        [
                            "id": "app-1",
                            "attributes": ["bundleId": "com.example.app", "name": "Example"],
                        ]
                    ]
                ])
            }

            // Build lookup after altool upload (polling by version)
            if path == "/v1/builds", query["filter[version]"] == "1" {
                return .json([
                    "data": [["id": "build-123", "attributes": ["version": "1"]]]
                ])
            }

            // Build processing status check
            if path == "/v1/builds/build-123", request.httpMethod == "GET" {
                return .json([
                    "data": [
                        "id": "build-123",
                        "attributes": ["processingState": "VALID", "version": "1"],
                    ]
                ])
            }

            // Beta groups
            if path == "/v1/betaGroups", request.httpMethod == "GET" {
                betaGroupQuery = query
                return .json([
                    "data": [
                        [
                            "id": "group-1",
                            "attributes": ["name": "Internal QA"],
                        ]
                    ]
                ])
            }

            // Distribute to group
            if path == "/v1/betaGroups/group-1/relationships/builds", request.httpMethod == "POST" {
                return .empty(statusCode: 204)
            }

            return .error(statusCode: 404, body: "not found")
        }

        let base = ActionContext.mock(executor: executor)
        let shell = isolatedShell(from: base.shell, executor: executor)
        let client = AppStoreConnectClient(
            keyID: "TESTKEY",
            issuerID: "test-issuer",
            privateKeyData: Data("placeholder".utf8),
            session: session,
            tokenProvider: { "test-token" }
        )
        let context = ActionContext(
            shell: shell,
            logger: base.logger,
            config: ResolvedConfig(
                bundleID: "com.example.app",
                ascKeyID: "TESTKEY",
                ascIssuerID: "test-issuer",
                ascPrivateKeyData: Data(
                    "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n".utf8
                )
            ),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await TestFlightAction().run(
            with: .init(
                ipa: ipaURL.path,
                groups: ["Internal QA"],
                skipWaitingForBuildProcessing: false
            ),
            context: context
        )

        #expect(result.buildID == "build-123")
        #expect(result.processingComplete)
        #expect(result.distributedGroups == ["Internal QA"])
        #expect(betaGroupQuery["filter[app]"] == "app-1")
        #expect(betaGroupQuery["filter[builds]"] == nil)
    }

    @Test("skip waiting with no groups does not resolve build ID")
    func skipsBuildLookupWhenWaitingAndDistributionAreDisabled() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Example.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        nonisolated(unsafe) var ascWasCalled = false

        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let session = makeMockSession { _ in
            ascWasCalled = true
            return .error(statusCode: 500, body: "unexpected request")
        }

        let base = ActionContext.mock(executor: executor)
        let shell = isolatedShell(from: base.shell, executor: executor)
        let client = AppStoreConnectClient(
            keyID: "TESTKEY",
            issuerID: "test-issuer",
            privateKeyData: Data("placeholder".utf8),
            session: session,
            tokenProvider: { "test-token" }
        )
        let context = ActionContext(
            shell: shell,
            logger: base.logger,
            config: ResolvedConfig(
                bundleID: "com.example.app",
                ascKeyID: "TESTKEY",
                ascIssuerID: "test-issuer",
                ascPrivateKeyData: Data(
                    "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n".utf8
                ),
                skipWaitingForBuildProcessing: true
            ),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await TestFlightAction().run(
            with: .init(ipa: ipaURL.path),
            context: context
        )

        #expect(result.buildID == nil)
        #expect(result.processingComplete == false)
        #expect(result.distributedGroups.isEmpty)
        #expect(ascWasCalled == false)
    }

    @Test("Flutter iOS TestFlight discovers IPA from flutter archive output")
    func discoversFlutterIPAOutput() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaDirectory = tempDirectory.appendingPathComponent("build/ios/ipa", isDirectory: true)
        try FileManager.default.createDirectory(at: ipaDirectory, withIntermediateDirectories: true)
        try Data("ipa-data".utf8).write(to: ipaDirectory.appendingPathComponent("Example.ipa"))

        let executor = MockExecutor { command, _ in
            if command.arguments.first == "altool" {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            if command.executableName == "plutil" {
                return ShellOutput(stdout: "1\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
            if path == "/v1/apps" {
                return .json(["data": [["id": "app-1", "attributes": ["bundleId": "com.example.app"]]]])
            }
            if path == "/v1/builds", query["filter[version]"] == "1" {
                return .json(["data": [["id": "build-123", "attributes": ["version": "1"]]]])
            }
            return .error(statusCode: 404, body: "not found")
        }

        let base = ActionContext.mock(executor: executor)
        let shell = ShellContext(
            executor: executor,
            searchPaths: base.shell.searchPaths,
            environment: base.shell.environment,
            workingDirectory: tempDirectory.path,
            defaultTimeout: base.shell.defaultTimeout,
            defaultOutputLimit: base.shell.defaultOutputLimit
        )
        let client = AppStoreConnectClient(
            keyID: "TESTKEY",
            issuerID: "test-issuer",
            privateKeyData: Data("placeholder".utf8),
            session: session,
            tokenProvider: { "test-token" }
        )
        let context = ActionContext(
            shell: shell,
            logger: base.logger,
            config: ResolvedConfig(
                bundleID: "com.example.app",
                ascKeyID: "TESTKEY",
                ascIssuerID: "test-issuer",
                ascPrivateKeyData: Data("-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n".utf8),
                skipWaitingForBuildProcessing: true,
                iosBuildSystem: .flutter
            ),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await TestFlightAction().run(
            with: .init(skipWaitingForBuildProcessing: true),
            context: context
        )

        #expect(result.buildID == nil)
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func isolatedShell(from shell: ShellContext, executor: MockExecutor) -> ShellContext {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-testflight-home-\(UUID().uuidString)", isDirectory: true)
        return ShellContext(
            executor: executor,
            searchPaths: shell.searchPaths,
            environment: shell.environment.merging(["HOME": homeURL.path]) { _, new in new },
            workingDirectory: shell.workingDirectory,
            defaultTimeout: shell.defaultTimeout,
            defaultOutputLimit: shell.defaultOutputLimit
        )
    }
}
#endif
