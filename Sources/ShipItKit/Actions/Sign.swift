import OSLog
import SwiftyShell

/// Manages certificates and provisioning profiles via encrypted vault storage.
///
/// Supports syncing from a Git-backed repository, importing existing certificates,
/// and cleaning up CI-created keychains and profiles.
///
/// ## Usage
/// ```swift
/// let result = try await SignAction().run(
///     with: .init(operation: .sync, type: "appstore"),
///     context: context
/// )
/// ```
public struct SignAction: Action {
    public static let name = "sign"
    public static let description = "Manage certificates and provisioning profiles"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", SignAction.self)

    /// Creates a `SignAction`.
    public init() {}

    /// The signing operation to perform.
    public enum SignOperation: String, Codable, Sendable {
        /// Initialize a new encrypted certificate repository.
        case `init`
        /// Sync certificates and profiles from the storage repository.
        case sync
        /// Import a .p12 and .mobileprovision into the storage repository.
        case `import`
        /// Remove temporary keychain and installed profiles created during sync --ci.
        case cleanup
    }

    /// Configuration for the sign action.
    public struct Options: Codable, Sendable {
        /// The operation to perform.
        public var operation: SignOperation

        /// Profile type: `development`, `adhoc`, `appstore`, or `enterprise`.
        public var type: String?

        /// Whether running in CI mode (creates temporary keychain).
        public var ci: Bool?

        /// URL of the certificate Git repository.
        public var gitUrl: String?

        /// Path to a .p12 file to import.
        public var p12Path: String?

        /// Path to a .mobileprovision file to import.
        public var provisioningProfilePath: String?

        /// Creates `Options` for the sign action.
        ///
        /// - Parameter operation: The signing operation to perform.
        /// - Parameter type: Profile type: `development`, `adhoc`, `appstore`, or `enterprise`.
        /// - Parameter ci: Whether running in CI mode (creates a temporary keychain).
        /// - Parameter gitUrl: URL of the certificate Git repository.
        /// - Parameter p12Path: Path to a `.p12` file to import.
        /// - Parameter provisioningProfilePath: Path to a `.mobileprovision` file to import.
        public init(
            operation: SignOperation,
            type: String? = nil,
            ci: Bool? = nil,
            gitUrl: String? = nil,
            p12Path: String? = nil,
            provisioningProfilePath: String? = nil
        ) {
            self.operation = operation
            self.type = type
            self.ci = ci
            self.gitUrl = gitUrl
            self.p12Path = p12Path
            self.provisioningProfilePath = provisioningProfilePath
        }
    }

    /// Result of a signing operation.
    public struct Result: Codable, Sendable {
        /// The operation that was performed.
        public let operation: String

        /// Whether the operation succeeded.
        public let success: Bool

        /// Human-readable summary message.
        public let message: String

        /// Creates a `Result`.
        public init(operation: String, success: Bool, message: String) {
            self.operation = operation
            self.success = success
            self.message = message
        }
    }

    public func run(with options: Options, context: ActionContext) async throws -> Result {
        guard context.platform == .ios else {
            throw ShipItError.invalidConfiguration(reason: "SignAction requires iOS platform")
        }
        logger.info("Sign operation: \(options.operation.rawValue)")

        switch options.operation {
        case .sync:
            return try await performSync(options: options, context: context)
        case .`init`:
            return try await performInit(options: options, context: context)
        case .`import`:
            return try await performImport(options: options, context: context)
        case .cleanup:
            return try await performCleanup(options: options, context: context)
        }
    }

    // MARK: - Operations

    private func performSync(options: Options, context: ActionContext) async throws -> Result {
        if context.config.codeSigningType == "manual" {
            return try await performManualSync(options: options, context: context)
        }

        let gitUrl = options.gitUrl ?? context.config.codeSigningGitUrl
        guard let gitUrl else {
            throw ShipItError.invalidConfiguration(
                reason: "sign sync requires code_signing.git_url. Set it in Shipfile.yml or export SHIPIT_CODE_SIGNING__GIT_URL.")
        }

        let profileType = options.type ?? "development"
        let isCi = options.ci ?? false
        logger.info("Syncing \(profileType) certificates from \(gitUrl) (CI: \(isCi))")

        let certManager = CertificateManager()
        try await certManager.sync(
            gitUrl: gitUrl,
            profileType: profileType,
            ciMode: isCi,
            context: context
        )

        return Result(
            operation: "sync",
            success: true,
            message: "Successfully synced \(profileType) certificates and profiles"
        )
    }

