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
            let pemString = String(decoding: privateKeyData, as: UTF8.self)
            let ecKey = try ES256PrivateKey(pem: pemString)
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
