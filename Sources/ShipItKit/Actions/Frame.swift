import Foundation
import OSLog
import SwiftyShell

/// Overlays device frames on raw screenshots.
///
/// Takes screenshots from a directory and composites them with device bezels
/// (iPhone, iPad) to create App Store-ready framed screenshots.
///
/// ## Usage
/// ```swift
/// let result = try await FrameAction().run(
///     with: .init(screenshotsDirectory: "./screenshots"),
///     context: context
/// )
/// print("Framed \(result.framedCount) screenshots")
/// ```
public struct FrameAction: Action {
    public static let name = "frame"
    public static let description = "Overlay device frames on screenshots"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", FrameAction.self)

    /// Creates a `FrameAction`.
    public init() {}

    /// Configuration for the frame action.
    public struct Options: Codable, Sendable {
        /// Path to the directory containing raw screenshots.
        public var screenshotsDirectory: String?

        /// Path to write framed screenshots. Defaults to same directory with `_framed` suffix.
        public var outputDirectory: String?

        /// Whether to overwrite existing framed screenshots.
        public var force: Bool?

        /// Creates `Options` for the frame action.
        ///
        /// - Parameter screenshotsDirectory: Directory containing source screenshots.
        /// - Parameter outputDirectory: Directory where framed screenshots are written.
        /// - Parameter force: Overwrite existing framed screenshots.
        public init(
            screenshotsDirectory: String? = nil,
            outputDirectory: String? = nil,
            force: Bool? = nil
        ) {
            self.screenshotsDirectory = screenshotsDirectory
            self.outputDirectory = outputDirectory
            self.force = force
        }
    }

    /// Result of a frame operation.
    public struct Result: Codable, Sendable {
        /// Number of screenshots that were framed.
        public let framedCount: Int

        /// Output directory containing framed screenshots.
        public let outputDirectory: String

        /// Creates a `Result`.
        public init(framedCount: Int, outputDirectory: String) {
            self.framedCount = framedCount
            self.outputDirectory = outputDirectory
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .ios else {
            throw ShipItError.invalidConfiguration(reason: "FrameAction requires iOS platform")
        }
        let screenshotsDir = options.screenshotsDirectory ?? context.config.screenshotOutputDirectory
        let outputDir = options.outputDirectory ?? "\(screenshotsDir)_framed"

        logger.info("Framing screenshots from '\(screenshotsDir)' -> '\(outputDir)'")

        // Check if frameit is available. `which` exits 1 when the tool is not
        // found, causing Command.run() to throw — catch to handle the fallback.
        let frameitAvailable: Bool
        do {
            _ = try await Which(context: context.shell).tool("frameit").run()
            frameitAvailable = true
        } catch {
            frameitAvailable = false
        }

        if !frameitAvailable {
            logger.warning("frameit not found; installing via gem is required for device framing.")
            // Fallback: just copy screenshots without framing
            try copyScreenshots(from: screenshotsDir, to: outputDir)
            let count = countScreenshots(in: outputDir)
            return Result(framedCount: count, outputDirectory: outputDir)
        }

        try FileManager.default.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Run frameit in the screenshots directory.
        // Command.run() throws ShellError.exitFailure on non-zero exit; convert
        // to a typed ShipItError for callers.
        do {
            _ = try await Frameit(context: context.shell)
                .render(screenshotsDirectory: screenshotsDir, outputDirectory: outputDir)
                .run()
        } catch {
            logger.error("frameit failed: \(error.localizedDescription)")
            throw ShipItError.screenshotCaptureFailed(
                device: "all",
                locale: "all",
                reason: "frameit failed: \(error.localizedDescription)"
            )
        }

        let count = countScreenshots(in: outputDir)
        logger.info("Framed \(count) screenshots")
        return Result(framedCount: count, outputDirectory: outputDir)
    }

    private func copyScreenshots(from source: String, to destination: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: destination, withIntermediateDirectories: true, attributes: nil)

        guard let contents = try? fileManager.contentsOfDirectory(atPath: source) else { return }
        for file in contents {
            let srcPath = (source as NSString).appendingPathComponent(file)
            let dstPath = (destination as NSString).appendingPathComponent(file)
            try? fileManager.copyItem(atPath: srcPath, toPath: dstPath)
        }
    }

    private func countScreenshots(in directory: String) -> Int {
        let extensions = ["png", "jpg", "jpeg"]
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return 0 }
        return contents.filter { file in
            extensions.contains((file as NSString).pathExtension.lowercased())
        }.count
    }
}
