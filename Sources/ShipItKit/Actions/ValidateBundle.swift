import Foundation
import Logging

/// Validates an Android App Bundle (`.aab`) or APK for Google Play upload readiness.
///
/// Checks basic file format integrity, and optionally runs `bundletool validate`
/// if bundletool is available on the system.
///
/// ## Usage
/// ```swift
/// let result = try await ValidateBundleAction().run(
///     with: .init(aabPath: "./build/app-release.aab"),
///     context: androidContext
/// )
/// if result.issues.isEmpty {
///     print("Bundle is ready for Play Store upload!")
/// }
/// ```
public struct ValidateBundleAction: Action {
    public static let name = "validate_bundle"
    public static let description = "Validate Android App Bundle (.aab) or APK for Google Play upload readiness"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", ValidateBundleAction.self)

    /// Creates a `ValidateBundleAction`.
    public init() {}

    /// Configuration for the validate_bundle action.
    public struct Options: Codable, Sendable {
        /// Path to the `.aab` file to validate.
        public var aabPath: String?

        /// Path to the `.apk` file to validate.
        public var apkPath: String?

        /// When `true`, warnings are also treated as failures.
        public var failOnWarnings: Bool?

        /// Creates `Options` for the validate_bundle action.
        public init(aabPath: String? = nil, apkPath: String? = nil, failOnWarnings: Bool? = nil) {
            self.aabPath = aabPath
            self.apkPath = apkPath
            self.failOnWarnings = failOnWarnings
        }

        private enum CodingKeys: String, CodingKey {
            case aabPath = "aab_path"
            case apkPath = "apk_path"
            case failOnWarnings = "fail_on_warnings"
        }
    }

    /// A single issue found during bundle validation.
    public struct BundleIssue: Codable, Sendable, Equatable {
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

        /// Creates a `BundleIssue`.
        public init(code: String, message: String, severity: Severity) {
            self.code = code
            self.message = message
            self.severity = severity
        }
    }

    /// Result of a validate_bundle run.
    public struct Result: Codable, Sendable {
        /// The path that was validated.
        public let validatedPath: String

        /// Whether this is an AAB (`true`) or APK (`false`).
        public let isAAB: Bool

        /// All issues found (errors + warnings).
        public let issues: [BundleIssue]

        /// Whether the bundle passed all error-level checks.
        public var passed: Bool { issues.allSatisfy { $0.severity != .error } }

        /// Creates a `Result`.
        public init(validatedPath: String, isAAB: Bool, issues: [BundleIssue] = []) {
            self.validatedPath = validatedPath
            self.isAAB = isAAB
            self.issues = issues
        }

        private enum CodingKeys: String, CodingKey {
            case validatedPath = "validated_path"
            case isAAB = "is_aab"
            case issues
            case passed
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(validatedPath, forKey: .validatedPath)
            try container.encode(isAAB, forKey: .isAAB)
            try container.encode(issues, forKey: .issues)
            try container.encode(passed, forKey: .passed)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            validatedPath = try container.decode(String.self, forKey: .validatedPath)
            isAAB = try container.decode(Bool.self, forKey: .isAAB)
            issues = try container.decode([BundleIssue].self, forKey: .issues)
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        // Resolve target path — fall back to build-system defaults when no explicit path given
        let targetPath: String
        let isAAB: Bool

        if let aab = options.aabPath {
            targetPath = aab
            isAAB = true
        } else if let apk = options.apkPath {
            targetPath = apk
            isAAB = false
        } else {
            // Auto-discover well-known paths for the resolved Android build system.
            let buildSystem = context.config.androidBuildSystem
            switch buildSystem {
            case .flutter:
                targetPath = CrossPlatformArtifactPaths.flutterAAB(
                    flavor: context.config.androidGradleProperties["flavor"],
                    variant: context.config.androidBuildVariant
                )
                isAAB = true
            case .reactNative:
                targetPath = CrossPlatformArtifactPaths.reactNativeAAB(variant: context.config.androidBuildVariant)
                isAAB = true
            default:
                targetPath = CrossPlatformArtifactPaths.nativeAAB(
                    module: context.config.androidModule,
                    variant: context.config.androidBuildVariant
                )
                isAAB = true
                logger.info("Auto-discovered native AAB path: \(targetPath)")
            }
        }

        let workingDirectory = context.shell.workingDirectory ?? FileManager.default.currentDirectoryPath
        let resolvedTargetPath: String
        if (targetPath as NSString).isAbsolutePath {
            resolvedTargetPath = targetPath
        } else {
            resolvedTargetPath = (workingDirectory as NSString).appendingPathComponent(targetPath)
        }

        guard FileManager.default.fileExists(atPath: resolvedTargetPath) else {
            throw ShipItError.invalidConfiguration(
                reason: "validate_bundle: path not found: \(resolvedTargetPath)"
            )
        }

        logger.info("ValidateBundle: validating '\(resolvedTargetPath)'")

