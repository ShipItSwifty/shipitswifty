/// Define custom actions that extend ShipItSwifty.
///
/// In v1, plugins are statically linked Swift packages that register actions
/// during process startup. Arbitrary runtime loading of uncompiled packages or
/// dylibs is out of scope.
///
/// ## Creating a Plugin
/// 1. Create a Swift package with a target that depends on `ShipItKit`
/// 2. Export a type conforming to `ShipItPlugin`
/// 3. Add the package to `Package.swift`
/// 4. Register the plugin in the CLI/server bootstrap
///
/// ## Example
/// ```swift
/// public struct MyAnalyticsPlugin: ShipItPlugin {
///     public static let name = "analytics"
///     public static let description = "Analytics integration"
///     public static var actions: [ActionDescriptor] = [
///         TrackReleaseAction.descriptor
///     ]
/// }
/// ```
public protocol ShipItPlugin: Sendable {
    /// A short machine-readable identifier for this plugin.
    static var name: String { get }

    /// A human-readable description of what this plugin provides.
    static var description: String { get }

    /// The action descriptors contributed by this plugin.
    static var actions: [ActionDescriptor] { get }
}
