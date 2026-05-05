#if os(macOS)
import Foundation
import Logging

/// Validates a `.xcarchive`, exported `.ipa`, or app bundle for App Store upload readiness.
///
/// Catches common issues that would cause rejection or processing failures before you upload,
/// including invalid icon transparency, missing Info.plist keys, iPad orientation requirements,
/// and archive structure problems.
///
/// ## Usage
/// ```swift
/// let result = try await ValidateArchiveAction().run(
///     with: .init(archivePath: "./build/MyApp.xcarchive"),
///     context: context
/// )
/// if result.issues.isEmpty {
///     print("Archive is ready for upload!")
/// }
/// ```
public struct ValidateArchiveAction: Action {
    public static let name = "validate_archive"
    public static let description = "Validate xcarchive / ipa / app bundle for App Store upload readiness"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", ValidateArchiveAction.self)

    /// Creates a `ValidateArchiveAction`.
    public init() {}

    /// Configuration for the validate_archive action.
    public struct Options: Codable, Sendable {
        /// Path to the `.xcarchive` directory to validate.
        public var archivePath: String?

        /// Path to the `.ipa` file to validate.
        public var ipaPath: String?

        /// When true, warnings are also treated as failures.
        public var failOnWarnings: Bool?

        /// Creates `Options` for the validate_archive action.
        public init(archivePath: String? = nil, ipaPath: String? = nil, failOnWarnings: Bool? = nil) {
            self.archivePath = archivePath
            self.ipaPath = ipaPath
            self.failOnWarnings = failOnWarnings
        }

        private enum CodingKeys: String, CodingKey {
            case archivePath = "archive_path"
            case ipaPath = "ipa_path"
            case failOnWarnings = "fail_on_warnings"
        }
    }

    /// A single issue found during archive validation.
    public struct ArchiveIssue: Codable, Sendable, Equatable {
        /// Issue severity.
        public enum Severity: String, Codable, Sendable, Equatable {
            case error
            case warning
        }

        /// Machine-readable issue code.
        public let code: String

        /// Human-readable message.
        public let message: String

        /// Issue severity.
        public let severity: Severity

        /// Creates an `ArchiveIssue`.
        public init(code: String, message: String, severity: Severity) {
            self.code = code
            self.message = message
            self.severity = severity
        }
    }

    /// Result of a validate_archive run.
    public struct Result: Codable, Sendable {
        /// The path that was validated (archive or IPA).
        public let validatedPath: String

        /// The app bundle identifier extracted from the archive, if available.
        public let bundleID: String?

        /// All issues found (errors + warnings).
        public let issues: [ArchiveIssue]

        /// Whether the archive passed all error-level checks.
        public var passed: Bool { issues.allSatisfy { $0.severity != .error } }

        /// Creates a `Result`.
        public init(validatedPath: String, bundleID: String? = nil, issues: [ArchiveIssue] = []) {
            self.validatedPath = validatedPath
            self.bundleID = bundleID
            self.issues = issues
        }

        private enum CodingKeys: String, CodingKey {
            case validatedPath = "validated_path"
            case bundleID = "bundle_id"
            case issues
            case passed
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(validatedPath, forKey: .validatedPath)
            try container.encodeIfPresent(bundleID, forKey: .bundleID)
            try container.encode(issues, forKey: .issues)
            try container.encode(passed, forKey: .passed)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            validatedPath = try container.decode(String.self, forKey: .validatedPath)
            bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
            issues = try container.decode([ArchiveIssue].self, forKey: .issues)
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        // Resolve the target to validate: prefer explicit ipa_path, then archive_path, then config.archiveOutputPath
        let targetPath: String
        let isIPA: Bool

        if let ipa = options.ipaPath {
            targetPath = ipa
            isIPA = true
        } else if let archive = options.archivePath {
            targetPath = archive
            isIPA = false
        } else if let configArchive = context.config.archiveOutputPath {
            targetPath = configArchive
            isIPA = configArchive.hasSuffix(".ipa")
        } else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "validate_archive requires an archive path. Pass --archive-path ./build/MyApp.xcarchive or --ipa ./build/export/MyApp.ipa"
            )
        }

