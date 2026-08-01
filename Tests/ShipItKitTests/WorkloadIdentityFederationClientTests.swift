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

    @Test("Exchanges a GitHub token for a federated token, then impersonates the service account")
    func performsFullExchange() async throws {
        try await withGitHubActionsOIDCEnvironment {
            let session = makeMockSession { request in
                let urlString = request.url?.absoluteString ?? ""
                if urlString.contains("token.actions.githubusercontent.com") {
                    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gha-request-token")
                    #expect(urlString.contains("audience="))
                    return .json(["value": "github-oidc-jwt"])
                }
                if urlString.contains("sts.googleapis.com") {
                    return .json(["access_token": "federated-token", "expires_in": 3600, "token_type": "Bearer"])
                }
                if urlString.contains("iamcredentials.googleapis.com") {
                    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer federated-token")
                    return .json([
                        "accessToken": "impersonated-token",
                        "expireTime": "2099-01-01T00:00:00Z",
                    ])
                }
                return .error(statusCode: 404, body: "unexpected URL \(urlString)")
            }

            let client = WorkloadIdentityFederationClient(
                provider: Self.provider, serviceAccountEmail: Self.serviceAccountEmail, session: session)
            let token = try await client.cachedOrNewToken()
            #expect(token == "impersonated-token")
        }
    }

    @Test("Caches the token instead of re-running the exchange")
    func cachesToken() async throws {
        try await withGitHubActionsOIDCEnvironment {
            let callCount = Mutex(0)
            let session = makeMockSession { request in
                let urlString = request.url?.absoluteString ?? ""
                if urlString.contains("token.actions.githubusercontent.com") {
                    callCount.withLock { $0 += 1 }
                    return .json(["value": "github-oidc-jwt"])
                }
                if urlString.contains("sts.googleapis.com") {
                    return .json(["access_token": "federated-token", "expires_in": 3600, "token_type": "Bearer"])
                }
                return .json(["accessToken": "impersonated-token", "expireTime": "2099-01-01T00:00:00Z"])
            }

            let client = WorkloadIdentityFederationClient(
                provider: Self.provider, serviceAccountEmail: Self.serviceAccountEmail, session: session)
            _ = try await client.cachedOrNewToken()
            _ = try await client.cachedOrNewToken()
            #expect(callCount.withLock { $0 } == 1)
        }
    }

    @Test("Throws an actionable error when GitHub Actions OIDC env vars are absent")
    func throwsWithoutOIDCEnvironment() async throws {
        await withGitHubActionsOIDCEnvironment(requestURL: nil, requestToken: nil) {
            let session = makeMockSession { _ in .error(statusCode: 500, body: "should not be called") }
            let client = WorkloadIdentityFederationClient(
                provider: Self.provider, serviceAccountEmail: Self.serviceAccountEmail, session: session)
            await #expect(throws: ShipItError.self) {
                _ = try await client.cachedOrNewToken()
            }
        }
    }

    @Test("Surfaces a permission-denied hint when impersonation is rejected")
    func surfacesImpersonationPermissionError() async throws {
        await withGitHubActionsOIDCEnvironment {
            let session = makeMockSession { request in
                let urlString = request.url?.absoluteString ?? ""
                if urlString.contains("token.actions.githubusercontent.com") {
                    return .json(["value": "github-oidc-jwt"])
                }
                if urlString.contains("sts.googleapis.com") {
                    return .json(["access_token": "federated-token", "expires_in": 3600, "token_type": "Bearer"])
                }
                return .error(statusCode: 403, body: "PERMISSION_DENIED")
            }

            let client = WorkloadIdentityFederationClient(
                provider: Self.provider, serviceAccountEmail: Self.serviceAccountEmail, session: session)
            await #expect(throws: ShipItError.self) {
                _ = try await client.cachedOrNewToken()
            }
        }
    }
}
