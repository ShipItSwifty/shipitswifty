#if os(macOS)
import Foundation
import Testing

@testable import ShipItKit

@Suite("AppStoreConnectClient", .serialized)
struct AppStoreConnectClientTests {

    @Test("POST accepts 204 no-content responses")
    func postAcceptsNoContentResponse() async throws {
        let session = makeMockSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/betaGroups/group-1/relationships/builds")
            return .empty(statusCode: 204)
        }

        let client = AppStoreConnectClient(
            keyID: "KEY",
            issuerID: "ISSUER",
            privateKeyData: Data("placeholder".utf8),
            session: session,
            tokenProvider: { "test-token" }
        )

        let response: NoContentResponse = try await client.post(
            "/v1/betaGroups/group-1/relationships/builds",
            body: BuildAttachmentRequest(data: [.init(type: "builds", id: "build-1")])
        )

        _ = response
    }
}

private struct BuildAttachmentRequest: Encodable, Sendable {
    let data: [DataItem]

    struct DataItem: Encodable, Sendable {
        let type: String
        let id: String
    }
}
#endif
