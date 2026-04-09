import OSLog
import SwiftyShell

/// Archives the app using `xcodebuild archive`, producing a `.xcarchive`.
///
/// This is the canonical step for producing a distributable archive.
/// The resulting archive is consumed by `ExportAction` to produce an IPA.
///
/// ## Usage
/// ```swift
/// let result = try await ArchiveAction().run(
///     with: .init(scheme: "MyApp", exportMethod: "app-store"),
///     context: context
/// )
/// print("Archive: \(result.archivePath)")
/// ```
public struct ArchiveAction: Action {
    public static let name = "archive"
    public static let description = "Archive the app using xcodebuild archive"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", ArchiveAction.self)

    /// Creates an `ArchiveAction`.
    public init() {}

    /// Configuration for the archive action.
    public struct Options: Codable, Sendable {
        /// Xcode scheme to archive.
        public var scheme: String?

        /// Build configuration. Default: `Release`.
        public var configuration: String?

        /// Export method: `app-store`, `ad-hoc`, `development`, or `enterprise`.
        public var exportMethod: String?

        /// Output path for the `.xcarchive`. Default: `./build/<scheme>.xcarchive`.
        public var outputPath: String?

        /// Whether to include debug symbols.
        public var includeSymbols: Bool?

        /// Whether to include bitcode.
        public var includeBitcode: Bool?

        /// Creates `Options` for the archive action.
        ///
        /// All parameters are optional; unset values fall back to `ResolvedConfig`.
        public init(
            scheme: String? = nil,
            configuration: String? = nil,
            exportMethod: String? = nil,
            outputPath: String? = nil,
            includeSymbols: Bool? = nil,
            includeBitcode: Bool? = nil
        ) {
            self.scheme = scheme
            self.configuration = configuration
            self.exportMethod = exportMethod
            self.outputPath = outputPath
            self.includeSymbols = includeSymbols
            self.includeBitcode = includeBitcode
        }
    }

    /// Result of a successful archive.
    public struct Result: Codable, Sendable {
        /// Path to the created `.xcarchive`.
        public let archivePath: String

        /// Exit code from xcodebuild.
        public let exitCode: Int

        /// Creates a `Result`.
        public init(archivePath: String, exitCode: Int = 0) {
            self.archivePath = archivePath
            self.exitCode = exitCode
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        guard let scheme else {
            throw ShipItError.invalidConfiguration(reason: "Archive requires a scheme. Set app.scheme in Shipfile.yml or pass --scheme.")
        }

        let configuration = options.configuration ?? context.config.buildConfiguration
        let archivePath = options.outputPath
            ?? context.config.archiveOutputPath
            ?? "./build/\(scheme).xcarchive"

        logger.info("Archiving scheme '\(scheme)' (\(configuration)) -> \(archivePath)")

        var xcodeBuild = XcodeBuild(context: context.shell)
            .option(.scheme(scheme))
            .option(.configuration(configuration))
            .option(.archivePath(archivePath))
            .trailingArgument("archive")

        if let workspace = context.config.appWorkspace {
            xcodeBuild = xcodeBuild.option(.workspace(workspace))
        } else if let project = context.config.appProject {
            xcodeBuild = xcodeBuild.option(.project(project))
        }

        if let derivedData = context.config.derivedDataPath {
            xcodeBuild = xcodeBuild.option(.derivedDataPath(derivedData))
        }

        if context.config.automaticCodeSigning {
            xcodeBuild = xcodeBuild.option(.allowProvisioningUpdates)
        }

        let allXcargs = context.config.xcargs
        for (key, value) in allXcargs {
            xcodeBuild = xcodeBuild.buildSetting(key, value)
        }

        let output = try await xcodeBuild.run()

        if output.exitCode != 0 {
            logger.error("Archive failed with exit code \(output.exitCode)")
            throw ShipItError.archiveFailed(exitCode: Int(output.exitCode), log: output.stderr)
        }

        logger.info("Archive succeeded: \(archivePath)")
        return Result(archivePath: archivePath, exitCode: Int(output.exitCode))
    }
}
