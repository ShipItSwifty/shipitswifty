import Foundation
import SwiftyShell
import Synchronization
import Testing

@testable import ShipItKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("FirebaseAppDistributionAction", .serialized)
struct FirebaseAppDistributionActionTests {

    // MARK: - Helpers

    private static let iosAppID = "1:1234567890:ios:abc123"
    private static let androidAppID = "1:1234567890:android:def456"

    private func makeClient(session: URLSession) -> FirebaseAppDistributionClient {
        FirebaseAppDistributionClient(tokenProvider: { "test-token" }, session: session)
    }

    /// Creates a mock session that replays a fixed response queue in order.
    private func makeQueuedSession(_ responses: [MockHTTPResponse]) -> URLSession {
        let queue = ResponseQueue(responses)
        return makeMockSession { _ in queue.next() }
    }

    private func makeContext(workingDirectory: String, platform: Platform) -> ActionContext {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let shell = ShellContext(executor: executor, workingDirectory: workingDirectory)
        let config = ResolvedConfig(
            appScheme: "MockApp",
            bundleID: "com.example.mock",
            platform: platform
        )
        let logger = Logger.forType(subsystem: "ShipItSwiftyTests", ActionContext.self)
        #if os(macOS)
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        return ActionContext(
            shell: shell,
            logger: logger,
            config: config,
            appStoreConnect: AppStoreConnectClient(
                keyID: "MOCKKEY", issuerID: "mock-issuer-id", privateKeyData: dummyKeyData),
            platform: platform
        )
        #else
        return ActionContext(shell: shell, logger: logger, config: config, platform: platform)
        #endif
    }

    /// Creates a temporary directory containing an artifact with the given name.
    private func withArtifact<T>(
        named name: String,
        bytes: Data = Data("binary".utf8),
        _ body: (_ directory: String, _ path: String) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FirebaseAppDistTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = directory.appendingPathComponent(name)
        try bytes.write(to: artifact)
        return try await body(directory.path, artifact.path)
    }

    /// The canned upload → poll → distribute response sequence for a successful release.
    private func successResponses(releaseName: String) -> [MockHTTPResponse] {
        [
            .json(["name": "operations/upload-1"]),
            .json([
                "name": "operations/upload-1",
                "done": true,
                "response": [
                    "result": "RELEASE_CREATED",
                    "release": [
                        "name": releaseName,
                        "testingUri": "https://appdistribution.firebase.dev/i/testing",
                        "firebaseConsoleUri": "https://console.firebase.google.com/release",
                    ],
                ],
            ]),
            .json([:]),
        ]
    }

    // MARK: - App ID parsing

    @Test("Parses project number and platform out of a Firebase app ID")
    func parsesAppID() throws {
        let ios = try FirebaseAppID(Self.iosAppID)
        #expect(ios.projectNumber == "1234567890")
        #expect(ios.platform == .ios)
        #expect(ios.resourceName == "projects/1234567890/apps/\(Self.iosAppID)")

        let android = try FirebaseAppID(Self.androidAppID)
        #expect(android.platform == .android)
    }

    @Test(
        "Rejects malformed Firebase app IDs",
        arguments: [
            "", "not-an-app-id", "1:1234567890:ios", "1:1234567890:ios:abc123:extra",
            "1:abc:ios:abc123", "x:1234567890:ios:abc123", "1:1234567890:ios:zzz",
            "1:1234567890:tvos:abc123",
        ])
    func rejectsMalformedAppID(raw: String) {
        #expect(throws: ShipItError.self) { try FirebaseAppID(raw) }
    }

    @Test("Rejects web apps, which App Distribution cannot serve")
    func rejectsWebAppID() {
        #expect(throws: ShipItError.self) { try FirebaseAppID("1:1234567890:web:abc123") }
    }

    // MARK: - Artifact validation

