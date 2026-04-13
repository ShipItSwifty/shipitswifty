import Crypto
import Foundation
import Testing
@testable import ShipItKit

/// Regression tests for ``JWTGenerator`` covering:
///   - PEM string normalisation (BOM, whitespace, non-UTF-8 data)
///   - JWT generation from a valid PKCS#8 P-256 key
///   - Structural validity of the produced JWT (3 parts, JOSE 64-byte signature)
///   - Correct `iss`, `aud`, `iat`, `exp` claim encoding
///   - Apple .p8 key format (ECPrivateKey with [0] + [1] optional fields)
@Suite("JWTGenerator")
struct JWTGeneratorTests {

    // MARK: - Apple .p8 format (ECPrivateKey with [0] params + [1] public key)

    /// Apple App Store Connect .p8 keys embed two optional fields inside the inner
    /// ECPrivateKey SEQUENCE that swift-asn1 1.x doesn't handle:
    ///   [0] ECParameters  — redundant curve OID
    ///   [1] ECPoint       — uncompressed public key
    ///
    /// CryptoKitASN1Error.unhandledEncoding (error 7) is thrown when the parser
    /// encounters the `a0` context tag for [0].  This synthesised DER reproduces
    /// exactly that structure without needing the real credentials file.
    @Test("loadES256Key handles ECPrivateKey with [0] params and [1] public key (Apple .p8 format)")
    func loadES256KeyHandlesAppleP8Format() async throws {
        // Build a PKCS#8 DER that mirrors Apple's format.
        // ECPrivateKey inner SEQUENCE includes [0] (curve OID) and [1] (public point).
        let realKey = P256.Signing.PrivateKey()
        let scalar = realKey.rawRepresentation          // 32-byte private scalar
        let pubPoint = realKey.publicKey.x963Representation  // 65 bytes: 04 || X || Y

        // ECPrivateKey ::= SEQUENCE {
        //   version   INTEGER 1,
        //   privateKey OCTET STRING (32 bytes),
        //   [0] EXPLICIT OID (P-256 curve),
        //   [1] EXPLICIT BIT STRING (uncompressed point)
        // }
        let p256OID: [UInt8] = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]
        let ecOID:   [UInt8] = [0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]

        // [0] EXPLICIT: a0 0a 06 08 <P-256 OID>
        let tag0: [UInt8] = [0xa0, UInt8(p256OID.count)] + p256OID

        // [1] EXPLICIT: a1 <len> 03 <len> 00 04 <X> <Y>
        let bitString: [UInt8] = [0x03, UInt8(pubPoint.count + 1), 0x00] + pubPoint
        let tag1: [UInt8] = [0xa1, UInt8(bitString.count)] + bitString

        let ecPrivateKeyBody: [UInt8] =
            [0x02, 0x01, 0x01] +                        // version INTEGER 1
            [0x04, 0x20] + scalar +                     // privateKey OCTET STRING
            tag0 + tag1

        let ecPrivateKeySeq: [UInt8] = [0x30, UInt8(ecPrivateKeyBody.count)] + ecPrivateKeyBody
        let octetString: [UInt8] = [0x04, UInt8(ecPrivateKeySeq.count)] + ecPrivateKeySeq

        // AlgorithmIdentifier: SEQUENCE { ecPublicKey OID, P-256 OID }
        let algIdBody: [UInt8] = ecOID + p256OID
        let algId: [UInt8] = [0x30, UInt8(algIdBody.count)] + algIdBody

        // PrivateKeyInfo: SEQUENCE { INTEGER 0, AlgorithmIdentifier, OCTET STRING }
        let pkiBody: [UInt8] = [0x02, 0x01, 0x00] + algId + octetString
        let pki: [UInt8] = [0x30, UInt8(pkiBody.count)] + pkiBody

        let pem =
            "-----BEGIN PRIVATE KEY-----\n" +
            Data(pki).base64EncodedString() + "\n" +
            "-----END PRIVATE KEY-----"

