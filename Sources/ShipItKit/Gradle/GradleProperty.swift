import Foundation
import SwiftyShell

/// A typed Gradle `-P` project property.
///
/// Properties are passed as `-PversionCode=42` arguments to `gradlew`.
///
/// ## Usage
/// ```swift
/// let output = try await Gradle(context: context.shell)
///     .task(.bundleRelease)
///     .property(.versionCode(100))
///     .property(.versionName("2.1.0"))
///     .run()
/// ```
public struct GradleProperty: Sendable, Equatable, Hashable {

    /// The argument emitted for this property (e.g. `-PversionCode=42`).
    public let argument: String

    // MARK: - Common Properties

    /// `-PversionCode=<code>` — Override the Android `versionCode` integer.
    public static func versionCode(_ code: Int) -> GradleProperty {
        GradleProperty(key: "versionCode", value: "\(code)")
    }

    /// `-PversionName=<name>` — Override the Android `versionName` string.
    public static func versionName(_ name: String) -> GradleProperty {
        GradleProperty(key: "versionName", value: name)
    }

    /// `-P<key>=<value>` — Arbitrary custom Gradle project property.
    public static func custom(key: String, value: String) -> GradleProperty {
        GradleProperty(key: key, value: value)
    }

    // MARK: - Init

    /// Creates a `GradleProperty` with an explicit key/value pair.
    public init(key: String, value: String) {
        self.argument = "-P\(key)=\(value)"
    }

    private init(argument: String) {
        self.argument = argument
    }
}
