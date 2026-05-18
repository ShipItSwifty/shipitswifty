import Foundation
import Logging

/// Uploads a release artifact to Google Play and assigns it to a distribution track.
///
/// Wraps the `GooglePlayUploadService` transactional edit→upload→track→commit workflow.
/// Supports both AAB (preferred) and APK artifacts.
///
/// ## Usage
/// ```swift
/// let result = try await PlayStoreAction().run(
///     with: .init(
///         aabPath: "./build/app-release.aab",
///         track: "beta",
///         releaseNotes: ["en-US": "Bug fixes and improvements"]
///     ),
///     context: androidContext
/// )
/// print("Uploaded versionCode: \(result.versionCode)")
/// ```
///
/// ## Topics
/// ### Configuration
/// - ``Options``
/// ### Results
/// - ``Result``
public struct PlayStoreAction: Action {
    /// The registered name used in Shipfile lanes.
    public static let name = "play-store"

    /// Human-readable description for `--help` output.
    public static let description =
        "Upload Android release artifact to Google Play and assign to a track"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", PlayStoreAction.self)

    /// Creates a `PlayStoreAction`.
    public init() {}

    /// Configuration options for the Play Store upload action.
    public struct Options: Codable, Sendable {
        /// Path to the `.aab` file to upload. Takes precedence over `apkPath`.
        public var aabPath: String?

        /// Path to the `.apk` file to upload. Used when `aabPath` is nil.
        public var apkPath: String?

        /// Google Play distribution track (e.g. `"internal"`, `"alpha"`, `"beta"`, `"production"`).
        /// Defaults to `config.androidPlayTrack`.
        public var track: String?

        /// Per-language release notes. Keys are BCP-47 language tags (e.g. `"en-US"`).
        public var releaseNotes: [String: String]?

        /// Staged rollout fraction (0.0–1.0). `nil` means full rollout.
        /// Overrides `config.androidRolloutFraction`.
        public var rolloutFraction: Double?

        /// Android package name (e.g. `com.example.myapp`).
        /// Defaults to `config.androidPackageName`.
        public var packageName: String?

        /// Gradle build variant (e.g. `"prodRelease"`).
        /// Used for auto-discovering the artifact path when `aabPath`/`apkPath` are not set.
        /// Defaults to `config.androidBuildVariant`.
        public var buildVariant: String?

        /// Product flavor (e.g. `"prod"`). Used for Flutter artifact path auto-discovery.
        /// Defaults to `config.androidGradleProperties["flavor"]`.
        public var flavor: String?

        /// Human-readable release name shown in the Play Console (e.g. `"1.2.0 (42)"`).
        /// If nil, Google Play defaults to showing the versionCode.
        public var releaseName: String?

        /// Creates `Options` for the Play Store action.
        public init(
            aabPath: String? = nil,
            apkPath: String? = nil,
            track: String? = nil,
            releaseNotes: [String: String]? = nil,
            rolloutFraction: Double? = nil,
            packageName: String? = nil,
            buildVariant: String? = nil,
            flavor: String? = nil,
            releaseName: String? = nil
        ) {
            self.aabPath = aabPath
            self.apkPath = apkPath
            self.track = track
            self.releaseNotes = releaseNotes
            self.rolloutFraction = rolloutFraction
            self.packageName = packageName
            self.buildVariant = buildVariant
            self.flavor = flavor
            self.releaseName = releaseName
        }
    }

    /// Result of a successful Play Store upload.
    public struct Result: Codable, Sendable {
        /// The Android version code that was uploaded.
        public let versionCode: Int

        /// The track the release was assigned to.
        public let track: String

        /// The package name that was targeted.
        public let packageName: String

        /// Creates a `Result`.
        public init(versionCode: Int, track: String, packageName: String) {
            self.versionCode = versionCode
            self.track = track
            self.packageName = packageName
        }
    }

