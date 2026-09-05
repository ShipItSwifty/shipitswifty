import GoogleAuthKit
import GooglePlayKit
import AppStoreConnectKit
import Foundation
import Logging
import SwiftyShell

/// Shared context passed to every action during execution.
///
/// Provides access to the shell execution environment, logger,
/// resolved configuration, App Store Connect client, and (for Android) Google Play client.
///
/// ## Usage
/// ```swift
/// struct MyAction: Action {
///     func run(with options: Options, context: ActionContext) async throws -> Result {
///         let output = try await GitCLI(context: context.shell).statusPorcelain().run()
///         context.logger.info("Git status: \(output.stdout)")
///         return Result()
///     }
/// }
/// ```
public struct ActionContext: Sendable {
    /// SwiftyShell context for executing shell commands.
    public let shell: ShellContext

    /// Structured logger scoped to the current operation.
    public let logger: Logger

    /// Merged configuration from Shipfile + env + CLI.
    public let config: ResolvedConfig

    /// When `true`, raw stdout/stderr from shell commands is emitted at debug log level.
    ///
    /// Set by `--verbose` at the CLI layer via `buildActionContext(config:verbose:)`.
    public let verbose: Bool

    /// When `true`, the command's result is being emitted as machine-readable JSON on stdout.
    ///
    /// Set by `--output json` at the CLI layer. Long-running build helpers
    /// (``streamingGradle()`` / ``streamingXcodeBuild()``) must **not** stream live output to
    /// stdout in this mode — doing so would interleave build progress with the JSON result and
    /// corrupt it. They fall back to capturing instead so stdout stays pure JSON.
    public let jsonOutput: Bool

    #if os(macOS)
    /// App Store Connect API client (iOS, macOS only).
    public let appStoreConnect: AppStoreConnectClient
    #endif

    /// Google Play API client (Android). `nil` when Google Play credentials are not configured.
    public let googlePlay: GooglePlayClient?

    /// Target platform for this run.
    public let platform: Platform

    #if os(macOS)
    /// Creates an `ActionContext` (macOS).
    ///
    /// - Parameters:
    ///   - shell: Shell execution context.
    ///   - logger: Structured logger.
    ///   - config: Resolved configuration.
    ///   - appStoreConnect: App Store Connect API client.
    ///   - googlePlay: Google Play API client (optional; only present for Android).
    ///   - platform: Target platform (default: `.ios`).
    ///   - verbose: When `true`, raw command output is logged at debug level (default: `false`).
    ///   - jsonOutput: When `true`, suppresses human-oriented command streaming for JSON output.
    public init(
        shell: ShellContext,
        logger: Logger,
        config: ResolvedConfig,
        appStoreConnect: AppStoreConnectClient,
        googlePlay: GooglePlayClient? = nil,
        platform: Platform = .ios,
        verbose: Bool = false,
        jsonOutput: Bool = false
    ) {
        self.shell = shell
        self.logger = logger
        self.config = config
        self.appStoreConnect = appStoreConnect
        self.googlePlay = googlePlay
        self.platform = platform
        self.verbose = verbose
        self.jsonOutput = jsonOutput
    }
    #else
    /// Creates an `ActionContext` (Linux). App Store Connect features are unavailable on Linux.
    public init(
        shell: ShellContext,
        logger: Logger,
        config: ResolvedConfig,
        googlePlay: GooglePlayClient? = nil,
        platform: Platform = .android,
        verbose: Bool = false,
        jsonOutput: Bool = false
    ) {
        self.shell = shell
        self.logger = logger
        self.config = config
        self.googlePlay = googlePlay
        self.platform = platform
        self.verbose = verbose
        self.jsonOutput = jsonOutput
    }
    #endif