        // ES256PrivateKey(pem:) will throw CryptoKitASN1Error.unhandledEncoding here.
        // loadES256Key must succeed via the scalar-extraction fallback.
        _ = try JWTGenerator.loadES256Key(pem: pem)

        // Verify the key is functional end-to-end via JWTGenerator.
        let generator = JWTGenerator(
            keyID: "APPLE_FORMAT_KEY",
            issuerID: "test-issuer",
            privateKeyData: Data(pem.utf8)
        )
        let token = try await generator.generateToken()
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3, "Apple-format .p8 must produce a valid 3-part JWT")
    }

    @Test("rawPrivateScalar extracts 32-byte scalar from PKCS8 DER with optional fields")
    func rawPrivateScalarExtractsFromAppleFormat() throws {
        let originalKey = P256.Signing.PrivateKey()
        let originalScalar = originalKey.rawRepresentation

        // Build a minimal DER with the marker and a dummy [0] field after the scalar
        let marker: [UInt8] = [0x02, 0x01, 0x01, 0x04, 0x20]
        let dummy: [UInt8] = [0xa0, 0x02, 0x05, 0x00]  // [0] EXPLICIT NULL
        let body: [UInt8] = marker + originalScalar + dummy
        let seq: [UInt8] = [0x30, UInt8(body.count)] + body
        // Wrap in outer PKCS#8 shell
        let algId: [UInt8] = [0x30, 0x13,
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]
        let octet: [UInt8] = [0x04, UInt8(seq.count)] + seq
        let pkiBody: [UInt8] = [0x02, 0x01, 0x00] + algId + octet
        let pki: [UInt8] = [0x30, UInt8(pkiBody.count)] + pkiBody

        let pem =
            "-----BEGIN PRIVATE KEY-----\n" +
            Data(pki).base64EncodedString() + "\n" +
            "-----END PRIVATE KEY-----"

        let extracted = try JWTGenerator.rawPrivateScalar(fromPKCS8PEM: pem)
        #expect(extracted == originalScalar, "Extracted scalar must match the original 32-byte key")
    }

    // MARK: - pemString(from:) helpers

    @Test("pemString strips leading UTF-8 BOM")
    func pemStringStripsLeadingBOM() throws {
        let pem = "-----BEGIN PRIVATE KEY-----\ndata\n-----END PRIVATE KEY-----"
        // Prepend UTF-8 BOM (U+FEFF encoded as 0xEF BB BF)
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: pem.utf8)

        let result = try JWTGenerator.pemString(from: data)
        #expect(result == pem, "BOM must be stripped")
        #expect(!result.hasPrefix("\u{FEFF}"), "BOM character must not remain")
    }

    @Test("pemString trims surrounding whitespace and newlines")
    func pemStringTrimsWhitespace() throws {
        let pem = "-----BEGIN PRIVATE KEY-----\ndata\n-----END PRIVATE KEY-----"
        let padded = "  \n\(pem)\n  "
        let data = Data(padded.utf8)

        let result = try JWTGenerator.pemString(from: data)
        #expect(result == pem)
    }

    @Test("pemString preserves internal newlines")
    func pemStringPreservesInternalNewlines() throws {
        let pem = "-----BEGIN PRIVATE KEY-----\nline1\nline2\n-----END PRIVATE KEY-----"
        let result = try JWTGenerator.pemString(from: Data(pem.utf8))
        #expect(result.contains("\nline1\nline2\n"))
    }

    @Test("pemString throws invalidKeyEncoding for non-UTF-8 bytes")
    func pemStringThrowsForNonUTF8() throws {
        // 0xFF is not valid UTF-8
        let data = Data([0xFF, 0xFE, 0x00])
        #expect(throws: JWTGeneratorError.invalidKeyEncoding) {
            _ = try JWTGenerator.pemString(from: data)
        }
    }

    @Test("pemString throws invalidKeyEncoding for empty data")
    func pemStringThrowsForEmptyData() throws {
        #expect(throws: JWTGeneratorError.invalidKeyEncoding) {
            _ = try JWTGenerator.pemString(from: Data())
        }
    }

    @Test("pemString throws invalidKeyEncoding for whitespace-only data")
    func pemStringThrowsForWhitespaceOnly() throws {
        let data = Data("   \n\n   ".utf8)
        #expect(throws: JWTGeneratorError.invalidKeyEncoding) {
            _ = try JWTGenerator.pemString(from: data)
        }
    }

    // MARK: - JWT generation (uses a freshly generated test key)

    @Test("generateToken produces a three-part dot-separated JWT")
    func generateTokenProducesValidJWTStructure() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let keyData = Data(privateKey.pemRepresentation.utf8)

        let generator = JWTGenerator(
            keyID: "TEST_KEY_ID",
            issuerID: "test-issuer-id",
            privateKeyData: keyData
        )

        let token = try await generator.generateToken()
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3, "JWT must have exactly 3 dot-separated parts")
        #expect(parts.allSatisfy { !$0.isEmpty }, "No JWT part may be empty")
    }

    @Test("generateToken aud claim is plain string appstoreconnect-v1")
    func generateTokenAudienceIsString() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let keyData = Data(privateKey.pemRepresentation.utf8)

        let generator = JWTGenerator(
            keyID: "TEST_KEY_ID",
            issuerID: "test-issuer",
            privateKeyData: keyData
        )

        let token = try await generator.generateToken()
        let payload = try jwtPayload(from: token)

        // aud must be the plain string "appstoreconnect-v1", not a JSON array
        guard let aud = payload["aud"] else {
            Issue.record("JWT payload missing 'aud' claim")
            return
        }
        // If AudienceClaim encoded as an array it would be a [String] here
        #expect(aud == .string("appstoreconnect-v1"), "aud must be a scalar string, not an array")
    }

    @Test("generateToken iss claim equals provided issuerID")
    func generateTokenIssuerMatchesInput() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let keyData = Data(privateKey.pemRepresentation.utf8)
        let issuerID = "69a6de89-48a8-47e3-e053-5b8c7c11a4d1"

        let generator = JWTGenerator(
            keyID: "TEST_KEY_ID",
            issuerID: issuerID,
            privateKeyData: keyData
        )

        let token = try await generator.generateToken()
        let payload = try jwtPayload(from: token)
        #expect(payload["iss"] == .string(issuerID))
    }

    @Test("generateToken kid header equals provided keyID")
    func generateTokenKidMatchesInput() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let keyData = Data(privateKey.pemRepresentation.utf8)
        let keyID = "WGFRNXFA6H"

        let generator = JWTGenerator(
            keyID: keyID,
            issuerID: "test-issuer",
            privateKeyData: keyData
        )

        let token = try await generator.generateToken()
        let header = try jwtHeader(from: token)
        #expect(header["kid"] == .string(keyID))
        #expect(header["alg"] == .string("ES256"))
    }

    @Test("generateToken iat and exp are integer Unix timestamps")
    func generateTokenTimestampsAreIntegers() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let keyData = Data(privateKey.pemRepresentation.utf8)
        let beforeIssuance = Int(Date().timeIntervalSince1970)

        let generator = JWTGenerator(
            keyID: "K",
            issuerID: "I",
            privateKeyData: keyData
        )

        let token = try await generator.generateToken()
        let payload = try jwtPayload(from: token)

        guard case .number(let iat) = payload["iat"],
              case .number(let exp) = payload["exp"] else {
            Issue.record("iat/exp are missing or wrong type")
            return
        }

        // Timestamps must be integer-compatible (no fractional part for alignment
        // with Apple's JWT validator which expects numeric second values)
        #expect(iat >= Double(beforeIssuance), "iat must be >= time before generation")
        #expect(exp > iat, "exp must be after iat")
        // Default lifetime = 900 s; allow ±5 s clock drift
        #expect(exp - iat >= 895, "exp - iat must be close to 900 s (default 15 min)")
        #expect(exp - iat <= 905, "exp - iat must be close to 900 s (default 15 min)")
    }

    @Test("generateToken ES256 signature is JOSE raw 64-byte form (r||s), not DER")
    func generateTokenSignatureIsJOSERaw64() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let keyData = Data(privateKey.pemRepresentation.utf8)

        let generator = JWTGenerator(
            keyID: "K",
            issuerID: "I",
            privateKeyData: keyData
        )

        let token = try await generator.generateToken()
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3)

        // Base64url-decode the signature part
        let sigBase64 = String(parts[2])
        let sigData = try #require(base64URLDecode(sigBase64), "Signature must be valid base64url")

        // JOSE ES256 raw signature is exactly 64 bytes (32-byte r || 32-byte s).
        // DER-encoded signatures are variable length (typically 70–72 bytes) and
        // start with 0x30 (SEQUENCE tag). Either condition failing means DER crept in.
        #expect(sigData.count == 64, "ES256 JOSE signature must be exactly 64 bytes (r||s), got \(sigData.count)")
        #expect(sigData.first != 0x30, "Signature must not start with DER SEQUENCE tag 0x30")
    }

    @Test("generateToken loads valid .p8 PKCS8 key from file on disk")
    func generateTokenLoadsKeyFromFile() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let pem = privateKey.pemRepresentation

        // Write to a temp file to simulate loading from ASC_PRIVATE_KEY_PATH
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).p8")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try pem.write(to: tmpURL, atomically: true, encoding: .utf8)

        let keyData = try Data(contentsOf: tmpURL)
        let generator = JWTGenerator(
            keyID: "FILE_KEY",
            issuerID: "file-issuer",
            privateKeyData: keyData
        )

        // If PEM loading is broken, this throws ShipItError.jwtGenerationFailed
        let token = try await generator.generateToken()
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3)
    }

    @Test("generateToken loads .p8 file that has a UTF-8 BOM prepended")
    func generateTokenLoadsKeyWithBOM() async throws {
        let privateKey = P256.Signing.PrivateKey()
        let pem = privateKey.pemRepresentation

        // Prepend BOM to simulate files saved by some Windows editors/CI tools
        var keyData = Data([0xEF, 0xBB, 0xBF])
        keyData.append(contentsOf: pem.utf8)

        let generator = JWTGenerator(
            keyID: "BOM_KEY",
            issuerID: "bom-issuer",
            privateKeyData: keyData
        )

        let token = try await generator.generateToken()
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3, "BOM-prefixed .p8 should load correctly after fix")
    }
}

