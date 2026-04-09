import Foundation
import CryptoKit
import OSLog

/// Handles the multi-step asset upload protocol for App Store Connect.
///
/// ## Upload Flow
/// 1. Reserve the asset to get upload operations
/// 2. Stream binary data in parts to presigned S3 URLs
/// 3. Commit the upload with MD5 checksum verification
///
/// Assets are streamed from disk in chunks — the file is never fully loaded into
/// memory, making this safe for large IPAs (200 MB+).
/// Supports automatic retry with exponential backoff on transient part failures.
///
/// ## Usage
/// ```swift
/// let uploader = AssetUploader()
/// let commit = try await uploader.upload(fileURL: ipaURL, to: reservation) { progress in
///     print("Upload progress: \(Int(progress * 100))%")
/// }
/// ```
public struct AssetUploader: Sendable {
    private let session: URLSession
    private let retryPolicy: RetryPolicy
    private let logger = Logger.forType(subsystem: "ShipItSwifty", AssetUploader.self)

    /// Creates an `AssetUploader`.
    ///
    /// - Parameters:
    ///   - session: The `URLSession` to use for HTTP requests. Defaults to `.shared`.
    ///   - retryPolicy: Retry policy for transient failures. Defaults to 3 attempts with exponential backoff.
    public init(
        session: URLSession = .shared,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 3, initialDelay: .seconds(2))
    ) {
        self.session = session
        self.retryPolicy = retryPolicy
    }

    /// Upload a file asset using the App Store Connect multi-part protocol.
    ///
    /// - Parameters:
    ///   - fileURL: Local file URL of the asset to upload (IPA, screenshot, preview video).
    ///              Must be a file URL pointing to a readable regular file.
    ///   - reservation: The `UploadReservation` returned by the preceding ASC reserve call.
    ///   - progress: Called periodically with upload progress in the range `0.0 ... 1.0`.
    /// - Returns: An `UploadCommit` that must be sent to ASC to finalize the upload.
    /// - Throws: ``ShipItError/uploadFailed`` on unrecoverable failure after retries.
    public func upload(
        fileURL: URL,
        to reservation: UploadReservation,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> UploadCommit {
        logger.info("Starting upload for: \(fileURL.lastPathComponent) with \(reservation.operations.count) parts")

        _ = try fileSize(at: fileURL)
        var completedParts = 0

        // Upload each part
        for operation in reservation.operations {
            let partIndex = completedParts
            logger.debug("Uploading part \(partIndex + 1)/\(reservation.operations.count)")

            try await retryPolicy.execute {
                try await uploadPart(
                    fileURL: fileURL,
                    operation: operation,
                    fileName: fileURL.lastPathComponent
                )
            }

            completedParts += 1
            let progressValue = Double(completedParts) / Double(reservation.operations.count)
            progress(progressValue)
            logger.debug("Part \(completedParts)/\(reservation.operations.count) complete (\(Int(progressValue * 100))%)")
        }

        // Compute MD5 checksum of the full file
        let checksum = try computeMD5(at: fileURL)
        logger.info("Upload complete for \(fileURL.lastPathComponent), MD5: \(checksum)")

        return UploadCommit(id: reservation.id, checksum: checksum, uploaded: true)
    }

    // MARK: - Private

    private func uploadPart(
        fileURL: URL,
        operation: UploadOperation,
        fileName: String
    ) async throws {
        guard let url = URL(string: operation.url) else {
            throw ShipItError.uploadFailed(asset: fileName, reason: "Invalid upload URL: \(operation.url)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = operation.method

        // Apply required headers
        if let headers = operation.requestHeaders {
            for header in headers {
                request.setValue(header.value, forHTTPHeaderField: header.name)
            }
        }

        // Stream the specific byte range for this part
        let partData = try readPart(from: fileURL, offset: operation.offset, length: operation.length)
        request.httpBody = partData
        request.setValue(String(partData.count), forHTTPHeaderField: "Content-Length")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShipItError.uploadFailed(asset: fileName, reason: "Invalid response type")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ShipItError.uploadFailed(
                asset: fileName,
                reason: "HTTP \(httpResponse.statusCode) for part upload"
            )
        }
    }

    private func readPart(from fileURL: URL, offset: Int, length: Int) throws -> Data {
        guard let fileHandle = FileHandle(forReadingAtPath: fileURL.path) else {
            throw ShipItError.uploadFailed(asset: fileURL.lastPathComponent, reason: "Cannot open file for reading")
        }
        defer { try? fileHandle.close() }

        try fileHandle.seek(toOffset: UInt64(offset))
        guard let data = try fileHandle.read(upToCount: length) as Data? ?? fileHandle.readData(ofLength: length) as Data? else {
            throw ShipItError.uploadFailed(asset: fileURL.lastPathComponent, reason: "Failed to read part data")
        }
        return data
    }

    private func fileSize(at url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attrs[.size] as? Int else {
            throw ShipItError.uploadFailed(asset: url.lastPathComponent, reason: "Cannot determine file size")
        }
        return size
    }

    private func computeMD5(at url: URL) throws -> String {
        guard let inputStream = InputStream(url: url) else {
            throw ShipItError.uploadFailed(asset: url.lastPathComponent, reason: "Cannot open file for MD5 computation")
        }

        inputStream.open()
        defer { inputStream.close() }

        var hasher = Insecure.MD5()
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                throw ShipItError.uploadFailed(asset: url.lastPathComponent, reason: "Error reading file for MD5")
            }
            if bytesRead == 0 { break }
            hasher.update(data: Data(buffer[0..<bytesRead]))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
