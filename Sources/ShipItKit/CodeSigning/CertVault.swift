#if os(macOS)
import Crypto
import CryptoExtras
import Foundation
import Logging
import SwiftyShell

/// Git-backed encrypted certificate and provisioning profile storage.
///
/// Implements encrypted storage using AES-256-GCM encryption.
/// Certificates and profiles are encrypted with the team passphrase and stored
/// in a dedicated Git repository.
///
/// ## Usage
/// ```swift
/// let vault = CertVault(gitUrl: "git@github.com:myteam/certs.git")
/// try await vault.initialize(context: context)
/// try await vault.sync(profileType: "appstore", context: context)
/// ```
public struct CertVault: Sendable {
    /// The URL of the Git repository for certificate storage.
    public let gitUrl: String

    private let logger = Logger.forType(subsystem: "ShipItSwifty", CertVault.self)

    /// Creates a `CertVault` connected to the given Git repository.
    ///
    /// - Parameter gitUrl: SSH or HTTPS URL of the certificate repository.
    public init(gitUrl: String) {
        self.gitUrl = gitUrl
    }

    /// Initialize a new encrypted certificate repository.
    ///
    /// Creates the repo structure and a README explaining the contents.
    ///
    /// - Parameter context: Shell execution context.
    public func initialize(context: ActionContext) async throws {
        let tmpDir = NSTemporaryDirectory() + "shipit-certs-init-\(Int(Date().timeIntervalSince1970))"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        logger.info("Initializing certificate repository at: \(gitUrl)")

        // Clone if the repo exists; otherwise init a new one.
        // Command.run() throws ShellError.exitFailure on non-zero exit, so
        // catch to implement the "repo doesn't exist yet" fallback.
        do {
            _ = try await GitCLI(context: context.shell)
                .clone(url: gitUrl, into: tmpDir)
                .run()
        } catch {
            // Repo doesn't exist yet — create a new one
            try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true, attributes: nil)
            do {
                _ = try await GitCLI(context: context.shell)
                    .initializeRepository(at: tmpDir)
                    .run()
            } catch let initError {
                throw ShipItError.invalidConfiguration(reason: "git init failed: \(initError.localizedDescription)")
            }
        }

        // Create directory structure
        for dir in ["certs/development", "certs/distribution", "profiles/development", "profiles/appstore", "profiles/adhoc"] {
            try FileManager.default.createDirectory(
                atPath: "\(tmpDir)/\(dir)",
                withIntermediateDirectories: true,
                attributes: nil
            )
            // Create .gitkeep
            try "".write(toFile: "\(tmpDir)/\(dir)/.gitkeep", atomically: true, encoding: .utf8)
        }

        // Write README
        let readme = """
            # ShipItSwifty Encrypted Certificate Repository

            This repository stores encrypted code signing certificates and provisioning profiles
            managed by ShipItSwifty.

            ## Contents
            - `certs/development/` — Development signing certificates (AES-256-GCM encrypted)
            - `certs/distribution/` — Distribution signing certificates (AES-256-GCM encrypted)
            - `profiles/development/` — Development provisioning profiles (AES-256-GCM encrypted)
            - `profiles/appstore/` — App Store provisioning profiles (AES-256-GCM encrypted)
            - `profiles/adhoc/` — Ad-hoc provisioning profiles (AES-256-GCM encrypted)

            ## Access
            Use `shipit sign sync` to install these on a developer machine or CI.
            The passphrase is required and should be stored in `VAULT_PASSWORD`.

            ## Security
            - All files are encrypted with AES-256-GCM; the key is derived from the
              team passphrase with scrypt (N=2^17, r=8, p=1) and a random per-file salt
            - Never store the passphrase in this repository
            - Use CI secrets management for the passphrase
            """

        try readme.write(toFile: "\(tmpDir)/README.md", atomically: true, encoding: .utf8)