    private func performManualSync(options: Options, context: ActionContext) async throws -> Result {
        let p12Password = context.config.codeSigningP12Password ?? context.config.vaultPassword
        guard let p12Password, !p12Password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShipItError.invalidConfiguration(reason: "manual signing requires code_signing.p12_password or P12_PASSWORD.")
        }

        let keychain = KeychainHelper()
        if options.ci ?? false {
            try await keychain.createTemporaryKeychain(context: context)
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-manual-signing-\(UUID().uuidString)", isDirectory: true)
        var createdTempDirectory = false
        defer {
            if createdTempDirectory {
                try? FileManager.default.removeItem(at: tempDirectory)
            }
        }

        let p12Path = try writeManualSigningAssetIfNeeded(
            path: context.config.codeSigningP12Path,
            data: context.config.codeSigningP12Data,
            filename: "certificate.p12",
            tempDirectory: tempDirectory,
            createdTempDirectory: &createdTempDirectory,
            missingDescription: "manual signing requires code_signing.p12_path or code_signing.p12_base64."
        )
        let profilePath = try writeManualSigningAssetIfNeeded(
            path: context.config.codeSigningProvisioningProfilePath,
            data: context.config.codeSigningProvisioningProfileData,
            filename: "profile.mobileprovision",
            tempDirectory: tempDirectory,
            createdTempDirectory: &createdTempDirectory,
            missingDescription:
                "manual signing requires code_signing.provisioning_profile_path or code_signing.provisioning_profile_base64."
        )

        try await keychain.installCertificate(p12Path: p12Path, password: p12Password, context: context)
        try await keychain.installProvisioningProfile(profilePath: profilePath, context: context)

        return Result(
            operation: "sync",
            success: true,
            message: "Successfully installed manual signing certificate and provisioning profile"
        )
    }

    private func writeManualSigningAssetIfNeeded(
        path: String?,
        data: Data?,
        filename: String,
        tempDirectory: URL,
        createdTempDirectory: inout Bool,
        missingDescription: String
    ) throws -> String {
        if let path, FileManager.default.fileExists(atPath: path) {
            return path
        }

        guard let data else {
            throw ShipItError.invalidConfiguration(reason: missingDescription)
        }

        if !createdTempDirectory {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            createdTempDirectory = true
        }

        let fileURL = tempDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    private func performInit(options: Options, context: ActionContext) async throws -> Result {
        let gitUrl = options.gitUrl ?? context.config.codeSigningGitUrl
        guard let gitUrl else {
            throw ShipItError.invalidConfiguration(reason: "sign init requires --git-url. Pass --git-url <repository-url>.")
        }

        logger.info("Initializing certificate repository at \(gitUrl)")
        let storage = CertVault(gitUrl: gitUrl)
        try await storage.initialize(context: context)

        return Result(
            operation: "init",
            success: true,
            message: "Certificate repository initialized at \(gitUrl)"
        )
    }

    private func performImport(options: Options, context: ActionContext) async throws -> Result {
        guard let p12Path = options.p12Path else {
            throw ShipItError.invalidConfiguration(reason: "sign import requires --p12-path. Pass --p12-path /path/to/certificate.p12.")
        }

        guard let profilePath = options.provisioningProfilePath else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "sign import requires --provisioning-profile-path. Pass --provisioning-profile-path /path/to/profile.mobileprovision.")
        }

        let gitUrl = options.gitUrl ?? context.config.codeSigningGitUrl
        guard let gitUrl else {
            throw ShipItError.invalidConfiguration(
                reason: "sign import requires code_signing.git_url. Set it in Shipfile.yml or export SHIPIT_CODE_SIGNING__GIT_URL.")
        }

        logger.info("Importing certificate from \(p12Path) and profile from \(profilePath)")
        let storage = CertVault(gitUrl: gitUrl)
        try await storage.importCertificate(p12Path: p12Path, provisioningProfilePath: profilePath, context: context)

        return Result(
            operation: "import",
            success: true,
            message: "Successfully imported certificate and profile"
        )
    }

    private func performCleanup(options: Options, context: ActionContext) async throws -> Result {
        logger.info("Cleaning up temporary keychain and installed profiles")
        let keychain = KeychainHelper()
        try await keychain.cleanupTemporaryKeychain(context: context)

        return Result(
            operation: "cleanup",
            success: true,
            message: "Cleanup complete"
        )
    }
}
