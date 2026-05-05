#if os(macOS)
import Foundation
import Logging

/// Creates App IDs on the Apple Developer Portal and registers devices.
///
/// Uses the App Store Connect API to manage bundle IDs, device registrations,
/// and capabilities.
///
/// ## Usage
/// ```swift
/// let result = try await ProvisionAction().run(
///     with: .init(operation: .createAppId, bundleId: "com.example.myapp"),
///     context: context
/// )
/// ```
public struct ProvisionAction: Action {
    public static let name = "provision"
    public static let description = "Manage App IDs, devices, and capabilities"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", ProvisionAction.self)

    /// Creates a `ProvisionAction`.
    public init() {}

    /// Provisioning operations.
    public enum ProvisionOperation: String, Codable, Sendable {
        /// Create a new App ID (bundle ID) on the Developer Portal.
        case createAppId
        /// Register one or more devices by UDID.
        case registerDevices
        /// List registered devices.
        case listDevices
        /// List bundle IDs registered in the team.
        case listBundleIds
    }

    /// Configuration for provisioning.
    public struct Options: Codable, Sendable {
        /// Operation to perform.
        public var operation: ProvisionOperation

        /// Bundle ID to create (for `createAppId`).
        public var bundleId: String?

        /// App name for the new bundle ID.
        public var appName: String?

        /// Device UDIDs to register (for `registerDevices`).
        public var deviceUDIDs: [String]?

        /// Device names corresponding to the UDIDs.
        public var deviceNames: [String]?

        /// Creates `Options` for the provision action.
        ///
        /// - Parameter operation: The provisioning operation to perform.
        /// - Parameter bundleId: Bundle ID to create (for `createAppId`).
        /// - Parameter appName: App name for the new bundle ID.
        /// - Parameter deviceUDIDs: Device UDIDs to register (for `registerDevices`).
        /// - Parameter deviceNames: Device names corresponding to the UDIDs.
        public init(
            operation: ProvisionOperation = .listBundleIds,
            bundleId: String? = nil,
            appName: String? = nil,
            deviceUDIDs: [String]? = nil,
            deviceNames: [String]? = nil
        ) {
            self.operation = operation
            self.bundleId = bundleId
            self.appName = appName
            self.deviceUDIDs = deviceUDIDs
            self.deviceNames = deviceNames
        }
    }

    /// Result of a provision operation.
    public struct Result: Codable, Sendable {
        /// IDs of created or listed resources.
        public let resourceIDs: [String]

        /// Human-readable summary.
        public let message: String

        /// Creates a `Result`.
        public init(resourceIDs: [String] = [], message: String) {
            self.resourceIDs = resourceIDs
            self.message = message
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        logger.info("Provision operation: \(options.operation.rawValue)")

        switch options.operation {
        case .createAppId:
            return try await createAppId(options: options, context: context)
        case .registerDevices:
            return try await registerDevices(options: options, context: context)
        case .listDevices:
            return try await listDevices(context: context)
        case .listBundleIds:
            return try await listBundleIds(context: context)
        }
    }

    // MARK: - Operations

    private func createAppId(options: Options, context: ActionContext) async throws -> Result {
        let bundleId = options.bundleId ?? context.config.bundleID
        guard let bundleId else {
            throw ShipItError.invalidConfiguration(reason: "createAppId requires a bundle ID")
        }
        let appName = options.appName ?? bundleId

        logger.info("Creating App ID: \(bundleId)")

        let body = CreateBundleIdRequest(
            data: .init(
                type: "bundleIds",
                attributes: .init(
                    identifier: bundleId,
                    name: appName,
                    platform: "IOS"
                )
            )
        )

        let response: ASCResponse<BundleIdResource> = try await context.appStoreConnect.post(
            "/v1/bundleIds",
            body: body
        )

        logger.info("Created App ID: \(response.data.id)")
        return Result(resourceIDs: [response.data.id], message: "Created App ID '\(bundleId)' with ID \(response.data.id)")
    }

    private func registerDevices(options: Options, context: ActionContext) async throws -> Result {
        let udids = options.deviceUDIDs ?? []
        let names = options.deviceNames ?? udids

        guard !udids.isEmpty else {
            throw ShipItError.invalidConfiguration(reason: "registerDevices requires at least one UDID")
        }

        var registeredIDs: [String] = []

        for (index, udid) in udids.enumerated() {
            let name = index < names.count ? names[index] : udid
            logger.info("Registering device: \(name) (\(udid))")

            let body = RegisterDeviceRequest(
                data: .init(
                    type: "devices",
                    attributes: .init(name: name, udid: udid, platform: "IOS")
                )
            )

            let response: ASCResponse<DeviceResource> = try await context.appStoreConnect.post(
                "/v1/devices",
                body: body
            )
            registeredIDs.append(response.data.id)
        }

        return Result(resourceIDs: registeredIDs, message: "Registered \(registeredIDs.count) device(s)")
    }

    private func listDevices(context: ActionContext) async throws -> Result {
        let devices: ASCListResponse<DeviceResource> = try await context.appStoreConnect.get("/v1/devices")
        let ids = devices.data.map { $0.id }
        return Result(resourceIDs: ids, message: "Found \(ids.count) registered device(s)")
    }

    private func listBundleIds(context: ActionContext) async throws -> Result {
        let bundleIds: ASCListResponse<BundleIdResource> = try await context.appStoreConnect.get("/v1/bundleIds")
        let ids = bundleIds.data.map { $0.id }
        return Result(resourceIDs: ids, message: "Found \(ids.count) bundle ID(s)")
    }
}

// MARK: - Private Models

private struct CreateBundleIdRequest: Encodable, Sendable {
    let data: DataBody
    struct DataBody: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        struct Attributes: Encodable, Sendable {
            let identifier: String
            let name: String
            let platform: String
        }
    }
}

private struct RegisterDeviceRequest: Encodable, Sendable {
    let data: DataBody
    struct DataBody: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        struct Attributes: Encodable, Sendable {
            let name: String
            let udid: String
            let platform: String
        }
    }
}

private struct BundleIdResource: Codable, Sendable {
    let id: String
    let attributes: Attributes?
    struct Attributes: Codable, Sendable {
        let identifier: String?
        let name: String?
    }
}

private struct DeviceResource: Codable, Sendable {
    let id: String
    let attributes: Attributes?
    struct Attributes: Codable, Sendable {
        let name: String?
        let udid: String?
        let status: String?
    }
}
#endif