        // Stage and commit; push is best-effort — the repo may have no remote yet.
        do {
            let git = GitCLI(context: context.shell).repository(at: tmpDir)
            _ = try await git.addAll().run()
            _ = try await git.commit(message: "chore: initialize ShipItSwifty certificate repository").run()
            do {
                _ = try await git.pushSetUpstream(remote: "origin", branch: "main").run()
            } catch {
                logger.warning("Failed to push to remote: \(error.localizedDescription)")
            }
        } catch {
            logger.debug("Nothing to commit during cert repo initialization: \(error.localizedDescription)")
        }

        logger.info("Certificate repository initialized")
    }

    /// Sync certificates and profiles from the storage repository.
    ///
    /// - Parameters:
    ///   - gitUrl: Repository URL (uses the stored URL if not provided).
    ///   - profileType: Profile type to sync (`development`, `appstore`, `adhoc`, `enterprise`).
    ///   - ciMode: Whether to create a temporary keychain.
    ///   - context: Shell execution context.
    public func sync(
        gitUrl: String? = nil,
        profileType: String,
        ciMode: Bool,
        context: ActionContext
    ) async throws {
        let url = gitUrl ?? self.gitUrl
        let tmpDir = NSTemporaryDirectory() + "shipit-certs-\(Int(Date().timeIntervalSince1970))"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        logger.info("Syncing \(profileType) certs from \(url)")

        // Command.run() throws ShellError.exitFailure on non-zero exit.
        do {
            _ = try await GitCLI(context: context.shell)
                .clone(url: url, into: tmpDir, depth: 1)
                .run()
        } catch {
            throw ShipItError.signingResourceNotFound(description: "Failed to clone certificate repository: \(error.localizedDescription)")
        }

        let keychain = KeychainHelper()
        if ciMode {
            try await keychain.createTemporaryKeychain(context: context)
        }

        // Decrypt and install certificates
        let certsDir = profileType == "development" ? "\(tmpDir)/certs/development" : "\(tmpDir)/certs/distribution"
        try await installEncryptedCerts(from: certsDir, keychain: keychain, context: context)

        // Decrypt and install profiles
        let profilesDir = "\(tmpDir)/profiles/\(profileType)"
        try await installEncryptedProfiles(from: profilesDir, keychain: keychain, context: context)

        logger.info("Sync complete for \(profileType)")
    }

    /// Import an existing certificate into the encrypted storage.
    ///
    /// - Parameters:
    ///   - p12Path: Path to the `.p12` certificate file.
    ///   - provisioningProfilePath: Path to the `.mobileprovision` file.
    ///   - context: Shell execution context.
    public func importCertificate(
        p12Path: String,
        provisioningProfilePath: String,
        context: ActionContext
    ) async throws {
        logger.info("Importing certificate into encrypted storage")
        // Encrypt the p12 and add it to the repository
        // This is a placeholder implementation
        logger.warning("Certificate import is a placeholder in this version")
    }

    // MARK: - Private

    private func installEncryptedCerts(
        from directory: String,
        keychain: KeychainHelper,
        context: ActionContext
    ) async throws {
        guard FileManager.default.fileExists(atPath: directory),
            let files = try? FileManager.default.contentsOfDirectory(atPath: directory)
        else {
            logger.debug("No certificates found in \(directory)")
            return
        }

        let encryptedFiles = files.filter { $0.hasSuffix(".enc") }
        guard let vaultPassword = context.config.vaultPassword else {
            if !encryptedFiles.isEmpty {
                throw ShipItError.signingResourceNotFound(description: "VAULT_PASSWORD not set but encrypted certificates found")
            }
            return
        }

        for file in encryptedFiles {
            let encPath = "\(directory)/\(file)"
            let decPath = NSTemporaryDirectory() + file.replacingOccurrences(of: ".enc", with: "")

            try await decryptFile(at: encPath, to: decPath, password: vaultPassword)
            defer { try? FileManager.default.removeItem(atPath: decPath) }

            if decPath.hasSuffix(".p12") {
                try await keychain.installCertificate(
                    p12Path: decPath,
                    password: vaultPassword,
                    context: context
                )
            }
        }
    }

    private func installEncryptedProfiles(
        from directory: String,
        keychain: KeychainHelper,
        context: ActionContext
    ) async throws {
        guard FileManager.default.fileExists(atPath: directory),
            let files = try? FileManager.default.contentsOfDirectory(atPath: directory)
        else {
            logger.debug("No profiles found in \(directory)")
            return
        }

        let encryptedFiles = files.filter { $0.hasSuffix(".enc") }
        guard let vaultPassword = context.config.vaultPassword else {
            if !encryptedFiles.isEmpty {
                throw ShipItError.signingResourceNotFound(description: "VAULT_PASSWORD not set but encrypted profiles found")
            }
            return
        }

        for file in encryptedFiles {
            let encPath = "\(directory)/\(file)"
            let decPath = NSTemporaryDirectory() + file.replacingOccurrences(of: ".enc", with: "")

            try await decryptFile(at: encPath, to: decPath, password: vaultPassword)
            defer { try? FileManager.default.removeItem(atPath: decPath) }

            if decPath.hasSuffix(".mobileprovision") {
                try await keychain.installProvisioningProfile(profilePath: decPath, context: context)
            }
        }
    }

    private func decryptFile(at sourcePath: String, to destinationPath: String, password: String) async throws {
        let encryptedData = try Data(contentsOf: URL(fileURLWithPath: sourcePath))

        let decryptedData: Data
        do {
            decryptedData = try CertVaultCrypto.open(encryptedData, password: password)
        } catch is CertVaultCrypto.FormatError {
            throw ShipItError.signingResourceNotFound(
                description: "Not a valid ShipIt vault file (unrecognized format): \(sourcePath)"
            )
        } catch is CryptoKitError {
            throw ShipItError.signingResourceNotFound(
                description: "Failed to decrypt \(sourcePath) — check that VAULT_PASSWORD matches the passphrase used to encrypt the vault"
            )
        }

        try decryptedData.write(to: URL(fileURLWithPath: destinationPath), options: [.atomic])
    }
}