    @Test("Accepts an IPA for an iOS app and an APK for an Android app")
    func acceptsMatchingArtifacts() async throws {
        try await withArtifact(named: "App.ipa") { _, path in
            try FirebaseAppDistributionAction.validateArtifact(
                at: path, matches: try FirebaseAppID(Self.iosAppID))
        }
        try await withArtifact(named: "app-qa-release.apk") { _, path in
            try FirebaseAppDistributionAction.validateArtifact(
                at: path, matches: try FirebaseAppID(Self.androidAppID))
        }
    }

    @Test("Rejects an IPA uploaded against an Android app ID")
    func rejectsPlatformMismatch() async throws {
        try await withArtifact(named: "App.ipa") { _, path in
            #expect(throws: ShipItError.self) {
                try FirebaseAppDistributionAction.validateArtifact(
                    at: path, matches: try FirebaseAppID(Self.androidAppID))
            }
        }
    }

    @Test("Rejects an APK uploaded against an iOS app ID")
    func rejectsReversePlatformMismatch() async throws {
        try await withArtifact(named: "app.apk") { _, path in
            #expect(throws: ShipItError.self) {
                try FirebaseAppDistributionAction.validateArtifact(
                    at: path, matches: try FirebaseAppID(Self.iosAppID))
            }
        }
    }

    @Test("Rejects a missing artifact")
    func rejectsMissingArtifact() throws {
        #expect(throws: ShipItError.self) {
            try FirebaseAppDistributionAction.validateArtifact(
                at: "/nonexistent/path/App.ipa", matches: try FirebaseAppID(Self.iosAppID))
        }
    }

    @Test("Rejects a directory masquerading as an artifact")
    func rejectsDirectoryArtifact() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("App.ipa_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Name it so the extension check would pass — only the is-directory check catches it.
        let masquerading = directory.appendingPathComponent("App.ipa")
        try FileManager.default.createDirectory(at: masquerading, withIntermediateDirectories: true)
        #expect(throws: ShipItError.self) {
            try FirebaseAppDistributionAction.validateArtifact(
                at: masquerading.path, matches: try FirebaseAppID(Self.iosAppID))
        }
    }

    // MARK: - Option validation

    @Test("Requires an explicit app_id")
    func requiresAppID() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let action = FirebaseAppDistributionAction(client: makeClient(session: makeMockSession { _ in .json([:]) }))
            let context = makeContext(workingDirectory: directory, platform: .ios)
            await #expect(throws: ShipItError.self) {
                try await action.run(
                    with: .init(artifactPath: path, groups: ["qa"]), context: context)
            }
        }
    }

    @Test("Requires an artifact_path")
    func requiresArtifactPath() async throws {
        let action = FirebaseAppDistributionAction(client: makeClient(session: makeMockSession { _ in .json([:]) }))
        let context = makeContext(workingDirectory: "/tmp", platform: .ios)
        await #expect(throws: ShipItError.self) {
            try await action.run(
                with: .init(appId: Self.iosAppID, groups: ["qa"]), context: context)
        }
    }

    @Test("Requires at least one tester group or tester email")
    func requiresAudience() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let action = FirebaseAppDistributionAction(client: makeClient(session: makeMockSession { _ in .json([:]) }))
            let context = makeContext(workingDirectory: directory, platform: .ios)
            await #expect(throws: ShipItError.self) {
                try await action.run(
                    with: .init(appId: Self.iosAppID, artifactPath: path), context: context)
            }
        }
    }

    // MARK: - Dry run

    @Test("Dry run validates without performing any HTTP request")
    func dryRunPerformsNoRequests() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let requestCount = Mutex(0)
            let session = makeMockSession { _ in
                requestCount.withLock { $0 += 1 }
                return .json([:])
            }
            let action = FirebaseAppDistributionAction(client: makeClient(session: session))
            let context = makeContext(workingDirectory: directory, platform: .ios)

            let result = try await action.run(
                with: .init(
                    appId: Self.iosAppID, artifactPath: path, groups: ["qa-testers"], dryRun: true),
                context: context)

            #expect(result.dryRun)
            #expect(result.releaseName == nil)
            #expect(result.groups == ["qa-testers"])
            #expect(requestCount.withLock { $0 } == 0)
        }
    }

    @Test("Dry run still rejects a mismatched artifact")
    func dryRunStillValidatesArtifact() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let action = FirebaseAppDistributionAction(client: makeClient(session: makeMockSession { _ in .json([:]) }))
            let context = makeContext(workingDirectory: directory, platform: .android)
            await #expect(throws: ShipItError.self) {
                try await action.run(
                    with: .init(
                        appId: Self.androidAppID, artifactPath: path, groups: ["qa"], dryRun: true),
                    context: context)
            }
        }
    }

    // MARK: - Upload

    @Test("Uploads an IPA and distributes it to the requested groups")
    func uploadsIPA() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let session = makeQueuedSession(
                successResponses(releaseName: "projects/1234567890/apps/x/releases/r1"))
            let action = FirebaseAppDistributionAction(client: makeClient(session: session))
            let context = makeContext(workingDirectory: directory, platform: .ios)

            let result = try await action.run(
                with: .init(appId: Self.iosAppID, artifactPath: path, groups: ["qa-testers"]),
                context: context)

            #expect(result.dryRun == false)
            #expect(result.releaseName == "projects/1234567890/apps/x/releases/r1")
            #expect(result.testingUri == "https://appdistribution.firebase.dev/i/testing")
            #expect(result.consoleUri == "https://console.firebase.google.com/release")
            #expect(result.groups == ["qa-testers"])
        }
    }

    @Test("Uploads an APK for an Android app")
    func uploadsAPK() async throws {
        try await withArtifact(named: "app-qa-release.apk") { directory, path in
            let session = makeQueuedSession(
                successResponses(releaseName: "projects/1234567890/apps/y/releases/r2"))
            let action = FirebaseAppDistributionAction(client: makeClient(session: session))
            let context = makeContext(workingDirectory: directory, platform: .android)

            let result = try await action.run(
                with: .init(appId: Self.androidAppID, artifactPath: path, groups: ["qa-testers"]),
                context: context)

            #expect(result.releaseName == "projects/1234567890/apps/y/releases/r2")
        }
    }

    @Test("Sends the release notes patch only when notes are supplied")
    func patchesReleaseNotesWhenSupplied() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let methods = Mutex<[String]>([])
            let queue = ResponseQueue(
                successResponses(releaseName: "projects/1/apps/x/releases/r1") + [.json([:])])
            let session = makeMockSession { request in
                methods.withLock { $0.append(request.httpMethod ?? "") }
                return queue.next()
            }
            let action = FirebaseAppDistributionAction(client: makeClient(session: session))
            let context = makeContext(workingDirectory: directory, platform: .ios)

            _ = try await action.run(
                with: .init(
                    appId: Self.iosAppID, artifactPath: path, groups: ["qa"],
                    releaseNotes: "Staging candidate"),
                context: context)

            #expect(methods.withLock { $0 }.contains("PATCH"))
        }
    }

    @Test("Skips the release notes patch when no notes are supplied")
    func skipsReleaseNotesWhenAbsent() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let methods = Mutex<[String]>([])
            let queue = ResponseQueue(successResponses(releaseName: "projects/1/apps/x/releases/r1"))
            let session = makeMockSession { request in
                methods.withLock { $0.append(request.httpMethod ?? "") }
                return queue.next()
            }
            let action = FirebaseAppDistributionAction(client: makeClient(session: session))
            let context = makeContext(workingDirectory: directory, platform: .ios)

            _ = try await action.run(
                with: .init(appId: Self.iosAppID, artifactPath: path, groups: ["qa"]),
                context: context)

            #expect(!methods.withLock { $0 }.contains("PATCH"))
        }
    }

    @Test("Surfaces an operation error returned while polling")
    func surfacesPollingError() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let session = makeQueuedSession([
                .json(["name": "operations/upload-1"]),
                .json([
                    "name": "operations/upload-1", "done": true,
                    "error": ["code": 3, "message": "unsupported binary"],
                ]),
            ])
            let action = FirebaseAppDistributionAction(client: makeClient(session: session))
            let context = makeContext(workingDirectory: directory, platform: .ios)

            await #expect(throws: ShipItError.self) {
                try await action.run(
                    with: .init(appId: Self.iosAppID, artifactPath: path, groups: ["qa"]),
                    context: context)
            }
        }
    }

    @Test("Fails when the upload response carries no operation name")
    func failsWithoutOperationName() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let session = makeQueuedSession([.json([:])])
            let action = FirebaseAppDistributionAction(client: makeClient(session: session))
            let context = makeContext(workingDirectory: directory, platform: .ios)

            await #expect(throws: ShipItError.self) {
                try await action.run(
                    with: .init(appId: Self.iosAppID, artifactPath: path, groups: ["qa"]),
                    context: context)
            }
        }
    }

    // MARK: - Credential redaction

    @Test("API error messages never echo the raw response body")
    func errorMessagesDoNotEchoBody() {
        // A server that reflected a bearer token back in an error body must not leak it.
        let body = Data(
            """
            {"error":{"status":"PERMISSION_DENIED","message":"denied","token":"ya29.SECRET-TOKEN"}}
            """.utf8)
        let message = FirebaseAppDistributionClient.describeFailure(status: 403, body: body)
        #expect(!message.contains("ya29.SECRET-TOKEN"))
        #expect(message.contains("permission denied"))
    }

    @Test("Maps API error statuses to actionable messages")
    func mapsErrorStatuses() {
        func message(_ status: String) -> String {
            FirebaseAppDistributionClient.describeFailure(
                status: 400, body: Data(#"{"error":{"status":"\#(status)","message":"m"}}"#.utf8))
        }
        #expect(message("FAILED_PRECONDITION").contains("invalid testers"))
        #expect(message("INVALID_ARGUMENT").contains("invalid groups"))
        #expect(message("NOT_FOUND").contains("not found"))
    }

    @Test("Malformed service-account JSON is rejected without echoing the payload")
    func rejectsMalformedCredentialWithoutEchoing() {
        let secret = "-----BEGIN PRIVATE KEY-----SECRETMATERIAL-----END PRIVATE KEY-----"
        do {
            _ = try FirebaseAppDistributionClient(serviceAccountJSON: Data(secret.utf8))
            Issue.record("Expected malformed credential JSON to throw")
        } catch let error as ShipItError {
            #expect(!(error.errorDescription ?? "").contains("SECRETMATERIAL"))
        } catch {
            Issue.record("Expected a ShipItError, got \(error)")
        }
    }

    @Test("Tester emails are reported as a count, never as addresses")
    func testerEmailsAreNotEchoed() async throws {
        try await withArtifact(named: "App.ipa") { directory, path in
            let session = makeQueuedSession(
                successResponses(releaseName: "projects/1/apps/x/releases/r1"))
            let action = FirebaseAppDistributionAction(client: makeClient(session: session))
            let context = makeContext(workingDirectory: directory, platform: .ios)

            let result = try await action.run(
                with: .init(
                    appId: Self.iosAppID, artifactPath: path, groups: ["qa"],
                    testers: ["tester@example.com", "other@example.com"]),
                context: context)

            #expect(result.testerCount == 2)
            let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? ""
            #expect(!encoded.contains("tester@example.com"))
        }
    }

    // MARK: - Credential resolution

    @Test("Reports an actionable error when no credentials are configured")
    func reportsMissingCredentials() throws {
        // Only meaningful when the ambient environment has no Google credentials.
        let environment = ProcessInfo.processInfo.environment
        try #require(environment["GOOGLE_APPLICATION_CREDENTIALS"] == nil)
        try #require(environment["FIREBASE_SERVICE_ACCOUNT_JSON"] == nil)

        #expect(throws: ShipItError.self) {
            try FirebaseAppDistributionAction.makeClient(serviceAccountPath: nil)
        }
    }

    @Test("Reports an actionable error when the credential path does not exist")
    func reportsUnreadableCredentialPath() {
        #expect(throws: ShipItError.self) {
            try FirebaseAppDistributionAction.makeClient(
                serviceAccountPath: "/nonexistent/service-account.json")
        }
    }
}
