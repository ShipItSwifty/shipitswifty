import Foundation

/// Reads ShipItSwifty configuration from environment variables.
///
/// Supports both `SHIPIT_*` prefixed variables (mapping Shipfile YAML keys) and
/// bare secret names for CI compatibility (e.g. `ASC_KEY_ID`, `VAULT_PASSWORD`).
///
/// ## Naming Convention
/// Shipfile YAML keys map to env vars by upper-casing and joining path segments with `_`,
/// prefixed with `SHIPIT_`. Nested keys use `__` (double-underscore) as section separator.
///
/// | Shipfile key | Environment variable |
/// |---|---|
/// | `app.scheme` | `SHIPIT_APP__SCHEME` |
/// | `app.bundle_id` | `SHIPIT_APP__BUNDLE_ID` |
/// | `app_store_connect.key_id` | `SHIPIT_APP_STORE_CONNECT__KEY_ID` |
/// | `android.module` | `SHIPIT_ANDROID__MODULE` |
///
/// ## Bare Secrets
/// The following are also read without the `SHIPIT_` prefix for CI compatibility:
/// - `ASC_KEY_ID`
/// - `ASC_ISSUER_ID`
/// - `ASC_PRIVATE_KEY`
/// - `VAULT_PASSWORD`
/// - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
/// - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH`
/// - `SHIPIT_ANDROID__KEYSTORE_PASSWORD`
/// - `SHIPIT_ANDROID__KEY_PASSWORD`
public struct Environment: Sendable {
    private let env: [String: String]

    /// Creates an `Environment` reader from the given dictionary.
    /// Defaults to the current process environment.
    ///
    /// - Parameter env: Dictionary of environment variable names to values.
    public init(env: [String: String] = ProcessInfo.processInfo.environment) {
        self.env = env
    }

    // MARK: - Platform

    /// `SHIPIT_PLATFORM` — overrides platform auto-detection. Accepts `ios` or `android`.
    public var platform: String? { env["SHIPIT_PLATFORM"] }

    // MARK: - App Configuration

    /// `SHIPIT_APP__WORKSPACE`
    public var appWorkspace: String? { env["SHIPIT_APP__WORKSPACE"] }

    /// `SHIPIT_APP__PROJECT`
    public var appProject: String? { env["SHIPIT_APP__PROJECT"] }

    /// `SHIPIT_APP__SCHEME`
    public var appScheme: String? { env["SHIPIT_APP__SCHEME"] }

    /// `SHIPIT_APP__BUNDLE_ID`
    public var appBundleId: String? { env["SHIPIT_APP__BUNDLE_ID"] }

    /// `SHIPIT_APP__TEAM_ID`
    public var appTeamId: String? { env["SHIPIT_APP__TEAM_ID"] }

    // MARK: - App Store Connect

    /// `SHIPIT_APP_STORE_CONNECT__KEY_ID` or bare `ASC_KEY_ID`
    public var ascKeyId: String? {
        env["SHIPIT_APP_STORE_CONNECT__KEY_ID"] ?? env["ASC_KEY_ID"]
    }

    /// `SHIPIT_APP_STORE_CONNECT__ISSUER_ID` or bare `ASC_ISSUER_ID`
    public var ascIssuerId: String? {
        env["SHIPIT_APP_STORE_CONNECT__ISSUER_ID"] ?? env["ASC_ISSUER_ID"]
    }

    /// `SHIPIT_APP_STORE_CONNECT__KEY_PATH` or bare `ASC_PRIVATE_KEY_PATH`
    public var ascKeyPath: String? {
        env["SHIPIT_APP_STORE_CONNECT__KEY_PATH"] ?? env["ASC_PRIVATE_KEY_PATH"]
    }

    /// `ASC_PRIVATE_KEY` — raw P8 key contents (base64 or PEM)
    public var ascPrivateKey: String? { env["ASC_PRIVATE_KEY"] }

    // MARK: - Build

