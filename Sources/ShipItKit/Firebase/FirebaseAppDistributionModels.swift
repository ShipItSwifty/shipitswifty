import Foundation

/// The mobile platform encoded in a Firebase app ID.
///
/// Firebase app IDs carry their platform in the third colon-separated segment
/// (e.g. `1:1234567890:android:abc123`), which lets ShipIt reject an IPA being
/// uploaded to an Android app — and vice versa — before spending an upload.
public enum FirebaseAppPlatform: String, Codable, Sendable {
    /// An Android app registration.
    case android
    /// An iOS app registration.
    case ios
    /// A web app registration. Not distributable through App Distribution.
    case web
}

/// A parsed and validated Firebase app ID.
///
/// Firebase app IDs have the shape `{version}:{projectNumber}:{platform}:{hash}`.
/// The App Distribution API addresses apps by resource name rather than raw ID, and
/// the project number needed to build that name is embedded in the ID itself, so no
/// separate project configuration is required.
///
/// ## Usage
/// ```swift
/// let appID = try FirebaseAppID("1:1234567890:ios:abc123")
/// appID.platform      // .ios
/// appID.resourceName  // "projects/1234567890/apps/1:1234567890:ios:abc123"
/// ```
public struct FirebaseAppID: Sendable, Equatable {
    /// The raw app ID exactly as supplied.
    public let rawValue: String

    /// The Firebase project number parsed from the second segment.
    public let projectNumber: String

    /// The platform parsed from the third segment.
    public let platform: FirebaseAppPlatform

    /// The API resource name: `projects/{projectNumber}/apps/{appID}`.
    public var resourceName: String {
        "projects/\(projectNumber)/apps/\(rawValue)"
    }

    /// Parses and validates a Firebase app ID.
    ///
    /// - Parameter rawValue: An app ID such as `1:1234567890:android:abc123`.
    /// - Throws: ``ShipItError/invalidConfiguration(reason:)`` when the ID is malformed
    ///   or names a platform App Distribution cannot serve.
    public init(_ rawValue: String) throws {
        let segments = rawValue.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard segments.count == 4,
            !segments[0].isEmpty, segments[0].allSatisfy(\.isNumber),
            !segments[1].isEmpty, segments[1].allSatisfy(\.isNumber),
            !segments[3].isEmpty, segments[3].allSatisfy(\.isHexDigit),
            let platform = FirebaseAppPlatform(rawValue: segments[2])
        else {
            throw ShipItError.invalidConfiguration(
                reason: """
                    firebase-app-distribution: '\(rawValue)' is not a valid Firebase app ID. \
                    Expected the form '1:1234567890:android:abc123' — copy it from the Firebase \
                    console (Project settings → Your apps → App ID).
                    """
            )
        }
        guard platform != .web else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "firebase-app-distribution: app ID '\(rawValue)' is a web app. App Distribution supports only iOS and Android apps."
            )
        }
        self.rawValue = rawValue
        self.projectNumber = segments[1]
        self.platform = platform
    }
}

/// Release notes attached to an App Distribution release.
public struct FirebaseReleaseNotes: Codable, Sendable {
    /// The plain-text release notes shown to testers.
    public let text: String

    /// Creates release notes.
    public init(text: String) {
        self.text = text
    }
}

/// A release record returned by the App Distribution API.
public struct FirebaseRelease: Codable, Sendable {
    /// Resource name: `projects/{n}/apps/{appID}/releases/{releaseID}`.
    public let name: String

    /// Release notes, when present.
    public let releaseNotes: FirebaseReleaseNotes?

    /// The marketing version of the uploaded binary (e.g. `1.2.0`).
    public let displayVersion: String?

    /// The build number of the uploaded binary (e.g. `42`).
    public let buildVersion: String?

    /// Firebase console deep link for this release.
    public let firebaseConsoleUri: String?

    /// The link testers open to install this release.
    public let testingUri: String?

    /// Direct binary download link.
    public let binaryDownloadUri: String?
}

/// Outcome of an upload, distinguishing a new release from a re-upload of identical bytes.
public enum FirebaseUploadResult: String, Codable, Sendable {
    /// The API did not report a specific status.
    case unspecified = "UPLOAD_RELEASE_RESULT_UNSPECIFIED"
    /// A new release was created.
    case released = "RELEASE_CREATED"
    /// An existing release was updated.
    case updated = "RELEASE_UPDATED"
    /// The binary matched an existing release; nothing changed.
    case unmodified = "RELEASE_UNMODIFIED"
}

/// The payload returned once the upload long-running operation completes.
public struct FirebaseUploadReleaseResponse: Codable, Sendable {
    /// Whether the upload created, updated, or matched an existing release.
    public let result: FirebaseUploadResult?

    /// The resulting release.
    public let release: FirebaseRelease
}

/// A Google long-running operation envelope.
struct FirebaseOperation: Codable, Sendable {
    struct OperationError: Codable, Sendable {
        let code: Int?
        let message: String?
    }

    let name: String?
    let done: Bool?
    let error: OperationError?
    let response: FirebaseUploadReleaseResponse?
}
