import Foundation
import OSLog
import SwiftyShell

/// Reads and writes version values directly in a project spec YAML file
/// (e.g. XcodeGen's `project.yml`).
///
/// This is the versioning backend used when `versioning.source` is `project_spec`.
/// Instead of mutating the generated `.xcodeproj` (which would be overwritten on
/// next generation), it updates the source-of-truth spec file so that subsequent
/// project generation picks up the new values.
///
/// ## Supported keys
/// The build settings are expected to appear under `settings:` in the YAML file,
/// typically as:
/// ```yaml
/// settings:
///   CURRENT_PROJECT_VERSION: "42"
///   MARKETING_VERSION: "1.2.0"
/// ```
///
/// The key names are configurable via `versioning.build_key` and
/// `versioning.marketing_key` in the Shipfile.
struct ProjectSpecVersionSource: Sendable {
    private let context: ActionContext
    private let logger = Logger.forType(subsystem: "ShipItSwifty", ProjectSpecVersionSource.self)

    init(context: ActionContext) {
        self.context = context
    }

    /// The path to the project spec file.
    private var specPath: String {
        context.config.versioningSpecPath
            ?? context.config.projectGenerationSpecPath
            ?? "project.yml"
    }

    /// The YAML key used for the build number.
    private var buildKey: String {
        context.config.versioningBuildKey
    }

    /// The YAML key used for the marketing version.
    private var marketingKey: String {
        context.config.versioningMarketingKey
    }

    // MARK: - Read

    /// Read the current marketing version from the project spec.
    func readVersion() throws -> String {
        let content = try loadSpec()
        guard let value = extractSettingValue(key: marketingKey, from: content) else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find '\(marketingKey)' in project spec at '\(specPath)'. "
                    + "Ensure the setting exists under a `settings:` block."
            )
        }
        return value
    }

    /// Read the current build number from the project spec.
    func readBuildNumber() throws -> String {
        let content = try loadSpec()
        guard let value = extractSettingValue(key: buildKey, from: content) else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find '\(buildKey)' in project spec at '\(specPath)'. "
                    + "Ensure the setting exists under a `settings:` block."
            )
        }
        return value
    }

    // MARK: - Write

    /// Write a new marketing version to the project spec.
    func writeVersion(_ version: String) throws {
        try updateSetting(key: marketingKey, value: version)
        logger.info("Set \(marketingKey) to '\(version)' in '\(specPath)'")
    }

    /// Write a new build number to the project spec.
    func writeBuildNumber(_ build: String) throws {
        try updateSetting(key: buildKey, value: build)
        logger.info("Set \(buildKey) to '\(build)' in '\(specPath)'")
    }

    // MARK: - Private Helpers

    /// Load the spec file contents.
    private func loadSpec() throws -> String {
        let url = URL(fileURLWithPath: specPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ShipItError.invalidConfiguration(
                reason: "Project spec file not found at '\(specPath)'. "
                    + "Set versioning.spec_path or project_generation.spec_path in Shipfile.yml."
            )
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Extract a build setting value from YAML content.
    ///
    /// Searches for lines matching patterns like:
    /// - `CURRENT_PROJECT_VERSION: "42"` (quoted)
    /// - `CURRENT_PROJECT_VERSION: 42` (unquoted)
    /// - `  CURRENT_PROJECT_VERSION: "42"` (indented, under settings:)
    private func extractSettingValue(key: String, from content: String) -> String? {
        let lines = content.components(separatedBy: "\n")
        // Pattern: optional whitespace, key, colon, optional space, value
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            let afterColon = String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            // Strip quotes if present
            let unquoted =
                afterColon
                .trimmingCharacters(in: .init(charactersIn: "\"'"))
            if !unquoted.isEmpty {
                return unquoted
            }
        }
        return nil
    }

    /// Update a build setting value in the YAML file using line-by-line replacement.
    ///
    /// This approach preserves the file's formatting, comments, and structure
    /// rather than round-tripping through a full YAML parser which could
    /// reorder keys or strip comments.
    private func updateSetting(key: String, value: String) throws {
        let url = URL(fileURLWithPath: specPath)
        let content = try String(contentsOf: url, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        var found = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }

            // Preserve the indentation of the original line
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))

            // Determine quoting style: if the original was quoted, keep quotes
            let afterColon = String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            let useQuotes = afterColon.hasPrefix("\"") || afterColon.hasPrefix("'")

            if useQuotes {
                lines[index] = "\(indent)\(key): \"\(value)\""
            } else {
                lines[index] = "\(indent)\(key): \(value)"
            }
            found = true
            break
        }

        guard found else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find '\(key)' in project spec at '\(specPath)' to update. "
                    + "Ensure the setting exists in your spec file."
            )
        }

        let updated = lines.joined(separator: "\n")
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }
}