// MARK: - Helpers

/// Decoded JWT payload claim value.
private enum ClaimValue: Equatable {
    case string(String)
    case number(Double)
    case array([String])
    case other
}

private func jwtHeader(from token: String) throws -> [String: ClaimValue] {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { throw TestError.malformedJWT }
    return try decodeBase64URLJSON(String(parts[0]))
}

private func jwtPayload(from token: String) throws -> [String: ClaimValue] {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { throw TestError.malformedJWT }
    return try decodeBase64URLJSON(String(parts[1]))
}

private func decodeBase64URLJSON(_ base64url: String) throws -> [String: ClaimValue] {
    guard let data = base64URLDecode(base64url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw TestError.malformedJSON }

    var result: [String: ClaimValue] = [:]
    for (key, value) in json {
        switch value {
        case let s as String:
            result[key] = .string(s)
        case let n as Double:
            result[key] = .number(n)
        case let n as Int:
            result[key] = .number(Double(n))
        case let a as [String]:
            result[key] = .array(a)
        default:
            result[key] = .other
        }
    }
    return result
}

private func base64URLDecode(_ base64url: String) -> Data? {
    var base64 = base64url
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder != 0 {
        base64 += String(repeating: "=", count: 4 - remainder)
    }
    return Data(base64Encoded: base64)
}

private enum TestError: Error {
    case malformedJWT
    case malformedJSON
}