    /// Creates a mock `ActionContext` for use in tests.
    ///
    /// Injects a `MockExecutor` for shell commands so no real processes are spawned.
    ///
    /// ## Usage
    /// ```swift
    /// let executor = MockExecutor { command, _ in
    ///     ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
    /// }
    /// let context = ActionContext.mock(executor: executor)
    /// ```
    ///
    /// - Parameters:
    ///   - executor: A `MockExecutor` to capture and mock shell commands.
    ///   - versioningSource: Override the `versioning.source` value (default: `"xcodeproj"`).
    ///   - platform: Target platform (default: `.ios`).
    ///   - jsonOutput: When `true`, configures the context for JSON-oriented output.
    ///   - suppliedConfig: Optional fully resolved configuration for tests that exercise specific settings.
    /// - Returns: An `ActionContext` suitable for unit tests.
    public static func mock(
        executor: MockExecutor,
        versioningSource: String = "xcodeproj",
        platform: Platform = .ios,
        jsonOutput: Bool = false,
        config suppliedConfig: ResolvedConfig? = nil
    ) -> ActionContext {
        let shell = ShellContext(executor: executor)
        let config =
            suppliedConfig
            ?? ResolvedConfig(
                appScheme: "MockApp",
                bundleID: "com.example.mock",
                teamID: "MOCK12345",
                ascKeyID: "MOCKKEY",
                ascIssuerID: "mock-issuer-id",
                ascPrivateKeyData: nil,
                versioningSource: versioningSource,
                platform: platform
            )
        #if os(macOS)
        // Create a placeholder client — tests that need ASC API calls should mock at a higher level
        let dummyKeyData = Data(
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----"
                .utf8)
        let ascClient = AppStoreConnectClient(
            keyID: "MOCKKEY",
            issuerID: "mock-issuer-id",
            privateKeyData: dummyKeyData
        )
        return ActionContext(
            shell: shell,
            logger: Logger.forType(subsystem: "ShipItSwiftyTests", ActionContext.self),
            config: config,
            appStoreConnect: ascClient,
            googlePlay: nil,
            platform: platform,
            verbose: false,
            jsonOutput: jsonOutput
        )
        #else
        return ActionContext(
            shell: shell,
            logger: Logger.forType(subsystem: "ShipItSwiftyTests", ActionContext.self),
            config: config,
            googlePlay: nil,
            platform: platform,
            verbose: false,
            jsonOutput: jsonOutput
        )
        #endif
    }
}

extension ActionContext {
    public var configIsCI: Bool { config.ci }

    #if os(macOS)
    /// Typed App Store Connect credentials resolved from the merged configuration,
    /// or `nil` when key id / issuer id / private key are not all present.
    ///
    /// This is the type-safe seam passed to `AppStoreConnectKit` services in place
    /// of the whole `ActionContext`.
    public var ascCredentials: ASCCredentials? {
        guard
            let keyID = config.ascKeyID,
            let issuerID = config.ascIssuerID,
            let keyData = config.ascPrivateKeyData
        else { return nil }
        return ASCCredentials(keyID: keyID, issuerID: issuerID, privateKeyData: keyData)
    }
    #endif

    /// Logs `stdout` and `stderr` from a shell command at `.debug` level when verbose is enabled.
    ///
    /// Call this immediately after any `.run()` that you want surfaced under `--verbose`.
    /// Output is suppressed when `verbose` is `false` so there is no overhead in normal runs.
    ///
    /// - Parameters:
    ///   - output: The `ShellOutput` returned by a command.
    ///   - label: A short label shown before the output block, e.g. `"gradlew"`.
    public func logShellOutput(_ output: ShellOutput, label: String) {
        guard verbose else { return }
        if !output.stdout.isEmpty {
            logger.debug("\(label) stdout:\n\(output.stdout.trimmingCharacters(in: .newlines))")
        }
        if !output.stderr.isEmpty {
            logger.debug("\(label) stderr:\n\(output.stderr.trimmingCharacters(in: .newlines))")
        }
    }

    /// Creates a Gradle command family with ShipIt's resolved project settings applied.
    ///
    /// The returned value uses the configured Gradle project directory, explicit wrapper path,
    /// and Shipfile-level flags so direct action runs and workflow runs behave the same way.
    ///
    /// - Returns: A `Gradle` builder ready for tasks and properties.
    public func gradle() -> Gradle {
        var gradle = Gradle(context: shell)
            .projectDir(config.gradleProjectDir)
            .workingDirectory(config.gradleProjectDir)
            .flag(.noDaemon)

        if let gradlewPath = config.gradlewPath {
            gradle = gradle.settingGradlewPath(gradlewPath)
        }

        for flag in config.androidGradleFlags where flag != "--no-daemon" {
            gradle = gradle.flag(.custom(flag))
        }

        if verbose {
            let projectDir = config.gradleProjectDir
            let buildDir = "\(projectDir)/\(config.androidModule)/build"
            logger.debug("Gradle project dir: \(projectDir)")
            logger.debug("Android build output dir: \(buildDir)/outputs")
        }

        return gradle
    }

