import Foundation
import Logging
import SwiftyShell
import Yams

/// CLI-level options that can override Shipfile and environment settings.
///
/// Passed from the CLI entry point to `ConfigResolver.resolve(cliOptions:shipfilePath:)`.
public struct CLIOptions: Sendable {
    /// Explicit Xcode scheme override.
    public var scheme: String?

    /// Build configuration override.
    public var configuration: String?

    /// Whether CI mode is enabled (non-interactive, strict error handling).
    public var ci: Bool

    /// Whether dry-run mode is enabled (preview actions without executing).
    public var dryRun: Bool

    /// Output format override (`human` or `json`).
    public var outputFormat: String?

    /// Platform override.
    public var platform: Platform?

    /// Creates `CLIOptions`.
    ///
    /// All parameters are optional; defaults produce a minimal non-CI, non-dry-run configuration.
    public init(
        scheme: String? = nil,
        configuration: String? = nil,
        ci: Bool = false,
        dryRun: Bool = false,
        outputFormat: String? = nil,
        platform: Platform? = nil
    ) {
        self.scheme = scheme
        self.configuration = configuration
        self.ci = ci
        self.dryRun = dryRun
        self.outputFormat = outputFormat
        self.platform = platform
    }
}

/// Merges configuration from CLI flags, environment variables,
/// Shipfile.yml, and built-in defaults.
///
/// Resolution order (highest priority first):
/// 1. CLI flags
/// 2. Environment variables (`SHIPIT_*` prefix)
/// 3. Shipfile.yml values
/// 4. Built-in defaults
///
/// ## Usage
/// ```swift
/// let resolver = ConfigResolver()
/// let config = try await resolver.resolve(
///     cliOptions: CLIOptions(scheme: "MyApp"),
///     shipfilePath: "./Shipfile.yml"
/// )
/// ```
public struct ConfigResolver: Sendable {
    private let environment: Environment
    private let logger = Logger.forType(subsystem: "ShipItSwifty", ConfigResolver.self)
    private let shell: ShellContext

    /// Creates a `ConfigResolver` reading from the current process environment.
    public init() {
        self.environment = Environment()
        self.shell = ShellContext()
    }

    /// Creates a `ConfigResolver` with a custom environment (for testing).
    ///
    /// - Parameter environment: The environment to read variables from.
    public init(environment: Environment) {
        self.environment = environment
        self.shell = ShellContext()
    }

    /// Creates a `ConfigResolver` with a custom environment and shell context.
    ///
    /// - Parameters:
    ///   - environment: The environment to read variables from.
    ///   - shell: The shell context used for Xcode project introspection.
    public init(environment: Environment, shell: ShellContext) {
        self.environment = environment
        self.shell = shell
    }

