#if os(macOS)
import AppStoreConnectKit
import Foundation
import Logging

/// Manages code signing certificates — syncing from encrypted storage and
/// creating new certificates via the App Store Connect API.
///
/// ## Usage
/// ```swift
/// let manager = CertificateManager()
/// try await manager.sync(
///     gitUrl: "git@github.com:myteam/certs.git",
///     profileType: "appstore",
///     ciMode: true,
///     context: context
/// )
/// ```
public struct CertificateManager: Sendable {
    private let logger = Logger.forType(subsystem: "ShipItSwifty", CertificateManager.self)

    /// Creates a `CertificateManager`.
    public init() {}

    /// Sync certificates and provisioning profiles from the encrypted storage repository.
    ///
    /// - Parameters:
    ///   - gitUrl: URL of the encrypted certificate Git repository.
    ///   - profileType: Profile type: `development`, `adhoc`, `appstore`, or `enterprise`.
    ///   - ciMode: Whether to create a temporary CI keychain.
    ///   - context: Shell execution context.
    public func sync(
        gitUrl: String,
        profileType: String,
        ciMode: Bool,
        context: ActionContext
    ) async throws {
        logger.info("Syncing certificates for profile type: \(profileType)")
        let storage = CertVault(gitUrl: gitUrl)
        try await storage.sync(profileType: profileType, ciMode: ciMode, context: context)
    }

    /// Create a new distribution certificate via the App Store Connect API.
    ///
    /// - Parameters:
    ///   - certificateType: The type of certificate to create (e.g. `IOS_DISTRIBUTION`).
    ///   - context: Shell execution context.
    /// - Returns: The certificate serial number and PEM data.
    public func createCertificate(
        certificateType: String = "IOS_DISTRIBUTION",
        context: ActionContext
    ) async throws -> CertificateInfo {
        logger.info("Creating certificate of type: \(certificateType)")

        // Generate a CSR (certificate signing request)
        let csrData = try await generateCSR(context: context)

        // Submit to ASC
        let body = CreateCertificateRequest(
            data: .init(
                type: "certificates",
                attributes: .init(
                    certificateType: certificateType,
                    csrContent: csrData
                )
            )
        )

        let response: ASCResponse<CertificateResource> = try await mappingASCErrors {
            try await context.appStoreConnect.post("/v1/certificates", body: body)
        }

        logger.info("Certificate created: \(response.data.id)")
        return CertificateInfo(
            id: response.data.id,
            serialNumber: response.data.attributes?.serialNumber ?? response.data.id,
            pemData: response.data.attributes?.certificateContent ?? ""
        )
    }

    // MARK: - Private

    private func generateCSR(context: ActionContext) async throws -> String {
        // In a real implementation, use `openssl req` or CryptoKit to generate a CSR
        // This is a placeholder
        logger.warning("CSR generation is a placeholder in this version")
        return "PLACEHOLDER_CSR"
    }
}

/// Information about a code signing certificate.
public struct CertificateInfo: Sendable {
    /// App Store Connect certificate ID.
    public let id: String

    /// Certificate serial number.
    public let serialNumber: String

    /// PEM-encoded certificate content.
    public let pemData: String

    /// Creates a `CertificateInfo`.
    ///
    /// - Parameters:
    ///   - id: App Store Connect certificate ID.
    ///   - serialNumber: Certificate serial number.
    ///   - pemData: PEM-encoded certificate content.
    public init(id: String, serialNumber: String, pemData: String) {
        self.id = id
        self.serialNumber = serialNumber
        self.pemData = pemData
    }
}

// MARK: - Private Request Models

private struct CreateCertificateRequest: Encodable, Sendable {
    let data: DataBody
    struct DataBody: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        struct Attributes: Encodable, Sendable {
            let certificateType: String
            let csrContent: String
        }
    }
}

private struct CertificateResource: Codable, Sendable {
    let id: String
    let attributes: Attributes?
    struct Attributes: Codable, Sendable {
        let serialNumber: String?
        let certificateContent: String?
        let name: String?
        let certificateType: String?
    }
}
#endif
