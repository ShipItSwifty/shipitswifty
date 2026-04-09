import Foundation

/// Top-level error type for all ShipItSwifty failures.
///
/// Every `Action` either throws `ShipItError` directly or wraps a domain-specific
/// error inside one of its cases. The CLI maps each case to a documented exit code (§7.2).
///
/// ## Exit Codes
/// - Build/Archive/Export (10–12)
/// - Code Signing (20)
/// - API / Upload (30)
/// - Screenshots (40)
/// - Metadata / Precheck (50)
/// - Configuration / General (2)
public enum ShipItError: Error, Sendable {

    // MARK: - Build / Archive / Export (exit 10–12)

    /// `xcodebuild` exited with a non-zero code.
    case buildFailed(exitCode: Int, log: String)

    /// Test run exited non-zero or reported test failures.
    case testFailed(exitCode: Int, failureCount: Int, log: String)

    /// Archive or IPA export step failed.
    case archiveFailed(exitCode: Int, log: String)

    // MARK: - Code Signing (exit 20)

    /// A required certificate or provisioning profile was not found.
    case signingResourceNotFound(description: String)

    /// Keychain operation failed.
    case keychainError(underlying: any Error)

    // MARK: - API / Upload (exit 30)

    /// App Store Connect API returned an unexpected HTTP status.
    case apiError(statusCode: Int, body: String)

    /// JWT generation failed (bad key, missing fields, etc.).
    case jwtGenerationFailed(underlying: any Error)

    /// Asset upload to App Store Connect failed.
    case uploadFailed(asset: String, reason: String)

    // MARK: - Screenshots (exit 40)

    /// Simulator launch or screenshot capture failed.
    case screenshotCaptureFailed(device: String, locale: String, reason: String)

    // MARK: - Metadata / Precheck (exit 50)

    /// One or more metadata fields failed App Store guideline validation.
    case precheckFailed(violations: [String])

    // MARK: - Configuration / General (exit 2)

    /// Shipfile is missing, unreadable, or contains invalid YAML.
    case invalidConfiguration(reason: String)

    /// An action name collision was detected during plugin registration.
    case duplicateAction(name: String)

    /// A required tool (e.g. `xcodebuild`, `xcrun`) was not found on `PATH`.
    case missingTool(name: String)
}

extension ShipItError: LocalizedError {
    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .buildFailed(let exitCode, let log):
            return "Build failed with exit code \(exitCode).\n\(log)"
        case .testFailed(let exitCode, let failureCount, let log):
            return "Tests failed with \(failureCount) failure(s) (exit code \(exitCode)).\n\(log)"
        case .archiveFailed(let exitCode, let log):
            return "Archive failed with exit code \(exitCode).\n\(log)"
        case .signingResourceNotFound(let description):
            return "Signing resource not found: \(description)"
        case .keychainError(let underlying):
            return "Keychain error: \(underlying.localizedDescription)"
        case .apiError(let statusCode, let body):
            return "App Store Connect API error (\(statusCode)): \(body)"
        case .jwtGenerationFailed(let underlying):
            return "JWT generation failed: \(underlying.localizedDescription)"
        case .uploadFailed(let asset, let reason):
            return "Upload failed for \(asset): \(reason)"
        case .screenshotCaptureFailed(let device, let locale, let reason):
            return "Screenshot capture failed on \(device) (\(locale)): \(reason)"
        case .precheckFailed(let violations):
            return "Precheck failed with violations:\n" + violations.joined(separator: "\n")
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .duplicateAction(let name):
            return "Duplicate action registered: \(name)"
        case .missingTool(let name):
            return "Required tool not found: \(name)"
        }
    }

    /// The CLI exit code corresponding to this error.
    public var exitCode: Int32 {
        switch self {
        case .buildFailed: return 10
        case .testFailed: return 11
        case .archiveFailed: return 12
        case .signingResourceNotFound, .keychainError: return 20
        case .apiError, .jwtGenerationFailed, .uploadFailed: return 30
        case .screenshotCaptureFailed: return 40
        case .precheckFailed: return 50
        case .invalidConfiguration, .duplicateAction, .missingTool: return 2
        }
    }
}