    /// Resolve and merge all configuration sources into a `ResolvedConfig`.
    ///
    /// - Parameters:
    ///   - cliOptions: Options parsed from CLI flags.
    ///   - shipfilePath: Path to the Shipfile.yml (defaults to `./Shipfile.yml`).
    /// - Returns: A fully resolved configuration.
    /// - Throws: `ShipItError.invalidConfiguration` if the Shipfile cannot be parsed.
    public func resolve(
        cliOptions: CLIOptions = CLIOptions(),
        shipfilePath: String? = nil
    ) async throws -> ResolvedConfig {
        let resolvedPath = shipfilePath ?? "./Shipfile.yml"
        logger.info("Resolving configuration from: \(resolvedPath)")

        let shipfileLoadResult = try await loadShipfile(from: resolvedPath)
        let shipfile = shipfileLoadResult.shipfile

        // Resolve platform: CLI flag > SHIPIT_PLATFORM env var > Shipfile > auto-detect from project files
        let platform = resolvePlatform(cliOptions: cliOptions, shipfile: shipfile)
        logger.info("Resolved platform: \(platform.rawValue)")

        // Apply per-platform overrides from Shipfile ios:/android: blocks
        let effectiveApp = mergeAppConfig(base: shipfile?.app, platform: platform, shipfile: shipfile)
        let effectiveBuild = mergeBuildConfig(
            base: shipfile?.build, platform: platform, shipfile: shipfile)

        let privateKeyResolution = try resolvePrivateKeyData(shipfile: shipfile)
        let autoDetectedAppConfig = try await autoDetectAppConfig(
            shipfile: shipfile,
            effectiveApp: effectiveApp,
            cliOptions: cliOptions,
            platform: platform
        )
        let bundleIDFromTargetBuildSettings =
            environment.appBundleId == nil
            && effectiveApp?.bundleId == nil
            && autoDetectedAppConfig.bundleID != nil
        let teamIDFromTargetBuildSettings =
            environment.appTeamId == nil
            && effectiveApp?.teamId == nil
            && autoDetectedAppConfig.teamID != nil

        // Resolve Google Play service account data
        let googlePlayData = try resolveGooglePlayServiceAccountData(shipfile: shipfile)

        // Android config (from android: block merged with env vars)
        let androidConfig = shipfile?.android

        let p12Resolution = try resolveSigningAsset(
            path: environment.codeSigningP12Path ?? shipfile?.codeSigning?.p12Path,
            base64: environment.codeSigningP12Base64 ?? shipfile?.codeSigning?.p12Base64,
            missingPathDescription: "Code signing .p12 file"
        )
        let provisioningProfileResolution = try resolveSigningAsset(
            path: environment.codeSigningProvisioningProfilePath
                ?? shipfile?.codeSigning?.provisioningProfilePath,
            base64: environment.codeSigningProvisioningProfileBase64
                ?? shipfile?.codeSigning?.provisioningProfileBase64,
            missingPathDescription: "Code signing provisioning profile"
        )
        let processedFiles = [
            shipfileLoadResult.loadedPath,
            privateKeyResolution.loadedPath,
            p12Resolution.loadedPath,
            provisioningProfileResolution.loadedPath,
        ].compactMap { $0 }

        // Project generation config
        let projGen = shipfile?.projectGeneration
        let projGenTool = projGen?.tool
        let projGenCommand = projGen?.command ?? defaultProjectGenCommand(tool: projGenTool)
        let projGenSpecPath = projGen?.specPath
        let projGenOutputProject = projGen?.outputProject
        let projGenAutoGenerate = projGen?.autoGenerate ?? true

        // Versioning config — resolve spec_path from project_generation if not set
        let versioningSource = shipfile?.versioning?.source ?? "xcodeproj"
        let versioningSpecPath = shipfile?.versioning?.specPath ?? projGenSpecPath

        return ResolvedConfig(
            processedFiles: processedFiles,
            appWorkspace: environment.appWorkspace ?? effectiveApp?.workspace
                ?? autoDetectedAppConfig.workspace,
            appProject: environment.appProject ?? effectiveApp?.project ?? autoDetectedAppConfig.project,
            appScheme: cliOptions.scheme ?? environment.appScheme ?? effectiveApp?.scheme
                ?? autoDetectedAppConfig.scheme,
            bundleID: environment.appBundleId ?? effectiveApp?.bundleId ?? autoDetectedAppConfig.bundleID,
            bundleIDFromTargetBuildSettings: bundleIDFromTargetBuildSettings,
            teamID: environment.appTeamId ?? effectiveApp?.teamId ?? autoDetectedAppConfig.teamID,
            teamIDFromTargetBuildSettings: teamIDFromTargetBuildSettings,
            ascKeyID: environment.ascKeyId ?? shipfile?.appStoreConnect?.keyId,
            ascIssuerID: environment.ascIssuerId ?? shipfile?.appStoreConnect?.issuerId,
            ascPrivateKeyData: privateKeyResolution.data,
            buildConfiguration: cliOptions.configuration
                ?? environment.buildConfiguration
                ?? effectiveBuild?.configuration
                ?? "Release",
            derivedDataPath: environment.buildDerivedDataPath ?? effectiveBuild?.derivedDataPath,
            xcargs: effectiveBuild?.xcargs ?? [:],
            archiveExportMethod: environment.archiveExportMethod
                ?? shipfile?.archive?.exportMethod
                ?? "app-store",
            archiveIncludeSymbols: shipfile?.archive?.includeSymbols ?? true,
            archiveOutputPath: environment.archiveOutputPath ?? shipfile?.archive?.outputPath,
            exportArchivePath: shipfile?.export?.archivePath,
            exportOutputDirectory: shipfile?.export?.outputDirectory,
            codeSigningType: shipfile?.codeSigning?.type ?? "vault",
            automaticCodeSigning: (shipfile?.codeSigning?.type == "automatic") ? true : nil,
            codeSigningStorage: shipfile?.codeSigning?.storage ?? "git",
            codeSigningGitUrl: environment.codeSigningGitUrl ?? shipfile?.codeSigning?.gitUrl,
            vaultPassword: environment.vaultPassword,
            codeSigningP12Path: p12Resolution.path,
            codeSigningP12Data: p12Resolution.data,
            codeSigningP12Password: environment.codeSigningP12Password
                ?? shipfile?.codeSigning?.p12Password,
            codeSigningProvisioningProfilePath: provisioningProfileResolution.path,
            codeSigningProvisioningProfileData: provisioningProfileResolution.data,
            skipWaitingForBuildProcessing: shipfile?.testflight?.skipWaitingForBuildProcessing ?? false,
            distributeExternal: shipfile?.testflight?.distributeExternal ?? false,
            testFlightGroups: shipfile?.testflight?.groups ?? [],
            testFlightChangelog: shipfile?.testflight?.changelog,
            screenshotDevices: shipfile?.screenshots?.devices ?? [],
            screenshotLocales: shipfile?.screenshots?.locales ?? ["en-US"],
            screenshotScheme: shipfile?.screenshots?.scheme,
            screenshotOutputDirectory: shipfile?.screenshots?.outputDirectory ?? "./screenshots",
            metadataDirectory: shipfile?.metadata?.directory ?? "./metadata",
            submitForReview: shipfile?.metadata?.submitForReview ?? false,
            automaticRelease: shipfile?.metadata?.automaticRelease ?? false,
            phasedRelease: shipfile?.metadata?.phasedRelease ?? false,
            versioningStrategy: shipfile?.versioning?.strategy ?? "sequential",
            versioningSource: versioningSource,
            versioningSpecPath: versioningSpecPath,
            versioningBuildKey: shipfile?.versioning?.buildKey ?? "CURRENT_PROJECT_VERSION",
            versioningMarketingKey: shipfile?.versioning?.marketingKey ?? "MARKETING_VERSION",
            projectGenerationTool: projGenTool,
            projectGenerationCommand: projGenCommand,
            projectGenerationSpecPath: projGenSpecPath,
            projectGenerationOutputProject: projGenOutputProject,
            projectGenerationAutoGenerate: projGenAutoGenerate,
            slackWebhookUrl: environment.slackWebhookUrl ?? shipfile?.notifications?.slack?.webhookUrl,
            slackChannel: shipfile?.notifications?.slack?.channel,
            workflows: shipfile?.workflows ?? [:],
            customActions: shipfile?.customActions ?? [:],
            platform: platform,
            androidModule: environment.androidModule ?? androidConfig?.module ?? "app",
            androidBuildVariant: environment.androidBuildVariant ?? androidConfig?.buildVariant
                ?? "release",
            androidBuildType: AndroidBuildType(
                rawValue: environment.androidBuildType ?? androidConfig?.buildType?.rawValue ?? "")
                ?? androidConfig?.buildType ?? .aab,
            gradlewPath: environment.androidGradlewPath ?? androidConfig?.gradlewPath,
            androidKeystorePath: environment.androidKeystorePath ?? androidConfig?.keystorePath,
            androidKeystorePassword: environment.androidKeystorePassword,
            androidKeyAlias: environment.androidKeyAlias ?? androidConfig?.keystoreAlias,
            androidKeyPassword: environment.androidKeyPassword,
            androidPackageName: environment.androidPackageName ?? androidConfig?.packageName,
            androidPlayTrack: environment.androidPlayTrack ?? androidConfig?.playTrack ?? "qa",
            androidRolloutFraction: androidConfig?.rolloutFraction,
            androidGradleProperties: androidConfig?.gradleProperties ?? [:],
            googlePlayServiceAccountData: googlePlayData
        )
    }

