#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("UploadAction", .serialized)
struct UploadActionTests {

    @Test("UploadAction uploads IPA and returns build id")
    func uploadsIPA() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Example.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        let executor = MockExecutor { command, _ in
            // xcrun altool --upload-app → success
            if command.arguments.first == "altool" {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            // bash -c "unzip | plutil" → build version
            if command.arguments.first == "-c" {
                return ShellOutput(stdout: "1\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

            if path == "/v1/apps" {
                return .json([
                    "data": [
                        [
                            "id": "app-1",
                            "attributes": ["bundleId": "com.example.app", "name": "Example"],
                        ]
                    ]
                ])
            }
            // Build lookup after altool upload
            if path == "/v1/builds", query["filter[version]"] == "1" {
                return .json([
                    "data": [["id": "build-123", "attributes": ["version": "1"]]]
                ])
            }
            return .error(statusCode: 404, body: "not found")
        }

        let context = makeContext(executor: executor, session: session, bundleID: "com.example.app")
        let result = try await UploadAction().run(
            with: .init(ipaPath: ipaURL.path),
            context: context
        )

        #expect(result.buildID == "build-123")
    }

    @Test("UploadAction can create a review submission")
    func uploadCreatesReviewSubmission() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Example.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        let executor = MockExecutor { command, _ in
            if command.arguments.first == "altool" {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            if command.arguments.first == "-c" {
                return ShellOutput(stdout: "2\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

            if path == "/v1/apps" {
                return .json([
                    "data": [
                        [
                            "id": "app-1",
                            "attributes": ["bundleId": "com.example.app", "name": "Example"],
                        ]
                    ]
                ])
            }
            if path == "/v1/builds", query["filter[version]"] == "2" {
                return .json([
                    "data": [["id": "build-999", "attributes": ["version": "2"]]]
                ])
            }
            if path == "/v1/apps/app-1/appStoreVersions" {
                return .json([
                    "data": [
                        [
                            "id": "version-1",
                            "attributes": ["versionString": "1.2.3"],
                        ]
                    ]
                ])
            }
            if path == "/v1/appStoreVersions/version-1", request.httpMethod == "PATCH" {
                return .json([
                    "data": ["id": "version-1", "attributes": ["versionString": "1.2.3"]]
                ])
            }
            if path == "/v1/reviewSubmissions", request.httpMethod == "POST" {
                return .json(["data": ["id": "review-123"]])
            }
            return .error(statusCode: 404, body: "not found")
        }

        let context = makeContext(
            executor: executor,
            session: session,
            bundleID: "com.example.app",
            submitForReview: true
        )
        let result = try await UploadAction().run(
            with: .init(ipaPath: ipaURL.path, submitForReview: true),
            context: context
        )

        #expect(result.buildID == "build-999")
        #expect(result.reviewSubmissionID == "review-123")
    }

    @Test("UploadAction discovers Flutter IPA output when export directory is absent")
    func uploadDiscoversFlutterIPAOutput() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaDirectory = tempDirectory.appendingPathComponent("build/ios/ipa", isDirectory: true)
        try FileManager.default.createDirectory(at: ipaDirectory, withIntermediateDirectories: true)
        try Data("ipa-data".utf8).write(to: ipaDirectory.appendingPathComponent("Example.ipa"))

        let executor = MockExecutor { command, _ in
            if command.arguments.first == "altool" {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            if command.arguments.first == "-c" {
                return ShellOutput(stdout: "3\n", stderr: "", exitCode: 0)
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
            if path == "/v1/builds", query["filter[version]"] == "3" {
                return .json(["data": [["id": "build-333", "attributes": ["version": "3"]]]])
            }
            return .error(statusCode: 404, body: "not found")
        }

        let context = makeContext(
            executor: executor,
            session: session,
            bundleID: "com.example.app",
            iosBuildSystem: .flutter,
            workingDirectory: tempDirectory.path
        )
        let result = try await UploadAction().run(with: .init(), context: context)

        #expect(result.buildID == "build-333")
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeContext(
        executor: MockExecutor,
        session: URLSession,
        bundleID: String,
        submitForReview: Bool = false,
        iosBuildSystem: BuildSystem = .native,
        workingDirectory: String? = nil
    ) -> ActionContext {
        let base = ActionContext.mock(executor: executor)
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-upload-action-home-\(UUID().uuidString)", isDirectory: true)
        let shell = ShellContext(
            executor: executor,
            searchPaths: base.shell.searchPaths,
            environment: base.shell.environment.merging(["HOME": homeURL.path]) { _, new in new },
            workingDirectory: workingDirectory ?? base.shell.workingDirectory,
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
        return ActionContext(
            shell: shell,
            logger: base.logger,
            config: ResolvedConfig(
                bundleID: bundleID,
                ascKeyID: "TESTKEY",
                ascIssuerID: "test-issuer",
                ascPrivateKeyData: Data(
                    "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n".utf8
                ),
                submitForReview: submitForReview,
                iosBuildSystem: iosBuildSystem
            ),
            appStoreConnect: client,
            platform: .ios
        )
    }
}
#endif
