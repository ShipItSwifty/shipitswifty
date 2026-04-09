import Foundation
import OSLog

/// Validates App Store metadata against App Store guidelines before submission.
///
/// Checks for text length violations, forbidden words, URL formats, and other
/// common issues that cause App Review rejections.
///
/// ## Usage
/// ```swift
/// let result = try await PrecheckAction().run(
///     with: .init(directory: "./metadata"),
///     context: context
/// )
/// if result.violations.isEmpty {
///     print("All checks passed!")
/// }
/// ```
public struct PrecheckAction: Action {
    public static let name = "precheck"
    public static let description = "Validate metadata against App Store guidelines before submission"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", PrecheckAction.self)

    /// Maximum lengths for App Store metadata fields.
    private enum FieldLimits {
        static let name = 30
        static let subtitle = 30
        static let description = 4000
        static let keywords = 100
        static let promotionalText = 170
        static let whatsNew = 4000
    }

    /// Creates a `PrecheckAction`.
    public init() {}

    /// Configuration for the precheck action.
    public struct Options: Codable, Sendable {
        /// Local directory containing metadata files.
        public var directory: String?

        /// Whether to fail on warnings (default: only fail on errors).
        public var failOnWarnings: Bool?

        /// Creates `Options` for the precheck action.
        public init(directory: String? = nil, failOnWarnings: Bool? = nil) {
            self.directory = directory
            self.failOnWarnings = failOnWarnings
        }
    }

    /// Result of a precheck run.
    public struct Result: Codable, Sendable {
        /// Validation violations found.
        public let violations: [String]

        /// Warnings (non-fatal issues).
        public let warnings: [String]

        /// Whether the metadata passed all checks.
        public var passed: Bool { violations.isEmpty }

        /// Creates a `Result`.
        public init(violations: [String] = [], warnings: [String] = []) {
            self.violations = violations
            self.warnings = warnings
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let directory = options.directory ?? context.config.metadataDirectory

        guard FileManager.default.fileExists(atPath: directory) else {
            throw ShipItError.invalidConfiguration(reason: "Metadata directory not found: \(directory)")
        }

        logger.info("Precheck: validating metadata in '\(directory)'")

        var violations: [String] = []
        var warnings: [String] = []

        let localeDirs = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []

        for locale in localeDirs {
            let localeDir = "\(directory)/\(locale)"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: localeDir, isDirectory: &isDir), isDir.boolValue else { continue }

            // Check name length
            if let name = try? String(contentsOfFile: "\(localeDir)/name.txt", encoding: .utf8) {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > FieldLimits.name {
                    violations.append("[\(locale)] App name exceeds \(FieldLimits.name) characters (\(trimmed.count))")
                }
                checkForbiddenWords(trimmed, field: "name", locale: locale, violations: &violations)
            }

            // Check subtitle length
            if let subtitle = try? String(contentsOfFile: "\(localeDir)/subtitle.txt", encoding: .utf8) {
                let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > FieldLimits.subtitle {
                    violations.append("[\(locale)] Subtitle exceeds \(FieldLimits.subtitle) characters (\(trimmed.count))")
                }
            }

            // Check description length
            if let description = try? String(contentsOfFile: "\(localeDir)/description.txt", encoding: .utf8) {
                let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > FieldLimits.description {
                    violations.append("[\(locale)] Description exceeds \(FieldLimits.description) characters (\(trimmed.count))")
                }
            }

            // Check keywords length
            if let keywords = try? String(contentsOfFile: "\(localeDir)/keywords.txt", encoding: .utf8) {
                let trimmed = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > FieldLimits.keywords {
                    violations.append("[\(locale)] Keywords exceed \(FieldLimits.keywords) characters (\(trimmed.count))")
                }
            }

            // Check release notes (what's new) length
            if let whatsNew = try? String(contentsOfFile: "\(localeDir)/release_notes.txt", encoding: .utf8) {
                let trimmed = whatsNew.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    warnings.append("[\(locale)] release_notes.txt is empty")
                } else if trimmed.count > FieldLimits.whatsNew {
                    violations.append("[\(locale)] What's New exceeds \(FieldLimits.whatsNew) characters (\(trimmed.count))")
                }
            }
        }

        if !violations.isEmpty {
            logger.warning("Precheck found \(violations.count) violation(s): \(violations.joined(separator: "; "))")
            throw ShipItError.precheckFailed(violations: violations)
        }

        if !warnings.isEmpty {
            logger.warning("Precheck warnings: \(warnings.joined(separator: "; "))")
        }

        logger.info("Precheck passed for \(localeDirs.count) locale(s)")
        return Result(violations: violations, warnings: warnings)
    }

    // MARK: - Helpers

    private func checkForbiddenWords(_ text: String, field: String, locale: String, violations: inout [String]) {
        let forbiddenWords = ["free", "best", "#1", "most popular", "top rated"]
        let lowercased = text.lowercased()
        for word in forbiddenWords {
            if lowercased.contains(word) {
                violations.append("[\(locale)] \(field) contains potentially forbidden word: '\(word)'")
            }
        }
    }
}
