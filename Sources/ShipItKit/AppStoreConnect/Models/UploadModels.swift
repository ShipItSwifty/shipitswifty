import Foundation

/// Reservation returned by the App Store Connect API when reserving an asset upload slot.
///
/// Step 1 of the multi-step upload protocol. Contains the upload operations
/// (presigned S3 URLs) needed to stream the asset.
public struct UploadReservation: Codable, Sendable {
    /// Unique identifier for this upload reservation.
    public let id: String

    /// The upload operations (presigned URLs and HTTP methods) for each part.
    public let operations: [UploadOperation]

    /// Creates an `UploadReservation`.
    public init(id: String, operations: [UploadOperation]) {
        self.id = id
        self.operations = operations
    }
}

/// A single upload operation describing how to PUT one part of the asset.
///
/// Each operation corresponds to one chunk of the multi-part upload.
public struct UploadOperation: Codable, Sendable {
    /// The HTTP method to use (always `"PUT"` for S3 presigned URLs).
    public let method: String

    /// The presigned S3 URL to upload the part to.
    public let url: String

    /// The byte offset of this part within the full asset.
    public let offset: Int

    /// The length in bytes of this part.
    public let length: Int

    /// HTTP headers that must be included with the PUT request.
    public let requestHeaders: [UploadHeader]?

    /// Creates an `UploadOperation`.
    public init(
        method: String,
        url: String,
        offset: Int,
        length: Int,
        requestHeaders: [UploadHeader]? = nil
    ) {
        self.method = method
        self.url = url
        self.offset = offset
        self.length = length
        self.requestHeaders = requestHeaders
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case url
        case offset
        case length
        case requestHeaders
    }
}

/// An HTTP header included in an upload operation.
public struct UploadHeader: Codable, Sendable {
    /// The header name.
    public let name: String

    /// The header value.
    public let value: String

    /// Creates an `UploadHeader`.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Commit data sent to App Store Connect to finalize a multi-part upload.
///
/// Step 3 of the upload protocol. Must be sent after all parts are uploaded.
public struct UploadCommit: Codable, Sendable {
    /// The reservation ID returned in step 1.
    public let id: String

    /// MD5 checksum of the complete asset for integrity verification.
    public let checksum: String

    /// Set to `true` to signal that all parts have been uploaded.
    public let uploaded: Bool

    /// Creates an `UploadCommit`.
    public init(id: String, checksum: String, uploaded: Bool = true) {
        self.id = id
        self.checksum = checksum
        self.uploaded = uploaded
    }
}
