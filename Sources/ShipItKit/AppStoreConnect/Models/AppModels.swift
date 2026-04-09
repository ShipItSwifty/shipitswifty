import Foundation

// MARK: - Generic Response Wrappers

/// Generic single-resource response wrapper for App Store Connect API responses.
///
/// All ASC API responses for single resources follow the `{ "data": {...} }` envelope.
public struct ASCResponse<T: Codable & Sendable>: Codable, Sendable where T: Codable {
    /// The primary data payload.
    public let data: T

    /// Creates an `ASCResponse`.
    public init(data: T) {
        self.data = data
    }
}

/// Generic list response wrapper for App Store Connect API list endpoints.
///
/// All ASC API responses for resource collections follow the `{ "data": [...] }` envelope,
/// optionally including `links` for pagination.
public struct ASCListResponse<T: Codable & Sendable>: Codable, Sendable {
    /// Array of resources returned by the endpoint.
    public let data: [T]

    /// Pagination links.
    public let links: PagedLinks?

    /// Creates an `ASCListResponse`.
    public init(data: [T], links: PagedLinks? = nil) {
        self.data = data
        self.links = links
    }
}

/// Pagination links included in list API responses.
public struct PagedLinks: Codable, Sendable {
    /// URL for the current page.
    public let `self`: String?

    /// URL for the next page of results.
    public let next: String?

    /// URL for the first page of results.
    public let first: String?

    /// Creates a `PagedLinks`.
    public init(self selfURL: String? = nil, next: String? = nil, first: String? = nil) {
        self.`self` = selfURL
        self.next = next
        self.first = first
    }
}

// MARK: - App

/// An iOS or macOS app registered in App Store Connect.
public struct ASCApp: Codable, Sendable {
    /// Unique identifier for this app resource.
    public let id: String

    /// App attributes.
    public let attributes: Attributes?

    /// Creates an `ASCApp`.
    public init(id: String, attributes: Attributes? = nil) {
        self.id = id
        self.attributes = attributes
    }

    /// Attributes of an App Store Connect app.
    public struct Attributes: Codable, Sendable {
        /// The app's bundle identifier (e.g. `com.example.myapp`).
        public let bundleId: String?

        /// The app's display name on the App Store.
        public let name: String?

        /// Primary platform for the app.
        public let primaryLocale: String?

        /// Whether the app is available for sale.
        public let isOrEverWasMadeForKids: Bool?

        /// Creates `ASCApp.Attributes`.
        public init(
            bundleId: String? = nil,
            name: String? = nil,
            primaryLocale: String? = nil,
            isOrEverWasMadeForKids: Bool? = nil
        ) {
            self.bundleId = bundleId
            self.name = name
            self.primaryLocale = primaryLocale
            self.isOrEverWasMadeForKids = isOrEverWasMadeForKids
        }
    }
}

// MARK: - Build

/// A processed build associated with an app in App Store Connect.
public struct ASCBuild: Codable, Sendable {
    /// Unique identifier for this build.
    public let id: String

    /// Build attributes.
    public let attributes: Attributes?

    /// Creates an `ASCBuild`.
    public init(id: String, attributes: Attributes? = nil) {
        self.id = id
        self.attributes = attributes
    }

    /// Attributes of an App Store Connect build.
    public struct Attributes: Codable, Sendable {
        /// The build version string (e.g. `"142"`).
        public let version: String?

        /// Current processing state.
        public let processingState: String?

        /// Whether the build has expired.
        public let expired: Bool?

        /// Date when the build was uploaded.
        public let uploadedDate: String?

        /// Creates `ASCBuild.Attributes`.
        public init(
            version: String? = nil,
            processingState: String? = nil,
            expired: Bool? = nil,
            uploadedDate: String? = nil
        ) {
            self.version = version
            self.processingState = processingState
            self.expired = expired
            self.uploadedDate = uploadedDate
        }
    }
}

// MARK: - Beta Group

/// A TestFlight beta testing group.
public struct ASCBetaGroup: Codable, Sendable {
    /// Unique identifier for this beta group.
    public let id: String

    /// Beta group attributes.
    public let attributes: Attributes?

    /// Creates an `ASCBetaGroup`.
    public init(id: String, attributes: Attributes? = nil) {
        self.id = id
        self.attributes = attributes
    }

    /// Attributes of a TestFlight beta group.
    public struct Attributes: Codable, Sendable {
        /// The name of the beta group.
        public let name: String?

        /// Whether this is a public link group.
        public let publicLink: Bool?

        /// Whether the group is enabled.
        public let isInternalGroup: Bool?

        /// Creates `ASCBetaGroup.Attributes`.
        public init(
            name: String? = nil,
            publicLink: Bool? = nil,
            isInternalGroup: Bool? = nil
        ) {
            self.name = name
            self.publicLink = publicLink
            self.isInternalGroup = isInternalGroup
        }
    }
}

// MARK: - Beta Tester

/// A TestFlight beta tester.
public struct ASCBetaTester: Codable, Sendable {
    /// Unique identifier for this tester.
    public let id: String

    /// Tester attributes.
    public let attributes: Attributes?

    /// Creates an `ASCBetaTester`.
    public init(id: String, attributes: Attributes? = nil) {
        self.id = id
        self.attributes = attributes
    }

    /// Attributes of a TestFlight beta tester.
    public struct Attributes: Codable, Sendable {
        /// The tester's first name.
        public let firstName: String?

        /// The tester's last name.
        public let lastName: String?

        /// The tester's email address.
        public let email: String?

        /// Current invite type.
        public let inviteType: String?

        /// Creates `ASCBetaTester.Attributes`.
        public init(
            firstName: String? = nil,
            lastName: String? = nil,
            email: String? = nil,
            inviteType: String? = nil
        ) {
            self.firstName = firstName
            self.lastName = lastName
            self.email = email
            self.inviteType = inviteType
        }
    }
}
