#if os(macOS)
import Foundation
import Logging

/// Manages provisioning profiles — creating via ASC API and installing locally.
///
/// ## Usage
/// ```swift
/// let manager = ProfileManager()
/// let profile = try await manager.createProfile(
///     bundleId: "com.example.myapp",
///     type: "IOS_APP_STORE",
///     context: context
/// )
/// try await manager.install(profile: profile, context: context)
/// ```
public struct ProfileManager: Sendable {
    private let logger = Logger.forType(subsystem: "ShipItSwifty", ProfileManager.self)

    /// Creates a `ProfileManager`.
    public init() {}

    /// Create a provisioning profile via the App Store Connect API.
    ///
    /// - Parameters:
    ///   - bundleId: The app bundle identifier.
    ///   - type: Profile type: `IOS_APP_STORE`, `IOS_APP_ADHOC`, `IOS_APP_DEVELOPMENT`.
    ///   - certificateIds: IDs of certificates to include in the profile.
    ///   - deviceIds: IDs of devices to include (for development/adhoc).
    ///   - context: Shell execution context.
    /// - Returns: A `ProvisioningProfileInfo` with the profile data.
    public func createProfile(
        bundleId: String,
        type: String = "IOS_APP_STORE",
        certificateIds: [String] = [],
        deviceIds: [String] = [],
        context: ActionContext
    ) async throws -> ProvisioningProfileInfo {
        logger.info("Creating provisioning profile for: \(bundleId) (type: \(type))")

        // Look up the bundle ID resource
        let bundleIds: ASCListResponse<BundleIdResource> = try await context.appStoreConnect.get(
            "/v1/bundleIds",
            query: ["filter[identifier]": bundleId]
        )

        guard let bundleIdResource = bundleIds.data.first else {
            throw ShipItError.signingResourceNotFound(description: "Bundle ID '\(bundleId)' not found in ASC")
        }

        let body = CreateProfileRequest(
            data: .init(
                type: "profiles",
                attributes: .init(
                    name: "\(bundleId) \(type)",
                    profileType: type
                ),
                relationships: .init(
                    bundleId: .init(data: .init(type: "bundleIds", id: bundleIdResource.id)),
                    certificates: .init(
                        data: certificateIds.map { .init(type: "certificates", id: $0) }
                    ),
                    devices: deviceIds.isEmpty
                        ? nil
                        : .init(
                            data: deviceIds.map { .init(type: "devices", id: $0) }
                        )
                )
            )
        )

        let response: ASCResponse<ProfileResource> = try await context.appStoreConnect.post(
            "/v1/profiles",
            body: body
        )

        logger.info("Profile created: \(response.data.id)")
        return ProvisioningProfileInfo(
            id: response.data.id,
            name: response.data.attributes?.name ?? bundleId,
            profileContent: response.data.attributes?.profileContent ?? "",
            expirationDate: response.data.attributes?.expirationDate
        )
    }

    /// Install a provisioning profile to the user's Provisioning Profiles directory.
    ///
    /// - Parameters:
    ///   - profile: The profile info containing the base64-encoded profile content.
    ///   - context: Shell execution context (unused but kept for consistency).
    public func install(profile: ProvisioningProfileInfo, context: ActionContext) async throws {
        logger.info("Installing profile: \(profile.name)")

        let profilesDir = NSHomeDirectory() + "/Library/MobileDevice/Provisioning Profiles"
        try FileManager.default.createDirectory(
            atPath: profilesDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Decode base64 profile content
        guard let profileData = Data(base64Encoded: profile.profileContent) else {
            throw ShipItError.signingResourceNotFound(description: "Invalid profile content for: \(profile.name)")
        }

        let fileName = "\(profile.id).mobileprovision"
        let destPath = profilesDir + "/" + fileName
        try profileData.write(to: URL(fileURLWithPath: destPath))

        logger.info("Profile installed: \(destPath)")
    }
}

/// Information about a provisioning profile.
public struct ProvisioningProfileInfo: Sendable {
    /// App Store Connect profile ID.
    public let id: String

    /// Human-readable profile name.
    public let name: String

    /// Base64-encoded profile content (`.mobileprovision`).
    public let profileContent: String

    /// ISO 8601 expiration date string.
    public let expirationDate: String?

    /// Creates a `ProvisioningProfileInfo`.
    ///
    /// - Parameters:
    ///   - id: App Store Connect profile ID.
    ///   - name: Human-readable profile name.
    ///   - profileContent: Base64-encoded `.mobileprovision` content.
    ///   - expirationDate: ISO 8601 expiration date string.
    public init(id: String, name: String, profileContent: String, expirationDate: String? = nil) {
        self.id = id
        self.name = name
        self.profileContent = profileContent
        self.expirationDate = expirationDate
    }
}

// MARK: - Private Models

private struct BundleIdResource: Codable, Sendable {
    let id: String
    let attributes: Attributes?
    struct Attributes: Codable, Sendable {
        let identifier: String?
        let name: String?
    }
}

private struct CreateProfileRequest: Encodable, Sendable {
    let data: DataBody
    struct DataBody: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
        struct Attributes: Encodable, Sendable {
            let name: String
            let profileType: String
        }
        struct Relationships: Encodable, Sendable {
            let bundleId: RelationshipData
            let certificates: RelationshipList
            let devices: RelationshipList?
        }
    }
}

private struct RelationshipData: Encodable, Sendable {
    let data: ResourceRef
}

private struct RelationshipList: Encodable, Sendable {
    let data: [ResourceRef]
}

private struct ResourceRef: Encodable, Sendable {
    let type: String
    let id: String
}

private struct ProfileResource: Codable, Sendable {
    let id: String
    let attributes: Attributes?
    struct Attributes: Codable, Sendable {
        let name: String?
        let profileType: String?
        let profileContent: String?
        let expirationDate: String?
        let profileState: String?
    }
}
#endif
