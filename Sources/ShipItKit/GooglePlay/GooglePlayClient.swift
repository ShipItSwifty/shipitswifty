import Foundation
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// JWT-authenticated HTTP client for the Google Play Developer API (v3).
///
/// Mirrors `AppStoreConnectClient` in structure and usage patterns.
///
/// ## Authentication
/// Authenticates using a Google Cloud service account JSON key file via OAuth2
/// service account JWT flow (RS256).
///
/// ## Usage
/// ```swift
/// let client = try GooglePlayClient(serviceAccountJSON: jsonData)
/// // or
/// let client = try GooglePlayClient(serviceAccountJSONPath: "/path/to/key.json")
///
/// // Use via the upload service
/// let uploader = GooglePlayUploadService(client: client, packageName: "com.example.app")
/// try await uploader.uploadAndRelease(aabPath: "./build/app-release.aab", track: "qa")
/// ```
public struct GooglePlayClient: Sendable {

    /// Base URL for the Google Play Developer API.
    static let baseURL = "https://androidpublisher.googleapis.com/androidpublisher/v3"

    /// Base URL for resumable upload.
    static let uploadBaseURL = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"

    let jwtGenerator: GooglePlayJWTGenerator
    let session: URLSession
    /// Optional override for token generation. When non-nil, this closure is called instead
    /// of `jwtGenerator.cachedOrNewToken()`. Intended for use in tests.
    let tokenProvider: (@Sendable () async throws -> String)?
    private let logger = Logger.forType(subsystem: "ShipItSwifty", GooglePlayClient.self)

    // MARK: - Init

    /// Creates a `GooglePlayClient` from raw service account JSON data.
    ///
    /// - Parameter serviceAccountJSON: Raw bytes of a Google Cloud service account key JSON.
    public init(serviceAccountJSON: Data) throws {
        let credentials = try JSONDecoder().decode(GoogleServiceAccountCredentials.self, from: serviceAccountJSON)
        self.jwtGenerator = GooglePlayJWTGenerator(credentials: credentials)
        self.session = URLSession.shared
        self.tokenProvider = nil
    }

    /// Creates a `GooglePlayClient` with an explicit JWT generator and URL session.
    ///
    /// This initializer is intended for use in tests so that a mock `URLSession` and
    /// a pre-built `GooglePlayJWTGenerator` can be injected without disk I/O.
    init(jwtGenerator: GooglePlayJWTGenerator, session: URLSession) {
        self.jwtGenerator = jwtGenerator
        self.session = session
        self.tokenProvider = nil
    }

    /// Creates a `GooglePlayClient` with an explicit token provider and URL session.
    ///
    /// This initializer is intended for use in tests so that a canned token can be
    /// returned without performing RSA signing.
    init(tokenProvider: @escaping @Sendable () async throws -> String, session: URLSession) {
        let placeholderJSON = Data(
            """
            {
                "client_email": "test@example.com",
                "private_key": "",
                "token_uri": "https://oauth2.googleapis.com/token"
            }
            """.utf8)
        let credentials = (try? JSONDecoder().decode(GoogleServiceAccountCredentials.self, from: placeholderJSON))!
        self.jwtGenerator = GooglePlayJWTGenerator(credentials: credentials)
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// Creates a `GooglePlayClient` by reading a service account JSON file from disk.
    ///
    /// - Parameter serviceAccountJSONPath: Path to the service account JSON file.
    public init(serviceAccountJSONPath: String) throws {
        let url = URL(fileURLWithPath: serviceAccountJSONPath)
        let data = try Data(contentsOf: url)
        try self.init(serviceAccountJSON: data)
    }

    // MARK: - HTTP Primitives

    /// Returns a valid access token, using `tokenProvider` if set or the JWT generator otherwise.
    private func resolveToken() async throws -> String {
        if let provider = tokenProvider {
            return try await provider()
        }
        return try await jwtGenerator.cachedOrNewToken()
    }

    /// Perform a GET request and decode the response.
    func get<T: Codable>(_ path: String) async throws -> T {
        let token = try await resolveToken()
        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    /// Perform a POST request with an encodable body and decode the response.
    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let token = try await resolveToken()
        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    /// Perform a POST request with no body.
    func post<T: Decodable>(_ path: String) async throws -> T {
        let token = try await resolveToken()
        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    /// Perform a PUT request with an encodable body and decode the response.
    func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let token = try await resolveToken()
        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    /// Upload binary data via a resumable upload to the Play API.
    func uploadBinary(
        path: String,
        data: Data,
        contentType: String
    ) async throws -> Data {
        let token = try await resolveToken()
        guard let url = URL(string: "\(Self.uploadBaseURL)\(path)?uploadType=media") else {
            throw ShipItError.invalidConfiguration(reason: "Google Play: invalid upload URL for path '\(path)'")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data
        request.timeoutInterval = 600  // 10 minutes — AAB uploads can be large

        logger.info("Uploading \(data.count) bytes to \(path)")
        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let msg = String(data: responseData, encoding: .utf8) ?? ""
            throw ShipItError.uploadFailed(asset: path, reason: "HTTP \(status): \(msg)")
        }
        return responseData
    }

    // MARK: - Private

    private func buildURL(path: String) throws -> URL {
        guard let url = URL(string: "\(Self.baseURL)\(path)") else {
            throw ShipItError.invalidConfiguration(reason: "Google Play: invalid URL for path '\(path)'")
        }
        return url
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShipItError.uploadFailed(asset: request.url?.path ?? "", reason: "No HTTP response received")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            throw ShipItError.uploadFailed(
                asset: request.url?.path ?? "",
                reason: "HTTP \(httpResponse.statusCode): \(body)"
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
