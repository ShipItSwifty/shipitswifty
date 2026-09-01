#if os(macOS)
import AppStoreConnectKit
import Foundation
import Logging

/// Manages App Store metadata — pull from or push to App Store Connect.
///
/// Supports pulling current metadata into local files and pushing local
/// metadata files to App Store Connect per locale.
///
/// ## Usage
/// ```swift
/// // Pull metadata from ASC
/// let result = try await MetadataAction().run(
///     with: .init(pull: true),
///     context: context
/// )
///
/// // Push local metadata to ASC
/// let result = try await MetadataAction().run(
///     with: .init(push: true),
///     context: context
/// )
/// ```
public struct MetadataAction: Action {
    public static let name = "metadata"
    public static let description = "Pull/push App Store metadata from/to App Store Connect"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", MetadataAction.self)

    /// Creates a `MetadataAction`.
    public init() {}

    /// Configuration for the metadata action.
    public struct Options: Codable, Sendable {
        /// Pull current metadata from App Store Connect.
        public var pull: Bool?

        /// Push local metadata to App Store Connect.
        public var push: Bool?

        /// Local directory containing metadata files.
        public var directory: String?

        /// Submit for App Review after pushing metadata.
        public var submitForReview: Bool?

        /// Whether to use automatic release after approval.
        public var automaticRelease: Bool?

        /// Whether to use phased release.
        public var phasedRelease: Bool?

        /// Creates `Options` for the metadata action.
        ///
        /// Set `pull: true` to download metadata from ASC, `push: true` to upload.
        /// Defaults to pull if neither is set.
        public init(
            pull: Bool? = nil,
            push: Bool? = nil,
            directory: String? = nil,
            submitForReview: Bool? = nil,
            automaticRelease: Bool? = nil,
            phasedRelease: Bool? = nil
        ) {
            self.pull = pull
            self.push = push
            self.directory = directory
            self.submitForReview = submitForReview
            self.automaticRelease = automaticRelease
            self.phasedRelease = phasedRelease
        }
    }

    /// Result of a metadata operation.
    public struct Result: Codable, Sendable {
        /// Number of locales processed.
        public let localesProcessed: Int

        /// Whether the operation was a pull or push.
        public let operation: String

        /// Path to the metadata directory.
        public let directory: String

        /// Creates a `Result`.
        public init(localesProcessed: Int, operation: String, directory: String) {
            self.localesProcessed = localesProcessed
            self.operation = operation
            self.directory = directory
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let directory = options.directory ?? context.config.metadataDirectory
        let isPush = options.push ?? false
        let isPull = options.pull ?? !isPush

        if isPull {
            return try await pullMetadata(to: directory, context: context)
        } else {
            return try await pushMetadata(from: directory, options: options, context: context)
        }
    }

    // MARK: - Private Helpers

    private func pullMetadata(to directory: String, context: ActionContext) async throws -> Result {
        logger.info("Pulling metadata to '\(directory)'")

        guard let bundleID = context.config.bundleID else {
            throw ShipItError.invalidConfiguration(
                reason: "Metadata pull requires app.bundle_id. Set app.bundle_id in Shipfile.yml or export SHIPIT_APP__BUNDLE_ID.")
        }

        let syncResult = try await mappingASCErrors {
            try await AppStoreReleaseService(client: context.appStoreConnect).pullMetadata(
                bundleID: bundleID,
                directory: directory
            )
        }

        logger.info("Pulled metadata for \(syncResult.localesProcessed) locale(s)")
        return Result(localesProcessed: syncResult.localesProcessed, operation: "pull", directory: directory)
    }

    private func pushMetadata(from directory: String, options: Options, context: ActionContext) async throws -> Result {
        logger.info("Pushing metadata from '\(directory)'")

        guard FileManager.default.fileExists(atPath: directory) else {
            throw ShipItError.invalidConfiguration(reason: "Metadata directory not found: \(directory)")
        }

        guard let bundleID = context.config.bundleID else {
            throw ShipItError.invalidConfiguration(
                reason: "Metadata push requires app.bundle_id. Set app.bundle_id in Shipfile.yml or export SHIPIT_APP__BUNDLE_ID.")
        }

        let releaseService = AppStoreReleaseService(client: context.appStoreConnect)
        let resolveVersion: @Sendable () async throws -> String = {
            try await VersionBumper(context: context).readVersion()
        }
        let syncResult = try await mappingASCErrors {
            try await releaseService.pushMetadata(
                bundleID: bundleID,
                directory: directory,
                resolveVersionString: resolveVersion
            )
        }

        let shouldSubmit = options.submitForReview ?? context.config.submitForReview
        if shouldSubmit {
            _ = try await mappingASCErrors {
                try await releaseService.submitForReview(
                    bundleID: bundleID,
                    automaticRelease: options.automaticRelease ?? context.config.automaticRelease,
                    phasedRelease: options.phasedRelease ?? context.config.phasedRelease,
                    resolveVersionString: resolveVersion
                )
            }
        }

        logger.info("Pushed metadata for \(syncResult.localesProcessed) locale(s)")
        return Result(localesProcessed: syncResult.localesProcessed, operation: "push", directory: directory)
    }
}
#endif
