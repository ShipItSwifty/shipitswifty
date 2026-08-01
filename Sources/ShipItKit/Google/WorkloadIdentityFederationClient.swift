import Foundation
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exchanges a GitHub Actions OIDC token for a short-lived Google Cloud access token via
/// Workload Identity Federation — no service-account key ever exists on disk or in CI secrets.
///
/// This is the required alternative wherever an organization enforces the
/// `iam.disableServiceAccountKeyCreation` org policy (Google's own "Secure by Default"
/// recommendation), since `FirebaseAppDistributionClient`'s JSON-key flow depends on a
/// downloadable key that policy blocks from ever being created.
///
/// ## The three-step exchange
/// Mirrors what `google-github-actions/auth` does under the hood, done natively so shipit
/// depends on nothing beyond the GitHub Actions OIDC provider and standard Google APIs:
/// 1. Fetch a GitHub Actions OIDC ID token, audience-bound to the workload identity provider.
/// 2. Exchange it at Google's STS endpoint for a federated access token scoped to the pool.
/// 3. Use the federated token to impersonate the target service account via the IAM
///    Credentials API, producing a `cloud-platform`-scoped access token.
///
/// ## Usage
/// ```swift
/// let wif = WorkloadIdentityFederationClient(
///     provider: "projects/123456789/locations/global/workloadIdentityPools/github-actions/providers/github",
///     serviceAccountEmail: "firebase-app-distribution-ci@novalingo-staging.iam.gserviceaccount.com")
/// let token = try await wif.cachedOrNewToken()
/// ```
///
/// Requires `permissions: { id-token: write }` on the calling GitHub Actions job — without it,
/// `ACTIONS_ID_TOKEN_REQUEST_URL`/`ACTIONS_ID_TOKEN_REQUEST_TOKEN` are not set and step 1 throws.
/// The calling identity also needs `roles/iam.workloadIdentityUser` on the target service
/// account, scoped to the specific GitHub repository — not just pool membership — or step 3
/// fails with a permission-denied error.
public actor WorkloadIdentityFederationClient: Sendable {

    /// Resource name of the workload identity pool provider, e.g.
    /// `projects/123/locations/global/workloadIdentityPools/github-actions/providers/github`.
    private let provider: String

    /// Email of the service account to impersonate after the federated token is issued.
    private let serviceAccountEmail: String

    /// The raw request/response transport. Matches `URLSession.data(for:)`'s signature exactly,
    /// so production code just wraps a session while tests can inject a closure directly —
    /// deterministic, and independent of any shared URLProtocol-based HTTP mocking (and its
    /// cross-suite session-routing behavior, which is unreliable on Linux for concurrently
    /// running test suites; see `WorkloadIdentityFederationClientTests`).
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let logger = Logger.forType(subsystem: "ShipItSwifty", WorkloadIdentityFederationClient.self)

    private var cachedToken: String?
    private var tokenExpiresAt: Date?

    /// Creates a `WorkloadIdentityFederationClient`.
    ///
    /// - Parameters:
    ///   - provider: The workload identity pool provider's full resource name.
    ///   - serviceAccountEmail: The service account to impersonate.
    ///   - session: Overridable for tests; defaults to `.shared`.
    public init(provider: String, serviceAccountEmail: String, session: URLSession = .shared) {
        self.provider = provider
        self.serviceAccountEmail = serviceAccountEmail
        self.transport = { request in try await session.data(for: request) }
    }

    /// Creates a client with an injected transport, bypassing `URLSession` entirely.
    ///
    /// Intended for tests: a plain closure is a fully deterministic test double, with no
    /// dependency on `URLProtocol` registration or session-scoped routing.
    init(
        provider: String,
        serviceAccountEmail: String,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.provider = provider
        self.serviceAccountEmail = serviceAccountEmail
        self.transport = transport
    }

    /// Returns a valid access token, reusing the cached token if it hasn't expired.
    public func cachedOrNewToken() async throws -> String {
        let now = Date()
        if let token = cachedToken,
            let expiry = tokenExpiresAt,
            expiry.timeIntervalSince(now) > 60
        {
            return token
        }
        return try await fetchNewToken()
    }

    // MARK: - Private

    private func fetchNewToken() async throws -> String {
        logger.info("Exchanging GitHub Actions OIDC token for Google credentials via \(self.provider)")
        let githubToken = try await fetchGitHubActionsIDToken()
        let federatedToken = try await exchangeForFederatedToken(githubToken: githubToken)
        let (accessToken, expiresAt) = try await impersonateServiceAccount(federatedToken: federatedToken)
        cachedToken = accessToken
        tokenExpiresAt = expiresAt
        logger.info("Impersonated \(self.serviceAccountEmail), token expires at \(expiresAt)")
        return accessToken
    }

    /// Step 1: fetch a GitHub Actions OIDC ID token audience-bound to this WIF provider.
    private func fetchGitHubActionsIDToken() async throws -> String {
        let environment = ProcessInfo.processInfo.environment
        guard let requestURLString = environment["ACTIONS_ID_TOKEN_REQUEST_URL"], !requestURLString.isEmpty,
            let requestToken = environment["ACTIONS_ID_TOKEN_REQUEST_TOKEN"], !requestToken.isEmpty
        else {
            throw ShipItError.invalidConfiguration(
                reason: """
                    workload-identity-federation: ACTIONS_ID_TOKEN_REQUEST_URL / ACTIONS_ID_TOKEN_REQUEST_TOKEN \
                    are not set. Add `permissions: { id-token: write }` to the calling GitHub Actions job.
                    """
            )
        }

        guard var components = URLComponents(string: requestURLString) else {
            throw ShipItError.invalidConfiguration(
                reason: "workload-identity-federation: invalid ACTIONS_ID_TOKEN_REQUEST_URL")
        }
        var query = components.queryItems ?? []
        query.append(URLQueryItem(name: "audience", value: audience))
        components.queryItems = query
        guard let url = components.url else {
            throw ShipItError.invalidConfiguration(
                reason: "workload-identity-federation: could not build the GitHub Actions ID token request URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ShipItError.uploadFailed(
                asset: "github-actions-oidc-token",
                reason: "HTTP \(status) fetching the GitHub Actions OIDC token")
        }

        struct TokenEnvelope: Decodable { let value: String }
        return try JSONDecoder().decode(TokenEnvelope.self, from: data).value
    }

    /// Step 2: exchange the GitHub token at Google's STS endpoint for a federated access token.
    private func exchangeForFederatedToken(githubToken: String) async throws -> String {
        guard let url = URL(string: "https://sts.googleapis.com/v1/token") else {
            throw ShipItError.invalidConfiguration(reason: "workload-identity-federation: invalid STS URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            STSTokenRequest(
                audience: audience,
                grantType: "urn:ietf:params:oauth:grant-type:token-exchange",
                requestedTokenType: "urn:ietf:params:oauth:token-type:access_token",
                scope: "https://www.googleapis.com/auth/cloud-platform",
                subjectTokenType: "urn:ietf:params:oauth:token-type:jwt",
                subjectToken: githubToken
            ))

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ShipItError.uploadFailed(asset: "sts.googleapis.com/v1/token", reason: "HTTP \(status): \(body)")
        }
        return try JSONDecoder().decode(GoogleOAuth2TokenResponse.self, from: data).accessToken
    }

    /// Step 3: impersonate the target service account via the IAM Credentials API.
    private func impersonateServiceAccount(federatedToken: String) async throws -> (String, Date) {
        guard
            let url = URL(
                string:
                    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/\(serviceAccountEmail):generateAccessToken"
            )
        else {
            throw ShipItError.invalidConfiguration(
                reason: "workload-identity-federation: invalid IAM Credentials URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(federatedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateAccessTokenRequest(scope: ["https://www.googleapis.com/auth/cloud-platform"]))

        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ShipItError.uploadFailed(
                asset: "iamcredentials.googleapis.com:generateAccessToken",
                reason:
                    "HTTP \(status): \(body) — check that this GitHub repository is bound to roles/iam.workloadIdentityUser on \(serviceAccountEmail)"
            )
        }

        let decoded = try JSONDecoder().decode(GenerateAccessTokenResponse.self, from: data)
        guard let expiresAt = ISO8601DateFormatter().date(from: decoded.expireTime) else {
            throw ShipItError.uploadFailed(
                asset: "iamcredentials.googleapis.com:generateAccessToken",
                reason: "could not parse expireTime '\(decoded.expireTime)'")
        }
        return (decoded.accessToken, expiresAt)
    }

    /// Google's STS audience convention for a workload identity pool provider.
    private var audience: String { "//iam.googleapis.com/\(provider)" }

    // MARK: - Request/response bodies

    private struct STSTokenRequest: Encodable {
        let audience: String
        let grantType: String
        let requestedTokenType: String
        let scope: String
        let subjectTokenType: String
        let subjectToken: String

        enum CodingKeys: String, CodingKey {
            case audience
            case grantType = "grant_type"
            case requestedTokenType = "requested_token_type"
            case scope
            case subjectTokenType = "subject_token_type"
            case subjectToken = "subject_token"
        }
    }

    private struct GenerateAccessTokenRequest: Encodable {
        let scope: [String]
    }

    private struct GenerateAccessTokenResponse: Decodable {
        let accessToken: String
        let expireTime: String
    }
}
