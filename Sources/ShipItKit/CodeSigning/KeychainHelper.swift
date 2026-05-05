#if os(macOS)
import Foundation
import Logging
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

        // Throws ShipItError.keychainError on failure via do-catch below.
        do {
            _ = try await SecurityCLI(context: context.shell)
                .createKeychain(name: name, password: keychainPassword)
                .run()
        } catch {
            throw ShipItError.keychainError(
                underlying: ShipItError.invalidConfiguration(reason: "Failed to create keychain: \(error.localizedDescription)")
            )
        }

        // Set keychain settings: no auto-lock, no timeout.
        // Non-fatal — log a warning if this fails.
        do {
            _ = try await SecurityCLI(context: context.shell)
                .setKeychainSettings(name: name, timeout: 21600)
                .run()
        } catch {
            logger.warning("Failed to set keychain settings: \(error.localizedDescription)")
        }

        // Add to keychain search list.
        // Non-fatal — log a warning if this fails.
        do {
            _ = try await SecurityCLI(context: context.shell)
                .setUserKeychainSearchList([name, "login.keychain-db"])
                .run()
        } catch {
            logger.warning("Failed to add keychain to search list: \(error.localizedDescription)")
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

        do {
            _ = try await SecurityCLI(context: context.shell)
                .importCertificate(
                    at: p12Path,
                    keychainName: keychainName,
                    password: password,
                    trustedApplications: ["/usr/bin/codesign", "/usr/bin/security"]
                )
                .run()
        } catch {
            throw ShipItError.keychainError(
                underlying: ShipItError.invalidConfiguration(reason: "Certificate import failed: \(error.localizedDescription)")
            )
        }

        // Allow codesign to access the key without prompting.
        // Non-fatal — log a warning if this fails.
        do {
            _ = try await SecurityCLI(context: context.shell)
                .setKeyPartitionList(services: "apple-tool:,apple:", password: password, keychainName: keychainName)
                .run()
        } catch {
            logger.warning("Failed to set key partition list: \(error.localizedDescription)")
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
        do {
            _ = try await SecurityCLI(context: context.shell)
                .unlockKeychain(name: name, password: password)
                .run()
        } catch {
            throw ShipItError.keychainError(
                underlying: ShipItError.invalidConfiguration(reason: "Failed to unlock keychain: \(error.localizedDescription)")
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

        // Non-fatal — keychain may not exist when cleanup runs.
        do {
            _ = try await SecurityCLI(context: context.shell)
                .deleteKeychain(name: name)
                .run()
        } catch {
            logger.debug("delete-keychain returned non-zero (may not exist): \(error.localizedDescription)")
        }

        // Restore default keychain list.
        // Non-fatal — log a warning if this fails.
        do {
            _ = try await SecurityCLI(context: context.shell)
                .setUserKeychainSearchList(["login.keychain-db"])
                .run()
        } catch {
            logger.warning("Failed to restore keychain search list: \(error.localizedDescription)")
        }

        logger.info("Temporary keychain cleanup complete")
    }

    // MARK: - Private

    private func generatePassword() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).compactMap { _ in chars.randomElement() })
    }
}
#endif
