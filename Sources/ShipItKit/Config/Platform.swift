/// The target platform for build and distribution workflows.
///
/// In v1, only `.ios` is fully supported. `.android` is reserved for the v2 roadmap.
/// Actions that are platform-specific throw `ShipItError/invalidConfiguration` when
/// called with an incompatible platform.
///
/// ## Usage
/// ```swift
/// let context = ActionContext(platform: .ios, ...)
/// guard context.platform == .ios else {
///     throw ShipItError.invalidConfiguration(reason: "ArchiveAction requires iOS platform")
/// }
/// ```
public enum Platform: String, Codable, Sendable, CaseIterable {
    /// Apple iOS platform. Fully supported in v1.
    case ios

    /// Android platform. Reserved for v2 roadmap.
    case android
}
