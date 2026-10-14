import Foundation
import MobileCore

#if canImport(ArgumentParser)
import ArgumentParser
#endif

public enum SchemaValueKind: String, Codable, Sendable, Hashable {
    case any
    case string
    case integer
    case number
    case boolean
    case object
    case array
}

public indirect enum SchemaFieldNode: Codable, Sendable, Hashable {
    case field(SchemaField)

    public var value: SchemaField {
        switch self {
        case .field(let field):
            return field
        }
    }
}

public struct SchemaField: Codable, Sendable, Hashable {
    public let name: String
    public let type: SchemaValueKind
    public let required: Bool
    public let description: String
    public let defaultValue: JSONValue?
    public let allowedValues: [JSONValue]
    public let example: JSONValue?
    public let envVar: String?
    public let isSecret: Bool
    public let notes: [String]
    public let properties: [SchemaFieldNode]
    public let items: SchemaFieldNode?
    public let allowsAdditionalProperties: Bool
    public let additionalProperties: SchemaFieldNode?

    public init(
        name: String,
        type: SchemaValueKind,
        required: Bool = false,
        description: String,
        defaultValue: JSONValue? = nil,
        allowedValues: [JSONValue] = [],
        example: JSONValue? = nil,
        envVar: String? = nil,
        isSecret: Bool = false,
        notes: [String] = [],
        properties: [SchemaFieldNode] = [],
        items: SchemaFieldNode? = nil,
        allowsAdditionalProperties: Bool = false,
        additionalProperties: SchemaFieldNode? = nil
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
        self.defaultValue = defaultValue
        self.allowedValues = allowedValues
        self.example = example
        self.envVar = envVar
        self.isSecret = isSecret
        self.notes = notes
        self.properties = properties
        self.items = items
        self.allowsAdditionalProperties = allowsAdditionalProperties
        self.additionalProperties = additionalProperties
    }
}

extension SchemaField {
    public static func string(
        _ name: String,
        required: Bool = false,
        description: String,
        defaultValue: JSONValue? = nil,
        allowedValues: [String] = [],
        example: JSONValue? = nil,
        envVar: String? = nil,
        isSecret: Bool = false,
        notes: [String] = []
    ) -> SchemaField {
        SchemaField(
            name: name,
            type: .string,
            required: required,
            description: description,
            defaultValue: defaultValue,
            allowedValues: allowedValues.map(JSONValue.string),
            example: example,
            envVar: envVar,
            isSecret: isSecret,
            notes: notes
        )
    }

    public static func integer(
        _ name: String,
        required: Bool = false,
        description: String,
        defaultValue: JSONValue? = nil,
        example: JSONValue? = nil,
        notes: [String] = []
    ) -> SchemaField {
        SchemaField(
            name: name,
            type: .integer,
            required: required,
            description: description,
            defaultValue: defaultValue,
            example: example,
            notes: notes
        )
    }

    public static func boolean(
        _ name: String,
        required: Bool = false,
        description: String,
        defaultValue: JSONValue? = nil,
        example: JSONValue? = nil,
        notes: [String] = []
    ) -> SchemaField {
        SchemaField(
            name: name,
            type: .boolean,
            required: required,
            description: description,
            defaultValue: defaultValue,
            example: example,
            notes: notes
        )
    }

    public static func number(
        _ name: String,
        required: Bool = false,
        description: String,
        defaultValue: JSONValue? = nil,
        example: JSONValue? = nil,
        notes: [String] = []
    ) -> SchemaField {
        SchemaField(
            name: name,
            type: .number,
            required: required,
            description: description,
            defaultValue: defaultValue,
            example: example,
            notes: notes
        )
    }

    public static func object(
        _ name: String,
        required: Bool = false,
        description: String,
        example: JSONValue? = nil,
        envVar: String? = nil,
        isSecret: Bool = false,
        notes: [String] = [],
        properties: [SchemaField] = [],
        allowsAdditionalProperties: Bool = false,
        additionalProperties: SchemaField? = nil
    ) -> SchemaField {
        SchemaField(
            name: name,
            type: .object,
            required: required,
            description: description,
            example: example,
            envVar: envVar,
            isSecret: isSecret,
            notes: notes,
            properties: properties.map(SchemaFieldNode.field),
            allowsAdditionalProperties: allowsAdditionalProperties,
            additionalProperties: additionalProperties.map(SchemaFieldNode.field)
        )
    }

