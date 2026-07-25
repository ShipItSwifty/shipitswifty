import Crypto
import CryptoExtras
import Foundation
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Generates and caches Google OAuth2 access tokens for service account authentication.
///
/// Uses RS256 JWT signing to authenticate with `https://oauth2.googleapis.com/token`,
/// mirroring the pattern of `JWTGenerator` in the App Store Connect client.
///
/// ## Usage
/// ```swift
/// let generator = GooglePlayJWTGenerator(credentials: credentials)
/// let token = try await generator.cachedOrNewToken()
///
/// // Firebase App Distribution needs a different scope:
/// let firebase = GooglePlayJWTGenerator(credentials: credentials, scope: .cloudPlatform)
/// ```
public actor GooglePlayJWTGenerator: Sendable {

    /// An OAuth2 scope requested when exchanging the signed JWT for an access token.
    ///
    /// Google issues scope-limited tokens, so each API family needs the scope it accepts:
    /// the Play Developer API only honours ``androidPublisher``, while the Firebase App
    /// Distribution API only honours ``cloudPlatform``.
    public struct Scope: RawRepresentable, Hashable, Sendable {
        /// The fully-qualified scope URL sent in the JWT payload.
        public let rawValue: String

        /// Creates a scope from a fully-qualified Google OAuth2 scope URL.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Scope for the Google Play Developer API (`androidpublisher`).
        public static let androidPublisher = Scope(
            rawValue: "https://www.googleapis.com/auth/androidpublisher"
        )

        /// Scope for the Firebase App Distribution API (`cloud-platform`).
        public static let cloudPlatform = Scope(
            rawValue: "https://www.googleapis.com/auth/cloud-platform"
        )
    }

    private let credentials: GoogleServiceAccountCredentials
    private let scope: Scope
    private let logger = Logger.forType(subsystem: "ShipItSwifty", GooglePlayJWTGenerator.self)

    // Cached access token
    private var cachedToken: String?
    private var tokenExpiresAt: Date?

    /// Creates a `GooglePlayJWTGenerator` with service account credentials.
    ///
    /// - Parameters:
    ///   - credentials: The parsed service-account key.
    ///   - scope: The OAuth2 scope to request. Defaults to ``Scope/androidPublisher``.
    public init(credentials: GoogleServiceAccountCredentials, scope: Scope = .androidPublisher) {
        self.credentials = credentials
        self.scope = scope
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
        let token = try await fetchNewToken()
        return token
    }

    // MARK: - Private

    private func fetchNewToken() async throws -> String {
        logger.info("Fetching new Google OAuth2 access token for \(self.credentials.clientEmail)")

        let jwt = try buildJWT()
        let tokenResponse = try await exchangeJWTForToken(jwt: jwt)

        cachedToken = tokenResponse.accessToken
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        logger.info("Google OAuth2 token fetched, expires in \(tokenResponse.expiresIn)s")
        return tokenResponse.accessToken
    }

    func buildJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let expiry = now + 3600

        // Header
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let headerB64 = base64URLEncode(Data(header.utf8))

        // Payload
        let payload = """
            {
              "iss": "\(credentials.clientEmail)",
              "scope": "\(scope.rawValue)",
              "aud": "\(credentials.tokenUri)",
              "iat": \(now),
              "exp": \(expiry)
            }
            """
        let payloadB64 = base64URLEncode(Data(payload.utf8))

        let signingInput = "\(headerB64).\(payloadB64)"

        // Sign with RS256
        let privateKeyPEM = credentials.privateKey
        let signature = try rsaSign(input: signingInput, pemKey: privateKeyPEM)
        let sigB64 = base64URLEncode(signature)

        return "\(signingInput).\(sigB64)"
    }

    /// RS256 signing for Google service-account PKCS#8 PEM keys.
    private func rsaSign(input: String, pemKey: String) throws -> Data {
        do {
            let privateKey = try _RSA.Signing.PrivateKey(pemRepresentation: pemKey)
            let digest = SHA256.hash(data: Data(input.utf8))
            let signature = try privateKey.signature(for: digest, padding: .insecurePKCS1v1_5)
            return signature.rawRepresentation
        } catch {
            throw ShipItError.invalidConfiguration(
                reason: "Google OAuth2: RSA signing failed — \(error.localizedDescription)"
            )
        }
    }

    private func exchangeJWTForToken(jwt: String) async throws -> GoogleOAuth2TokenResponse {
        guard let url = URL(string: credentials.tokenUri) else {
            throw ShipItError.invalidConfiguration(reason: "Google OAuth2: invalid token URI '\(credentials.tokenUri)'")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(jwt)"
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ShipItError.uploadFailed(asset: "oauth2/token", reason: "HTTP \(status): \(body)")
        }

        return try JSONDecoder().decode(GoogleOAuth2TokenResponse.self, from: data)
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
