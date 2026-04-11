import OSLog
import SwiftyShell

/// Shared context passed to every action during execution.
///
/// Provides access to the shell execution environment, logger,
/// resolved configuration, and the App Store Connect client.
///
/// ## Usage
/// ```swift
/// struct MyAction: Action {
///     func run(with options: Options, context: ActionContext) async throws -> Result {
///         let output = try await Command("git", "status").run(in: context.shell)
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

    /// App Store Connect API client.
    public let appStoreConnect: AppStoreConnectClient

    /// Target platform for this run.
    public let platform: Platform

    /// Creates an `ActionContext`.
    ///
    /// - Parameters:
    ///   - shell: Shell execution context.
    ///   - logger: Structured logger.
    ///   - config: Resolved configuration.
    ///   - appStoreConnect: App Store Connect API client.
    ///   - platform: Target platform (default: `.ios`).
    public init(
        shell: ShellContext,
        logger: Logger,
        config: ResolvedConfig,
        appStoreConnect: AppStoreConnectClient,
        platform: Platform = .ios
    ) {
        self.shell = shell
        self.logger = logger
        self.config = config
        self.appStoreConnect = appStoreConnect
        self.platform = platform
    }

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
    /// - Returns: An `ActionContext` suitable for unit tests.
    public static func mock(executor: MockExecutor, versioningSource: String = "xcodeproj") -> ActionContext {
        let shell = ShellContext(executor: executor)
        let config = ResolvedConfig(
            appScheme: "MockApp",
            bundleID: "com.example.mock",
            teamID: "MOCK12345",
            ascKeyID: "MOCKKEY",
            ascIssuerID: "mock-issuer-id",
            ascPrivateKeyData: nil,
            versioningSource: versioningSource
        )
        // Create a placeholder client — tests that need ASC API calls should mock at a higher level
        let dummyKeyData = Data("-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBkg4DUVQ1fIFUHBABCLRrFwNVm7MAkGByqGSM49AgEFoWQDYgAE\n-----END EC PRIVATE KEY-----".utf8)
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
            platform: .ios
        )
    }
}