    public static func array(
        _ name: String,
        required: Bool = false,
        description: String,
        defaultValue: JSONValue? = nil,
        example: JSONValue? = nil,
        notes: [String] = [],
        items: SchemaField
    ) -> SchemaField {
        SchemaField(
            name: name,
            type: .array,
            required: required,
            description: description,
            defaultValue: defaultValue,
            example: example,
            notes: notes,
            items: .field(items)
        )
    }

    public static func any(
        _ name: String,
        required: Bool = false,
        description: String,
        example: JSONValue? = nil,
        notes: [String] = []
    ) -> SchemaField {
        SchemaField(
            name: name,
            type: .any,
            required: required,
            description: description,
            example: example,
            notes: notes
        )
    }
}

extension SchemaField {
    public var propertyValues: [SchemaField] {
        properties.map(\.value)
    }

    public var itemValue: SchemaField? {
        items?.value
    }

    public var additionalPropertyValue: SchemaField? {
        additionalProperties?.value
    }
}

public struct SchemaSection: Codable, Sendable, Hashable {
    public let name: String
    public let description: String
    public let fields: [SchemaField]

    public init(name: String, description: String, fields: [SchemaField]) {
        self.name = name
        self.description = description
        self.fields = fields
    }
}

public struct ActionSchema: Codable, Sendable, Hashable {
    public let name: String
    public let description: String
    public let options: [SchemaField]
    public let example: JSONValue?

    public init(name: String, description: String, options: [SchemaField], example: JSONValue? = nil) {
        self.name = name
        self.description = description
        self.options = options
        self.example = example
    }
}

public enum ValidationIssueSeverity: String, Codable, Sendable, Hashable {
    case error
    case warning
}

public struct ValidationIssue: Codable, Sendable, Hashable {
    public let severity: ValidationIssueSeverity
    public let path: String
    public let message: String

    public init(severity: ValidationIssueSeverity, path: String, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }
}

public struct ValidationReport: Codable, Sendable, Hashable {
    public let shipfilePath: String
    public let issues: [ValidationIssue]

    public var isValid: Bool {
        issues.allSatisfy { $0.severity != .error }
    }

    public init(shipfilePath: String, issues: [ValidationIssue]) {
        self.shipfilePath = shipfilePath
        self.issues = issues
    }
}

/// What a root `Package.swift` says about how its tests can run, read from the manifest and sources without
/// building anything.
public struct SwiftPackageSummary: Codable, Sendable, Hashable {
    /// `Package(name:)`, when the manifest states it as a literal.
    public let name: String?
    /// Number of library and executable products. Xcode names the scheme that tests a package after the package
    /// when it has at most one product, and `<name>-Package` when it has several.
    public let productCount: Int
    /// Package sources (relative paths) that import a framework the host cannot build, such as UIKit, without a
    /// `canImport` or `os(...)` guard. When non-empty `swift test` cannot build the package on this machine, so its
    /// tests run through `xcodebuild` on a simulator instead.
    public let hostIncompatibleSources: [String]

    public init(name: String?, productCount: Int, hostIncompatibleSources: [String]) {
        self.name = name
        self.productCount = productCount
        self.hostIncompatibleSources = hostIncompatibleSources
    }

    /// Whether `swift test` can build and run the package on this machine.
    public var isHostTestable: Bool { hostIncompatibleSources.isEmpty }

    /// The scheme Xcode generates for a package directory, or `nil` when the manifest does not name the package.
    public var testScheme: String? {
        guard let name else { return nil }
        return productCount > 1 ? "\(name)-Package" : name
    }
}

public struct ProjectInspection: Codable, Sendable, Hashable {
    public struct XcodeContainer: Codable, Sendable, Hashable {
        public let kind: String
        public let path: String

        public init(kind: String, path: String) {
            self.kind = kind
            self.path = path
        }
    }

    public struct SchemeSummary: Codable, Sendable, Hashable {
        public let name: String
        public let containerPath: String
        public let bundleID: String?
        public let teamID: String?
        public let likelyRunnable: Bool

        public init(name: String, containerPath: String, bundleID: String? = nil, teamID: String? = nil, likelyRunnable: Bool) {
            self.name = name
            self.containerPath = containerPath
            self.bundleID = bundleID
            self.teamID = teamID
            self.likelyRunnable = likelyRunnable
        }
    }

    public struct SuggestedAppConfig: Codable, Sendable, Hashable {
        public let workspace: String?
        public let project: String?
        public let scheme: String?
        public let bundleID: String?
        public let teamID: String?

