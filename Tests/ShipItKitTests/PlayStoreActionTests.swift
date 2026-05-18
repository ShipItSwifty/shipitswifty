import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("PlayStoreAction", .serialized)
struct PlayStoreActionTests {

    // MARK: - Helpers

    /// Creates a `GooglePlayClient` backed by a mock `URLSession` and canned token (no RSA signing).
    private func makeGooglePlayClient(session: URLSession) -> GooglePlayClient {
        GooglePlayClient(tokenProvider: { "test-token" }, session: session)
    }

    /// Creates an `ActionContext` for Android with the given working directory and Google Play client.
    private func makeAndroidContext(
        workingDirectory: String,
        googlePlay: GooglePlayClient
    ) -> ActionContext {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        let shell = ShellContext(executor: executor, workingDirectory: workingDirectory)
        let config = ResolvedConfig(
            appScheme: "MockApp",
            bundleID: "com.example.mock",
            teamID: "MOCK12345",
            ascKeyID: "MOCKKEY",
            ascIssuerID: "mock-issuer-id",
            ascPrivateKeyData: nil,
            platform: .android,
            androidModule: "app",
            androidBuildVariant: "release",
            androidPackageName: "com.example.mock",
            androidPlayTrack: "internal"
        )
        let logger = Logger.forType(subsystem: "ShipItSwiftyTests", ActionContext.self)
        #if os(macOS)
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(
            keyID: "MOCKKEY",
            issuerID: "mock-issuer-id",
            privateKeyData: dummyKeyData
        )
        return ActionContext(
            shell: shell,
            logger: logger,
            config: config,
            appStoreConnect: ascClient,
            googlePlay: googlePlay,
            platform: .android
        )
        #else
        return ActionContext(
            shell: shell,
            logger: logger,
            config: config,
            googlePlay: googlePlay,
            platform: .android
        )
        #endif
    }

    // MARK: - Tests

    @Test("PlayStoreAction resolves relative AAB path against shell workingDirectory")
    func relativeAABPathAnchoredToWorkingDirectory() async throws {
        // Arrange: create a temp project directory with an AAB at the conventional location
        let projectDir = try makeTempDirectory(prefix: "PlayStoreTests")
        defer { try? FileManager.default.removeItem(at: projectDir) }

        let aabRelative = "app/build/outputs/bundle/release/app-release.aab"
        let aabURL = projectDir.appendingPathComponent(aabRelative, isDirectory: false)
        try FileManager.default.createDirectory(
            at: aabURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake-aab".utf8).write(to: aabURL)

        // Mock the Play API: OAuth token → create edit → upload bundle → assign track → commit
        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            if path.contains("oauth2.googleapis.com") || path.hasSuffix("/token") {
                return .json([
                    "access_token": "test-access-token",
                    "expires_in": 3600,
                    "token_type": "Bearer",
                ])
            }
            if path.hasSuffix("/edits") && request.httpMethod == "POST" {
                return .json(["id": "edit-123", "expiryTimeSeconds": "86400"])
            }
            if path.contains("/bundles") {
                return .json(["versionCode": 42])
            }
            if path.contains("/tracks/") {
                return .json([
                    "track": "internal",
                    "releases": [["versionCodes": ["42"], "status": "completed"]],
                ])
            }
            if path.hasSuffix(":commit") {
                return .json(["id": "edit-123", "expiryTimeSeconds": "86400"])
            }
            return .error(statusCode: 404, body: "unexpected: \(path)")
        }

        let googlePlay = makeGooglePlayClient(session: session)
        let context = makeAndroidContext(
            workingDirectory: projectDir.path, googlePlay: googlePlay)

        // Act: run with no explicit aabPath — action must auto-discover and anchor to workingDirectory
        let result = try await PlayStoreAction().run(with: .init(), context: context)

        // Assert
        #expect(result.versionCode == 42)
        #expect(result.track == "internal")
        #expect(result.packageName == "com.example.mock")
    }

    @Test("PlayStoreAction throws invalidConfiguration when AAB not found at anchored path")
    func throwsWhenAABMissingAtAnchoredPath() async throws {
        let projectDir = try makeTempDirectory(prefix: "PlayStoreTests")
        defer { try? FileManager.default.removeItem(at: projectDir) }

        // Do NOT create the AAB — the action should throw before hitting the API

        let session = makeMockSession { _ in .empty() }
        let googlePlay = makeGooglePlayClient(session: session)
        let context = makeAndroidContext(
            workingDirectory: projectDir.path, googlePlay: googlePlay)

        await #expect(throws: (any Error).self) {
            _ = try await PlayStoreAction().run(with: .init(), context: context)
        }
    }

    @Test("PlayStoreAction uses per-step buildVariant for artifact path discovery")
    func perStepBuildVariantOverridesConfig() async throws {
        // Arrange: config says "release" but step options say "prodRelease"
        let projectDir = try makeTempDirectory(prefix: "PlayStoreTests")
        defer { try? FileManager.default.removeItem(at: projectDir) }

        let aabRelative = "app/build/outputs/bundle/prodRelease/app-prodRelease.aab"
        let aabURL = projectDir.appendingPathComponent(aabRelative, isDirectory: false)
        try FileManager.default.createDirectory(
            at: aabURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake-aab".utf8).write(to: aabURL)

        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            if path.contains("oauth2.googleapis.com") || path.hasSuffix("/token") {
                return .json([
                    "access_token": "test-access-token",
                    "expires_in": 3600,
                    "token_type": "Bearer",
                ])
            }
            if path.hasSuffix("/edits") && request.httpMethod == "POST" {
                return .json(["id": "edit-123", "expiryTimeSeconds": "86400"])
            }
            if path.contains("/bundles") {
                return .json(["versionCode": 99])
            }
            if path.contains("/tracks/") {
                return .json([
                    "track": "beta",
                    "releases": [["versionCodes": ["99"], "status": "completed"]],
                ])
            }
            if path.hasSuffix(":commit") {
                return .json(["id": "edit-123", "expiryTimeSeconds": "86400"])
            }
            return .error(statusCode: 404, body: "unexpected: \(path)")
        }

        let googlePlay = makeGooglePlayClient(session: session)
        // Config has androidBuildVariant: "release" (default), but step overrides to "prodRelease"
        let context = makeAndroidContext(
            workingDirectory: projectDir.path, googlePlay: googlePlay)

        let options = PlayStoreAction.Options(
            track: "beta",
            buildVariant: "prodRelease"
        )
        let result = try await PlayStoreAction().run(with: options, context: context)

        #expect(result.versionCode == 99)
        #expect(result.track == "beta")
    }
}
