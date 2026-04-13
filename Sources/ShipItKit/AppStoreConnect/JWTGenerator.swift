import Crypto
import Foundation
import JWTKit
import OSLog

/// Generates ES256-signed JWTs for App Store Connect API authentication.
///
/// Tokens are cached and reused until near expiry (default: 15 min lifetime).
/// Supports both Team API Keys and Individual API Keys.
///
/// **Lifetime guidance:**
/// - Standard operations: use the default 15-minute lifetime.
/// - Long-lived GET-only tokens (e.g. for read-only CI dashboards): pass
///   `lifetime: .months(6)` together with a `scope` array. Apple only allows
///   extended lifetimes for scoped tokens on select read endpoints.
///
/// ## Usage
/// ```swift
/// let generator = JWTGenerator(
///     keyID: "2X9R4HXF34",
///     issuerID: "57246542-96fe-1a63-e053-0824d011072a",
///     privateKey: p8KeyData
/// )
/// // Standard short-lived token
/// let token = try await generator.generateToken()
///
/// // Long-lived scoped read token (up to 6 months)
/// let readToken = try await generator.generateToken(
///     scope: ["GET /v1/apps"],
///     lifetime: .months(6)
/// )
/// ```
public actor JWTGenerator {
    /// Token lifetime used when no explicit value is provided.
    public static let defaultLifetime: Duration = .seconds(15 * 60)

    private let keyID: String
    private let issuerID: String
    private let privateKeyData: Data
    private var cachedToken: String?
    private var tokenExpiresAt: Date?
    /// In-flight generation task; deduplicated so concurrent callers share one signing operation.
    private var inflightTokenTask: Task<String, any Error>?
    private let logger = Logger.forType(subsystem: "ShipItSwifty", JWTGenerator.self)

    /// Creates a `JWTGenerator`.
    ///
    /// - Parameters:
    ///   - keyID: The API Key ID from App Store Connect.
    ///   - issuerID: The Issuer ID from App Store Connect.
    ///   - privateKeyData: Raw contents of the `.p8` private key file.
    public init(keyID: String, issuerID: String, privateKeyData: Data) {
        self.keyID = keyID
        self.issuerID = issuerID
        self.privateKeyData = privateKeyData
    }

    /// Generate a new signed JWT.
    ///
    /// - Parameters:
    ///   - scope: Optional array of allowed operations (restricts token surface).
    ///   - lifetime: Token validity window. Defaults to 15 minutes.
    ///     Apple enforces a hard cap of 20 minutes for unscoped tokens;
    ///     scoped GET-only tokens on select resources allow up to 6 months.
    /// - Throws: ``ShipItError/jwtGenerationFailed`` if signing fails.
    public func generateToken(
        scope: [String]? = nil,
        lifetime: Duration = JWTGenerator.defaultLifetime
    ) async throws -> String {
        logger.info("Generating JWT token with keyID: \(self.keyID)")

        do {
            let pemString = try JWTGenerator.pemString(from: privateKeyData)
            let ecKey = try JWTGenerator.loadES256Key(pem: pemString)
            let keyCollection = await JWTKeyCollection()
                .add(ecdsa: ecKey, kid: JWKIdentifier(string: keyID))

            let now = Date()
            let lifetimeSeconds = Int(lifetime.components.seconds)
            let expiresAt = now.addingTimeInterval(TimeInterval(lifetimeSeconds))

            let payload = ASCJWTPayload(
                issuerID: issuerID,
                issuedAt: now,
                expiresAt: expiresAt,
                audience: "appstoreconnect-v1",
                scope: scope
            )

            let token = try await keyCollection.sign(payload, kid: JWKIdentifier(string: keyID))
            logger.debug("JWT token generated, expires at: \(expiresAt)")
            return token
        } catch {
            logger.error("JWT generation failed: \(error.localizedDescription)")
            throw ShipItError.jwtGenerationFailed(underlying: error)
        }
    }

    /// Return the cached token if still valid (with a 60-second buffer),
    /// otherwise generate and cache a new one.
    ///
    /// Concurrent callers that both observe a cache miss share a single in-flight
    /// `Task` so only one JWT signing operation is performed at a time.
    ///
    /// - Returns: A valid JWT token string.
    /// - Throws: ``ShipItError/jwtGenerationFailed`` if signing fails.
    public func cachedOrNewToken() async throws -> String {
        let bufferSeconds: TimeInterval = 60
        if let token = cachedToken,
           let expiry = tokenExpiresAt,
           Date().addingTimeInterval(bufferSeconds) < expiry {
            logger.debug("Returning cached JWT token")
            return token
        }

        // Reuse an already-running generation task to avoid duplicate signing.
        if let task = inflightTokenTask {
            logger.debug("Awaiting in-flight JWT generation task")
            return try await task.value
        }

        logger.info("Generating new JWT token (cache miss or near expiry)")
        let lifetimeSeconds = Int(JWTGenerator.defaultLifetime.components.seconds)
        let task = Task { [weak self] () throws -> String in
            guard let self else { throw ShipItError.jwtGenerationFailed(underlying: CancellationError()) }
            return try await self.generateToken()
        }
        inflightTokenTask = task
        defer { inflightTokenTask = nil }

        let token = try await task.value
        cachedToken = token
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(lifetimeSeconds))
        return token
    }

    // MARK: - Internal Helpers

    /// Loads an ES256 private key from a PEM string.
    ///
    /// Primary path: `ES256PrivateKey(pem:)` via JWTKit → swift-asn1.
    ///
    /// Fallback path (Apple `.p8` keys): Apple's PKCS#8 keys embed optional
    /// `[0] ECParameters` and `[1] ECPoint` fields inside the `ECPrivateKey`
    /// SEQUENCE. swift-asn1 1.x throws `CryptoKitASN1Error.unhandledEncoding`
    /// (error 7) when it encounters those context tags. The fallback scans the
    /// raw DER for the known marker `02 01 01 04 20` (ECPrivateKey version +
    /// 32-byte private-scalar OCTET STRING) and constructs the key directly
    /// from the scalar bytes, bypassing swift-asn1 entirely.
    static func loadES256Key(pem: String) throws -> ES256PrivateKey {
        // 1. Try the normal path first (handles SEC1 and well-formed PKCS#8).
        if let key = try? ES256PrivateKey(pem: pem) {
            return key
        }

        // 2. Fallback: extract the raw 32-byte scalar from PKCS#8 DER directly.
        let scalar = try JWTGenerator.rawPrivateScalar(fromPKCS8PEM: pem)
        let p256Key = try P256.Signing.PrivateKey(rawRepresentation: scalar)
        return try ES256PrivateKey(backing: p256Key)
    }

    /// Extracts the 32-byte P-256 private scalar from a PKCS#8 PEM string
    /// by scanning the raw DER for the ECPrivateKey marker sequence.
    ///
    /// The marker `[0x02, 0x01, 0x01, 0x04, 0x20]` is:
    /// - `02 01 01` — `ECPrivateKey.version` INTEGER value 1
    /// - `04 20`    — `ECPrivateKey.privateKey` OCTET STRING, length 32
    ///
    /// The 32 bytes that follow are the raw big-endian private scalar.
    static func rawPrivateScalar(fromPKCS8PEM pem: String) throws -> Data {
        let b64 = pem
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("-") }
            .joined()
        guard let der = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
            throw JWTGeneratorError.invalidKeyEncoding
        }

        let bytes = [UInt8](der)
        let marker: [UInt8] = [0x02, 0x01, 0x01, 0x04, 0x20]
        let scalarLength = 32
        guard bytes.count > marker.count + scalarLength else {
            throw JWTGeneratorError.invalidKeyEncoding
        }

        for i in 0...(bytes.count - marker.count - scalarLength) {
            if bytes[i..<(i + marker.count)].elementsEqual(marker) {
                let start = i + marker.count
                return Data(bytes[start..<(start + scalarLength)])
            }
        }

        throw JWTGeneratorError.invalidKeyEncoding
    }

    /// Converts raw `.p8` key bytes to a clean PEM string.
    ///
    /// Uses a strict (non-lossy) UTF-8 decode so that corrupted data raises an
    /// error instead of silently replacing bad bytes with `\uFFFD`, which would
    /// corrupt the base64 payload and cause `CryptoKitASN1Error` downstream.
    /// Strips a leading UTF-8 BOM (`\u{FEFF}`) and trims surrounding whitespace
    /// so that files saved by certain editors/CI tools parse correctly.
    static func pemString(from data: Data) throws -> String {
        guard var pem = String(data: data, encoding: .utf8) else {
            throw JWTGeneratorError.invalidKeyEncoding
        }
        // Strip UTF-8 BOM if present (some editors/tools prepend U+FEFF)
        if pem.hasPrefix("\u{FEFF}") {
            pem = String(pem.dropFirst())
        }
        pem = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pem.isEmpty else {
            throw JWTGeneratorError.invalidKeyEncoding
        }
        guard pem.hasPrefix("-----BEGIN") else {
            throw JWTGeneratorError.missingPEMHeader
        }
        return pem
    }
}

