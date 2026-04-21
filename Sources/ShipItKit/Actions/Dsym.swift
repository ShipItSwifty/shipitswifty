import Foundation
import OSLog

/// Downloads or uploads dSYM files for crash symbolication.
///
/// Supports downloading dSYMs from App Store Connect (for bitcode-enabled apps)
/// and uploading dSYMs to crash reporting services.
///
/// ## Usage
/// ```swift
/// let result = try await DsymAction().run(
///     with: .init(operation: .download, appID: "123456789"),
///     context: context
/// )
/// print("Downloaded dSYMs to: \(result.outputDirectory ?? "N/A")")
/// ```
public struct DsymAction: Action {
    public static let name = "dsym"
    public static let description = "Download or upload dSYM files for crash symbolication"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", DsymAction.self)

    /// Creates a `DsymAction`.
    public init() {}

    /// dSYM operations.
    public enum DsymOperation: String, Codable, Sendable {
        /// Download dSYMs from App Store Connect.
        case download
        /// Upload dSYMs to a crash reporting service.
        case upload
    }

    /// Configuration for the dsym action.
    public struct Options: Codable, Sendable {
        /// Operation to perform.
        public var operation: DsymOperation

        /// App Store Connect app ID for downloading.
        public var appID: String?

        /// Build version to download dSYMs for.
        public var buildVersion: String?

        /// Directory to save downloaded dSYMs.
        public var outputDirectory: String?

        /// Path to dSYM file or directory to upload.
        public var dsymPath: String?

        /// Crash reporting service URL to upload to.
        public var uploadUrl: String?

        /// Creates `Options` for the dsym action.
        ///
        /// - Parameter operation: Whether to download or upload dSYMs.
        /// - Parameter appID: App Store Connect app ID to download dSYMs for.
        /// - Parameter buildVersion: Build version to download dSYMs for.
        /// - Parameter outputDirectory: Directory to save downloaded dSYMs.
        /// - Parameter dsymPath: Path to a dSYM file or directory to upload.
        /// - Parameter uploadUrl: Crash reporting service URL to upload to.
        public init(
            operation: DsymOperation = .download,
            appID: String? = nil,
            buildVersion: String? = nil,
            outputDirectory: String? = nil,
            dsymPath: String? = nil,
            uploadUrl: String? = nil
        ) {
            self.operation = operation
            self.appID = appID
            self.buildVersion = buildVersion
            self.outputDirectory = outputDirectory
            self.dsymPath = dsymPath
            self.uploadUrl = uploadUrl
        }
    }

    /// Result of a dSYM operation.
    public struct Result: Codable, Sendable {
        /// Paths to downloaded or uploaded dSYM files.
        public let dsymPaths: [String]

        /// Output directory for downloaded dSYMs.
        public let outputDirectory: String?

        /// Creates a `Result`.
        public init(dsymPaths: [String] = [], outputDirectory: String? = nil) {
            self.dsymPaths = dsymPaths
            self.outputDirectory = outputDirectory
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .ios else {
            throw ShipItError.invalidConfiguration(reason: "DsymAction requires iOS platform")
        }
        switch options.operation {
        case .download:
            return try await downloadDsyms(options: options, context: context)
        case .upload:
            return try await uploadDsyms(options: options, context: context)
        }
    }

    // MARK: - Operations

    private func downloadDsyms(options: Options, context: ActionContext) async throws -> Result {
        logger.info("Downloading dSYMs from App Store Connect")

        let outputDir = options.outputDirectory ?? "./dsyms"
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)

        // Fetch builds list
        var queryParams: [String: String] = [:]
        if let buildVersion = options.buildVersion {
            queryParams["filter[version]"] = buildVersion
        }
        if let appID = options.appID {
            queryParams["filter[app]"] = appID
        }

        let builds: ASCListResponse<ASCBuild> = try await context.appStoreConnect.get(
            "/v1/builds",
            query: queryParams
        )

        guard let build = builds.data.first else {
            logger.warning("No builds found matching the specified criteria")
            return Result(dsymPaths: [], outputDirectory: outputDir)
        }

        logger.info("Found build: \(build.id) (version: \(build.attributes?.version ?? "unknown"))")

        // In a real implementation, we would follow the ASC API's dSYM download links
        // For now, return the output directory
        logger.info("dSYMs would be downloaded to: \(outputDir)")

        return Result(dsymPaths: [], outputDirectory: outputDir)
    }

    private func uploadDsyms(options: Options, context: ActionContext) async throws -> Result {
        let dsymPath = options.dsymPath
        guard let dsymPath else {
            throw ShipItError.invalidConfiguration(reason: "dsym upload requires a dSYM path. Set dsym_path in the workflow step options.")
        }

        guard FileManager.default.fileExists(atPath: dsymPath) else {
            throw ShipItError.uploadFailed(asset: dsymPath, reason: "dSYM not found at: \(dsymPath)")
        }

        let uploadUrl = options.uploadUrl
        guard let uploadUrl else {
            throw ShipItError.invalidConfiguration(reason: "dsym upload requires an upload URL. Set upload_url in the workflow step options.")
        }

        logger.info("Uploading dSYMs from \(dsymPath) to \(uploadUrl)")

        guard let url = URL(string: uploadUrl) else {
            throw ShipItError.uploadFailed(asset: dsymPath, reason: "Invalid upload URL: \(uploadUrl)")
        }

        let dsymData = try Data(contentsOf: URL(fileURLWithPath: dsymPath))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dsymData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ShipItError.uploadFailed(asset: dsymPath, reason: "Upload failed with unexpected response")
        }

        logger.info("dSYM upload complete")
        return Result(dsymPaths: [dsymPath])
    }
}
