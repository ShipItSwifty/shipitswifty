#if os(macOS)
import Foundation
import Logging

/// Shared App Store release operations built on top of `AppStoreConnectClient`.
///
/// This service coordinates App Store version lookup/creation, metadata localization
/// updates, and review submission workflows so multiple actions can reuse the same logic.
public struct AppStoreReleaseService: Sendable {
    private let client: AppStoreConnectClient
    private let logger = Logger.forType(subsystem: "ShipItSwifty", AppStoreReleaseService.self)

    /// Creates an `AppStoreReleaseService` bound to an ASC client.
    public init(client: AppStoreConnectClient) {
        self.client = client
    }

    /// Result of a metadata sync operation.
    public struct MetadataSyncResult: Sendable {
        /// Number of locales whose metadata was processed.
        public let localesProcessed: Int
        /// The App Store Connect app ID.
        public let appID: String
        /// The App Store version ID that was updated, if any.
        public let appStoreVersionID: String?

        /// Creates a `MetadataSyncResult`.
        public init(localesProcessed: Int, appID: String, appStoreVersionID: String?) {
            self.localesProcessed = localesProcessed
            self.appID = appID
            self.appStoreVersionID = appStoreVersionID
        }
    }

    /// Result of submitting an app for App Review.
    public struct ReviewSubmissionResult: Sendable {
        /// The App Store version ID that was submitted.
        public let appStoreVersionID: String
        /// The review submission ID created by ASC.
        public let reviewSubmissionID: String

        /// Creates a `ReviewSubmissionResult`.
        public init(appStoreVersionID: String, reviewSubmissionID: String) {
            self.appStoreVersionID = appStoreVersionID
            self.reviewSubmissionID = reviewSubmissionID
        }
    }

    /// Downloads App Store metadata localizations to the local filesystem.
    ///
    /// For each locale, creates a subdirectory under `directory` and writes
    /// `name.txt`, `subtitle.txt`, `description.txt`, `keywords.txt`, and `release_notes.txt`.
    ///
    /// - Parameters:
    ///   - bundleID: The app's bundle identifier used to look up the ASC app.
    ///   - directory: Local directory path where locale subdirectories will be written.
    ///   - context: The action execution context.
    /// - Returns: A `MetadataSyncResult` summarising how many locales were processed.
    /// - Throws: `ShipItError.apiError` if the app or API calls fail.
    public func pullMetadata(
        bundleID: String,
        directory: String,
        context: ActionContext
    ) async throws -> MetadataSyncResult {
        let app = try await resolveApp(bundleID: bundleID)
        let appStoreVersion = try await resolveLatestAppStoreVersion(appID: app.id)

        let infoLocalizations: ASCListResponse<AppInfoLocalizationResource> = try await client.get(
            "/v1/apps/\(app.id)/appInfoLocalizations"
        )

        let versionLocalizations: [AppStoreVersionLocalizationResource]
        if let appStoreVersion {
            let response: ASCListResponse<AppStoreVersionLocalizationResource> = try await client.get(
                "/v1/appStoreVersionLocalizations",
                query: ["filter[appStoreVersion]": appStoreVersion.id]
            )
            versionLocalizations = response.data
        } else {
            versionLocalizations = []
        }

        var versionLocalizationsByLocale: [String: AppStoreVersionLocalizationResource] = [:]
        for localization in versionLocalizations {
            if let locale = localization.attributes?.locale {
                versionLocalizationsByLocale[locale] = localization
            }
        }

        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)

        var localeCount = 0
        for infoLocalization in infoLocalizations.data {
            guard let locale = infoLocalization.attributes?.locale else { continue }
            let localeDir = "\(directory)/\(locale)"
            try FileManager.default.createDirectory(atPath: localeDir, withIntermediateDirectories: true, attributes: nil)

            try writeIfPresent(infoLocalization.attributes?.name, to: "\(localeDir)/name.txt")
            try writeIfPresent(infoLocalization.attributes?.subtitle, to: "\(localeDir)/subtitle.txt")

            let versionLocalization = versionLocalizationsByLocale[locale]
            try writeIfPresent(versionLocalization?.attributes?.description, to: "\(localeDir)/description.txt")
            try writeIfPresent(versionLocalization?.attributes?.keywords, to: "\(localeDir)/keywords.txt")
            try writeIfPresent(versionLocalization?.attributes?.whatsNew, to: "\(localeDir)/release_notes.txt")
            localeCount += 1
        }

