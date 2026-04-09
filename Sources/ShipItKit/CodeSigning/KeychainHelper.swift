import Foundation
import OSLog
import SwiftyShell

/// Wraps macOS `security` CLI commands for keychain management.
///
/// Used by `SignAction` to create temporary CI keychains, install certificates,
/// and clean up after a build run.
///
/// ## Usage
/// ```swift
/// let keychain = KeychainHelper()
/// try await keychain.createTemporaryKeychain(name: "shipit-ci", context: context)
/// try await keychain.installCertificate(p12Path: "./cert.p12", context: context)
/// try await keychain.cleanupTemporaryKeychain(context: context)
/// ```
public struct KeychainHelper: Sendable {
    /// Name of the temporary keychain created in CI mode.
    public static let temporaryKeychainName = "shipit-ci.keychain"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", KeychainHelper.self)

    /// Creates a `KeychainHelper`.
    public init() {}

    /// Creates a temporary keychain for use in CI.
    ///
    /// - Parameters:
    ///   - name: Name of the keychain to create. Defaults to `shipit-ci.keychain`.
    ///   - password: Password for the keychain. Auto-generated if not provided.
    ///   - context: Shell execution context.
    public func createTemporaryKeychain(
        name: String = temporaryKeychainName,
        password: String? = nil,
        context: ActionContext
    ) async throws {
        let keychainPassword = password ?? generatePassword()
        logger.info("Creating temporary keychain: \(name)")

        // TODO: verify SwiftyShell API
        let createOutput = try await Command(
            "security", "create-keychain", "-p", keychainPassword, name
        ).run(in: context.shell)

        if createOutput.exitCode != 0 {
            throw ShipItError.keychainError(
                underlying: ShipItError.invalidConfiguration(reason: "Failed to create keychain: \(createOutput.stderr)")
            )
        }

        // Set keychain settings: no auto-lock, no timeout
        let settingsOutput = try await Command(
            "security", "set-keychain-settings", "-lut", "21600", name
        ).run(in: context.shell)

        if settingsOutput.exitCode != 0 {
            logger.warning("Failed to set keychain settings: \(settingsOutput.stderr)")
        }

        // Add to keychain search list
        let addOutput = try await Command(
            "security", "list-keychains", "-d", "user", "-s", name, "login.keychain-db"
        ).run(in: context.shell)

        if addOutput.exitCode != 0 {
            logger.warning("Failed to add keychain to search list: \(addOutput.stderr)")
        }

        // Unlock the keychain
        try await unlockKeychain(name: name, password: keychainPassword, context: context)

        logger.info("Temporary keychain created and unlocked: \(name)")
    }

    /// Installs a `.p12` certificate into the specified keychain.
    ///
    /// - Parameters:
    ///   - p12Path: Path to the `.p12` certificate file.
    ///   - password: The `.p12` passphrase.
    ///   - keychainName: Destination keychain. Defaults to the temporary keychain.
    ///   - context: Shell execution context.
    public func installCertificate(
        p12Path: String,
        password: String,
        keychainName: String = temporaryKeychainName,
        context: ActionContext
    ) async throws {
        logger.info("Installing certificate from: \(p12Path)")

        // TODO: verify SwiftyShell API
        let output = try await Command(
            "security", "import", p12Path,
            "-k", keychainName,
            "-P", password,
            "-T", "/usr/bin/codesign",
            "-T", "/usr/bin/security"
        ).run(in: context.shell)

        if output.exitCode != 0 {
            throw ShipItError.keychainError(
                underlying: ShipItError.invalidConfiguration(reason: "Certificate import failed: \(output.stderr)")
            )
        }

        // Allow codesign to access the key without prompting
        let allowOutput = try await Command(
            "security", "set-key-partition-list",
            "-S", "apple-tool:,apple:",
            "-s", "-k", password, keychainName
        ).run(in: context.shell)

        if allowOutput.exitCode != 0 {
            logger.warning("Failed to set key partition list: \(allowOutput.stderr)")
        }

        logger.info("Certificate installed successfully")
    }

    /// Installs a provisioning profile to the standard profiles directory.
    ///
    /// - Parameters:
    ///   - profilePath: Path to the `.mobileprovision` file.
    ///   - context: Shell execution context (not used for file copy, but kept for consistency).
    public func installProvisioningProfile(
        profilePath: String,
        context: ActionContext
    ) async throws {
        logger.info("Installing provisioning profile: \(profilePath)")

        let profilesDir = NSHomeDirectory() + "/Library/MobileDevice/Provisioning Profiles"
        try FileManager.default.createDirectory(
            atPath: profilesDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let profileURL = URL(fileURLWithPath: profilePath)
        let destPath = profilesDir + "/" + profileURL.lastPathComponent
        try FileManager.default.copyItem(atPath: profilePath, toPath: destPath)

        logger.info("Provisioning profile installed to: \(destPath)")
    }

    /// Unlocks a keychain.
    ///
    /// - Parameters:
    ///   - name: Keychain name.
    ///   - password: Keychain password.
    ///   - context: Shell execution context.
    public func unlockKeychain(name: String, password: String, context: ActionContext) async throws {
        // TODO: verify SwiftyShell API
        let output = try await Command(
            "security", "unlock-keychain", "-p", password, name
        ).run(in: context.shell)

        if output.exitCode != 0 {
            throw ShipItError.keychainError(
                underlying: ShipItError.invalidConfiguration(reason: "Failed to unlock keychain: \(output.stderr)")
            )
        }
    }

    /// Deletes the temporary CI keychain and removes it from the search list.
    ///
    /// Safe to call even if `createTemporaryKeychain` was not called.
    ///
    /// - Parameter context: Shell execution context.
    public func cleanupTemporaryKeychain(context: ActionContext) async throws {
        let name = Self.temporaryKeychainName
        logger.info("Cleaning up temporary keychain: \(name)")

        // TODO: verify SwiftyShell API
        let deleteOutput = try await Command(
            "security", "delete-keychain", name
        ).run(in: context.shell)

        if deleteOutput.exitCode != 0 {
            // Not fatal — keychain may not exist
            logger.debug("delete-keychain returned non-zero (may not exist): \(deleteOutput.stderr)")
        }

        // Restore default keychain list
        let restoreOutput = try await Command(
            "security", "list-keychains", "-d", "user", "-s", "login.keychain-db"
        ).run(in: context.shell)

        if restoreOutput.exitCode != 0 {
            logger.warning("Failed to restore keychain search list: \(restoreOutput.stderr)")
        }

        logger.info("Temporary keychain cleanup complete")
    }

    // MARK: - Private

    private func generatePassword() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).compactMap { _ in chars.randomElement() })
    }
}