        guard FileManager.default.fileExists(atPath: targetPath) else {
            throw ShipItError.invalidConfiguration(
                reason: "validate_archive: path not found: \(targetPath)"
            )
        }

        logger.info("ValidateArchive: validating '\(targetPath)'")

        var issues: [ArchiveIssue] = []
        var bundleID: String?

        if isIPA {
            try await validateIPA(at: targetPath, issues: &issues, context: context)
        } else {
            bundleID = try await validateXCArchive(at: targetPath, issues: &issues, context: context)
        }

        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count

        if errorCount > 0 {
            logger.warning("ValidateArchive: found \(errorCount) error(s), \(warningCount) warning(s) in '\(targetPath)'")
        } else if warningCount > 0 {
            logger.info("ValidateArchive: found \(warningCount) warning(s) in '\(targetPath)'")
        } else {
            logger.info("ValidateArchive: '\(targetPath)' passed all checks")
        }

        let result = Result(validatedPath: targetPath, bundleID: bundleID, issues: issues)

        // Fail if errors found, or if failOnWarnings is set and warnings found
        let shouldFail = errorCount > 0 || ((options.failOnWarnings == true) && warningCount > 0)
        if shouldFail {
            throw ShipItError.validateArchiveFailed(
                issues: issues.map { "[\($0.severity.rawValue.uppercased())] \($0.code): \($0.message)" })
        }

