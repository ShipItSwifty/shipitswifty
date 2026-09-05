import GoogleAuthKit
import Foundation
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// JWT-authenticated HTTP client for the Firebase App Distribution API (v1).
///
/// Mirrors ``GooglePlayClient`` in structure and usage patterns, but requests the
/// `cloud-platform` OAuth scope that the App Distribution API accepts.
///
/// ## Authentication
/// Two supported paths:
/// - A Google Cloud service-account key via the OAuth2 service-account JWT flow (RS256).
///   Credentials are supplied as raw JSON or a path on disk — never inline in a Shipfile.
/// - Workload Identity Federation (see ``WorkloadIdentityFederationClient``), which exchanges
///   a GitHub Actions OIDC token for short-lived credentials with no key ever created. Required
///   wherever an org enforces the `iam.disableServiceAccountKeyCreation` policy.
///
/// ## Usage
/// Callers normally reach this through ``FirebaseAppDistributionAction`` rather than directly:
/// ```swift
/// let client = try FirebaseAppDistributionClient(serviceAccountJSONPath: "/path/to/key.json")
/// let appID = try FirebaseAppID("1:1234567890:ios:abc123")
/// let operation = try await client.uploadRelease(
///     appID: appID, fileName: "App.ipa", data: artifactData)
/// let response = try await client.pollUpload(operationName: operation)
/// try await client.distribute(
///     releaseName: response.release.name, groups: ["qa-testers"], testers: [])
/// ```
public struct FirebaseAppDistributionClient: Sendable {

    /// Base URL for the App Distribution API.
    static let baseURL = "https://firebaseappdistribution.googleapis.com/v1"

    /// Base URL for binary uploads.
    static let uploadBaseURL = "https://firebaseappdistribution.googleapis.com/upload/v1"

    let jwtGenerator: GoogleServiceAccountJWTGenerator
    let session: URLSession
    /// Optional override for token generation. When non-nil, this closure is called instead
    /// of `jwtGenerator.cachedOrNewToken()`. Intended for use in tests.
    let tokenProvider: (@Sendable () async throws -> String)?
    private let logger = Logger.forType(subsystem: "ShipItSwifty", FirebaseAppDistributionClient.self)

    // MARK: - Init

    /// Creates a client from raw service-account JSON data.
    ///
    /// - Parameter serviceAccountJSON: Raw bytes of a Google Cloud service-account key JSON.
    public init(serviceAccountJSON: Data) throws {
        let credentials: GoogleServiceAccountCredentials
        do {
            credentials = try JSONDecoder().decode(
                GoogleServiceAccountCredentials.self, from: serviceAccountJSON)
        } catch {
            // Deliberately does not echo the payload — it is a private key.
            throw ShipItError.invalidConfiguration(
                reason:
                    "firebase-app-distribution: the service-account credential is not a valid Google service-account key JSON."
            )
        }
        self.jwtGenerator = GoogleServiceAccountJWTGenerator(credentials: credentials, scope: .cloudPlatform)
        self.session = URLSession.shared
        self.tokenProvider = nil
    }

