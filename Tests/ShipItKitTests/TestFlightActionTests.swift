import Foundation
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

        let uploadServer = MockUploadServer()
        nonisolated(unsafe) var betaGroupQuery: [String: String] = [:]

        let session = makeMockSession { request in
            let path = request.url?.path ?? ""
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

            if path == "/v1/apps", query["filter[bundleId]"] == "com.example.app" {
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

            if path == "/v1/builds/build-123", request.httpMethod == "GET" {
                return .json([
                    "data": [
                        "id": "build-123",
                        "attributes": [
                            "processingState": "VALID",
                            "version": "1"
                        ]
                    ]
                ])
            }

            if path == "/v1/betaGroups", request.httpMethod == "GET" {
                betaGroupQuery = query
                return .json([
                    "data": [[
                        "id": "group-1",
                        "attributes": ["name": "Internal QA"]
                    ]]
                ])
            }

            if path == "/v1/betaGroups/group-1/relationships/builds", request.httpMethod == "POST" {
                return .empty(statusCode: 204)
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

        let context = ActionContext(
            shell: .init(),
            logger: .forType(subsystem: "ShipItSwiftyTests", TestFlightAction.self),
            config: ResolvedConfig(bundleID: "com.example.app"),
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
}
