/// The target platform for build and distribution workflows.
///
/// Pass `--platform ios` or `--platform android` on the CLI, or omit it to let
/// ShipItSwifty auto-detect the platform from project files in the working directory.
///
/// ## Auto-detection rules
/// | Project file detected | Platform |
/// |---|---|
/// | `gradlew` or `build.gradle.kts` | `.android` |
/// | `*.xcworkspace` or `*.xcodeproj` | `.ios` |
///
/// ## Usage
/// ```swift
/// let context = ActionContext(platform: .ios, ...)
/// guard context.platform == .ios else {
///     throw ShipItError.invalidConfiguration(reason: "ArchiveAction requires iOS platform")
/// }
/// ```
public enum Platform: String, Codable, Sendable, CaseIterable {
    /// Apple iOS platform. Fully supported.
    case ios

    /// Android platform.
    case android
}