    /// Returns a Gradle builder configured to stream output live for long-running builds.
    ///
    /// Builds on ``gradle()`` and additionally:
    /// - Routes stdout and stderr through ``SwiftyShell/OutputDestination/tee`` so Gradle's
    ///   progress is echoed to the parent process's stdout/stderr **as it is produced**, while
    ///   still being captured into `ShellOutput.stdout` for downstream parsing (e.g. AAB path,
    ///   test counts, build summary).
    /// - Lifts the captured-output limit (`outputLimit(0)`) so a long `--info`/`--scan` build
    ///   cannot fail by exceeding the default capture cap.
    ///
    /// Use this for the long-running Android Gradle invocations (archive/build/test) where live
    /// progress matters in CI; prefer ``gradle()`` for short, purely-parsed invocations.
    ///
    /// In `--output json` mode (``jsonOutput``) this falls back to plain ``gradle()`` capture so
    /// streamed build progress does not interleave with the JSON result on stdout.
    public func streamingGradle() -> Gradle {
        guard !jsonOutput else { return gradle() }
        return
            gradle()
            .settingStdoutDestination(.tee)
            .settingStderrDestination(.tee)
            .outputLimit(0)
    }

    #if os(macOS)
    /// Returns an `XcodeBuild` builder configured to stream output live for long-running builds.
    ///
    /// Routes stdout and stderr through ``SwiftyShell/OutputDestination/tee`` so xcodebuild's
    /// progress is echoed to the parent process's stdout/stderr **as it is produced**, while still
    /// being captured into `ShellOutput.stdout` for downstream parsing (app/dSYM paths, warning
    /// counts, test-count fallback). Also lifts the captured-output limit (`outputLimit(0)`) —
    /// xcodebuild output is voluminous, so the default cap could otherwise truncate or fail a build.
    ///
    /// Use this for the long-running iOS invocations (build/archive/test); prefer a plain
    /// `XcodeBuild(context:)` for short, purely-parsed invocations (e.g. `-showBuildSettings`,
    /// destination discovery).
    ///
    /// In `--output json` mode (``jsonOutput``) this falls back to a plain capturing
    /// `XcodeBuild(context:)` so streamed build progress does not interleave with — and corrupt —
    /// the JSON result on stdout.
    public func streamingXcodeBuild() -> XcodeBuild {
        guard !jsonOutput else { return XcodeBuild(context: shell) }
        return
            XcodeBuild(context: shell)
            .settingStdoutDestination(.tee)
            .settingStderrDestination(.tee)
            .outputLimit(0)
    }
    #endif

    /// Returns a copy of this context with the given config, preserving all other fields.
    ///
    /// Used by `Workflow.run()` to apply per-workflow config overrides (e.g. `build_variant`).
    public func withConfig(_ newConfig: ResolvedConfig) -> ActionContext {
        #if os(macOS)
        return ActionContext(
            shell: shell,
            logger: logger,
            config: newConfig,
            appStoreConnect: appStoreConnect,
            googlePlay: googlePlay,
            platform: platform,
            verbose: verbose, jsonOutput: jsonOutput
        )
        #else
        return ActionContext(
            shell: shell,
            logger: logger,
            config: newConfig,
            googlePlay: googlePlay,
            platform: platform,
            verbose: verbose, jsonOutput: jsonOutput
        )
        #endif
    }

    /// Returns a copy of this context with the Gradle project directory overridden.
    public func withGradleProjectDir(_ dir: String) -> ActionContext {
        #if os(macOS)
        return ActionContext(
            shell: shell, logger: logger,
            config: config.overriding(gradleProjectDir: dir),
            appStoreConnect: appStoreConnect, googlePlay: googlePlay,
            platform: platform, verbose: verbose, jsonOutput: jsonOutput
        )
        #else
        return ActionContext(
            shell: shell, logger: logger,
            config: config.overriding(gradleProjectDir: dir),
            googlePlay: googlePlay, platform: platform, verbose: verbose, jsonOutput: jsonOutput
        )
        #endif
    }
}
