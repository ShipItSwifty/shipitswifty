import Foundation
import Testing
@testable import ShipItKit

@Suite("IPAUploadService", .serialized)
struct IPAUploadServiceTests {

    @Test("reserve upload request uses builds resource type")
    func reserveRequestUsesBuildsType() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Example.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        let uploadServer = MockUploadServer()
        nonisolated(unsafe) var capturedType: String?

        let session = makeMockSession { request in
            let path = request.url?.path ?? ""

            if path == "/v1/apps" {
                return .json([
                    "data": [[
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app"]
                    ]]
                ])
            }

            if path == "/v1/builds", request.httpMethod == "POST" {
                let requestBody = httpBodyData(from: request)
                let body = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
                let data = body?["data"] as? [String: Any]
                capturedType = data?["type"] as? String

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

        let result = try await IPAUploadService(client: client).uploadIPA(at: ipaURL, bundleID: "com.example.app")

        #expect(result.buildID == "build-123")
        #expect(capturedType == "builds")
    }

    @Test("throws when app lookup returns no matching app")
    func throwsWhenAppIsMissing() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Missing.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        let client = makeClient(responses: [
            .json(["data": []])
        ])

        await #expect(throws: ShipItError.self) {
            _ = try await IPAUploadService(client: client).uploadIPA(at: ipaURL, bundleID: "com.example.missing")
        }
    }

    @Test("throws when reserve upload request fails")
    func throwsWhenReserveFails() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Reserve.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        let client = makeClient(responses: [
            .json([
                "data": [[
                    "id": "app-1",
                    "attributes": ["bundleId": "com.example.app"]
                ]]
            ]),
            .error(statusCode: 409, body: "reservation failed"),
        ])

        await #expect(throws: ShipItError.self) {
            _ = try await IPAUploadService(client: client).uploadIPA(at: ipaURL, bundleID: "com.example.app")
        }
    }

    @Test("throws when commit request fails")
    func throwsWhenCommitFails() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let ipaURL = tempDirectory.appendingPathComponent("Commit.ipa")
        try Data("ipa-data".utf8).write(to: ipaURL)

        let uploadServer = MockUploadServer()
        let session = makeMockSession { request in
            let path = request.url?.path ?? ""

            if path == "/v1/apps" {
                return .json([
                    "data": [[
                        "id": "app-1",
                        "attributes": ["bundleId": "com.example.app"]
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
                return .error(statusCode: 500, body: "commit failed")
            }

            if request.url == uploadServer.uploadURL {
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

        await #expect(throws: ShipItError.self) {
            _ = try await IPAUploadService(client: client).uploadIPA(at: ipaURL, bundleID: "com.example.app")
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func httpBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }

        return data
    }
}