    /// Execute the Play Store upload action.
    ///
    /// - Parameters:
    ///   - options: Play Store upload options.
    ///   - context: Shared execution context (must have `googlePlay` client configured).
    /// - Returns: Upload result with versionCode, track, and package name.
    /// - Throws: ``ShipItError/invalidConfiguration(reason:)`` if credentials or artifact path are missing.
    ///   ``ShipItError/uploadFailed(asset:reason:)`` if the Play API returns an error.
    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .android else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "PlayStoreAction is only supported on Android. Current platform: \(context.platform.rawValue)"
            )
        }

        guard let googlePlay = context.googlePlay else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "Google Play credentials are not configured. Set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH."
            )
        }

        let packageName = options.packageName ?? context.config.androidPackageName
        guard let packageName else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "Play Store upload requires an Android package name. Set android.package_name in Shipfile.yml or pass --package-name."
            )
        }

        let track = options.track ?? context.config.androidPlayTrack
        let rolloutFraction = options.rolloutFraction ?? context.config.androidRolloutFraction

        // Resolve artifact path: explicit option → auto-discovery for Flutter/RN → error
        let resolvedAABPath: String?
        let resolvedAPKPath: String?

        if options.aabPath != nil || options.apkPath != nil {
            resolvedAABPath = options.aabPath
            resolvedAPKPath = options.apkPath
        } else {
            // Auto-discover well-known paths for Flutter / React Native
            let buildSystem = context.config.androidBuildSystem
            let variant = options.buildVariant ?? context.config.androidBuildVariant
            let flavor = options.flavor ?? context.config.androidGradleProperties["flavor"]
            switch buildSystem {
            case .flutter:
                resolvedAABPath = CrossPlatformArtifactPaths.flutterAAB(
                    flavor: flavor,
                    variant: variant
                )
                resolvedAPKPath = nil
                logger.info("Auto-discovered \(buildSystem.rawValue) AAB path: \(resolvedAABPath!)")
            case .reactNative:
                resolvedAABPath = CrossPlatformArtifactPaths.reactNativeAAB(variant: variant)
                resolvedAPKPath = nil
                logger.info("Auto-discovered \(buildSystem.rawValue) AAB path: \(resolvedAABPath!)")
            default:
                // Native Gradle: derive the conventional AAB output path from module + variant
                let module = context.config.androidModule
                let aab = CrossPlatformArtifactPaths.nativeAAB(module: module, variant: variant)
                resolvedAABPath = aab
                resolvedAPKPath = nil
                logger.info("Auto-discovered native AAB path: \(aab). Override with --aab or build_variant option if the path differs.")
            }
        }

        // Anchor relative paths against the shell's working directory so that
        // shipit can be invoked from any directory and still locate the artifact.
        let workingDirectory = context.shell.workingDirectory ?? FileManager.default.currentDirectoryPath
        let anchoredAABPath = resolvedAABPath.map { path -> String in
            guard !(path as NSString).isAbsolutePath else { return path }
            return (workingDirectory as NSString).appendingPathComponent(path)
        }
        let anchoredAPKPath = resolvedAPKPath.map { path -> String in
            guard !(path as NSString).isAbsolutePath else { return path }
            return (workingDirectory as NSString).appendingPathComponent(path)
        }

        let notes = buildReleaseNotes(from: options.releaseNotes)
        let releaseStatus: GooglePlayReleaseStatus = rolloutFraction != nil ? .inProgress : .completed

        logger.info("Uploading to Google Play — package: '\(packageName)', track: '\(track)'")

        let uploader = GooglePlayUploadService(client: googlePlay, packageName: packageName)
        let versionCode = try await uploader.uploadAndRelease(
            aabPath: anchoredAABPath,
            apkPath: anchoredAPKPath,
            track: track,
            releaseName: options.releaseName,
            releaseNotes: notes,
            status: releaseStatus,
            userFraction: rolloutFraction
        )

        logger.info("Play Store upload succeeded — versionCode=\(versionCode) on track '\(track)'")

        return Result(
            versionCode: versionCode,
            track: track,
            packageName: packageName
        )
    }

    // MARK: - Private

    private func buildReleaseNotes(from map: [String: String]?) -> [GooglePlayReleaseNote] {
        guard let map, !map.isEmpty else { return [] }
        return map.map { language, text in
            GooglePlayReleaseNote(language: language, text: text)
        }
    }
}
