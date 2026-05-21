import Foundation
import Logging

/// Orchestrates the Google Play edit → upload → track → commit workflow.
///
/// This mirrors the transactional model required by the Play Developer API v3:
/// all changes must be made within an edit session and committed atomically.
///
/// ## Workflow
/// ```
/// 1. POST /edits               → create edit (editId)
/// 2. POST /edits/{id}/bundles  → upload AAB
///    or POST /edits/{id}/apks  → upload APK
/// 3. PUT  /edits/{id}/tracks   → assign version codes to a track
/// 4. POST /edits/{id}:commit   → commit changes
/// ```
///
/// ## Usage
/// ```swift
/// let client = try GooglePlayClient(serviceAccountJSONPath: "./service-account.json")
/// let uploader = GooglePlayUploadService(client: client, packageName: "com.example.app")
/// let result = try await uploader.uploadAndRelease(
///     aabPath: "./build/app-release.aab",
///     track: "internal",
///     releaseNotes: [GooglePlayReleaseNote(language: "en-US", text: "Bug fixes")],
///     status: .completed
/// )
/// ```
public struct GooglePlayUploadService: Sendable {

    private let client: GooglePlayClient
    private let packageName: String
    private let logger = Logger.forType(subsystem: "ShipItSwifty", GooglePlayUploadService.self)

    /// Creates a `GooglePlayUploadService`.
    ///
    /// - Parameters:
    ///   - client: Authenticated Google Play client.
    ///   - packageName: Android package name (e.g. `com.example.app`).
    public init(client: GooglePlayClient, packageName: String) {
        self.client = client
        self.packageName = packageName
    }

    /// Full upload-and-release workflow: create edit, upload artifact, assign track, commit.
    ///
    /// - Parameters:
    ///   - aabPath: Path to the `.aab` file. Use `apkPath` instead for APK uploads.
    ///   - apkPath: Path to the `.apk` file. Mutually exclusive with `aabPath`.
    ///   - track: Play Store track (e.g. `"internal"`, `"alpha"`, `"beta"`, `"production"`).
    ///   - releaseNotes: Per-language release notes.
    ///   - status: Release status (`.completed`, `.inProgress`, `.draft`).
    ///   - userFraction: Rollout fraction (0.0–1.0). Only used with `.inProgress` status.
    /// - Returns: The committed `GooglePlayBundle` or `GooglePlayApk` version code.
    @discardableResult
    public func uploadAndRelease(
        aabPath: String? = nil,
        apkPath: String? = nil,
        track: String,
        releaseName: String? = nil,
        releaseNotes: [GooglePlayReleaseNote] = [],
        status: GooglePlayReleaseStatus = .completed,
        userFraction: Double? = nil
    ) async throws -> Int {
        guard aabPath != nil || apkPath != nil else {
            throw ShipItError.invalidConfiguration(reason: "GooglePlayUploadService: provide either aabPath or apkPath")
        }

        // 0. Read artifact before creating an edit (validates existence and avoids orphaned edits)
        let artifactData: Data
        if let aab = aabPath {
            artifactData = try readArtifact(path: aab)
        } else if let apk = apkPath {
            artifactData = try readArtifact(path: apk)
        } else {
            // Unreachable due to guard above, but satisfies the compiler
            throw ShipItError.invalidConfiguration(reason: "GooglePlayUploadService: no artifact path provided")
        }

        // 1. Create edit
        logger.info("Creating Play Store edit for package '\(self.packageName)'")
        let edit: GooglePlayEdit = try await client.post("/applications/\(packageName)/edits")
        let editId = edit.id
        logger.info("Created edit: \(editId)")

        // 2. Upload artifact
        let versionCode: Int
        if aabPath != nil {
            let bundle = try await uploadBundleData(editId: editId, data: artifactData)
            versionCode = bundle.versionCode
            logger.info("Uploaded AAB versionCode=\(versionCode)")
        } else {
            let uploadedApk = try await uploadApkData(editId: editId, data: artifactData)
            versionCode = uploadedApk.versionCode
            logger.info("Uploaded APK versionCode=\(versionCode)")
        }

        // 3. Assign to track
        logger.info("Assigning versionCode=\(versionCode) to track '\(track)'")
        try await assignToTrack(
            editId: editId,
            track: track,
            versionCode: versionCode,
            releaseName: releaseName,
            releaseNotes: releaseNotes,
            status: status,
            userFraction: userFraction
        )

        // 4. Commit edit
        logger.info("Committing Play Store edit \(editId)")
        let _: GooglePlayEdit = try await client.post("/applications/\(packageName)/edits/\(editId):commit")
        logger.info("Play Store edit committed. versionCode=\(versionCode) is live on track '\(track)'")

        return versionCode
    }

    // MARK: - Private

    private func uploadBundle(editId: String, aabPath: String) async throws -> GooglePlayBundle {
        let data = try readArtifact(path: aabPath)
        return try await uploadBundleData(editId: editId, data: data)
    }

    private func uploadBundleData(editId: String, data: Data) async throws -> GooglePlayBundle {
        let path = "/applications/\(packageName)/edits/\(editId)/bundles"
        let responseData = try await client.uploadBinary(
            path: path,
            data: data,
            contentType: "application/octet-stream"
        )
        return try JSONDecoder().decode(GooglePlayBundle.self, from: responseData)
    }

    private func uploadApk(editId: String, apkPath: String) async throws -> GooglePlayApk {
        let data = try readArtifact(path: apkPath)
        return try await uploadApkData(editId: editId, data: data)
    }

    private func uploadApkData(editId: String, data: Data) async throws -> GooglePlayApk {
        let path = "/applications/\(packageName)/edits/\(editId)/apks"
        let responseData = try await client.uploadBinary(
            path: path,
            data: data,
            contentType: "application/vnd.android.package-archive"
        )
        return try JSONDecoder().decode(GooglePlayApk.self, from: responseData)
    }

    private func assignToTrack(
        editId: String,
        track: String,
        versionCode: Int,
        releaseName: String?,
        releaseNotes: [GooglePlayReleaseNote],
        status: GooglePlayReleaseStatus,
        userFraction: Double?
    ) async throws {
        let release = GooglePlayRelease(
            name: releaseName,
            versionCodes: ["\(versionCode)"],
            status: status,
            userFraction: userFraction,
            releaseNotes: releaseNotes.isEmpty ? nil : releaseNotes
        )
        let body = GooglePlayTrack(track: track, releases: [release])
        let path = "/applications/\(packageName)/edits/\(editId)/tracks/\(track)"
        let _: GooglePlayTrack = try await client.put(path, body: body)
    }

    private func readArtifact(path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ShipItError.invalidConfiguration(reason: "Google Play: artifact not found at '\(path)'")
        }
        return try Data(contentsOf: url)
    }
}
