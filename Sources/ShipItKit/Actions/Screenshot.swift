#if os(macOS)
import Foundation
import Logging
import SwiftyShell

/// Captures localized screenshots on simulators by running UI tests.
///
/// Launches simulators for each device/locale combination and runs the
/// screenshot UI test scheme, organizing output into a `locale/device/` directory structure.
///
/// ## Usage
/// ```swift
/// let result = try await SnapshotAction().run(
///     with: .init(devices: ["iPhone 16 Pro Max"], locales: ["en-US", "ja"]),
///     context: context
/// )
/// print("Captured \(result.screenshotCount) screenshots")
/// ```
public struct SnapshotAction: Action {
    public static let name = "snapshot"
    public static let description = "Capture localized screenshots on simulators"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", SnapshotAction.self)

    /// Creates a `SnapshotAction`.
    public init() {}

    /// Configuration for screenshot capture.
    public struct Options: Codable, Sendable {
        /// Simulator device names to capture on.
        public var devices: [String]?

        /// Locale identifiers (e.g. `en-US`, `ja`, `de-DE`).
        public var locales: [String]?

        /// Xcode scheme with the screenshot UI tests.
        public var scheme: String?

        /// Output directory for organized screenshots.
        public var outputDirectory: String?

        /// Whether to clear previous screenshots before capture.
        public var clear: Bool?

        /// Creates `Options` for the snapshot action.
        ///
        /// - Parameter devices: Simulator device names to capture (e.g. `["iPhone 15 Pro"]`).
        /// - Parameter locales: Locales to capture (e.g. `["en-US", "fr-FR"]`).
        /// - Parameter scheme: Xcode scheme containing the UI test target.
        /// - Parameter outputDirectory: Directory where screenshots are saved.
        /// - Parameter clear: Remove existing screenshots before capturing.
        public init(
            devices: [String]? = nil,
            locales: [String]? = nil,
            scheme: String? = nil,
            outputDirectory: String? = nil,
            clear: Bool? = nil
        ) {
            self.devices = devices
            self.locales = locales
            self.scheme = scheme
            self.outputDirectory = outputDirectory
            self.clear = clear
        }
    }

    /// Result of a screenshot capture run.
    public struct Result: Codable, Sendable {
        /// Total number of screenshots captured.
        public let screenshotCount: Int

        /// Path to the directory containing organized screenshots.
        public let outputDirectory: String

        /// Device/locale combinations that failed.
        public let failures: [String]

        /// Creates a `Result`.
        public init(screenshotCount: Int, outputDirectory: String, failures: [String] = []) {
            self.screenshotCount = screenshotCount
            self.outputDirectory = outputDirectory
            self.failures = failures
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .ios else {
            throw ShipItError.invalidConfiguration(reason: "SnapshotAction requires iOS platform")
        }
        let devices = options.devices ?? context.config.screenshotDevices
        let locales = options.locales ?? context.config.screenshotLocales
        let scheme = options.scheme ?? context.config.screenshotScheme ?? context.config.appScheme

        guard let scheme else {
            throw ShipItError.invalidConfiguration(
                reason: "Snapshot requires a scheme. Set screenshots.scheme or app.scheme in Shipfile.yml, or pass --scheme.")
        }

        guard !devices.isEmpty else {
            throw ShipItError.invalidConfiguration(
                reason: "Snapshot requires at least one device. Pass --devices or configure screenshots.devices in Shipfile.yml.")
        }

        let outputDirectory = options.outputDirectory ?? context.config.screenshotOutputDirectory

        if options.clear == true {
            // Clear previous screenshots
            try? FileManager.default.removeItem(atPath: outputDirectory)
        }

        try FileManager.default.createDirectory(
            atPath: outputDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        logger.info("Capturing screenshots: \(devices.count) device(s), \(locales.count) locale(s)")

        var totalScreenshots = 0
        var failures: [String] = []

        for locale in locales {
            for device in devices {
                let deviceOutputDir = "\(outputDirectory)/\(locale)/\(device.replacingOccurrences(of: " ", with: "_"))"

                do {
                    try FileManager.default.createDirectory(
                        atPath: deviceOutputDir,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )

                    logger.info("Capturing screenshots: \(device) / \(locale)")

                    var xcodeBuild = XcodeBuild(context: context.shell)
                        .option(.scheme(scheme))
                        .option(.destination("platform=iOS Simulator,name=\(device)"))
                        .buildSetting("SNAPSHOT_LOCALE", locale)
                        .buildSetting("SCREENSHOT_OUTPUT_DIR", deviceOutputDir)
                        .trailingArgument("test")

                    if let workspace = context.config.appWorkspace {
                        xcodeBuild = xcodeBuild.option(.workspace(workspace))
                    } else if let project = context.config.appProject {
                        xcodeBuild = xcodeBuild.option(.project(project))
                    }

                    let output = try await xcodeBuild.run()

                    if output.exitCode != 0 {
                        logger.error("Screenshot capture failed for \(device) / \(locale)")
                        failures.append("\(device)/\(locale)")
                    } else {
                        // Count screenshots in the output directory
                        let count = countScreenshots(in: deviceOutputDir)
                        totalScreenshots += count
                        logger.info("Captured \(count) screenshots for \(device) / \(locale)")
                    }
                } catch {
                    logger.error("Screenshot capture error for \(device) / \(locale): \(error.localizedDescription)")
                    failures.append("\(device)/\(locale)")
                }
            }
        }

        if !failures.isEmpty {
            logger.warning("Screenshot capture failed for: \(failures.joined(separator: ", "))")
        }

        return Result(screenshotCount: totalScreenshots, outputDirectory: outputDirectory, failures: failures)
    }

    private func countScreenshots(in directory: String) -> Int {
        let extensions = ["png", "jpg", "jpeg"]
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return 0 }
        return contents.filter { file in
            extensions.contains((file as NSString).pathExtension.lowercased())
        }.count
    }
}
#endif
