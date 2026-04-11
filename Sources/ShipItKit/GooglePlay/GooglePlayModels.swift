import Foundation

// MARK: - Google Play Developer API v3 Models

/// A Google Play edit session. All publishing changes are made within an edit
/// and then committed atomically.
public struct GooglePlayEdit: Codable, Sendable {
    /// Unique edit identifier returned by the Edits API.
    public let id: String
    /// RFC 3339 expiry timestamp for this edit session.
    public let expiryTimeSeconds: String?
}

/// An uploaded Android App Bundle.
public struct GooglePlayBundle: Codable, Sendable {
    /// The version code of the uploaded bundle.
    public let versionCode: Int
    /// SHA-256 hash of the bundle.
    public let sha256: String?
}

/// An uploaded APK.
public struct GooglePlayApk: Codable, Sendable {
    /// The version code of the uploaded APK.
    public let versionCode: Int
    /// SHA-256 hash of the APK.
    public let sha256: String?
    /// Binary information.
    public let binary: GooglePlayApkBinary?

    public struct GooglePlayApkBinary: Codable, Sendable {
        public let sha256: String?
    }
}

/// A release note for a specific language.
public struct GooglePlayReleaseNote: Codable, Sendable {
    /// BCP 47 language tag (e.g. `"en-US"`).
    public let language: String
    /// The release note text (max 500 chars).
    public let text: String

    public init(language: String, text: String) {
        self.language = language
        self.text = text
    }
}

/// Deployment status for a track release.
public enum GooglePlayReleaseStatus: String, Codable, Sendable {
    /// Saved but not yet deployed. Finalize in Play Console.
    case draft
    /// Staged rollout to a fraction of users.
    case inProgress
    /// Paused staged rollout.
    case halted
    /// Full rollout to all users.
    case completed
}

/// A release within a track, tying version codes to a status and release notes.
public struct GooglePlayRelease: Codable, Sendable {
    /// Internal name for this release (optional, used in Play Console UI).
    public let name: String?
    /// Version codes included in this release.
    public let versionCodes: [String]
    /// Release status.
    public let status: GooglePlayReleaseStatus
    /// Staged rollout fraction (0.0–1.0). Only meaningful for `.inProgress`.
    public let userFraction: Double?
    /// Per-language release notes.
    public let releaseNotes: [GooglePlayReleaseNote]?

    public init(
        name: String? = nil,
        versionCodes: [String],
        status: GooglePlayReleaseStatus,
        userFraction: Double? = nil,
        releaseNotes: [GooglePlayReleaseNote]? = nil
    ) {
        self.name = name
        self.versionCodes = versionCodes
        self.status = status
        self.userFraction = userFraction
        self.releaseNotes = releaseNotes
    }
}

/// A Google Play distribution track (e.g. internal, alpha, beta, production).
public struct GooglePlayTrack: Codable, Sendable {
    /// Track identifier: `"qa"` (internal), `"alpha"`, `"beta"`, `"production"`.
    public let track: String
    /// Current releases on this track.
    public let releases: [GooglePlayRelease]?

    public init(track: String, releases: [GooglePlayRelease]? = nil) {
        self.track = track
        self.releases = releases
    }
}

/// Service account credentials loaded from a Google Cloud service account JSON key file.
public struct GoogleServiceAccountCredentials: Sendable {
    /// Service account email.
    public let clientEmail: String
    /// PEM-encoded RSA private key.
    public let privateKey: String
    /// Token URI (typically `https://oauth2.googleapis.com/token`).
    public let tokenUri: String
    /// Project ID.
    public let projectId: String?

    enum CodingKeys: String, CodingKey {
        case clientEmail = "client_email"
        case privateKey = "private_key"
        case tokenUri = "token_uri"
        case projectId = "project_id"
    }
}

extension GoogleServiceAccountCredentials: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientEmail = try c.decode(String.self, forKey: .clientEmail)
        privateKey = try c.decode(String.self, forKey: .privateKey)
        tokenUri = try c.decode(String.self, forKey: .tokenUri)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clientEmail, forKey: .clientEmail)
        try c.encode(privateKey, forKey: .privateKey)
        try c.encode(tokenUri, forKey: .tokenUri)
        try c.encodeIfPresent(projectId, forKey: .projectId)
    }
}

// MARK: - Upload session

/// Resumable upload session response from the Google APIs.
struct GooglePlayUploadSessionResponse: Codable, Sendable {
    let uploadId: String?
    let status: String?
}

/// OAuth2 access token response from Google's token endpoint.
struct GoogleOAuth2TokenResponse: Codable, Sendable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}