// MARK: - JWTGeneratorError

/// Errors thrown by ``JWTGenerator`` before reaching the JWT-signing layer.
public enum JWTGeneratorError: Error, Sendable {
    /// The private key data could not be decoded as UTF-8 PEM text.
    case invalidKeyEncoding
    /// The data does not begin with a PEM header (`-----BEGIN`).
    /// Most likely cause: App Store Connect credentials are not configured
    /// (ASC_PRIVATE_KEY / ASC_PRIVATE_KEY_PATH not set or not exported).
    case missingPEMHeader
}

// MARK: - JWT Payload

/// JWT payload structure for App Store Connect API authentication.
private struct ASCJWTPayload: JWTPayload {
    var issuerID: IssuerClaim
    var issuedAt: IssuedAtClaim
    var expiresAt: ExpirationClaim
    var audience: AudienceClaim
    var scope: [String]?

    init(
        issuerID: String,
        issuedAt: Date,
        expiresAt: Date,
        audience: String,
        scope: [String]?
    ) {
        self.issuerID = IssuerClaim(value: issuerID)
        self.issuedAt = IssuedAtClaim(value: issuedAt)
        self.expiresAt = ExpirationClaim(value: expiresAt)
        self.audience = AudienceClaim(value: audience)
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case issuerID = "iss"
        case issuedAt = "iat"
        case expiresAt = "exp"
        case audience = "aud"
        case scope
    }

    func verify(using _: some JWTAlgorithm) async throws {
        try expiresAt.verifyNotExpired()
    }
}
