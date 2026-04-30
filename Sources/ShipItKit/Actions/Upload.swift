import Foundation
import OSLog

/// Uploads an IPA and metadata to App Store Connect.
///
/// Uses the App Store Connect API to create a new app version,
/// upload the IPA binary, and optionally submit for review.
///
/// ## Usage
/// ```swift
/// let result = try await UploadAction().run(
///     with: .init(ipaPath: "./build/MyApp.ipa"),
///     context: context
/// )
/// print("Uploaded build: \(result.buildID ?? "unknown")")
/// ```
public struct UploadAction: Action {
    public static let name = "upload"
    public static let description = "Upload IPA and metadata to App Store Connect"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", UploadAction.self)

    /// Creates an `UploadAction`.
    public init() {}

    /// Configuration for the upload action.
    public struct Options: Codable, Sendable {
        /// Path to the `.ipa` file to upload.
        public var ipaPath: String?

        /// Whether to submit for App Review after upload.
        public var submitForReview: Bool?

        /// Whether to use phased release.
        public var phasedRelease: Bool?

        /// Creates `Options` for the upload action.
        ///
        /// All parameters are optional; unset values fall back to `ResolvedConfig`.
        public init(
            ipaPath: String? = nil,
            submitForReview: Bool? = nil,
            phasedRelease: Bool? = nil
        ) {
            self.ipaPath = ipaPath
            self.submitForReview = submitForReview
            self.phasedRelease = phasedRelease
        }
    }

    /// Result of a successful upload.
    public struct Result: Codable, Sendable {
        /// The App Store Connect build ID, if available.
        public let buildID: String?

        /// The App Store Connect review submission ID, if one was created.
        public let reviewSubmissionID: String?

        /// Human-readable status message.
        public let message: String

        /// Creates a `Result`.
        public init(buildID: String? = nil, reviewSubmissionID: String? = nil, message: String) {
            self.buildID = buildID
            self.reviewSubmissionID = reviewSubmissionID
            self.message = message
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .ios else {
            throw ShipItError.invalidConfiguration(reason: "UploadAction requires iOS platform")
        }
        guard let ipaPath = options.ipaPath ?? locateExportedIPA(context: context) else {
            throw ShipItError.invalidConfiguration(reason: "Upload requires an IPA path. Pass --ipa /path/to/App.ipa.")
        }
        guard let bundleID = context.config.bundleID else {
            throw ShipItError.invalidConfiguration(
                reason: "Upload requires app.bundle_id. Set app.bundle_id in Shipfile.yml or export SHIPIT_APP__BUNDLE_ID.")
        }

        logger.info("Uploading IPA: \(ipaPath)")
        let uploadResult = try await IPAUploadService(client: context.appStoreConnect).uploadIPA(
            at: URL(fileURLWithPath: ipaPath),
            bundleID: bundleID,
            context: context
        )

        var reviewSubmissionID: String?
        let shouldSubmit = options.submitForReview ?? context.config.submitForReview
        if shouldSubmit {
            let submission = try await AppStoreReleaseService(client: context.appStoreConnect).submitForReview(
                bundleID: bundleID,
                automaticRelease: context.config.automaticRelease,
                phasedRelease: options.phasedRelease ?? context.config.phasedRelease,
                context: context
            )
            reviewSubmissionID = submission.reviewSubmissionID
        }

        logger.info("Upload complete for build \(uploadResult.buildID ?? "unknown")")
        return Result(
            buildID: uploadResult.buildID,
            reviewSubmissionID: reviewSubmissionID,
            message: reviewSubmissionID == nil
                ? "Successfully uploaded IPA to App Store Connect"
                : "Successfully uploaded IPA and created App Review submission"
        )
    }

    private func locateExportedIPA(context: ActionContext) -> String? {
        let outputDirectory = context.config.exportOutputDirectory ?? "./build/export"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: outputDirectory) else {
            return nil
        }
        guard let ipaName = contents.sorted().first(where: { $0.hasSuffix(".ipa") }) else {
            return nil
        }
        return (outputDirectory as NSString).appendingPathComponent(ipaName)
    }
}