    // MARK: - Private Helpers

    /// Resolves the target platform.
    ///
    /// Priority: CLI flag > `SHIPIT_PLATFORM` env var > Shipfile > auto-detect from project files.
    private func resolvePlatform(cliOptions: CLIOptions, shipfile: Shipfile?) -> Platform {
        // 1. CLI flag (highest priority)
        if let platform = cliOptions.platform { return platform }

        // 2. Environment variable
        if let rawValue = environment.platform,
            let platform = Platform(rawValue: rawValue.lowercased())
        {
            return platform
        }

        // 3. Shipfile value
        if let platform = shipfile?.platform { return platform }

        // 4. Auto-detect from file system
        let fm = FileManager.default
        if fm.fileExists(atPath: "./gradlew") || fm.fileExists(atPath: "./build.gradle.kts")
            || fm.fileExists(atPath: "./build.gradle")
        {
            return .android
        }

        // Look for .xcworkspace or .xcodeproj in cwd
        if let items = try? fm.contentsOfDirectory(atPath: ".") {
            for item in items {
                if item.hasSuffix(".xcworkspace") || item.hasSuffix(".xcodeproj") {
                    return .ios
                }
            }
        }

        // 5. Default to iOS (existing behaviour)
        return .ios
    }

    /// Returns the effective `AppConfig` after merging per-platform overrides.
    private func mergeAppConfig(
        base: AppConfig?, platform: Platform, shipfile: Shipfile?
    )
        -> AppConfig?
    {
        guard platform == .ios, let iosOverrides = shipfile?.ios else {
            return base
        }
        var merged = base ?? AppConfig()
        if let scheme = iosOverrides.scheme { merged.scheme = scheme }
        if let workspace = iosOverrides.workspace { merged.workspace = workspace }
        if let project = iosOverrides.project { merged.project = project }
        return merged
    }