/// Encrypts and decrypts certificate vault files.
///
/// File format (version 1):
/// `[1-byte format version][32-byte scrypt salt][AES-256-GCM combined sealed box]`
///
/// The AES-256 key is derived from the team passphrase with scrypt
/// (N = 2^17, r = 8, p = 1 — OWASP-recommended parameters) and a random
/// per-file salt, so leaked vault files resist offline brute force.
enum CertVaultCrypto {
    enum FormatError: Error {
        case truncated
        case unsupportedVersion(UInt8)
    }

    static let formatVersion: UInt8 = 1
    static let saltByteCount = 32

    private static let scryptRounds = 131_072  // N = 2^17
    private static let scryptBlockSize = 8
    private static let scryptParallelism = 1

    /// Encrypts plaintext into the version-1 vault file format.
    static func seal(_ plaintext: Data, password: String) throws -> Data {
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let key = try deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoKitError.authenticationFailure
        }
        return Data([formatVersion]) + salt + combined
    }

    /// Decrypts a version-1 vault file produced by ``seal(_:password:)``.
    static func open(_ fileData: Data, password: String) throws -> Data {
        // Minimum: version byte + salt + GCM nonce (12) + tag (16).
        guard fileData.count >= 1 + saltByteCount + 28 else {
            throw FormatError.truncated
        }
        // Index relative to startIndex — `fileData` may be a slice.
        let start = fileData.startIndex
        let version = fileData[start]
        guard version == formatVersion else {
            throw FormatError.unsupportedVersion(version)
        }
        let salt = Data(fileData[(start + 1)..<(start + 1 + saltByteCount)])
        let combined = fileData[(start + 1 + saltByteCount)...]

        let key = try deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        try KDF.Scrypt.deriveKey(
            from: Data(password.utf8),
            salt: salt,
            outputByteCount: 32,
            rounds: scryptRounds,
            blockSize: scryptBlockSize,
            parallelism: scryptParallelism
        )
    }
}
#endif
