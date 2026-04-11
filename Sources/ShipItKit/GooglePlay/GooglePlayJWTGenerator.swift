import Foundation
import Crypto
import OSLog

/// Generates and caches Google OAuth2 access tokens for service account authentication.
///
/// Uses RS256 JWT signing to authenticate with `https://oauth2.googleapis.com/token`,
/// mirroring the pattern of `JWTGenerator` in the App Store Connect client.
///
/// ## Usage
/// ```swift
/// let generator = GooglePlayJWTGenerator(credentials: credentials)
/// let token = try await generator.cachedOrNewToken()
/// ```
public actor GooglePlayJWTGenerator: Sendable {

    private let credentials: GoogleServiceAccountCredentials
    private let logger = Logger.forType(subsystem: "ShipItSwifty", GooglePlayJWTGenerator.self)

    // Cached access token
    private var cachedToken: String?
    private var tokenExpiresAt: Date?

    /// Creates a `GooglePlayJWTGenerator` with service account credentials.
    public init(credentials: GoogleServiceAccountCredentials) {
        self.credentials = credentials
    }

    /// Returns a valid access token, reusing the cached token if it hasn't expired.
    public func cachedOrNewToken() async throws -> String {
        let now = Date()
        if let token = cachedToken,
           let expiry = tokenExpiresAt,
           expiry.timeIntervalSince(now) > 60 {
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

    private func buildJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let expiry = now + 3600

        // Header
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let headerB64 = base64URLEncode(Data(header.utf8))

        // Payload
        let payload = """
        {
          "iss": "\(credentials.clientEmail)",
          "scope": "https://www.googleapis.com/auth/androidpublisher",
          "aud": "\(credentials.tokenUri)",
          "iat": \(now),
          "exp": \(expiry)
        }
        """
        let payloadB64 = base64URLEncode(Data(payload.utf8))

        let signingInput = "\(headerB64).\(payloadB64)"

        // Sign with RS256
        let privateKeyPEM = credentials.privateKey
        let keyData = Data(privateKeyPEM.utf8)
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        _ = keyData  // suppress unused warning
        let signature = try rsaSign(input: signingInput, pemKey: privateKeyPEM)
        let sigB64 = base64URLEncode(signature)

        return "\(signingInput).\(sigB64)"
    }

    /// RS256 signing using system Security framework (available on macOS 15+).
    private func rsaSign(input: String, pemKey: String) throws -> Data {
        // Use Security framework for RSA-SHA256 since swift-crypto doesn't expose RSA signing
        let inputData = Data(input.utf8)

        // Strip PEM headers and decode the base64 DER
        let stripped = pemKey
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()
        guard let derData = Data(base64Encoded: stripped) else {
            throw ShipItError.invalidConfiguration(reason: "Google Play: failed to decode RSA private key PEM")
        }

        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        guard let secKey = SecKeyCreateWithData(derData as CFData, attributes as CFDictionary, &error) else {
            throw ShipItError.invalidConfiguration(
                reason: "Google Play: failed to create RSA key — \(error?.takeRetainedValue().localizedDescription ?? "unknown")"
            )
        }

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            inputData as CFData,
            &signError
        ) else {
            throw ShipItError.invalidConfiguration(
                reason: "Google Play: RSA signing failed — \(signError?.takeRetainedValue().localizedDescription ?? "unknown")"
            )
        }
        return signature as Data
    }

    private func exchangeJWTForToken(jwt: String) async throws -> GoogleOAuth2TokenResponse {
        guard let url = URL(string: credentials.tokenUri) else {
            throw ShipItError.invalidConfiguration(reason: "Google Play: invalid token URI '\(credentials.tokenUri)'")
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
