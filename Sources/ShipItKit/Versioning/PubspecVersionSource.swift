import Foundation
import Logging

/// Reads and writes Flutter version values from `pubspec.yaml`.
///
/// This backend is selected when `versioning.source` is `pubspec` in the Shipfile, and is
/// the default versioning source when the resolved build system is Flutter. Flutter treats
/// the pubspec `version:` key as the single source of truth — `flutter build` stamps
/// `CFBundleShortVersionString`/`CFBundleVersion` and `versionName`/`versionCode` from it,
/// so writing the native project files directly would be overwritten on the next build.
///
/// ## File layout
/// ```yaml
/// # pubspec.yaml
/// name: my_app
/// version: 1.2.3+45
/// ```
///
/// The part before `+` is the marketing version; the part after is the build number.
/// When the `+build` suffix is absent, the build number reads as `0` so the first
/// `bump build` produces `+1`. Only the top-level (column-zero) `version:` key is
/// touched — indented `version:` keys inside dependency blocks are ignored.
///
/// Line-based replacement preserves comments and ordering. If the top-level `version:`
/// key is missing the source throws so callers can surface a clear error rather than
/// silently inserting a value at an unpredictable location.
struct PubspecVersionSource: Sendable {
    private let context: ActionContext
    private let logger = Logger.forType(subsystem: "ShipItSwifty", PubspecVersionSource.self)

    init(context: ActionContext) {
        self.context = context
    }

    /// Path to the pubspec file. Falls back to `pubspec.yaml` at the project root when
    /// `versioning.spec_path` is unset.
    private var pubspecPath: String {
        context.config.versioningSpecPath ?? "pubspec.yaml"
    }

    // MARK: - Read

    func readVersion() throws -> String {
        try parsedVersion().marketing
    }

    func readBuildNumber() throws -> String {
        try parsedVersion().build ?? "0"
    }

    // MARK: - Write

    func writeVersion(_ version: String) throws {
        let current = try parsedVersion()
        let newValue = current.build.map { "\(version)+\($0)" } ?? version
        try replaceVersionLine(with: newValue)
        logger.info("Set pubspec version to '\(newValue)' in '\(pubspecPath)'")
    }

    func writeBuildNumber(_ build: String) throws {
        let current = try parsedVersion()
        let newValue = "\(current.marketing)+\(build)"
        try replaceVersionLine(with: newValue)
        logger.info("Set pubspec version to '\(newValue)' in '\(pubspecPath)'")
    }

    // MARK: - Private helpers

    private func loadPubspec() throws -> String {
        let url = URL(fileURLWithPath: pubspecPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ShipItError.invalidConfiguration(
                reason: "pubspec.yaml not found at '\(pubspecPath)'. "
                    + "Set versioning.spec_path in Shipfile.yml to the pubspec that holds the version."
            )
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Splits the raw `version:` value into marketing and optional build components.
    private func parsedVersion() throws -> (marketing: String, build: String?) {
        let content = try loadPubspec()
        guard let raw = extractVersionValue(from: content) else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find a top-level 'version:' key in '\(pubspecPath)'. "
                    + "Add one (e.g. `version: 1.0.0+1`) before running version bumps."
            )
        }
        guard let plusIndex = raw.firstIndex(of: "+") else {
            return (marketing: raw, build: nil)
        }
        return (
            marketing: String(raw[..<plusIndex]),
            build: String(raw[raw.index(after: plusIndex)...])
        )
    }

    /// Extracts the top-level `version:` value, skipping comments, stripping an inline
    /// comment, and unquoting. Indented `version:` keys (dependency blocks) never match.
    private func extractVersionValue(from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            guard line.hasPrefix("version:") else { continue }
            var value = String(line.dropFirst("version:".count))
            if let hashIndex = value.firstIndex(of: "#") {
                value = String(value[..<hashIndex])
            }
            value = value.trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Rewrites the top-level `version:` line in place, preserving all other content.
    private func replaceVersionLine(with newValue: String) throws {
        let url = URL(fileURLWithPath: pubspecPath)
        let content = try String(contentsOf: url, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        var found = false

        for (index, line) in lines.enumerated() {
            guard line.hasPrefix("version:") else { continue }
            var suffix = ""
            if let hashIndex = line.firstIndex(of: "#") {
                // Keep an inline comment (and its leading spacing) intact.
                var commentStart = hashIndex
                while commentStart > line.startIndex, line[line.index(before: commentStart)] == " " {
                    commentStart = line.index(before: commentStart)
                }
                suffix = String(line[commentStart...])
            }
            lines[index] = "version: \(newValue)\(suffix)"
            found = true
            break
        }

        guard found else {
            throw ShipItError.invalidConfiguration(
                reason: "Could not find a top-level 'version:' key in '\(pubspecPath)' to update. "
                    + "Add one (e.g. `version: 1.0.0+1`) before running version bumps."
            )
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
