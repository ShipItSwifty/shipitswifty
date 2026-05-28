#if os(macOS)
import Foundation
import Logging
import SwiftyShell

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

        // Generate export options plist
        let plistPath = try await writeExportOptionsPlist(
            exportMethod: exportMethod,
            outputDirectory: outputDirectory,
            context: context
        )
        defer {
            try? FileManager.default.removeItem(atPath: plistPath)
        }

        var command = XcodeBuild(context: context.shell)
            .trailingArguments([
                "-exportArchive",
                "-archivePath", archivePath,
                "-exportPath", outputDirectory,
                "-exportOptionsPlist", plistPath,
            ])

        if context.config.automaticCodeSigning {
            command = command.trailingArgument("-allowProvisioningUpdates")
        }

        let output = try await command.run()

        if output.exitCode != 0 {
            logger.error("Export failed with exit code \(output.exitCode)")
            throw ShipItError.archiveFailed(exitCode: Int(output.exitCode), log: output.stderr)
        }

        // Find the IPA in the output directory
        let ipaPath = try findIPA(in: outputDirectory)
        logger.info("Export succeeded: \(ipaPath)")

        return Result(ipaPath: ipaPath, outputDirectory: outputDirectory)
    }

    // MARK: - Private Helpers

    private func writeExportOptionsPlist(
        exportMethod: String,
        outputDirectory: String,
        context: ActionContext
    ) async throws -> String {
        let tmpPath = NSTemporaryDirectory() + "ExportOptions_\(UUID().uuidString).plist"

        var plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>method</key>
                <string>\(exportMethod)</string>
            """

        if let teamID = context.config.teamID {
            plistContent += """

                    <key>teamID</key>
                    <string>\(teamID)</string>
                """
        }

        plistContent += """

                <key>signingStyle</key>
                <string>\(context.config.automaticCodeSigning ? "automatic" : "manual")</string>

            </dict>
            </plist>
            """

        try plistContent.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        return tmpPath
    }

    private func findIPA(in directory: String) throws -> String {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
            throw ShipItError.archiveFailed(exitCode: 1, log: "Cannot list export directory: \(directory)")
        }
        guard let ipaFile = contents.first(where: { $0.hasSuffix(".ipa") }) else {
            throw ShipItError.archiveFailed(exitCode: 1, log: "No IPA found in export directory: \(directory)")
        }
        return (directory as NSString).appendingPathComponent(ipaFile)
    }
}
#endif