    /// Creates a client by reading a service-account JSON file from disk.
    ///
    /// - Parameter serviceAccountJSONPath: Path to the service-account JSON file.
    public init(serviceAccountJSONPath: String) throws {
        let url = URL(fileURLWithPath: serviceAccountJSONPath)
        guard let data = try? Data(contentsOf: url) else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "firebase-app-distribution: could not read the service-account key at '\(serviceAccountJSONPath)'."
            )
        }
        try self.init(serviceAccountJSON: data)
    }

    /// Creates a client authenticated via Workload Identity Federation (GitHub Actions OIDC),
    /// impersonating the given service account. No service-account key ever exists on disk or
    /// in CI secrets — this is the supported path when an org enforces
    /// `iam.disableServiceAccountKeyCreation`.
    ///
    /// - Parameters:
    ///   - workloadIdentityProvider: The workload identity pool provider's full resource name.
    ///   - serviceAccountEmail: The service account to impersonate.
    public init(workloadIdentityProvider: String, serviceAccountEmail: String) {
        let federation = WorkloadIdentityFederationClient(
            provider: workloadIdentityProvider, serviceAccountEmail: serviceAccountEmail)
        self.init(tokenProvider: { try await federation.cachedOrNewToken() }, session: .shared)
    }

    /// Creates a client with an explicit token provider and URL session.
    ///
    /// Used both by the Workload Identity Federation initializer above and by tests, so a
    /// canned or externally-sourced token can be supplied without RSA signing.
    init(tokenProvider: @escaping @Sendable () async throws -> String, session: URLSession) {
        let placeholderJSON = Data(
            """
            {
                "client_email": "test@example.com",
                "private_key": "",
                "token_uri": "https://oauth2.googleapis.com/token"
            }
            """.utf8)
        let credentials =
            (try? JSONDecoder().decode(
                GoogleServiceAccountCredentials.self, from: placeholderJSON))!
        self.jwtGenerator = GoogleServiceAccountJWTGenerator(credentials: credentials, scope: .cloudPlatform)
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - API

    /// Uploads a binary and returns the name of the long-running upload operation.
    ///
    /// - Parameters:
    ///   - appID: The validated Firebase app ID to upload against.
    ///   - fileName: The artifact's file name, sent so the console shows a sensible label.
    ///   - data: The raw artifact bytes.
    /// - Returns: The operation resource name to poll with ``pollUpload(operationName:)``.
    func uploadRelease(appID: FirebaseAppID, fileName: String, data: Data) async throws -> String {
        let token = try await resolveToken()
        let path = "/\(appID.resourceName)/releases:upload"
        guard let url = URL(string: "\(Self.uploadBaseURL)\(path)") else {
            throw ShipItError.invalidConfiguration(
                reason: "firebase-app-distribution: invalid upload URL for path '\(path)'")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue(
            fileName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? fileName,
            forHTTPHeaderField: "X-Goog-Upload-File-Name")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data
        request.timeoutInterval = 600  // 10 minutes — IPA/APK uploads can be large

        logger.info("Uploading \(data.count) bytes to Firebase App Distribution")
        let operation: FirebaseOperation = try await perform(request, asset: fileName)
        guard let name = operation.name else {
            throw ShipItError.uploadFailed(
                asset: fileName,
                reason: "Firebase App Distribution did not return an upload operation name.")
        }
        return name
    }

    /// Polls an upload operation until it completes.
    ///
    /// - Parameters:
    ///   - operationName: The operation resource name returned by ``uploadRelease(appID:fileName:data:)``.
    ///   - timeout: Maximum time to wait before giving up.
    ///   - sleep: Sleep hook, overridden in tests to avoid real delays.
    /// - Returns: The completed upload response containing the release.
    func pollUpload(
        operationName: String,
        timeout: Duration = .seconds(300),
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> FirebaseUploadReleaseResponse {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        var backoff = Duration.seconds(1)

        while true {
            let operation: FirebaseOperation = try await get("/\(operationName)")

            if let error = operation.error {
                throw ShipItError.uploadFailed(
                    asset: operationName,
                    reason: "Firebase App Distribution upload failed: \(error.message ?? "unknown error")"
                )
            }
            if operation.done == true {
                guard let response = operation.response else {
                    throw ShipItError.uploadFailed(
                        asset: operationName,
                        reason: "Firebase App Distribution reported the upload done but returned no release."
                    )
                }
                return response
            }
            guard ContinuousClock().now < deadline else {
                throw ShipItError.uploadFailed(
                    asset: operationName,
                    reason:
                        "Firebase App Distribution upload did not finish within \(timeout). The binary may still be processing — check the Firebase console."
                )
            }
            try await sleep(backoff)
            backoff = min(backoff * 2, .seconds(10))
        }
    }

    /// Sets the release notes on an existing release.
    ///
    /// The updated release is decoded permissively: the response body is not used, so an
    /// unexpected shape must not fail a release whose binary already uploaded successfully.
    /// A non-2xx status still throws.
    ///
    /// - Parameter sleep: Sleep hook, overridden in tests to avoid real delays.
    func updateReleaseNotes(
        releaseName: String, notes: String,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws {
        let body = ReleaseNotesPatch(name: releaseName, releaseNotes: FirebaseReleaseNotes(text: notes))
        try await withReleasePropagationRetry(releaseName: releaseName, sleep: sleep) {
            let _: EmptyResponse = try await self.patch(
                "/\(releaseName)", query: "updateMask=release_notes.text", body: body)
        }
    }

    /// Distributes a release to tester groups and/or individual testers.
    ///
    /// - Parameter sleep: Sleep hook, overridden in tests to avoid real delays.
    func distribute(
        releaseName: String, groups: [String], testers: [String],
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws {
        let body = DistributeRequest(groupAliases: groups, testerEmails: testers)
        try await withReleasePropagationRetry(releaseName: releaseName, sleep: sleep) {
            // The API returns an empty JSON object on success.
            let _: EmptyResponse = try await self.post("/\(releaseName):distribute", body: body)
        }
    }

    /// Retries an operation against a just-uploaded release that can 404 briefly: the upload
    /// operation reports `done` before the release resource is reliably queryable by other
    /// endpoints (`:distribute`, release-notes `PATCH`), so an immediate follow-up call can hit
    /// that propagation gap even though the release already exists — visible in the Firebase
    /// console — and the binary already uploaded successfully.
    private func withReleasePropagationRetry(
        releaseName: String,
        attempts: Int = 4,
        sleep: @Sendable (Duration) async throws -> Void,
        _ operation: @Sendable () async throws -> Void
    ) async throws {
        var backoff = Duration.seconds(1)
        for attempt in 1...attempts {
            do {
                try await operation()
                return
            } catch ShipItError.uploadFailed(let asset, let reason) where reason.hasPrefix("HTTP 404") {
                guard attempt < attempts else {
                    throw ShipItError.uploadFailed(asset: asset, reason: reason)
                }
                logger.info(
                    "Release \(releaseName) not yet queryable (attempt \(attempt)/\(attempts)) — retrying in \(backoff)"
                )
                try await sleep(backoff)
                backoff = min(backoff * 2, .seconds(10))
            }
        }
    }

    // MARK: - HTTP Primitives

    private func resolveToken() async throws -> String {
        if let provider = tokenProvider {
            return try await provider()
        }
        return try await jwtGenerator.cachedOrNewToken()
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let token = try await resolveToken()
        let url = try buildURL(path: path, query: nil)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request, asset: path)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let token = try await resolveToken()
        let url = try buildURL(path: path, query: nil)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request, asset: path)
    }

    private func patch<B: Encodable, T: Decodable>(_ path: String, query: String?, body: B) async throws -> T {
        let token = try await resolveToken()
        let url = try buildURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request, asset: path)
    }

    private func buildURL(path: String, query: String?) throws -> URL {
        var string = "\(Self.baseURL)\(path)"
        if let query {
            string += "?\(query)"
        }
        guard let url = URL(string: string) else {
            throw ShipItError.invalidConfiguration(
                reason: "firebase-app-distribution: invalid URL for path '\(path)'")
        }
        return url
    }

    private func perform<T: Decodable>(_ request: URLRequest, asset: String) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShipItError.uploadFailed(asset: asset, reason: "No HTTP response received")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ShipItError.uploadFailed(
                asset: asset,
                reason: Self.describeFailure(status: httpResponse.statusCode, body: data)
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ShipItError.uploadFailed(
                asset: asset,
                reason: "Could not decode the Firebase App Distribution response (HTTP \(httpResponse.statusCode)).")
        }
    }

    /// Turns an API error body into an actionable message.
    ///
    /// Only the API's own `error.status`/`error.message` fields are surfaced; the raw body is
    /// never echoed, so a credential accidentally reflected by the server cannot reach the log.
    static func describeFailure(status: Int, body: Data) -> String {
        struct ErrorEnvelope: Decodable {
            struct Payload: Decodable {
                let status: String?
                let message: String?
            }
            let error: Payload?
        }

        let payload = (try? JSONDecoder().decode(ErrorEnvelope.self, from: body))?.error
        let detail = payload?.message ?? "no further detail"

        switch payload?.status {
        case "FAILED_PRECONDITION":
            return
                "HTTP \(status): invalid testers — one or more tester emails are not registered in this Firebase project."
        case "INVALID_ARGUMENT":
            return
                "HTTP \(status): invalid groups — check that every tester group alias exists in this Firebase project."
        case "PERMISSION_DENIED":
            return
                "HTTP \(status): permission denied — the service account needs the Firebase App Distribution Admin role on this project."
        case "NOT_FOUND":
            return
                "HTTP \(status): not found — check that the app ID exists in the Firebase project the credential belongs to."
        default:
            return "HTTP \(status): \(detail)"
        }
    }

    // MARK: - Request/response bodies

    private struct ReleaseNotesPatch: Encodable {
        let name: String
        let releaseNotes: FirebaseReleaseNotes
    }

    private struct DistributeRequest: Encodable {
        let groupAliases: [String]
        let testerEmails: [String]
    }

    private struct EmptyResponse: Decodable {}
}
