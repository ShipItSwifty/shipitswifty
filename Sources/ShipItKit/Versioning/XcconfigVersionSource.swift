import Foundation
import Logging

/// Reads and writes the marketing version and build number directly from an Xcode
/// configuration file (`.xcconfig`).
///
/// This backend is selected when `versioning.source` is `xcconfig` in the Shipfile.
/// It is intended for projects that keep their version as a single source of truth in an
/// `.xcconfig` file and reference it from the `.xcodeproj` via build-setting indirection,
/// e.g.:
///
/// ```
/// // Config/Version.xcconfig
/// JOT_MARKETING_VERSION = 1.0.0
/// JOT_BUILD_NUMBER = 1
/// ```
/// ```
/// // project.pbxproj
/// MARKETING_VERSION = "$(JOT_MARKETING_VERSION)"
/// CURRENT_PROJECT_VERSION = "$(JOT_BUILD_NUMBER)"
/// ```
///
/// Unlike the `xcodeproj` source — which writes literal values into the project's build
/// configurations via `agvtool` and would clobber the `$(...)` indirection — this source edits
/// only the named keys in the `.xcconfig` file, preserving the single-source-of-truth layout.
///
/// ## Configuration
/// - `versioning.spec_path` — path to the `.xcconfig` file (required).
/// - `versioning.marketing_key` — key holding the marketing version (default `MARKETING_VERSION`).
/// - `versioning.build_key` — key holding the build number (default `CURRENT_PROJECT_VERSION`).
///
/// Line-based replacement preserves surrounding lines and indentation. xcconfig values are
/// unquoted; trailing `//` comments are ignored when reading. This source performs pure file I/O
/// (no shell), so it is Linux-compatible.
struct XcconfigVersionSource: Sendable {
    private let context: ActionContext
    private let logger = Logger.forType(subsystem: "ShipItSwifty", XcconfigVersionSource.self)

    init(context: ActionContext) {
        self.context = context
    }

    private var marketingKey: String { context.config.versioningMarketingKey }
    private var buildKey: String { context.config.versioningBuildKey }

    /// Path to the `.xcconfig` file. Required — there is no conventional default location.
    private var xcconfigPath: String {
        get throws {
            guard let path = context.config.versioningSpecPath else {
                throw ShipItError.invalidConfiguration(
                    reason: "versioning.source is 'xcconfig' but versioning.spec_path is not set. "
                        + "Set versioning.spec_path in Shipfile.yml to the .xcconfig file holding the version."
                )
            }
            guard FileManager.default.fileExists(atPath: path) else {
                throw ShipItError.invalidConfiguration(
                    reason: "xcconfig file not found at '\(path)'. "
                        + "Check versioning.spec_path in Shipfile.yml."
                )
            }
            return path
        }
    }

    // MARK: - Read

    func readVersion() throws -> String {
        try read(key: marketingKey)
    }

    func readBuildNumber() throws -> String {
        try read(key: buildKey)
    }

    private func read(key: String) throws -> String {
        let path = try xcconfigPath
        let content = try String(contentsOfFile: path, encoding: .utf8)
        guard let value = extractValue(key: key, from: content) else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find '\(key)' in '\(path)'. "
                    + "Ensure the key is set directly (e.g. `\(key) = 1.0.0`)."
            )
        }
        return value
    }

    // MARK: - Write

    func writeVersion(_ version: String) throws {
        try write(key: marketingKey, value: version)
    }

    func writeBuildNumber(_ build: String) throws {
        try write(key: buildKey, value: build)
    }

    private func write(key: String, value: String) throws {
        let path = try xcconfigPath
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let updated = try replaceValue(key: key, with: value, in: content, path: path)
        try updated.write(toFile: path, atomically: true, encoding: .utf8)
        logger.info("Set \(key) to '\(value)' in '\(path)'")
    }

    // MARK: - Parsing

    /// Returns the value assigned to `key` on a `KEY = VALUE` line, or `nil` if absent.
    /// Skips `//` comment lines and `#include`/`#import` directives. Trailing `//` comments
    /// on the value are stripped.
    private func extractValue(key: String, from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") { continue }
            guard let value = assignedValue(key: key, in: trimmed) else { continue }
            return value
        }
        return nil
    }

    /// Parses the value from a single trimmed line if it assigns `key`.
    ///
    /// Requires the character following `key` to be whitespace or `=` so that a key like
    /// `JOT_BUILD_NUMBER` does not match `JOT_BUILD_NUMBER_SUFFIX`. xcconfig also supports
    /// conditional suffixes (e.g. `KEY[sdk=*] = ...`) — those are intentionally not matched here.
    private func assignedValue(key: String, in line: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        let afterKey = line.dropFirst(key.count)
        guard let separator = afterKey.first, separator == "=" || separator == " " || separator == "\t"
        else { return nil }

        let rest = afterKey.trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("=") else { return nil }

        var value = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        // Strip a trailing inline comment.
        if let commentRange = value.range(of: "//") {
            value = String(value[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return value.isEmpty ? nil : value
    }

    /// Replaces the value of `key`, preserving the line's leading indentation. Throws if the key
    /// is not present.
    private func replaceValue(
        key: String, with newValue: String, in content: String, path: String
    )
        throws -> String
    {
        var lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") { continue }
            guard assignedValue(key: key, in: trimmed) != nil else { continue }

            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            lines[index] = "\(indent)\(key) = \(newValue)"
            return lines.joined(separator: "\n")
        }

        throw ShipItError.invalidConfiguration(
            reason: "Could not find '\(key)' in '\(path)' to update. "
                + "Ensure the key is set directly (e.g. `\(key) = 1.0.0`)."
        )
    }
}