    /// `SHIPIT_BUILD__CONFIGURATION`
    public var buildConfiguration: String? { env["SHIPIT_BUILD__CONFIGURATION"] }

    /// `SHIPIT_BUILD__DERIVED_DATA_PATH`
    public var buildDerivedDataPath: String? { env["SHIPIT_BUILD__DERIVED_DATA_PATH"] }

    // MARK: - Archive

    /// `SHIPIT_ARCHIVE__EXPORT_METHOD`
    public var archiveExportMethod: String? { env["SHIPIT_ARCHIVE__EXPORT_METHOD"] }

    /// `SHIPIT_ARCHIVE__OUTPUT_PATH`
    public var archiveOutputPath: String? { env["SHIPIT_ARCHIVE__OUTPUT_PATH"] }

    // MARK: - Code Signing

    /// `SHIPIT_CODE_SIGNING__GIT_URL`
    public var codeSigningGitUrl: String? { env["SHIPIT_CODE_SIGNING__GIT_URL"] }

    /// `VAULT_PASSWORD` — passphrase for the encrypted certificate repository
    public var vaultPassword: String? { env["VAULT_PASSWORD"] }

    // MARK: - Android

    /// `SHIPIT_ANDROID__MODULE` — Gradle module name (e.g. `app`)
    public var androidModule: String? { env["SHIPIT_ANDROID__MODULE"] }

    /// `SHIPIT_ANDROID__BUILD_VARIANT` — Gradle build variant (e.g. `release`)
    public var androidBuildVariant: String? { env["SHIPIT_ANDROID__BUILD_VARIANT"] }

    /// `SHIPIT_ANDROID__BUILD_TYPE` — Output type: `apk` or `aab`
    public var androidBuildType: String? { env["SHIPIT_ANDROID__BUILD_TYPE"] }

    /// `SHIPIT_ANDROID__GRADLEW_PATH` — Path to the gradlew wrapper script
    public var androidGradlewPath: String? { env["SHIPIT_ANDROID__GRADLEW_PATH"] }

    /// `SHIPIT_ANDROID__KEYSTORE_PATH` — Path to the Android keystore file
    public var androidKeystorePath: String? { env["SHIPIT_ANDROID__KEYSTORE_PATH"] }

    /// `SHIPIT_ANDROID__KEYSTORE_PASSWORD` — Keystore password (secret)
    public var androidKeystorePassword: String? { env["SHIPIT_ANDROID__KEYSTORE_PASSWORD"] }

    /// `SHIPIT_ANDROID__KEY_ALIAS` — Signing key alias within the keystore
    public var androidKeyAlias: String? { env["SHIPIT_ANDROID__KEY_ALIAS"] }

    /// `SHIPIT_ANDROID__KEY_PASSWORD` — Key password (secret)
    public var androidKeyPassword: String? { env["SHIPIT_ANDROID__KEY_PASSWORD"] }

    /// `SHIPIT_ANDROID__PACKAGE_NAME` — Android application package name (e.g. `com.example.app`)
    public var androidPackageName: String? { env["SHIPIT_ANDROID__PACKAGE_NAME"] }

    /// `SHIPIT_ANDROID__PLAY_TRACK` — Google Play track (`qa`, `alpha`, `beta`, `production`)
    public var androidPlayTrack: String? { env["SHIPIT_ANDROID__PLAY_TRACK"] }

    // MARK: - Google Play

    /// `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` — raw service account JSON contents (secret)
    public var googlePlayServiceAccountJson: String? { env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"] }

    /// `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH` — path to service account JSON file
    public var googlePlayServiceAccountJsonPath: String? { env["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH"] }

    // MARK: - Notifications

    /// `SLACK_WEBHOOK_URL`
    public var slackWebhookUrl: String? { env["SLACK_WEBHOOK_URL"] }

    // MARK: - Generic Access

    /// Returns the raw value for the given environment variable key.
    ///
    /// - Parameter key: The exact environment variable name to read.
    /// - Returns: The value if present, otherwise `nil`.
    public func value(for key: String) -> String? {
        env[key]
    }
}

