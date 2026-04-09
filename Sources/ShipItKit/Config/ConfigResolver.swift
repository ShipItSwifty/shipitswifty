import Foundation
import SwiftyShell
import Yams
import OSLog

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

        let privateKeyResolution = try resolvePrivateKeyData(shipfile: shipfile)
        let processedFiles = [shipfileLoadResult.loadedPath, privateKeyResolution.loadedPath].compactMap { $0 }
        let autoDetectedAppConfig = try await autoDetectAppConfig(shipfile: shipfile, cliOptions: cliOptions)
        let bundleIDFromTargetBuildSettings = environment.appBundleId == nil
            && shipfile?.app?.bundleId == nil
            && autoDetectedAppConfig.bundleID != nil
        let teamIDFromTargetBuildSettings = environment.appTeamId == nil
            && shipfile?.app?.teamId == nil
            && autoDetectedAppConfig.teamID != nil

        return ResolvedConfig(
            processedFiles: processedFiles,
            appWorkspace: environment.appWorkspace ?? shipfile?.app?.workspace ?? autoDetectedAppConfig.workspace,
            appProject: environment.appProject ?? shipfile?.app?.project ?? autoDetectedAppConfig.project,
            appScheme: cliOptions.scheme ?? environment.appScheme ?? shipfile?.app?.scheme ?? autoDetectedAppConfig.scheme,
            bundleID: environment.appBundleId ?? shipfile?.app?.bundleId ?? autoDetectedAppConfig.bundleID,
            bundleIDFromTargetBuildSettings: bundleIDFromTargetBuildSettings,
            teamID: environment.appTeamId ?? shipfile?.app?.teamId ?? autoDetectedAppConfig.teamID,
            teamIDFromTargetBuildSettings: teamIDFromTargetBuildSettings,
            ascKeyID: environment.ascKeyId ?? shipfile?.appStoreConnect?.keyId,
            ascIssuerID: environment.ascIssuerId ?? shipfile?.appStoreConnect?.issuerId,
            ascPrivateKeyData: privateKeyResolution.data,
            buildConfiguration: cliOptions.configuration
                ?? environment.buildConfiguration
                ?? shipfile?.build?.configuration
                ?? "Release",
            derivedDataPath: environment.buildDerivedDataPath ?? shipfile?.build?.derivedDataPath,
            xcargs: shipfile?.build?.xcargs ?? [:],
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
            versioningSource: shipfile?.versioning?.source ?? "xcodeproj",
            slackWebhookUrl: environment.slackWebhookUrl ?? shipfile?.notifications?.slack?.webhookUrl,
            slackChannel: shipfile?.notifications?.slack?.channel,
            workflows: shipfile?.workflows ?? [:]
        )
    }

    // MARK: - Private Helpers

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
            throw ShipItError.invalidConfiguration(reason: "Failed to parse Shipfile at \(path): \(error.localizedDescription)")
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

    private func autoDetectAppConfig(shipfile: Shipfile?, cliOptions: CLIOptions) async throws -> AutoDetectedAppConfig {
        let workspace = environment.appWorkspace ?? shipfile?.app?.workspace
        let project = environment.appProject ?? shipfile?.app?.project
        let scheme = cliOptions.scheme ?? environment.appScheme ?? shipfile?.app?.scheme

        let needsBundleID = environment.appBundleId == nil && shipfile?.app?.bundleId == nil
        let needsTeamID = environment.appTeamId == nil && shipfile?.app?.teamId == nil

        guard needsBundleID || needsTeamID else {
            return AutoDetectedAppConfig(workspace: workspace, project: project, scheme: scheme)
        }

        guard let scheme,
              let containerOption = xcodeContainerOption(workspace: workspace, project: project) else {
            return AutoDetectedAppConfig(workspace: workspace, project: project, scheme: scheme)
        }

        do {
            let output = try await XcodeBuild(context: shell)
                .option(containerOption)
                .option(.scheme(scheme))
                .option(.showBuildSettings)
                .run()

            guard output.exitCode == 0 else {
                logger.warning("Failed to auto-detect build settings for scheme '\(scheme)': \(output.stderr)")
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
    }

    private func xcodeContainerOption(workspace: String?, project: String?) -> XcodeBuildOption? {
        if let workspace {
            return .workspace(workspace)
        }

        if let project {
            return .project(project)
        }

        return nil
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
