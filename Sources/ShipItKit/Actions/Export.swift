#if os(macOS)
import Foundation
import Logging
import MobileBuild
import SwiftyShell
import XcodeBuildKit

/// Exports an IPA from an `.xcarchive` using `xcodebuild -exportArchive`.
///
/// Consumes an existing `.xcarchive` (produced by `ArchiveAction`) and generates
/// an `.ipa` file suitable for distribution.
///
/// ## Usage
/// ```swift
/// let result = try await ExportAction().run(
///     with: .init(archivePath: "./build/MyApp.xcarchive", outputDirectory: "./build/export"),
///     context: context
/// )
/// print("IPA: \(result.ipaPath)")
/// ```
public struct ExportAction: Action {
    public static let name = "export"
    public static let description = "Export IPA from xcarchive using xcodebuild -exportArchive"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", ExportAction.self)

    /// Creates an `ExportAction`.
    public init() {}

    /// Configuration for the export action.
    public struct Options: Codable, Sendable {
        /// Path to the `.xcarchive` to export.
        public var archivePath: String?

        /// Directory to write the exported IPA.
        public var outputDirectory: String?

        /// Export method: `app-store`, `ad-hoc`, `development`, or `enterprise`.
        public var exportMethod: String?

        /// Creates `Options` for the export action.
        ///
        /// - Parameter archivePath: Path to the `.xcarchive` to export.
        /// - Parameter outputDirectory: Directory where the exported IPA is written.
        /// - Parameter exportMethod: Export method: `app-store`, `ad-hoc`, `development`, or `enterprise`.
        public init(
            archivePath: String? = nil,
            outputDirectory: String? = nil,
            exportMethod: String? = nil
        ) {
            self.archivePath = archivePath
            self.outputDirectory = outputDirectory
            self.exportMethod = exportMethod
        }
    }

    /// Result of a successful export.
    public struct Result: Codable, Sendable {
        /// Path to the exported `.ipa` file.
        public let ipaPath: String

        /// Directory containing the exported products.
        public let outputDirectory: String

        /// Creates a `Result`.
        public init(ipaPath: String, outputDirectory: String) {
            self.ipaPath = ipaPath
            self.outputDirectory = outputDirectory
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .ios else {
            throw ShipItError.invalidConfiguration(reason: "ExportAction requires iOS platform")
        }
        if context.config.iosBuildSystem == .flutter {
            throw ShipItError.invalidConfiguration(
                reason: "Flutter iOS archives do not use a separate export step. "
                    + "'flutter build ipa' (run by the archive action) already produces a distributable IPA. "
                    + "Remove 'export' from your workflow and proceed directly to 'testflight' or 'upload'."
            )
        }
        let defaultArchivePath: String? =
            context.config.appScheme.map { "./build/\($0).xcarchive" }
        let archivePath =
            options.archivePath
            ?? context.config.exportArchivePath
            ?? context.config.archiveOutputPath
            ?? defaultArchivePath

        guard let archivePath else {
            throw ShipItError.invalidConfiguration(
                reason: "Export requires an archive path. Pass --archive or set export.archive_path / archive.output_path in Shipfile.yml.")
        }

        let outputDirectory =
            options.outputDirectory
            ?? context.config.exportOutputDirectory
            ?? "./build/export"

        let exportMethod = options.exportMethod ?? context.config.archiveExportMethod
        logger.info("Exporting archive '\(archivePath)' -> '\(outputDirectory)'")

        // Materialize ASC API key flags so `-allowProvisioningUpdates` can authenticate
        // to Apple in headless CI. Resolved only for automatic signing.
        let ascAuth =
            context.config.automaticCodeSigning
            ? try ASCAuthenticationKey.resolve(config: context.config)
            : nil
        defer { ascAuth?.cleanup() }

        let exportOptions = ExportOptions(
            method: exportMethod,
            teamID: context.config.teamID,
            signingStyle: context.config.automaticCodeSigning ? "automatic" : "manual"
        )

        let outcome = try await mappingBuildFailures(
            { exitCode, log in
                logger.error("Export failed with exit code \(exitCode)")
                return .archiveFailed(exitCode: exitCode, log: log)
            },
            {
                try await XcodeBuilder(shell: context.shell)
                    .exportArchive(
                        archivePath: archivePath,
                        exportPath: outputDirectory,
                        options: exportOptions,
                        additionalOptions: context.config.automaticCodeSigning
                            ? [.allowProvisioningUpdates] + (ascAuth?.options ?? [])
                            : [])
            })

        guard let ipaPath = outcome.artifacts(.ipa).first else {
            throw ShipItError.archiveFailed(exitCode: 1, log: "No IPA found in export directory: \(outputDirectory)")
        }
        logger.info("Export succeeded: \(ipaPath)")

        return Result(ipaPath: ipaPath, outputDirectory: outputDirectory)
    }
}
#endif
