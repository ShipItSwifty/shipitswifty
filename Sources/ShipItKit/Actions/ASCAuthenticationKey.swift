#if os(macOS)
import Foundation

/// Resolves App Store Connect API key credentials into `xcodebuild` authentication
/// flags (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`).
///
/// These flags let `-allowProvisioningUpdates` authenticate to Apple's provisioning
/// servers in headless CI environments where no Apple ID is signed in to Xcode. Without
/// them, automatic signing silently fails to reach Apple even though ShipIt holds the
/// credentials.
///
/// `xcodebuild -authenticationKeyPath` requires a *file path*, but the private key may be
/// supplied as raw PEM data (`ASC_PRIVATE_KEY`). This type materializes the key to a
/// temporary `.p8` file with owner-only permissions and removes it on ``cleanup()``.
struct ASCAuthenticationKey {
    /// App Store Connect API Key ID.
    let keyID: String

    /// App Store Connect Issuer ID.
    let issuerID: String

    /// Path to the `.p8` private key file passed to `xcodebuild`.
    let keyPath: String

    /// Temporary file created during resolution, removed on ``cleanup()``.
    private let temporaryKeyPath: String?

    /// `xcodebuild` options that authenticate automatic signing with the ASC API key.
    var options: [XcodeBuildOption] {
        [
            .authenticationKeyPath(keyPath),
            .authenticationKeyID(keyID),
            .authenticationKeyIssuerID(issuerID),
        ]
    }

    /// Resolves ASC authentication from the resolved config.
    ///
    /// - Returns: A value whose ``options`` should be appended to the `xcodebuild`
    ///   invocation, or `nil` when key ID, issuer ID, or private-key material is missing
    ///   (in which case automatic signing falls back to the signed-in Xcode account).
    static func resolve(config: ResolvedConfig) throws -> ASCAuthenticationKey? {
        guard let keyID = config.ascKeyID,
            let issuerID = config.ascIssuerID,
            let keyData = config.ascPrivateKeyData
        else {
            return nil
        }

        let path = NSTemporaryDirectory() + "ShipItASCKey_\(UUID().uuidString).p8"
        let created = FileManager.default.createFile(
            atPath: path,
            contents: keyData,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw ShipItError.invalidConfiguration(
                reason: "Failed to write temporary App Store Connect private key for xcodebuild authentication."
            )
        }

        return ASCAuthenticationKey(
            keyID: keyID,
            issuerID: issuerID,
            keyPath: path,
            temporaryKeyPath: path
        )
    }

    /// Removes any temporary key file created during resolution.
    func cleanup() {
        if let temporaryKeyPath {
            try? FileManager.default.removeItem(atPath: temporaryKeyPath)
        }
    }
}
#endif