        return MetadataSyncResult(
            localesProcessed: localeCount,
            appID: app.id,
            appStoreVersionID: appStoreVersion?.id
        )
    }

    /// Uploads local metadata files to App Store Connect localizations.
    ///
    /// Reads locale subdirectories from `directory` and upserts `name`, `subtitle`,
    /// `description`, `keywords`, and `whatsNew` (release notes) for each locale.
    ///
    /// - Parameters:
    ///   - bundleID: The app's bundle identifier used to look up the ASC app.
    ///   - directory: Local directory containing locale subdirectories with metadata files.
    ///   - context: The action execution context (used to resolve the version string when creating a new App Store version).
    /// - Returns: A `MetadataSyncResult` summarising how many locales were processed.
    /// - Throws: `ShipItError.apiError` if the app or API calls fail.
    public func pushMetadata(
        bundleID: String,
        directory: String,
        context: ActionContext
    ) async throws -> MetadataSyncResult {
        let app = try await resolveApp(bundleID: bundleID)
        let appStoreVersion = try await resolveOrCreateAppStoreVersion(appID: app.id, context: context)
        let appInfoID = try await resolveAppInfoID(appID: app.id)
        let localeDirs = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        var localeCount = 0

        for locale in localeDirs {
            let localeDir = "\(directory)/\(locale)"
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: localeDir, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let metadata = LocalizedMetadata(
                locale: locale,
                name: try? readTrimmedText(at: "\(localeDir)/name.txt"),
                subtitle: try? readTrimmedText(at: "\(localeDir)/subtitle.txt"),
                description: try? readTrimmedText(at: "\(localeDir)/description.txt"),
                keywords: try? readTrimmedText(at: "\(localeDir)/keywords.txt"),
                whatsNew: try? readTrimmedText(at: "\(localeDir)/release_notes.txt")
            )

            try await upsertAppInfoLocalization(appID: app.id, appInfoID: appInfoID, metadata: metadata)
            try await upsertAppStoreVersionLocalization(appStoreVersionID: appStoreVersion.id, metadata: metadata)
            localeCount += 1
        }

        return MetadataSyncResult(
            localesProcessed: localeCount,
            appID: app.id,
            appStoreVersionID: appStoreVersion.id
        )
    }

    /// Submits the current App Store version for App Review.
    ///
    /// Sets the release type (`AFTER_APPROVAL` or `MANUAL`), optionally creates a phased
    /// release schedule, then posts a review submission to App Store Connect.
    ///
    /// - Parameters:
    ///   - bundleID: The app's bundle identifier used to look up the ASC app.
    ///   - automaticRelease: If `true`, the build is released automatically after approval.
    ///   - phasedRelease: If `true`, a phased-release schedule is created.
    ///   - context: The action execution context (used to resolve the version string if needed).
    /// - Returns: A `ReviewSubmissionResult` with the version and submission IDs.
    /// - Throws: `ShipItError.apiError` if the app or API calls fail.
    public func submitForReview(
        bundleID: String,
        automaticRelease: Bool,
        phasedRelease: Bool,
        context: ActionContext
    ) async throws -> ReviewSubmissionResult {
        let app = try await resolveApp(bundleID: bundleID)
        let appStoreVersion = try await resolveOrCreateAppStoreVersion(appID: app.id, context: context)

        let releaseType = automaticRelease || phasedRelease ? "AFTER_APPROVAL" : "MANUAL"
        let _: ASCResponse<AppStoreVersionResource> = try await client.patch(
            "/v1/appStoreVersions/\(appStoreVersion.id)",
            body: AppStoreVersionUpdateRequest(
                data: .init(
                    type: "appStoreVersions",
                    id: appStoreVersion.id,
                    attributes: .init(releaseType: releaseType)
                )
            )
        )

        if phasedRelease {
            let _: ASCResponse<AppStoreVersionPhasedReleaseResource> = try await client.post(
                "/v1/appStoreVersionPhasedReleases",
                body: AppStoreVersionPhasedReleaseCreateRequest(
                    data: .init(
                        type: "appStoreVersionPhasedReleases",
                        relationships: .init(
                            appStoreVersion: .init(data: .init(type: "appStoreVersions", id: appStoreVersion.id))
                        )
                    )
                )
            )
        }

        let submission: ASCResponse<ReviewSubmissionResource> = try await client.post(
            "/v1/reviewSubmissions",
            body: ReviewSubmissionCreateRequest(
                data: .init(
                    type: "reviewSubmissions",
                    relationships: .init(
                        appStoreVersion: .init(data: .init(type: "appStoreVersions", id: appStoreVersion.id))
                    )
                )
            )
        )

        logger.info("Created review submission '\(submission.data.id)' for version '\(appStoreVersion.id)'")
        return ReviewSubmissionResult(appStoreVersionID: appStoreVersion.id, reviewSubmissionID: submission.data.id)
    }

    private func resolveApp(bundleID: String) async throws -> ASCApp {
        let apps: ASCListResponse<ASCApp> = try await client.get(
            "/v1/apps",
            query: ["filter[bundleId]": bundleID]
        )

        guard let app = apps.data.first else {
            throw ShipItError.apiError(statusCode: 404, body: "App with bundle ID '\(bundleID)' not found in App Store Connect")
        }

        return app
    }

    private func resolveLatestAppStoreVersion(appID: String) async throws -> AppStoreVersionResource? {
        let response: ASCListResponse<AppStoreVersionResource> = try await client.get(
            "/v1/apps/\(appID)/appStoreVersions",
            query: ["filter[platform]": "IOS", "limit": "1"]
        )
        return response.data.first
    }

    private func resolveAppInfoID(appID: String) async throws -> String {
        let response: ASCListResponse<AppInfoResource> = try await client.get(
            "/v1/apps/\(appID)/appInfos",
            query: ["limit": "1"]
        )

        guard let appInfo = response.data.first else {
            throw ShipItError.apiError(statusCode: 404, body: "App info for app '\(appID)' not found in App Store Connect")
        }

        return appInfo.id
    }

    private func resolveOrCreateAppStoreVersion(appID: String, context: ActionContext) async throws -> AppStoreVersionResource {
        if let existing = try await resolveLatestAppStoreVersion(appID: appID) {
            return existing
        }

        let versionString = try await VersionBumper(context: context).readVersion()
        let created: ASCResponse<AppStoreVersionResource> = try await client.post(
            "/v1/appStoreVersions",
            body: AppStoreVersionCreateRequest(
                data: .init(
                    type: "appStoreVersions",
                    attributes: .init(platform: "IOS", versionString: versionString),
                    relationships: .init(app: .init(data: .init(type: "apps", id: appID)))
                )
            )
        )
        return created.data
    }

    private func upsertAppInfoLocalization(appID: String, appInfoID: String, metadata: LocalizedMetadata) async throws {
        guard metadata.name != nil || metadata.subtitle != nil else { return }

        let existing: ASCListResponse<AppInfoLocalizationResource> = try await client.get(
            "/v1/apps/\(appID)/appInfoLocalizations",
            query: ["filter[locale]": metadata.locale]
        )

        if let localization = existing.data.first {
            let _: ASCResponse<AppInfoLocalizationResource> = try await client.patch(
                "/v1/appInfoLocalizations/\(localization.id)",
                body: AppInfoLocalizationUpdateRequest(
                    data: .init(
                        type: "appInfoLocalizations",
                        id: localization.id,
                        attributes: .init(name: metadata.name, subtitle: metadata.subtitle)
                    )
                )
            )
        } else {
            let _: ASCResponse<AppInfoLocalizationResource> = try await client.post(
                "/v1/appInfoLocalizations",
                body: AppInfoLocalizationCreateRequest(
                    data: .init(
                        type: "appInfoLocalizations",
                        attributes: .init(
                            locale: metadata.locale,
                            name: metadata.name,
                            subtitle: metadata.subtitle
                        ),
                        relationships: .init(
                            appInfo: .init(data: .init(type: "appInfos", id: appInfoID))
                        )
                    )
                )
            )
        }
    }

    private func upsertAppStoreVersionLocalization(appStoreVersionID: String, metadata: LocalizedMetadata) async throws {
        guard metadata.description != nil || metadata.keywords != nil || metadata.whatsNew != nil else { return }

        let existing: ASCListResponse<AppStoreVersionLocalizationResource> = try await client.get(
            "/v1/appStoreVersionLocalizations",
            query: [
                "filter[appStoreVersion]": appStoreVersionID,
                "filter[locale]": metadata.locale,
            ]
        )

        if let localization = existing.data.first {
            let _: ASCResponse<AppStoreVersionLocalizationResource> = try await client.patch(
                "/v1/appStoreVersionLocalizations/\(localization.id)",
                body: AppStoreVersionLocalizationUpdateRequest(
                    data: .init(
                        type: "appStoreVersionLocalizations",
                        id: localization.id,
                        attributes: .init(
                            description: metadata.description,
                            keywords: metadata.keywords,
                            whatsNew: metadata.whatsNew
                        )
                    )
                )
            )
        } else {
            let _: ASCResponse<AppStoreVersionLocalizationResource> = try await client.post(
                "/v1/appStoreVersionLocalizations",
                body: AppStoreVersionLocalizationCreateRequest(
                    data: .init(
                        type: "appStoreVersionLocalizations",
                        attributes: .init(
                            locale: metadata.locale,
                            description: metadata.description,
                            keywords: metadata.keywords,
                            whatsNew: metadata.whatsNew
                        ),
                        relationships: .init(
                            appStoreVersion: .init(data: .init(type: "appStoreVersions", id: appStoreVersionID))
                        )
                    )
                )
            )
        }
    }

    private func writeIfPresent(_ value: String?, to path: String) throws {
        guard let value, !value.isEmpty else { return }
        try value.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func readTrimmedText(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LocalizedMetadata: Sendable {
    let locale: String
    let name: String?
    let subtitle: String?
    let description: String?
    let keywords: String?
    let whatsNew: String?
}

private struct AppInfoLocalizationResource: Codable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Codable, Sendable {
        let locale: String?
        let name: String?
        let subtitle: String?
    }
}

private struct AppInfoResource: Codable, Sendable {
    let id: String
}

private struct AppInfoLocalizationCreateRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships

        struct Attributes: Encodable, Sendable {
            let locale: String
            let name: String?
            let subtitle: String?
        }

        struct Relationships: Encodable, Sendable {
            let appInfo: AppInfoRelationship
        }
    }
}

private struct AppInfoLocalizationUpdateRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes

        struct Attributes: Encodable, Sendable {
            let name: String?
            let subtitle: String?
        }
    }
}

private struct AppInfoRelationship: Encodable, Sendable {
    let data: ResourceIdentifier
}

private struct AppStoreVersionResource: Codable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Codable, Sendable {
        let versionString: String?
        let appStoreState: String?
    }
}

private struct AppStoreVersionCreateRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships

        struct Attributes: Encodable, Sendable {
            let platform: String
            let versionString: String
        }

        struct Relationships: Encodable, Sendable {
            let app: AppRelationship
        }
    }
}

private struct AppRelationship: Encodable, Sendable {
    let data: ResourceIdentifier
}

private struct ResourceIdentifier: Codable, Sendable {
    let type: String
    let id: String
}

private struct AppStoreVersionUpdateRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes

        struct Attributes: Encodable, Sendable {
            let releaseType: String
        }
    }
}

private struct AppStoreVersionLocalizationResource: Codable, Sendable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Codable, Sendable {
        let locale: String?
        let description: String?
        let keywords: String?
        let whatsNew: String?
    }
}

private struct AppStoreVersionLocalizationCreateRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships

        struct Attributes: Encodable, Sendable {
            let locale: String
            let description: String?
            let keywords: String?
            let whatsNew: String?
        }

        struct Relationships: Encodable, Sendable {
            let appStoreVersion: AppStoreVersionRelationship
        }
    }
}

private struct AppStoreVersionLocalizationUpdateRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes

        struct Attributes: Encodable, Sendable {
            let description: String?
            let keywords: String?
            let whatsNew: String?
        }
    }
}

private struct AppStoreVersionRelationship: Encodable, Sendable {
    let data: ResourceIdentifier
}

private struct ReviewSubmissionResource: Codable, Sendable {
    let id: String
}

private struct ReviewSubmissionCreateRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let relationships: Relationships

        struct Relationships: Encodable, Sendable {
            let appStoreVersion: AppStoreVersionRelationship
        }
    }
}

private struct AppStoreVersionPhasedReleaseResource: Codable, Sendable {
    let id: String
}

private struct AppStoreVersionPhasedReleaseCreateRequest: Encodable, Sendable {
    let data: DataBody

    struct DataBody: Encodable, Sendable {
        let type: String
        let relationships: Relationships

        struct Relationships: Encodable, Sendable {
            let appStoreVersion: AppStoreVersionRelationship
        }
    }
}
#endif
