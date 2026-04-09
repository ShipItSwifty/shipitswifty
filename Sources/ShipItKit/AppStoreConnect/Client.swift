import Foundation
import OSLog

/// A response type with no body content (e.g. 204 No Content).
///
/// Conform to this protocol for ASC endpoints that return an empty body.
public protocol EmptyBodyResponse: Decodable, Sendable {
    /// Creates an empty response value.
    init()
}

/// Default empty-body response used for 204 No Content ASC endpoints.
public struct NoContentResponse: EmptyBodyResponse {
    /// Creates a `NoContentResponse`.
    public init() {}
}

/// Actor-isolated client for the App Store Connect REST API.
///
/// Manages JWT lifecycle (via `JWTGenerator`), enforces rate-limit backoff
/// (via `RateLimiter`), and optionally routes through the ShipItSwifty
/// Vapor proxy server when `serverURL` is set.
///
/// All methods are `async throws`; errors are typed as `ShipItError`.
///
/// ## Usage
/// ```swift
/// let client = AppStoreConnectClient(
///     keyID: "2X9R4HXF34",
///     issuerID: "57246542-96fe-1a63-e053-0824d011072a",
///     privateKeyData: p8Data
/// )
/// let apps: ASCListResponse<ASCApp> = try await client.get("/v1/apps")
/// ```
public actor AppStoreConnectClient: Sendable {
    private static let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    private let keyID: String
    private let issuerID: String
    private let privateKeyData: Data
    private let serverURL: URL?
    private let session: URLSession
    private let tokenProvider: (@Sendable () async throws -> String)?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger.forType(subsystem: "ShipItSwifty", AppStoreConnectClient.self)

    /// The JWT token generator used for authentication.
    public let jwtGenerator: JWTGenerator

    /// The rate limiter used to enforce Apple's API rate limits.
    public let rateLimiter: RateLimiter

    /// Creates an `AppStoreConnectClient`.
    ///
    /// - Parameters:
    ///   - keyID: The API Key ID from App Store Connect.
    ///   - issuerID: The Issuer ID from App Store Connect.
    ///   - privateKeyData: Raw `.p8` private key contents.
    ///   - serverURL: Optional proxy server URL (for use with `shipit-server`).
    ///   - session: URL session used for outbound HTTP requests.
    ///   - tokenProvider: Optional auth token provider used instead of `JWTGenerator`.
    public init(
        keyID: String,
        issuerID: String,
        privateKeyData: Data,
        serverURL: URL? = nil,
        session: URLSession = .shared,
        tokenProvider: (@Sendable () async throws -> String)? = nil
    ) {
        self.keyID = keyID
        self.issuerID = issuerID
        self.privateKeyData = privateKeyData
        self.serverURL = serverURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.jwtGenerator = JWTGenerator(keyID: keyID, issuerID: issuerID, privateKeyData: privateKeyData)
        self.rateLimiter = RateLimiter()

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = enc
    }

    // MARK: - Generic REST

    /// Perform a GET request and decode the response.
    ///
    /// - Parameters:
    ///   - path: The API path (e.g. `"/v1/apps"`).
    ///   - query: Optional query parameters.
    /// - Returns: Decoded response of type `T`.
    /// - Throws: ``ShipItError/apiError`` on non-2xx responses.
    public func get<T: Decodable & Sendable>(
        _ path: String,
        query: [String: String] = [:]
    ) async throws -> T {
        let request = try await buildRequest(method: "GET", path: path, query: query, body: nil as EmptyBody?)
        return try await perform(request)
    }

    /// Perform a POST request with a body and decode the response.
    ///
    /// - Parameters:
    ///   - path: The API path.
    ///   - body: The request body (encoded as JSON).
    /// - Returns: Decoded response of type `Response`.
    /// - Throws: ``ShipItError/apiError`` on non-2xx responses.
    public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        let request = try await buildRequest(method: "POST", path: path, query: [:], body: body)
        return try await perform(request)
    }

    /// Perform a PATCH request with a body and decode the response.
    ///
    /// - Parameters:
    ///   - path: The API path.
    ///   - body: The request body (encoded as JSON).
    /// - Returns: Decoded response of type `Response`.
    /// - Throws: ``ShipItError/apiError`` on non-2xx responses.
    public func patch<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        let request = try await buildRequest(method: "PATCH", path: path, query: [:], body: body)
        return try await perform(request)
    }

    // MARK: - Asset Upload

    /// Upload an asset (IPA, screenshot, preview) using the multi-step protocol.
    ///
    /// Implements the 3-step App Store Connect upload protocol:
    /// 1. Upload parts to presigned URLs
    /// 2. Commit the upload with MD5 checksum
    ///
    /// - Parameters:
    ///   - fileURL: Local file URL of the asset to upload.
    ///   - reservation: The reservation returned by a prior ASC API call.
    /// - Returns: The upload commit, which should be sent to ASC to finalize.
    /// - Throws: ``ShipItError/uploadFailed`` on failure.
    public func uploadAsset(at fileURL: URL, reservation: UploadReservation) async throws -> UploadCommit {
        logger.info("Uploading asset: \(fileURL.lastPathComponent)")
        let uploader = AssetUploader(session: session)
        return try await uploader.upload(fileURL: fileURL, to: reservation) { progress in
            self.logger.debug("Upload progress: \(Int(progress * 100))%")
        }
    }

    // MARK: - Private Helpers

    private func buildRequest<Body: Encodable>(
        method: String,
        path: String,
        query: [String: String],
        body: Body?
    ) async throws -> URLRequest {
        let baseURL = serverURL ?? AppStoreConnectClient.baseURL
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)

        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw ShipItError.invalidConfiguration(reason: "Invalid URL for path: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token: String
        if let tokenProvider {
            token = try await tokenProvider()
        } else {
            token = try await jwtGenerator.cachedOrNewToken()
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body = body {
            let bodyData = try encoder.encode(body)
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func perform<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        await rateLimiter.throttleIfNeeded()

        logger.debug("ASC API \(request.httpMethod ?? "GET") \(request.url?.path ?? "")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShipItError.apiError(statusCode: 0, body: "Invalid response type")
        }

        // Update rate limiter from response headers
        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { dict, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                dict[key] = value
            }
        }
        await rateLimiter.update(from: headers)

        logger.debug("ASC API response: \(httpResponse.statusCode)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            logger.error("ASC API error \(httpResponse.statusCode): \(body)")
            throw ShipItError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        if data.isEmpty {
            guard let emptyResponseType = T.self as? any EmptyBodyResponse.Type else {
                throw ShipItError.apiError(
                    statusCode: httpResponse.statusCode,
                    body: "Received empty response body for \(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
                )
            }
            return emptyResponseType.init() as! T
        }

        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Helpers

private struct EmptyBody: Encodable, Sendable {}
