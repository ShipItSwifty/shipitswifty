import Foundation
import Synchronization
import Testing

@testable import ShipItKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `.serialized` because these tests mutate process-wide environment variables
/// (`ACTIONS_ID_TOKEN_REQUEST_URL`/`ACTIONS_ID_TOKEN_REQUEST_TOKEN`) that a parallel test
/// would race on.
///
/// These tests inject the transport closure directly rather than going through the shared
/// `makeMockSession`/`MockURLProtocol` helper in TestSupport.swift — that helper routes mock
/// responses by a session-ID HTTP header, which is not reliably delivered to `URLProtocol` on
/// Linux under concurrent test execution, causing responses to cross-talk between unrelated
/// test suites. Injecting the transport directly is fully deterministic and platform-independent.
@Suite("WorkloadIdentityFederationClient", .serialized)
struct WorkloadIdentityFederationClientTests {

    private static let provider = "projects/1/locations/global/workloadIdentityPools/github-actions/providers/github"
    private static let serviceAccountEmail = "firebase-app-distribution-ci@novalingo-staging.iam.gserviceaccount.com"

    /// Sets the two GitHub Actions OIDC env vars for the duration of `body`, restoring
    /// whatever was there before (normally nothing, outside real GitHub Actions).
    private func withGitHubActionsOIDCEnvironment<T>(
        requestURL: String? = "https://token.actions.githubusercontent.com/request",
        requestToken: String? = "gha-request-token",
        _ body: () async throws -> T
    ) async rethrows -> T {
        let urlKey = "ACTIONS_ID_TOKEN_REQUEST_URL"
        let tokenKey = "ACTIONS_ID_TOKEN_REQUEST_TOKEN"
        let previousURL = ProcessInfo.processInfo.environment[urlKey]
        let previousToken = ProcessInfo.processInfo.environment[tokenKey]

        func apply(_ key: String, _ value: String?) {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }

        apply(urlKey, requestURL)
        apply(tokenKey, requestToken)
        defer {
            apply(urlKey, previousURL)
            apply(tokenKey, previousToken)
        }
        return try await body()
    }

    private func jsonResponse(_ object: [String: Any], statusCode: Int = 200) -> (Data, URLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: statusCode, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }

    private func errorResponse(statusCode: Int, body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: statusCode, httpVersion: nil,
            headerFields: [:])!
        return (Data(body.utf8), response)
    }

    private func makeClient(
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) -> WorkloadIdentityFederationClient {
        WorkloadIdentityFederationClient(
            provider: Self.provider, serviceAccountEmail: Self.serviceAccountEmail, transport: transport)
    }

    @Test("Exchanges a GitHub token for a federated token, then impersonates the service account")
    func performsFullExchange() async throws {
        try await withGitHubActionsOIDCEnvironment {
            let client = makeClient { request in
                let urlString = request.url?.absoluteString ?? ""
                if urlString.contains("token.actions.githubusercontent.com") {
                    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gha-request-token")
                    #expect(urlString.contains("audience="))
                    return self.jsonResponse(["value": "github-oidc-jwt"])
                }
                if urlString.contains("sts.googleapis.com") {
                    return self.jsonResponse(["access_token": "federated-token", "expires_in": 3600, "token_type": "Bearer"])
                }
                if urlString.contains("iamcredentials.googleapis.com") {
                    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer federated-token")
                    return self.jsonResponse([
                        "accessToken": "impersonated-token",
                        "expireTime": "2099-01-01T00:00:00Z",
                    ])
                }
                return self.errorResponse(statusCode: 404, body: "unexpected URL \(urlString)")
            }

            let token = try await client.cachedOrNewToken()
            #expect(token == "impersonated-token")
        }
    }

    @Test("Caches the token instead of re-running the exchange")
    func cachesToken() async throws {
        try await withGitHubActionsOIDCEnvironment {
            let callCount = Mutex(0)
            let client = makeClient { request in
                let urlString = request.url?.absoluteString ?? ""
                if urlString.contains("token.actions.githubusercontent.com") {
                    callCount.withLock { $0 += 1 }
                    return self.jsonResponse(["value": "github-oidc-jwt"])
                }
                if urlString.contains("sts.googleapis.com") {
                    return self.jsonResponse(["access_token": "federated-token", "expires_in": 3600, "token_type": "Bearer"])
                }
                return self.jsonResponse(["accessToken": "impersonated-token", "expireTime": "2099-01-01T00:00:00Z"])
            }

            _ = try await client.cachedOrNewToken()
            _ = try await client.cachedOrNewToken()
            #expect(callCount.withLock { $0 } == 1)
        }
    }

    @Test("Throws an actionable error when GitHub Actions OIDC env vars are absent")
    func throwsWithoutOIDCEnvironment() async throws {
        await withGitHubActionsOIDCEnvironment(requestURL: nil, requestToken: nil) {
            let client = makeClient { _ in self.errorResponse(statusCode: 500, body: "should not be called") }
            await #expect(throws: ShipItError.self) {
                _ = try await client.cachedOrNewToken()
            }
        }
    }

    @Test("Surfaces a permission-denied hint when impersonation is rejected")
    func surfacesImpersonationPermissionError() async throws {
        await withGitHubActionsOIDCEnvironment {
            let client = makeClient { request in
                let urlString = request.url?.absoluteString ?? ""
                if urlString.contains("token.actions.githubusercontent.com") {
                    return self.jsonResponse(["value": "github-oidc-jwt"])
                }
                if urlString.contains("sts.googleapis.com") {
                    return self.jsonResponse(["access_token": "federated-token", "expires_in": 3600, "token_type": "Bearer"])
                }
                return self.errorResponse(statusCode: 403, body: "PERMISSION_DENIED")
            }

            await #expect(throws: ShipItError.self) {
                _ = try await client.cachedOrNewToken()
            }
        }
    }
}
