import Foundation
import Logging

/// Reads and writes `versionName` and `versionCode` directly from a Gradle build file
/// (`build.gradle.kts` or `build.gradle`).
///
/// This backend is selected when `versioning.source` is `gradle` in the Shipfile.
/// It supports both Kotlin DSL (`versionName = "1.2.3"`) and Groovy DSL
/// (`versionName "1.2.3"` or `versionName = "1.2.3"`).
///
/// ## Supported patterns
/// ```kotlin
/// // Kotlin DSL (build.gradle.kts)
/// versionCode = 42
/// versionName = "1.2.3"
/// ```
/// ```groovy
/// // Groovy DSL (build.gradle)
/// versionCode 42
/// versionName "1.2.3"
/// ```
///
/// Line-based replacement preserves surrounding code structure. If a key is missing the
/// source throws so callers can surface a clear error.
struct GradleVersionSource: Sendable {
    private let context: ActionContext
    private let logger = Logger.forType(subsystem: "ShipItSwifty", GradleVersionSource.self)

    init(context: ActionContext) {
        self.context = context
    }

    /// Path to the Gradle build file. Falls back to `app/build.gradle.kts` when
    /// `versioning.spec_path` is unset. Also tries `app/build.gradle` as a fallback.
    private var gradleFilePath: String {
        get throws {
            if let explicit = context.config.versioningSpecPath {
                guard FileManager.default.fileExists(atPath: explicit) else {
                    throw ShipItError.invalidConfiguration(
                        reason: "Gradle build file not found at '\(explicit)'. "
                            + "Check versioning.spec_path in Shipfile.yml."
                    )
                }
                return explicit
            }

            let candidates = [
                "app/build.gradle.kts",
                "app/build.gradle",
            ]
            for candidate in candidates {
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
            throw ShipItError.invalidConfiguration(
                reason: "Could not find Gradle build file. Tried: \(candidates.joined(separator: ", ")). "
                    + "Set versioning.spec_path in Shipfile.yml to specify the file."
            )
        }
    }

    // MARK: - Read

    func readVersion() throws -> String {
        let path = try gradleFilePath
        let content = try String(contentsOfFile: path, encoding: .utf8)
        guard let value = extractVersionName(from: content) else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find 'versionName' in '\(path)'. "
                    + "Ensure versionName is set directly (not via a variable reference)."
            )
        }
        return value
    }

    func readBuildNumber() throws -> String {
        let path = try gradleFilePath
        let content = try String(contentsOfFile: path, encoding: .utf8)
        guard let value = extractVersionCode(from: content) else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find 'versionCode' in '\(path)'. "
                    + "Ensure versionCode is set directly (not via a variable reference)."
            )
        }
        return value
    }

    // MARK: - Write

    func writeVersion(_ version: String) throws {
        let path = try gradleFilePath
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let updated = try replaceVersionName(in: content, with: version, path: path)
        try updated.write(toFile: path, atomically: true, encoding: .utf8)
        logger.info("Set versionName to '\(version)' in '\(path)'")
    }

    func writeBuildNumber(_ build: String) throws {
        let path = try gradleFilePath
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let updated = try replaceVersionCode(in: content, with: build, path: path)
        try updated.write(toFile: path, atomically: true, encoding: .utf8)
        logger.info("Set versionCode to '\(build)' in '\(path)'")
    }

    // MARK: - Private: extraction

    /// Matches `versionName = "X.Y.Z"` (Kotlin DSL) or `versionName "X.Y.Z"` (Groovy DSL).
    private func extractVersionName(from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { continue }

            if let value = extractAssignment(key: "versionName", line: trimmed, quoted: true) {
                return value
            }
        }
        return nil
    }

    /// Matches `versionCode = 42` (Kotlin DSL) or `versionCode 42` (Groovy DSL).
    private func extractVersionCode(from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { continue }

            if let value = extractAssignment(key: "versionCode", line: trimmed, quoted: false) {
                return value
            }
        }
        return nil
    }

    /// Generic extractor for `key = value` or `key value` patterns.
    /// When `quoted` is true, expects the value to be in double quotes.
    private func extractAssignment(key: String, line: String, quoted: Bool) -> String? {
        guard line.hasPrefix(key) else { return nil }
        let rest = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)

        let valueStr: String
        if rest.hasPrefix("=") {
            // Kotlin DSL: `key = value` or `key= value`
            valueStr = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if !rest.isEmpty && !rest.hasPrefix("{") && !rest.hasPrefix("(") {
            // Groovy DSL: `key value`
            valueStr = rest
        } else {
            return nil
        }

        if quoted {
            // Strip quotes
            let unquoted = valueStr.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return unquoted.isEmpty ? nil : unquoted
        } else {
            // Numeric — strip any trailing comments
            let clean = valueStr.components(separatedBy: "//").first?
                .trimmingCharacters(in: .whitespaces) ?? valueStr
            return clean.isEmpty ? nil : clean
        }
    }

    // MARK: - Private: replacement

    private func replaceVersionName(in content: String, with version: String, path: String) throws -> String {
        try replaceLine(in: content, key: "versionName", newValue: "\"\(version)\"", quoted: true, path: path)
    }

    private func replaceVersionCode(in content: String, with build: String, path: String) throws -> String {
        try replaceLine(in: content, key: "versionCode", newValue: build, quoted: false, path: path)
    }

    private func replaceLine(in content: String, key: String, newValue: String, quoted: Bool, path: String) throws -> String {
        var lines = content.components(separatedBy: "\n")
        var found = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") { continue }
            guard trimmed.hasPrefix(key) else { continue }

            let rest = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            let isAssignment = rest.hasPrefix("=")
            let isGroovyCall = !rest.isEmpty && !rest.hasPrefix("{") && !rest.hasPrefix("(") && !isAssignment

            guard isAssignment || isGroovyCall else { continue }

            // Preserve indentation
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            if isAssignment {
                lines[index] = "\(indent)\(key) = \(newValue)"
            } else {
                lines[index] = "\(indent)\(key) \(newValue)"
            }
            found = true
            break
        }

        guard found else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find '\(key)' in '\(path)' to update. "
                    + "Ensure \(key) is set directly in the defaultConfig block."
            )
        }

        return lines.joined(separator: "\n")
    }
}
