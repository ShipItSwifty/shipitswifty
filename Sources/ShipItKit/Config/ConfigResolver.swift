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

/// Merges configuration from CLI flags, Shipfile.yml, environment variables,
/// and built-in defaults.
///
/// Resolution order (highest priority first):
/// 1. CLI flags
/// 2. Shipfile.yml values
/// 3. Environment variables (`SHIPIT_*` prefix)
/// 4. Built-in defaults
///
/// - Note: Inline **secrets** are the one intentional exception to this order. The raw
///   ASC private key prefers the environment (`ASC_PRIVATE_KEY`) over the Shipfile
///   (`app_store_connect.private_key`) so CI secrets win without having to strip the value
///   from a committed Shipfile. See ``resolvePrivateKeyData(shipfile:)``.
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
        let projectRoot: String =
            shipfileLoadResult.loadedPath.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            } ?? "."

        // Resolve platform: CLI flag > Shipfile > SHIPIT_PLATFORM env var > auto-detect from project files
        let platform = resolvePlatform(cliOptions: cliOptions, shipfile: shipfile, detectionRoot: projectRoot)
        logger.info("Resolved platform: \(platform.rawValue)")

        // Resolve build system per platform: env var > Shipfile ios.build_system / android.build_system >
        // auto-detect from project files > .native.
        // Inspect the directory that holds the loaded Shipfile when available so that
        // `--shipfile path/to/Shipfile.yml` (or `SHIPIT_SHIPFILE` pointing outside the cwd)
        // doesn't silently fall through to `.native` against the wrong tree.
        let inspectedBuildSystem = BuildSystem.autoDetect(in: projectRoot)
        let autoDetectedBuildSystem: BuildSystem? = inspectedBuildSystem
        let iosBuildSystem = resolveBuildSystem(
            platform: .ios,
            shipfile: shipfile,
            autoDetected: autoDetectedBuildSystem
        )
        let androidBuildSystem = resolveBuildSystem(
            platform: .android,
            shipfile: shipfile,
            autoDetected: autoDetectedBuildSystem
        )
        if iosBuildSystem != .native || androidBuildSystem != .native {
            logger.info(
                "Resolved build systems — iOS: \(iosBuildSystem.rawValue), Android: \(androidBuildSystem.rawValue)"
            )
        }

        // Apply per-platform overrides from Shipfile ios:/android: blocks
        let effectiveApp = mergeAppConfig(base: shipfile?.app, platform: platform, shipfile: shipfile)
        let effectiveBuild = mergeBuildConfig(
            base: shipfile?.build, platform: platform, shipfile: shipfile)

        let privateKeyResolution = try resolvePrivateKeyData(shipfile: shipfile, projectRoot: projectRoot)
        let autoDetectedAppConfig = try await autoDetectAppConfig(
            shipfile: shipfile,
            effectiveApp: effectiveApp,
            cliOptions: cliOptions,
            platform: platform,
            projectRoot: projectRoot
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
            path: resolvePath(
                shipfile?.codeSigning?.p12Path ?? environment.codeSigningP12Path,
                relativeTo: projectRoot
            ),
            base64: shipfile?.codeSigning?.p12Base64 ?? environment.codeSigningP12Base64,
            missingPathDescription: "Code signing .p12 file"
        )
        let provisioningProfileResolution = try resolveSigningAsset(
            path: resolvePath(
                shipfile?.codeSigning?.provisioningProfilePath
                    ?? environment.codeSigningProvisioningProfilePath,
                relativeTo: projectRoot
            ),
            base64: shipfile?.codeSigning?.provisioningProfileBase64
                ?? environment.codeSigningProvisioningProfileBase64,
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
        let projGenSpecPath = resolvePath(projGen?.specPath, relativeTo: projectRoot)
        let projGenOutputProject = resolvePath(projGen?.outputProject, relativeTo: projectRoot)
        let projGenAutoGenerate = projGen?.autoGenerate ?? true

        // Versioning config — resolve spec_path from project_generation if not set.
        // Flutter owns the version in pubspec.yaml (`flutter build` stamps the native
        // projects from it), so writing xcodeproj/gradle directly would be overwritten.
        let platformBuildSystem = platform == .android ? androidBuildSystem : iosBuildSystem
        let versioningSourceDefault =
            platformBuildSystem == .flutter
            ? "pubspec"
            : platform == .android ? "gradle" : "xcodeproj"
        let versioningSource = shipfile?.versioning?.source ?? versioningSourceDefault
        let versioningSpecPath = resolvePath(shipfile?.versioning?.specPath, relativeTo: projectRoot) ?? projGenSpecPath
        var androidGradleProperties = androidConfig?.gradleProperties ?? [:]
        if let flavor = androidConfig?.flavor, !flavor.isEmpty {
            androidGradleProperties["flavor"] = flavor
        }

        // For React Native / Flutter iOS, the Xcode project lives in `ios/` — fall back to
        // scanning that subdirectory when no workspace or project has been resolved yet.
        let rnFallbackWorkspace: String?
        let rnFallbackProject: String?
        if platform == .ios,
            iosBuildSystem == .reactNative || iosBuildSystem == .flutter,
            effectiveApp?.workspace == nil, environment.appWorkspace == nil,
            autoDetectedAppConfig.workspace == nil
        {
            let detected = autoDetectXcodeContainer(in: "\(projectRoot)/ios")
            rnFallbackWorkspace = detected?.workspace
            rnFallbackProject = detected?.project
        } else {
            rnFallbackWorkspace = nil
            rnFallbackProject = nil
        }

        return ResolvedConfig(
            processedFiles: processedFiles,
            appWorkspace: resolvePath(
                effectiveApp?.workspace ?? environment.appWorkspace
                    ?? autoDetectedAppConfig.workspace ?? rnFallbackWorkspace,
                relativeTo: projectRoot
            ),
            appProject: resolvePath(
                effectiveApp?.project ?? environment.appProject
                    ?? autoDetectedAppConfig.project ?? rnFallbackProject,
                relativeTo: projectRoot
            ),
            appScheme: cliOptions.scheme ?? effectiveApp?.scheme ?? environment.appScheme
                ?? autoDetectedAppConfig.scheme,
            bundleID: effectiveApp?.bundleId ?? environment.appBundleId ?? autoDetectedAppConfig.bundleID,
            bundleIDFromTargetBuildSettings: bundleIDFromTargetBuildSettings,
            teamID: effectiveApp?.teamId ?? environment.appTeamId ?? autoDetectedAppConfig.teamID,
            teamIDFromTargetBuildSettings: teamIDFromTargetBuildSettings,
            ascKeyID: shipfile?.appStoreConnect?.keyId ?? environment.ascKeyId,
            ascIssuerID: shipfile?.appStoreConnect?.issuerId ?? environment.ascIssuerId,
            ascPrivateKeyData: privateKeyResolution.data,
            buildConfiguration: cliOptions.configuration
                ?? effectiveBuild?.configuration
                ?? environment.buildConfiguration
                ?? "Release",
            derivedDataPath: resolvePath(
                effectiveBuild?.derivedDataPath ?? environment.buildDerivedDataPath,
                relativeTo: projectRoot
            ),
            xcargs: effectiveBuild?.xcargs ?? [:],
            archiveExportMethod: shipfile?.archive?.exportMethod
                ?? environment.archiveExportMethod
                ?? "app-store",
            archiveIncludeSymbols: shipfile?.archive?.includeSymbols ?? true,
            archiveOutputPath: resolvePath(
                shipfile?.archive?.outputPath ?? environment.archiveOutputPath,
                relativeTo: projectRoot
            ),
            exportArchivePath: resolvePath(shipfile?.export?.archivePath, relativeTo: projectRoot),
            exportOutputDirectory: resolvePath(shipfile?.export?.outputDirectory, relativeTo: projectRoot),
            codeSigningType: shipfile?.codeSigning?.type ?? "vault",
            automaticCodeSigning: (shipfile?.codeSigning?.type == "automatic") ? true : nil,
            codeSigningStorage: shipfile?.codeSigning?.storage ?? "git",
            codeSigningGitUrl: shipfile?.codeSigning?.gitUrl ?? environment.codeSigningGitUrl,
            vaultPassword: environment.vaultPassword,
            codeSigningP12Path: p12Resolution.path,
            codeSigningP12Data: p12Resolution.data,
            codeSigningP12Password: shipfile?.codeSigning?.p12Password
                ?? environment.codeSigningP12Password,
            codeSigningProvisioningProfilePath: provisioningProfileResolution.path,
            codeSigningProvisioningProfileData: provisioningProfileResolution.data,
            skipWaitingForBuildProcessing: shipfile?.testflight?.skipWaitingForBuildProcessing ?? false,
            distributeExternal: shipfile?.testflight?.distributeExternal ?? false,
            testFlightGroups: shipfile?.testflight?.groups ?? [],
            testFlightChangelog: shipfile?.testflight?.changelog,
            screenshotDevices: shipfile?.screenshots?.devices ?? [],
            screenshotLocales: shipfile?.screenshots?.locales ?? ["en-US"],
            screenshotScheme: shipfile?.screenshots?.scheme,
            screenshotOutputDirectory: resolvePath(
                shipfile?.screenshots?.outputDirectory ?? "./screenshots",
                relativeTo: projectRoot
            ) ?? "\(projectRoot)/screenshots",
            metadataDirectory: resolvePath(
                shipfile?.metadata?.directory ?? "./metadata",
                relativeTo: projectRoot
            ) ?? "\(projectRoot)/metadata",
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
            slackWebhookUrl: shipfile?.notifications?.slack?.webhookUrl ?? environment.slackWebhookUrl,
            slackChannel: shipfile?.notifications?.slack?.channel,
            workflows: shipfile?.workflows ?? [:],
            customActions: shipfile?.customActions ?? [:],
            platform: platform,
            iosBuildSystem: iosBuildSystem,
            androidBuildSystem: androidBuildSystem,
            ci: cliOptions.ci,
            projectRoot: projectRoot,
            kmpSharedModule: shipfile?.ios?.kmpSharedModule ?? environment.iosKMPSharedModule ?? "shared",
            kmpBuildTarget: shipfile?.ios?.kmpBuildTarget ?? environment.iosKMPBuildTarget ?? "IosSimulatorArm64",
            kmpArchiveTarget: shipfile?.ios?.kmpArchiveTarget ?? environment.iosKMPArchiveTarget ?? "IosArm64",
            kmpTestTask: shipfile?.ios?.kmpTestTask ?? environment.iosKMPTestTask ?? "iosSimulatorArm64Test",
            androidModule: androidConfig?.module ?? environment.androidModule ?? "app",
            androidScope: androidConfig?.scope ?? .module,
            androidTestKind: androidConfig?.testKind ?? .unit,
            androidTestDevices: androidConfig?.testDevices ?? TestDeviceConfig(strategy: .none),
            androidBuildVariant: androidConfig?.buildVariant ?? environment.androidBuildVariant
                ?? "release",
            androidBuildType: androidConfig?.buildType
                ?? AndroidBuildType(rawValue: environment.androidBuildType ?? "")
                ?? .aab,
            gradlewPath: resolvePath(
                androidConfig?.gradlewPath ?? environment.androidGradlewPath,
                relativeTo: projectRoot
            ),
            gradleProjectDir: resolvePath(
                androidConfig?.gradleProjectDir ?? environment.androidGradleProjectDir,
                relativeTo: projectRoot
            ),
            androidGradleFlags: androidConfig?.gradleFlags ?? [],
            androidKeystorePath: resolvePath(
                androidConfig?.keystorePath ?? environment.androidKeystorePath,
                relativeTo: projectRoot
            ),
            androidKeystorePassword: environment.androidKeystorePassword,
            androidKeyAlias: androidConfig?.keystoreAlias ?? environment.androidKeyAlias,
            androidKeyPassword: environment.androidKeyPassword,
            androidPackageName: androidConfig?.packageName ?? environment.androidPackageName,
            androidRolloutFraction: androidConfig?.rolloutFraction,
            androidGradleProperties: androidGradleProperties,
            googlePlayServiceAccountData: googlePlayData
        )
    }

    // MARK: - Private Helpers

    /// Resolves the target platform.
    ///
    /// Priority: CLI flag > Shipfile > `SHIPIT_PLATFORM` env var > auto-detect from project files.
    private func resolvePlatform(cliOptions: CLIOptions, shipfile: Shipfile?, detectionRoot: String) -> Platform {
        // 1. CLI flag (highest priority)
        if let platform = cliOptions.platform { return platform }

        // 2. Shipfile value
        if let platform = shipfile?.platform { return platform }

        // 3. Environment variable
        if let rawValue = environment.platform,
            let platform = Platform(rawValue: rawValue.lowercased())
        {
            return platform
        }

        // 4. Auto-detect from file system
        let fm = FileManager.default
        let root = URL(fileURLWithPath: detectionRoot)
        if fm.fileExists(atPath: root.appendingPathComponent("gradlew").path)
            || fm.fileExists(atPath: root.appendingPathComponent("build.gradle.kts").path)
            || fm.fileExists(atPath: root.appendingPathComponent("build.gradle").path)
        {
            return .android
        }

        // Look for .xcworkspace or .xcodeproj in the resolved project root
        if let items = try? fm.contentsOfDirectory(atPath: root.path) {
            for item in items {
                if item.hasSuffix(".xcworkspace") || item.hasSuffix(".xcodeproj") {
                    return .ios
                }
            }
        }

        // 5. Default to iOS (existing behaviour)
        return .ios
    }

    /// Resolves the build system for a given target platform.
    ///
    /// Priority: Shipfile `ios.build_system` / `android.build_system`
    /// > env var (`SHIPIT_IOS__BUILD_SYSTEM` / `SHIPIT_ANDROID__BUILD_SYSTEM`)
    /// > auto-detected value
    /// > ``BuildSystem/native``.
    private func resolveBuildSystem(
        platform: Platform,
        shipfile: Shipfile?,
        autoDetected: BuildSystem?
    ) -> BuildSystem {
        let envValue: String?
        let shipfileValue: BuildSystem?
        switch platform {
        case .ios:
            envValue = environment.iosBuildSystem
            shipfileValue = shipfile?.ios?.buildSystem
        case .android:
            envValue = environment.androidBuildSystem
            shipfileValue = shipfile?.android?.buildSystem
        }

        if let shipfileValue { return shipfileValue }

        if let raw = envValue?.trimmingCharacters(in: .whitespaces).lowercased(),
            !raw.isEmpty,
            let resolved = BuildSystem(rawValue: raw)
        {
            return resolved
        }

        return autoDetected ?? .native
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

    private func resolvePath(_ path: String?, relativeTo root: String) -> String? {
        guard let path = nonEmpty(path) else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL.path }
        return URL(fileURLWithPath: root).appendingPathComponent(path).standardizedFileURL.path
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

    /// Expands `${VAR_NAME}` references in the Shipfile against the process environment.
    ///
    /// Makes a single pass over the text and looks up only the variables that are
    /// actually referenced (rather than scanning every environment variable against the
    /// whole document). Undefined references are left untouched and logged as a warning so
    /// a typo'd `${VAR}` surfaces instead of silently expanding to empty.
    private func expandEnvVars(in text: String) -> String {
        // `${NAME}` where NAME is a conventional env var identifier.
        let pattern = #"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let env = ProcessInfo.processInfo.environment
        let fullRange = NSRange(text.startIndex..., in: text)
        var result = ""
        var lastEnd = text.startIndex
        var undefined: Set<String> = []

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match,
                let matchRange = Range(match.range, in: text),
                let nameRange = Range(match.range(at: 1), in: text)
            else { return }

            result += text[lastEnd..<matchRange.lowerBound]
            let name = String(text[nameRange])
            if let value = env[name] {
                result += value
            } else {
                undefined.insert(name)
                result += text[matchRange]  // leave the literal `${NAME}` in place
            }
            lastEnd = matchRange.upperBound
        }
        result += text[lastEnd...]

        if !undefined.isEmpty {
            logger.warning(
                "Shipfile references undefined environment variable(s): \(undefined.sorted().joined(separator: ", ")). Left unexpanded."
            )
        }
        return result
    }

    /// Resolves the ASC private key data.
    ///
    /// Unlike most fields, the raw env value (`ASC_PRIVATE_KEY`) intentionally outranks the
    /// Shipfile value so a CI secret wins over anything checked into the repo. See the
    /// resolution-order note on ``ConfigResolver``.
    private func resolvePrivateKeyData(
        shipfile: Shipfile?,
        projectRoot: String
    ) throws -> PrivateKeyResolution {
        // Priority: env ASC_PRIVATE_KEY (raw) > Shipfile private_key > env ASC_PRIVATE_KEY_PATH > Shipfile key_path
        if let rawKey = environment.ascPrivateKey {
            return PrivateKeyResolution(data: Data(rawKey.utf8), loadedPath: nil)
        }

        if let rawKey = shipfile?.appStoreConnect?.privateKey {
            return PrivateKeyResolution(data: Data(rawKey.utf8), loadedPath: nil)
        }

        let keyPath = resolvePath(
            environment.ascKeyPath ?? shipfile?.appStoreConnect?.keyPath,
            relativeTo: projectRoot
        )
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
        platform: Platform,
        projectRoot: String
    ) async throws -> AutoDetectedAppConfig {
        let workspace = resolvePath(
            effectiveApp?.workspace ?? environment.appWorkspace,
            relativeTo: projectRoot
        )
        let project = resolvePath(
            effectiveApp?.project ?? environment.appProject,
            relativeTo: projectRoot
        )
        let scheme = cliOptions.scheme ?? effectiveApp?.scheme ?? environment.appScheme

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
                .container(containerOption)
                .option(.scheme(scheme))
                .showBuildSettings()
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
    private func xcodeContainerOption(workspace: String?, project: String?) -> XcodeBuildContainer? {
        if let workspace {
            return .workspace(workspace)
        }

        if let project {
            return .project(project)
        }

        return nil
    }
    #endif

    /// Scans `directory` for the first `.xcworkspace` (preferred) or `.xcodeproj` and returns
    /// a lightweight holder with the relative path. Used to auto-resolve `ios/` for RN/Flutter.
    private func autoDetectXcodeContainer(
        in directory: String
    ) -> (workspace: String?, project: String?)? {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        var foundWorkspace: String?
        var foundProject: String?
        for item in items {
            let full = "\(directory)/\(item)"
            if item.hasSuffix(".xcworkspace") {
                foundWorkspace = full
            } else if item.hasSuffix(".xcodeproj") {
                foundProject = foundProject ?? full
            }
        }
        guard foundWorkspace != nil || foundProject != nil else { return nil }
        return (workspace: foundWorkspace, project: foundWorkspace == nil ? foundProject : nil)
    }

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
