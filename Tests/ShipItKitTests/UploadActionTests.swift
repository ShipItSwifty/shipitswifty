import Foundation
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

        let uploadServer = MockUploadServer()
        let session = makeMockSession { request in
            let path = request.url?.path ?? ""

            if path == "/v1/apps" {
                return .json([
                    "data": [[
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app", "name": "Example"]
                    ]]
                ])
            }

            if path == "/v1/builds", request.httpMethod == "POST" {
                return .json([
                    "data": [
                        "id": "build-123",
                        "attributes": [
                            "uploadOperations": [[
                                "method": "PUT",
                                "url": uploadServer.uploadURL.absoluteString,
                                "offset": 0,
                                "length": 8,
                                "requestHeaders": []
                            ]]
                        ]
                    ]
                ])
            }

            if path == "/v1/builds/build-123", request.httpMethod == "PATCH" {
                return .json([
                    "data": [
                        "id": "build-123",
                        "attributes": ["version": "1"]
                    ]
                ])
            }

            if request.url == uploadServer.uploadURL {
                uploadServer.receivedBodies.append(request.httpBody ?? Data())
                return .empty(statusCode: 200)
            }

            return .error(statusCode: 404, body: "not found")
        }

        let client = AppStoreConnectClient(
            keyID: "KEY",
            issuerID: "ISSUER",
            privateKeyData: Data("placeholder".utf8),
            session: session,
            tokenProvider: { "test-token" }
        )

        let context = ActionContext(
            shell: .init(),
            logger: .forType(subsystem: "ShipItSwiftyTests", UploadAction.self),
            config: ResolvedConfig(bundleID: "com.example.app"),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await UploadAction().run(with: .init(ipaPath: ipaURL.path), context: context)

        #expect(result.buildID == "build-123")
        #expect(uploadServer.receivedBodies.count == 1)
    }

    @Test("UploadAction can create a review submission")
    func uploadCreatesReviewSubmission() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Example.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        let uploadServer = MockUploadServer()
        let session = makeMockSession { request in
            let path = request.url?.path ?? ""

            if path == "/v1/apps" {
                return .json([
                    "data": [[
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app", "name": "Example"]
                    ]]
                ])
            }

            if path == "/v1/builds", request.httpMethod == "POST" {
                return .json([
                    "data": [
                        "id": "build-999",
                        "attributes": [
                            "uploadOperations": [[
                                "method": "PUT",
                                "url": uploadServer.uploadURL.absoluteString,
                                "offset": 0,
                                "length": 8,
                                "requestHeaders": []
                            ]]
                        ]
                    ]
                ])
            }

            if path == "/v1/builds/build-999", request.httpMethod == "PATCH" {
                return .json([
                    "data": [
                        "id": "build-999",
                        "attributes": ["version": "1"]
                    ]
                ])
            }

            if path == "/v1/apps/app-1/appStoreVersions" {
                return .json([
                    "data": [[
                        "id": "version-1",
                        "attributes": ["versionString": "1.2.3"]
                    ]]
                ])
            }

            if path == "/v1/appStoreVersions/version-1", request.httpMethod == "PATCH" {
                return .json([
                    "data": [
                        "id": "version-1",
                        "attributes": ["versionString": "1.2.3"]
                    ]
                ])
            }

            if path == "/v1/reviewSubmissions", request.httpMethod == "POST" {
                return .json([
                    "data": [
                        "id": "review-123"
                    ]
                ])
            }

            if request.url == uploadServer.uploadURL {
                uploadServer.receivedBodies.append(request.httpBody ?? Data())
                return .empty(statusCode: 200)
            }

            return .error(statusCode: 404, body: "not found")
        }

        let client = AppStoreConnectClient(
            keyID: "KEY",
            issuerID: "ISSUER",
            privateKeyData: Data("placeholder".utf8),
            session: session,
            tokenProvider: { "test-token" }
        )

        let context = ActionContext(
            shell: .init(),
            logger: .forType(subsystem: "ShipItSwiftyTests", UploadAction.self),
            config: ResolvedConfig(bundleID: "com.example.app", submitForReview: true),
            appStoreConnect: client,
            platform: .ios
        )

        let result = try await UploadAction().run(
            with: .init(ipaPath: ipaURL.path, submitForReview: true),
            context: context
        )

        #expect(result.buildID == "build-999")
        #expect(result.reviewSubmissionID == "review-123")
    }
}
