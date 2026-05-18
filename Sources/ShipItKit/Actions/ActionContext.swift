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
    public init(
        shell: ShellContext,
        logger: Logger,
        config: ResolvedConfig,
        appStoreConnect: AppStoreConnectClient,
        googlePlay: GooglePlayClient? = nil,
        platform: Platform = .ios,
        verbose: Bool = false
    ) {
        self.shell = shell
        self.logger = logger
        self.config = config
        self.appStoreConnect = appStoreConnect
        self.googlePlay = googlePlay
        self.platform = platform
        self.verbose = verbose
    }
    #else
    /// Creates an `ActionContext` (Linux). App Store Connect features are unavailable on Linux.
    public init(
        shell: ShellContext,
        logger: Logger,
        config: ResolvedConfig,
        googlePlay: GooglePlayClient? = nil,
        platform: Platform = .android,
        verbose: Bool = false
    ) {
        self.shell = shell
        self.logger = logger
        self.config = config
        self.googlePlay = googlePlay
        self.platform = platform
        self.verbose = verbose
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
    /// - Returns: An `ActionContext` suitable for unit tests.
    public static func mock(
        executor: MockExecutor,
        versioningSource: String = "xcodeproj",
        platform: Platform = .ios
    ) -> ActionContext {
        let shell = ShellContext(executor: executor)
        let config = ResolvedConfig(
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
            platform: platform
        )
        #else
        return ActionContext(
            shell: shell,
            logger: Logger.forType(subsystem: "ShipItSwiftyTests", ActionContext.self),
            config: config,
            googlePlay: nil,
            platform: platform
        )
        #endif
    }
}

extension ActionContext {
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
}