        public init(workspace: String? = nil, project: String? = nil, scheme: String? = nil, bundleID: String? = nil, teamID: String? = nil)
        {
            self.workspace = workspace
            self.project = project
            self.scheme = scheme
            self.bundleID = bundleID
            self.teamID = teamID
        }
    }

    public let rootPath: String
    public let xcodeContainers: [XcodeContainer]
    public let preferredContainer: XcodeContainer?
    public let schemes: [SchemeSummary]
    /// Discovered `.xctestplan` files, relative to the project root.
    public let testPlans: [String]
    public let suggestedAppConfig: SuggestedAppConfig
    public let existingShipfiles: [String]
    public let fastlaneFiles: [String]
    public let ciFiles: [String]
    public let warnings: [String]
    /// Best-effort inferred Android package name from Gradle or AndroidManifest.xml.
    public let suggestedAndroidPackageName: String?
    /// Auto-detected platform based on project file presence. `.android` when `gradlew` or
    /// `build.gradle.kts` is found; `.ios` when `.xcworkspace`/`.xcodeproj` is found; defaults to `.ios`.
    public let detectedPlatform: Platform
    /// Gradle-related files found under the root path (e.g. `gradlew`, `build.gradle.kts`).
    public let gradleFiles: [String]
    /// Auto-detected cross-platform build system driving the project, or `nil` for native projects.
    /// When non-`nil`, the same value applies to both iOS and Android target pipelines.
    public let detectedBuildSystem: AppFramework?
    /// Build-system marker files found under the root path (e.g. `pubspec.yaml`, `package.json`).
    /// Empty for native projects.
    public let buildSystemFiles: [String]
    /// The root Swift package, when `Package.swift` sits at the root path.
    public let swiftPackage: SwiftPackageSummary?

    public init(
        rootPath: String,
        xcodeContainers: [XcodeContainer],
        preferredContainer: XcodeContainer?,
        schemes: [SchemeSummary],
        testPlans: [String] = [],
        suggestedAppConfig: SuggestedAppConfig,
        existingShipfiles: [String],
        fastlaneFiles: [String],
        ciFiles: [String],
        warnings: [String],
        suggestedAndroidPackageName: String? = nil,
        detectedPlatform: Platform = .ios,
        gradleFiles: [String] = [],
        detectedBuildSystem: AppFramework? = nil,
        buildSystemFiles: [String] = [],
        swiftPackage: SwiftPackageSummary? = nil
    ) {
        self.rootPath = rootPath
        self.xcodeContainers = xcodeContainers
        self.preferredContainer = preferredContainer
        self.schemes = schemes
        self.testPlans = testPlans
        self.suggestedAppConfig = suggestedAppConfig
        self.existingShipfiles = existingShipfiles
        self.fastlaneFiles = fastlaneFiles
        self.ciFiles = ciFiles
        self.warnings = warnings
        self.suggestedAndroidPackageName = suggestedAndroidPackageName
        self.detectedPlatform = detectedPlatform
        self.gradleFiles = gradleFiles
        self.detectedBuildSystem = detectedBuildSystem
        self.buildSystemFiles = buildSystemFiles
        self.swiftPackage = swiftPackage
    }
}

public enum SuggestionGoal: String, Codable, Sendable, CaseIterable {
    case local
    case beta
    case release
}

#if canImport(ArgumentParser)
extension SuggestionGoal: ExpressibleByArgument {}
#endif

public struct SuggestedShipfile: Codable, Sendable, Hashable {
    public struct MissingValue: Codable, Sendable, Hashable {
        public let keyPath: String
        public let reason: String
        public let envVar: String?

        public init(keyPath: String, reason: String, envVar: String? = nil) {
            self.keyPath = keyPath
            self.reason = reason
            self.envVar = envVar
        }
    }

    /// What the suggestion sets up.
    public enum Kind: String, Codable, Sendable, Hashable {
        /// An app's build, test and distribution workflows.
        case app
        /// A Swift package's test workflow, selected by `test_workflow`; it needs no app identity or signing.
        case swiftPackage = "swift_package"
    }

    public let goal: SuggestionGoal
    public let kind: Kind
    public let inspection: ProjectInspection
    public let missingValues: [MissingValue]
    public let warnings: [String]
    public let yaml: String

    public init(
        goal: SuggestionGoal,
        kind: Kind = .app,
        inspection: ProjectInspection,
        missingValues: [MissingValue],
        warnings: [String],
        yaml: String
    ) {
        self.goal = goal
        self.kind = kind
        self.inspection = inspection
        self.missingValues = missingValues
        self.warnings = warnings
        self.yaml = yaml
    }
}