    /// Returns the effective `BuildConfig` after merging per-platform overrides.
    private func mergeBuildConfig(
        base: BuildConfig?, platform: Platform, shipfile: Shipfile?
    )
        -> BuildConfig?
    {
        // No build overrides in ios: block for now — return base as-is
        return base
    }

    private func resolveGooglePlayServiceAccountData(shipfile: Shipfile?) throws -> Data? {
        // Priority: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (raw JSON) > GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH (file)
        if let rawJSON = environment.googlePlayServiceAccountJson {
            return Data(rawJSON.utf8)
        }

        if let path = environment.googlePlayServiceAccountJsonPath {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.warning("Google Play service account JSON not found at: \(path)")
                return nil
            }
            return try Data(contentsOf: url)
        }

        return nil
    }

    private func resolveSigningAsset(
        path: String?,
        base64: String?,
        missingPathDescription: String
    ) throws -> (path: String?, data: Data?, loadedPath: String?) {
        if let path = nonEmpty(path) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return (url.path, nil, url.path)
            }
            logger.warning("\(missingPathDescription) not found at: \(path)")
        }

        guard let encoded = nonEmpty(base64) else {
            return (nil, nil, nil)
        }

        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
            throw ShipItError.invalidConfiguration(
                reason: "\(missingPathDescription) base64 content is not valid base64")
        }

        return (nil, data, nil)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadShipfile(from path: String) async throws -> ShipfileLoadResult {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.debug("No Shipfile found at \(path), using environment and defaults only")
            return ShipfileLoadResult(shipfile: nil, loadedPath: nil)
        }

        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            // Expand environment variables in the form ${VAR_NAME}
            let expanded = expandEnvVars(in: contents)
            let decoder = YAMLDecoder()
            let shipfile = try decoder.decode(Shipfile.self, from: expanded)
            logger.info("Loaded Shipfile from \(path)")
            return ShipfileLoadResult(shipfile: shipfile, loadedPath: fileURL.path)
        } catch {
            logger.error("Failed to parse Shipfile at \(path): \(error.localizedDescription)")
            throw ShipItError.invalidConfiguration(
                reason: "Failed to parse Shipfile at \(path): \(error.localizedDescription)")
        }
    }

    private func expandEnvVars(in text: String) -> String {
        var result = text
        let env = ProcessInfo.processInfo.environment
        for (key, value) in env {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result
    }

    private func resolvePrivateKeyData(shipfile: Shipfile?) throws -> PrivateKeyResolution {
        // Priority: env ASC_PRIVATE_KEY (raw) > Shipfile private_key > env ASC_PRIVATE_KEY_PATH > Shipfile key_path
        if let rawKey = environment.ascPrivateKey {
            return PrivateKeyResolution(data: Data(rawKey.utf8), loadedPath: nil)
        }

        if let rawKey = shipfile?.appStoreConnect?.privateKey {
            return PrivateKeyResolution(data: Data(rawKey.utf8), loadedPath: nil)
        }

        let keyPath = environment.ascKeyPath ?? shipfile?.appStoreConnect?.keyPath
        guard let path = keyPath else { return PrivateKeyResolution(data: nil, loadedPath: nil) }

        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.warning("ASC private key file not found at: \(path)")
            return PrivateKeyResolution(data: nil, loadedPath: nil)
        }

        return PrivateKeyResolution(data: try Data(contentsOf: fileURL), loadedPath: fileURL.path)
    }

    private func autoDetectAppConfig(
        shipfile: Shipfile?,
        effectiveApp: AppConfig?,
        cliOptions: CLIOptions,
        platform: Platform
    ) async throws -> AutoDetectedAppConfig {
        let workspace = environment.appWorkspace ?? effectiveApp?.workspace
        let project = environment.appProject ?? effectiveApp?.project
        let scheme = cliOptions.scheme ?? environment.appScheme ?? effectiveApp?.scheme

        // Skip xcodebuild auto-detection for Android or non-macOS hosts
        #if os(macOS)
        guard platform == .ios else {
            return AutoDetectedAppConfig(workspace: workspace, project: project, scheme: scheme)
        }

        let needsBundleID = environment.appBundleId == nil && effectiveApp?.bundleId == nil
        let needsTeamID = environment.appTeamId == nil && effectiveApp?.teamId == nil

        guard needsBundleID || needsTeamID else {
            return AutoDetectedAppConfig(workspace: workspace, project: project, scheme: scheme)
        }

        guard let scheme,
            let containerOption = xcodeContainerOption(workspace: workspace, project: project)
        else {
            return AutoDetectedAppConfig(workspace: workspace, project: project, scheme: scheme)
        }

        do {
            let output = try await XcodeBuild(context: shell)
                .option(containerOption)
                .option(.scheme(scheme))
                .option(.showBuildSettings)
                .run()

            guard output.exitCode == 0 else {
                logger.warning(
                    "Failed to auto-detect build settings for scheme '\(scheme)': \(output.stderr)")
                return AutoDetectedAppConfig(workspace: workspace, project: project, scheme: scheme)
            }

            let settings = parseBuildSettings(from: output.stdout)
            return AutoDetectedAppConfig(
                workspace: workspace,
                project: project,
                scheme: scheme,
                bundleID: settings["PRODUCT_BUNDLE_IDENTIFIER"],
                teamID: settings["DEVELOPMENT_TEAM"]
            )
        } catch {
            logger.warning("Skipping build settings auto-detection: \(error.localizedDescription)")
            return AutoDetectedAppConfig(workspace: workspace, project: project, scheme: scheme)
        }
        #else
        return AutoDetectedAppConfig(workspace: workspace, project: project, scheme: scheme)
        #endif
    }

    #if os(macOS)
    private func xcodeContainerOption(workspace: String?, project: String?) -> XcodeBuildOption? {
        if let workspace {
            return .workspace(workspace)
        }

        if let project {
            return .project(project)
        }

        return nil
    }
    #endif

    private func parseBuildSettings(from output: String) -> [String: String] {
        output.split(separator: "\n").reduce(into: [String: String]()) { settings, line in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { return }
            settings[key] = value
        }
    }

    /// Returns the default generation command for a known project generation tool.
    private func defaultProjectGenCommand(tool: String?) -> String? {
        switch tool?.lowercased() {
        case "xcodegen":
            return "xcodegen generate"
        case "tuist":
            return "tuist generate"
        default:
            return nil
        }
    }
}

private struct AutoDetectedAppConfig: Sendable {
    let workspace: String?
    let project: String?
    let scheme: String?
    let bundleID: String?
    let teamID: String?

    init(
        workspace: String? = nil,
        project: String? = nil,
        scheme: String? = nil,
        bundleID: String? = nil,
        teamID: String? = nil
    ) {
        self.workspace = workspace
        self.project = project
        self.scheme = scheme
        self.bundleID = bundleID
        self.teamID = teamID
    }
}

private struct ShipfileLoadResult: Sendable {
    let shipfile: Shipfile?
    let loadedPath: String?
}

private struct PrivateKeyResolution: Sendable {
    let data: Data?
    let loadedPath: String?
}
