import Foundation
import Logging

/// Reads and writes Kotlin Multiplatform version values from `gradle.properties`.
///
/// This backend is selected when `versioning.source` is `kmp` in the Shipfile.
/// It updates the source-of-truth Gradle properties file so that subsequent
/// `gradlew` invocations and downstream Android/iOS builds pick up the new values.
///
/// ## Supported keys
/// Defaults are `versionName` (marketing version) and `versionCode` (build number).
/// Both keys are overridable via `versioning.marketing_key` and `versioning.build_key`
/// respectively.
///
/// ## File layout
/// ```properties
/// # gradle.properties
/// versionName=1.2.3
/// versionCode=45
/// ```
///
/// Line-based replacement preserves comments and ordering. If a key is missing the
/// source throws so callers can surface a clear error rather than silently inserting
/// a value at an unpredictable location.
struct KMPVersionSource: Sendable {
    private let context: ActionContext
    private let logger = Logger.forType(subsystem: "ShipItSwifty", KMPVersionSource.self)

    init(context: ActionContext) {
        self.context = context
    }

    /// Path to the Gradle properties file. Falls back to `gradle.properties` at the project
    /// root when `versioning.spec_path` is unset.
    private var propertiesPath: String {
        context.config.versioningSpecPath ?? "gradle.properties"
    }

    /// Key used for the build number. Defaults to `versionCode` when the configured key still
    /// points at the iOS-flavored `CURRENT_PROJECT_VERSION`.
    private var buildKey: String {
        let configured = context.config.versioningBuildKey
        return configured == "CURRENT_PROJECT_VERSION" ? "versionCode" : configured
    }

    /// Key used for the marketing version. Defaults to `versionName` when the configured key
    /// still points at the iOS-flavored `MARKETING_VERSION`.
    private var marketingKey: String {
        let configured = context.config.versioningMarketingKey
        return configured == "MARKETING_VERSION" ? "versionName" : configured
    }

    // MARK: - Read

    func readVersion() throws -> String {
        let content = try loadProperties()
        guard let value = extractValue(key: marketingKey, from: content) else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find '\(marketingKey)' in Gradle properties at '\(propertiesPath)'. "
                    + "Ensure the key is defined, or override it via versioning.marketing_key."
            )
        }
        return value
    }

    func readBuildNumber() throws -> String {
        let content = try loadProperties()
        guard let value = extractValue(key: buildKey, from: content) else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find '\(buildKey)' in Gradle properties at '\(propertiesPath)'. "
                    + "Ensure the key is defined, or override it via versioning.build_key."
            )
        }
        return value
    }

    // MARK: - Write

    func writeVersion(_ version: String) throws {
        try updateProperty(key: marketingKey, value: version)
        logger.info("Set \(marketingKey) to '\(version)' in '\(propertiesPath)'")
    }

    func writeBuildNumber(_ build: String) throws {
        try updateProperty(key: buildKey, value: build)
        logger.info("Set \(buildKey) to '\(build)' in '\(propertiesPath)'")
    }

    // MARK: - Private helpers

    private func loadProperties() throws -> String {
        let url = URL(fileURLWithPath: propertiesPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ShipItError.invalidConfiguration(
                reason: "Gradle properties file not found at '\(propertiesPath)'. "
                    + "Set versioning.spec_path in Shipfile.yml to the file that holds versionName/versionCode."
            )
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Extracts a `key=value` pair value, skipping comment lines and ignoring whitespace
    /// around the equals sign.
    private func extractValue(key: String, from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("!") { continue }
            guard trimmed.hasPrefix("\(key)=") || trimmed.hasPrefix("\(key) =") else { continue }
            let afterEquals =
                trimmed
                .drop(while: { $0 != "=" })
                .dropFirst()
            let value = afterEquals.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Updates an existing `key=value` line in place. Throws when the key is missing rather
    /// than appending at an unpredictable location.
    private func updateProperty(key: String, value: String) throws {
        let url = URL(fileURLWithPath: propertiesPath)
        let content = try String(contentsOf: url, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        var found = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("!") { continue }
            guard trimmed.hasPrefix("\(key)=") || trimmed.hasPrefix("\(key) =") else { continue }

            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            lines[index] = "\(indent)\(key)=\(value)"
            found = true
            break
        }

        guard found else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find '\(key)' in Gradle properties at '\(propertiesPath)' to update. "
                    + "Add the key (e.g. `versionName=1.0.0`) before running version bumps."
            )
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