        return result
    }

    // MARK: - xcarchive validation

    /// Validates an xcarchive and returns the bundle identifier extracted from the app bundle, if available.
    @discardableResult
    private func validateXCArchive(at path: String, issues: inout [ArchiveIssue], context: ActionContext) async throws -> String? {
        // Validate archive directory structure
        let productsPath = "\(path)/Products"
        let infoPlistPath = "\(path)/Info.plist"

        guard FileManager.default.fileExists(atPath: productsPath) else {
            issues.append(
                .init(
                    code: "ARCHIVE_MISSING_PRODUCTS",
                    message: "Archive is missing the Products directory — this is not a valid .xcarchive.",
                    severity: .error
                ))
            return nil
        }

        if !FileManager.default.fileExists(atPath: infoPlistPath) {
            issues.append(
                .init(
                    code: "ARCHIVE_MISSING_INFO_PLIST",
                    message: "Archive is missing Info.plist at the archive root.",
                    severity: .error
                ))
            // Still continue — check app bundle if it exists
        }

        // Locate the .app bundle inside Products/Applications/
        let applicationsPath = "\(path)/Products/Applications"
        let appBundlePath = findAppBundle(in: applicationsPath)

        if let appBundle = appBundlePath {
            return try validateAppBundle(at: appBundle, issues: &issues)
        } else {
            issues.append(
                .init(
                    code: "ARCHIVE_NO_APP_BUNDLE",
                    message: "No .app bundle found inside Products/Applications/ — archive may be malformed.",
                    severity: .error
                ))
            return nil
        }
    }

    // MARK: - IPA validation

    private func validateIPA(at path: String, issues: inout [ArchiveIssue], context: ActionContext) async throws {
        if !path.hasSuffix(".ipa") {
            issues.append(
                .init(
                    code: "IPA_INVALID_EXTENSION",
                    message: "File does not have a .ipa extension: \(path)",
                    severity: .warning
                ))
        }

        // IPAs are ZIP archives; we check the file header
        guard let fileHandle = FileHandle(forReadingAtPath: path),
            let header = try? fileHandle.read(upToCount: 4)
        else {
            issues.append(
                .init(
                    code: "IPA_UNREADABLE",
                    message: "Cannot read IPA file at \(path)",
                    severity: .error
                ))
            return
        }
        fileHandle.closeFile()

        // ZIP magic bytes: PK\x03\x04
        let isZip = header.count >= 4 && header[0] == 0x50 && header[1] == 0x4B && header[2] == 0x03 && header[3] == 0x04
        if !isZip {
            issues.append(
                .init(
                    code: "IPA_NOT_ZIP",
                    message: "IPA file does not appear to be a valid ZIP archive (incorrect file header).",
                    severity: .error
                ))
        }

        // Warn: we can't do deep bundle inspection without extracting the IPA
        issues.append(
            .init(
                code: "IPA_SHALLOW_VALIDATION",
                message: "Deep bundle inspection requires an .xcarchive. IPA validation is limited to file format checks.",
                severity: .warning
            ))
    }

    // MARK: - App bundle validation

    /// Validates an app bundle and returns the bundle identifier if present and valid.
    @discardableResult
    private func validateAppBundle(at appBundle: String, issues: inout [ArchiveIssue]) throws -> String? {
        let infoPlistPath = "\(appBundle)/Info.plist"

        // Ensure Info.plist exists
        guard FileManager.default.fileExists(atPath: infoPlistPath) else {
            issues.append(
                .init(
                    code: "BUNDLE_MISSING_INFO_PLIST",
                    message: "App bundle is missing Info.plist at \(infoPlistPath).",
                    severity: .error
                ))
            return nil
        }

        guard let plist = NSDictionary(contentsOfFile: infoPlistPath) else {
            issues.append(
                .init(
                    code: "BUNDLE_UNPARSEABLE_INFO_PLIST",
                    message: "Info.plist exists but could not be parsed at \(infoPlistPath).",
                    severity: .error
                ))
            return nil
        }

        let extractedBundleID = validateBundleIdentifier(plist: plist, issues: &issues)
        validateVersionKeys(plist: plist, issues: &issues)
        validateIconKey(plist: plist, appBundle: appBundle, issues: &issues)
        validateIPadOrientations(plist: plist, issues: &issues)
        validateUIMainStoryboard(plist: plist, issues: &issues)
        return extractedBundleID
    }

    /// Validates CFBundleIdentifier and returns the extracted value (even if invalid).
    @discardableResult
    private func validateBundleIdentifier(plist: NSDictionary, issues: inout [ArchiveIssue]) -> String? {
        guard let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            issues.append(
                .init(
                    code: "BUNDLE_MISSING_BUNDLE_ID",
                    message: "Info.plist is missing CFBundleIdentifier.",
                    severity: .error
                ))
            return nil
        }
        // Validate bundle ID format (reverse-DNS)
        let bundleIDRegex = try? NSRegularExpression(pattern: #"^[A-Za-z0-9\-\.]+$"#)
        let range = NSRange(bundleID.startIndex..., in: bundleID)
        if bundleIDRegex?.firstMatch(in: bundleID, range: range) == nil {
            issues.append(
                .init(
                    code: "BUNDLE_INVALID_BUNDLE_ID",
                    message: "CFBundleIdentifier '\(bundleID)' contains invalid characters. Use reverse-DNS format (e.g. com.example.app).",
                    severity: .error
                ))
        }
        return bundleID
    }

    private func validateVersionKeys(plist: NSDictionary, issues: inout [ArchiveIssue]) {
        if (plist["CFBundleShortVersionString"] as? String).isNilOrEmpty {
            issues.append(
                .init(
                    code: "BUNDLE_MISSING_MARKETING_VERSION",
                    message: "Info.plist is missing CFBundleShortVersionString (marketing version).",
                    severity: .error
                ))
        }
        if (plist["CFBundleVersion"] as? String).isNilOrEmpty {
            issues.append(
                .init(
                    code: "BUNDLE_MISSING_BUILD_NUMBER",
                    message: "Info.plist is missing CFBundleVersion (build number).",
                    severity: .error
                ))
        }
    }

    private func validateIconKey(plist: NSDictionary, appBundle: String, issues: inout [ArchiveIssue]) {
        // Warn if no icon declaration — this is an App Store submission requirement,
        // not a hard build error. Unsigned/simulator archives legitimately lack icon declarations.
        let hasPrimaryIcon = plist["CFBundleIcons"] != nil || plist["CFBundleIconFiles"] != nil
        if !hasPrimaryIcon {
            issues.append(
                .init(
                    code: "BUNDLE_MISSING_ICON_DECLARATION",
                    message: "Info.plist has no CFBundleIcons or CFBundleIconFiles key. App Store requires a 1024×1024 app icon.",
                    severity: .warning
                ))
        }

        // Check asset catalog icon for alpha channel (1024x1024 icon must be opaque)
        checkIconAlpha(in: appBundle, issues: &issues)
    }

    private func checkIconAlpha(in appBundle: String, issues: inout [ArchiveIssue]) {
        // Look for AppIcon in Assets.car or loose icon files; check PNG alpha
        // We only check loose icon files here — .car inspection requires assetutil
        let assetsCar = "\(appBundle)/Assets.car"
        if FileManager.default.fileExists(atPath: assetsCar) {
            // We can't inspect Assets.car without assetutil; emit a warning to remind users
            issues.append(
                .init(
                    code: "ICON_ALPHA_CHECK_SKIPPED",
                    message:
                        "App icon alpha check skipped: Assets.car requires assetutil to inspect. Ensure the 1024×1024 App Store icon has no transparency.",
                    severity: .warning
                ))
            return
        }

        // Loose PNG check
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: appBundle) else { return }
        let iconFiles = contents.filter { $0.hasPrefix("AppIcon") && $0.hasSuffix(".png") }
        for iconFile in iconFiles {
            let iconPath = "\(appBundle)/\(iconFile)"
            if pngHasAlpha(at: iconPath) {
                issues.append(
                    .init(
                        code: "ICON_HAS_ALPHA",
                        message: "App icon '\(iconFile)' contains an alpha channel. The 1024×1024 App Store icon must be fully opaque.",
                        severity: .error
                    ))
            }
        }
    }

    private func pngHasAlpha(at path: String) -> Bool {
        // PNG signature + IHDR chunk — color type byte at offset 25 indicates alpha
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
            data.count > 25
        else { return false }
        // PNG signature: 8 bytes, IHDR: 4 (length) + 4 (type) + 13 (data) = 25 bytes total
        // Byte 25 (0-indexed) = color type: 4 = grayscale+alpha, 6 = RGBA
        let colorType = data[25]
        return colorType == 4 || colorType == 6
    }

    private func validateIPadOrientations(plist: NSDictionary, issues: inout [ArchiveIssue]) {
        // Check UISupportedInterfaceOrientations~ipad
        guard let ipadOrientations = plist["UISupportedInterfaceOrientations~ipad"] as? [String] else {
            // Not declared — not necessarily a problem unless UIRequiresFullScreen is absent
            return
        }

        let requiresFullScreen = plist["UIRequiresFullScreen"] as? Bool ?? false

        // iPad multitasking requires all four orientations unless full-screen-only is declared
        let allOrientations: Set<String> = [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ]
        let declaredSet = Set(ipadOrientations)

        if !requiresFullScreen && !allOrientations.isSubset(of: declaredSet) {
            let missing = allOrientations.subtracting(declaredSet).sorted()
            issues.append(
                .init(
                    code: "APPSTORE_ORIENTATION_IPAD",
                    message: "iPad multitasking requires all four supported orientations unless UIRequiresFullScreen is true. "
                        + "Missing: \(missing.joined(separator: ", ")). "
                        + "Either add the missing orientations or set UIRequiresFullScreen = YES in Info.plist.",
                    severity: .error
                ))
        }
    }

    private func validateUIMainStoryboard(plist: NSDictionary, issues: inout [ArchiveIssue]) {
        // Warn if neither UIMainStoryboardFile nor UISceneDelegateClassName is set (likely empty launch)
        let hasStoryboard = (plist["UIMainStoryboardFile"] as? String) != nil
        let hasSceneManifest = plist["UIApplicationSceneManifest"] != nil
        if !hasStoryboard && !hasSceneManifest {
            issues.append(
                .init(
                    code: "BUNDLE_NO_LAUNCH_INTERFACE",
                    message:
                        "Info.plist has neither UIMainStoryboardFile nor UIApplicationSceneManifest. The app may have no launch interface configured.",
                    severity: .warning
                ))
        }
    }

    // MARK: - Helpers

    private func findAppBundle(in directory: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }
        return
            contents
            .filter { $0.hasSuffix(".app") }
            .map { "\(directory)/\($0)" }
            .first
    }
}

// MARK: - Internal helpers

extension Optional where Wrapped == String {
    fileprivate var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
#endif