        var issues: [BundleIssue] = []

        // 1. File format check (ZIP magic bytes — both AAB and APK are ZIP-based)
        validateZipFormat(at: resolvedTargetPath, isAAB: isAAB, issues: &issues)

        // 2. Extension check
        if isAAB && !resolvedTargetPath.hasSuffix(".aab") {
            issues.append(
                .init(
                    code: "BUNDLE_INVALID_EXTENSION",
                    message: "Expected a .aab file extension, got: \(resolvedTargetPath)",
                    severity: .warning
                ))
        } else if !isAAB && !resolvedTargetPath.hasSuffix(".apk") {
            issues.append(
                .init(
                    code: "BUNDLE_INVALID_EXTENSION",
                    message: "Expected a .apk file extension, got: \(resolvedTargetPath)",
                    severity: .warning
                ))
        }

        // 3. Size sanity check
        validateFileSize(at: resolvedTargetPath, issues: &issues)

        // 4. bundletool validate (if available)
        await validateWithBundletool(path: resolvedTargetPath, isAAB: isAAB, issues: &issues, context: context)

        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count

        if errorCount > 0 {
            logger.warning("ValidateBundle: found \(errorCount) error(s), \(warningCount) warning(s) in '\(resolvedTargetPath)'")
        } else {
            logger.info("ValidateBundle: '\(resolvedTargetPath)' passed all checks (\(warningCount) warning(s))")
        }

        let result = Result(validatedPath: resolvedTargetPath, isAAB: isAAB, issues: issues)

        let shouldFail = errorCount > 0 || ((options.failOnWarnings == true) && warningCount > 0)
        if shouldFail {
            throw ShipItError.invalidConfiguration(
                reason: "Bundle validation failed with \(errorCount) error(s) and \(warningCount) warning(s). Path: \(resolvedTargetPath)"
            )
        }

        return result
    }

    // MARK: - Private

    private func validateZipFormat(at path: String, isAAB: Bool, issues: inout [BundleIssue]) {
        guard let fileHandle = FileHandle(forReadingAtPath: path),
            let header = try? fileHandle.read(upToCount: 4)
        else {
            issues.append(
                .init(
                    code: "BUNDLE_UNREADABLE",
                    message: "Cannot read artifact at \(path)",
                    severity: .error
                ))
            return
        }
        fileHandle.closeFile()

        // ZIP magic: PK\x03\x04
        let isZip =
            header.count >= 4
            && header[0] == 0x50 && header[1] == 0x4B
            && header[2] == 0x03 && header[3] == 0x04
        if !isZip {
            let kind = isAAB ? "AAB" : "APK"
            issues.append(
                .init(
                    code: "BUNDLE_NOT_ZIP",
                    message: "\(kind) file does not appear to be a valid ZIP archive (incorrect file header).",
                    severity: .error
                ))
        }
    }

    private func validateFileSize(at path: String, issues: inout [BundleIssue]) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? Int
        else { return }

        // Warn if suspiciously small (likely empty / malformed)
        if size < 1024 {
            issues.append(
                .init(
                    code: "BUNDLE_SUSPICIOUSLY_SMALL",
                    message: "Artifact is only \(size) bytes — this is likely empty or malformed.",
                    severity: .error
                ))
        }

        // Warn if AAB exceeds the Google Play 200 MB limit
        let maxBytes = 200 * 1024 * 1024
        if size > maxBytes {
            let mb = size / (1024 * 1024)
            issues.append(
                .init(
                    code: "BUNDLE_EXCEEDS_PLAY_LIMIT",
                    message: "Artifact is \(mb) MB which exceeds the Google Play 200 MB limit.",
                    severity: .error
                ))
        }
    }

    private func validateWithBundletool(
        path: String,
        isAAB: Bool,
        issues: inout [BundleIssue],
        context: ActionContext
    ) async {
        guard isAAB else {
            // bundletool validate only supports AABs
            return
        }

        // Check if bundletool is available by running `bundletool version`
        let bundletool = Bundletool(context: context.shell)

        // Run bundletool validate
        let validateOutput =
            try? await bundletool
            .validate(bundle: path)
            .run()

        if let output = validateOutput, output.exitCode != 0 {
            context.logShellOutput(output, label: "bundletool validate")
            let stderr = output.stderr.isEmpty ? output.stdout : output.stderr
            issues.append(
                .init(
                    code: "BUNDLETOOL_VALIDATION_FAILED",
                    message: "bundletool validate reported errors: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))",
                    severity: .error
                ))
        } else if let output = validateOutput {
            context.logShellOutput(output, label: "bundletool validate")
        } else if validateOutput == nil {
            // bundletool not installed or not on PATH
            issues.append(
                .init(
                    code: "BUNDLETOOL_NOT_AVAILABLE",
                    message:
                        "bundletool is not installed or not on PATH. Deep AAB validation skipped. Install via: brew install bundletool",
                    severity: .warning
                ))
        }
    }
}
