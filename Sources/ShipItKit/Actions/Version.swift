#if os(macOS)
import Foundation
import Logging
import SwiftyShell

/// Bumps `CFBundleVersion` and/or `CFBundleShortVersionString` in the Xcode project.
///
/// Supports sequential, timestamp, and commit-count strategies for build numbers,
/// and major/minor/patch bumping for version strings.
///
/// ## Usage
/// ```swift
/// let result = try await VersionAction().run(
///     with: .init(bump: .build),
///     context: context
/// )
/// print("New version: \(result.version), build: \(result.buildNumber)")
/// ```
public struct VersionAction: Action {
    public static let name = "version"
    public static let description = "Bump CFBundleVersion and/or CFBundleShortVersionString"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", VersionAction.self)

    /// Creates a `VersionAction`.
    public init() {}

    /// The version component to bump.
    public enum BumpType: String, Codable, Sendable {
        /// Increment the build number (`CFBundleVersion`).
        case build
        /// Increment the patch component of the version string.
        case patch
        /// Increment the minor component of the version string.
        case minor
        /// Increment the major component of the version string.
        case major
        /// Set a specific version string.
        case set
    }

    /// Configuration for the version action.
    public struct Options: Codable, Sendable {
        /// Which version component to bump.
        public var bump: BumpType

        /// Specific version string to set (when `bump` is `.set`).
        public var version: String?

        /// Specific build number to set.
        public var buildNumber: String?

        /// Strategy for auto-incrementing build numbers.
        public var strategy: BuildNumberStrategy?

        /// Where to write the version bump. When `source_of_truth` is specified,
        /// the bump targets the project spec file (e.g. `project.yml`) rather than
        /// the generated `.xcodeproj`. This is required for XcodeGen repos where the
        /// `.xcodeproj` is regenerated and would lose changes.
        ///
        /// Valid values:
        /// - `nil` (default): uses the `versioning.source` from config
        /// - `"source_of_truth"` or `"project_spec"`: writes to the spec file
        /// - `"xcodeproj"`: writes to the Xcode project directly
        public var target: String?

        /// Creates `Options` for the version action.
        ///
        /// - Parameters:
        ///   - bump: Which version component to bump.
        ///   - version: Specific version string (used when `bump` is `.set`).
        ///   - buildNumber: Specific build number to set.
        ///   - strategy: Auto-increment strategy override.
        ///   - target: Override versioning target (`source_of_truth`, `project_spec`, `xcodeproj`).
        public init(
            bump: BumpType = .build,
            version: String? = nil,
            buildNumber: String? = nil,
            strategy: BuildNumberStrategy? = nil,
            target: String? = nil
        ) {
            self.bump = bump
            self.version = version
            self.buildNumber = buildNumber
            self.strategy = strategy
            self.target = target
        }
    }

    /// Result of a version bump.
    public struct Result: Codable, Sendable {
        /// The new marketing version string.
        public let version: String

        /// The new build number string.
        public let buildNumber: String

        /// Creates a `Result`.
        public init(version: String, buildNumber: String) {
            self.version = version
            self.buildNumber = buildNumber
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        logger.info("Bumping version: \(options.bump.rawValue)")
        let bumper = VersionBumper(context: context)
        return try await bumper.bump(options: options)
    }
}
#endif
