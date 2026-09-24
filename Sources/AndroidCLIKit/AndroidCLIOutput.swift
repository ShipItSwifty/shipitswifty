import Foundation

/// The kind of component `android run` launches (``AndroidCLI/run(apks:device:activity:type:installOptions:useDeltaInstall:debug:verbose:)``).
public enum AndroidComponentType: String, Codable, Sendable, CaseIterable {
    case activity = "ACTIVITY"
    case watchFace = "WATCH_FACE"
    case tile = "TILE"
    case complication = "COMPLICATION"
    case declarativeWatchFace = "DECLARATIVE_WATCH_FACE"
    case wearWidget = "WEAR_WIDGET"
}

/// A UI element returned by `android layout`. Unknown fields are intentionally ignored so newer
/// AndroidCLI releases that add fields keep decoding.
public struct AndroidLayoutElement: Codable, Sendable, Equatable {
    /// Visible text, if any.
    public let text: String?
    /// The view's resource ID (e.g. `"com.example:id/login"`).
    public let resourceId: String?
    /// The accessibility content description.
    public let contentDesc: String?
    /// Supported interactions (e.g. `"click"`, `"scroll"`).
    public let interactions: [String]?
    /// State flags (e.g. `"checked"`, `"focused"`).
    public let state: [String]?
    /// Bounds as reported by AndroidCLI (e.g. `"[0,0][1080,200]"`).
    public let bounds: String?
    /// Center point as reported by AndroidCLI (e.g. `"[540,100]"`), suitable for tap input.
    public let center: String?
    /// Whether the element is outside the visible viewport (JSON key `off-screen`).
    public let offScreen: Bool?

    public init(
        text: String? = nil, resourceId: String? = nil, contentDesc: String? = nil, interactions: [String]? = nil, state: [String]? = nil,
        bounds: String? = nil, center: String? = nil, offScreen: Bool? = nil
    ) {
        self.text = text
        self.resourceId = resourceId
        self.contentDesc = contentDesc
        self.interactions = interactions
        self.state = state
        self.bounds = bounds
        self.center = center
        self.offScreen = offScreen
    }

    enum CodingKeys: String, CodingKey {
        case text, resourceId, contentDesc, interactions, state, bounds, center
        case offScreen = "off-screen"
    }
}

/// Parsers for AndroidCLI output.
public enum AndroidCLIOutputParser {
    /// Decodes `android layout` JSON into typed elements.
    public static func layoutElements(from json: String) throws -> [AndroidLayoutElement] {
        try JSONDecoder().decode([AndroidLayoutElement].self, from: Data(json.utf8))
    }

    /// Parses `key: value` lines (e.g. `android info`) into a dictionary. Only the first `:` splits
    /// a line, so values containing colons (paths, URLs) are preserved; lines without `:` are skipped.
    public static func keyValues(from output: String) -> [String: String] {
        output.split(separator: "\n").reduce(into: [:]) { result, line in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return }
            result[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
    }
}
