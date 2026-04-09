import Foundation
import OSLog

/// Coordinates the App Store Connect IPA upload workflow.
///
/// This encapsulates the reserve, upload, and commit phases so both the CLI
/// and server can reuse the same implementation.
public struct IPAUploadService: Sendable {
    private let client: AppStoreConnectClient
    private let logger = Logger.forType(subsystem: "ShipItSwifty", IPAUploadService.self)

    /// Creates an `IPAUploadService` bound to an ASC client.
    public init(client: AppStoreConnectClient) {
        self.client = client
    }

    /// Result of a completed IPA upload.
    public struct Result: Codable, Sendable {
        /// The App Store Connect app ID the IPA was uploaded to.
        public let appID: String
        /// The build ID assigned by App Store Connect.
        public let buildID: String
        /// The original IPA file name.
        public let fileName: String

        /// Creates an `IPAUploadService.Result`.
        public init(appID: String, buildID: String, fileName: String) {
            self.appID = appID
            self.buildID = buildID
            self.fileName = fileName
        }
    }

    /// Uploads an IPA file for the given bundle identifier.
    ///
    /// - Parameters:
    ///   - ipaURL: Local path to the IPA file.
    ///   - bundleID: App bundle identifier used to resolve the ASC app.
    /// - Returns: The uploaded build metadata.
    public func uploadIPA(at ipaURL: URL, bundleID: String) async throws -> Result {
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            throw ShipItError.uploadFailed(asset: ipaURL.lastPathComponent, reason: "IPA file not found at: \(ipaURL.path)")
        }

        logger.info("Uploading IPA '\(ipaURL.lastPathComponent)' for bundle ID '\(bundleID)'")

        let apps: ASCListResponse<ASCApp> = try await client.get(
            "/v1/apps",
            query: ["filter[bundleId]": bundleID]
        )

        guard let app = apps.data.first else {
            throw ShipItError.apiError(statusCode: 404, body: "App with bundle ID '\(bundleID)' not found in App Store Connect")
        }

        let reservationBody = UploadReservationRequest(
            data: .init(
                type: "builds",
                attributes: .init(
                    fileName: ipaURL.lastPathComponent,
                    fileSize: try fileSize(at: ipaURL),
                    appID: app.id
                )
            )
        )

        let reservation: ASCResponse<UploadReservationData> = try await client.post(
            "/v1/builds",
            body: reservationBody
        )

        let uploadReservation = UploadReservation(
            id: reservation.data.id,
            operations: reservation.data.attributes?.uploadOperations?.map { operation in
                UploadOperation(
                    method: operation.method,
                    url: operation.url,
                    offset: operation.offset,
                    length: operation.length,
                    requestHeaders: operation.requestHeaders?.map {
                        UploadHeader(name: $0.name, value: $0.value)
                    }
                )
            } ?? []
        )

        let commit = try await client.uploadAsset(at: ipaURL, reservation: uploadReservation)
        let commitBody = BuildCommitRequest(
            data: .init(
                type: "builds",
                id: commit.id,
                attributes: .init(uploaded: true, checksum: commit.checksum)
            )
        )

        let _: ASCResponse<ASCBuild> = try await client.patch(
            "/v1/builds/\(commit.id)",
            body: commitBody
        )

        logger.info("Completed IPA upload for build '\(commit.id)'")
        return Result(appID: app.id, buildID: commit.id, fileName: ipaURL.lastPathComponent)
    }

    private func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? Int else {
            throw ShipItError.uploadFailed(asset: url.lastPathComponent, reason: "Cannot determine file size")
        }
        return size
    }
}

struct UploadReservationRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let attributes: Attributes

        struct Attributes: Encodable, Sendable {
            let fileName: String
            let fileSize: Int
            let appID: String
        }
    }
}

struct UploadReservationData: Codable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Codable, Sendable {
        let uploadOperations: [UploadOperationData]?
    }

    struct UploadOperationData: Codable, Sendable {
        let method: String
        let url: String
        let offset: Int
        let length: Int
        let requestHeaders: [HeaderData]?
    }

    struct HeaderData: Codable, Sendable {
        let name: String
        let value: String
    }
}

struct BuildCommitRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes

        struct Attributes: Encodable, Sendable {
            let uploaded: Bool
            let checksum: String
        }
    }
}
