import OSLog
import SwiftyShell

/// Compiles the app using `xcodebuild build`.
///
/// Produces compiled products in the derived data directory. Does not create
/// an `.xcarchive` or `.ipa` — use `ArchiveAction` for distribution builds.
///
/// ## Usage
/// ```swift
/// let result = try await BuildAction().run(
///     with: .init(scheme: "MyApp", configuration: .release),
///     context: context
/// )
/// print("App path: \(result.appPath ?? "N/A")")
/// ```
///
/// ## Topics
/// ### Configuration
/// - ``Options``
/// ### Results
/// - ``Result``
public struct BuildAction: Action {
    /// The registered name used in Shipfile lanes.
    public static let name = "build"

    /// Human-readable description for `--help` output.
    public static let description = "Compile the app using xcodebuild build"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", BuildAction.self)

    /// Creates a `BuildAction`.
    public init() {}

    /// Configuration options for the build action.
    public struct Options: Codable, Sendable {
        /// Xcode scheme to build. Overrides `config.appScheme`.
        public var scheme: String?

        /// Build configuration (e.g. `Release`, `Debug`). Default: `Release`.
        public var configuration: BuildConfiguration?

        /// Path to the Xcode workspace.
        public var workspace: String?

        /// Path to the Xcode project (used if `workspace` is nil).
        public var project: String?

        /// Path to derived data directory.
        public var derivedDataPath: String?

        /// Additional xcargs (key=value pairs).
        public var xcargs: [String: String]?

        /// Whether to clean before building.
        public var clean: Bool?

        /// Creates `Options` for the build action.
        ///
        /// All parameters are optional; unset values fall back to `ResolvedConfig`.
        public init(
            scheme: String? = nil,
            configuration: BuildConfiguration? = nil,
            workspace: String? = nil,
            project: String? = nil,
            derivedDataPath: String? = nil,
            xcargs: [String: String]? = nil,
            clean: Bool? = nil
        ) {
            self.scheme = scheme
            self.configuration = configuration
            self.workspace = workspace
            self.project = project
            self.derivedDataPath = derivedDataPath
            self.xcargs = xcargs
            self.clean = clean
        }
    }

    /// Build configuration preset.
    public enum BuildConfiguration: String, Codable, Sendable {
        case debug = "Debug"
        case release = "Release"
    }

    /// Result of a successful build.
    public struct Result: Codable, Sendable {
        /// Path to the compiled `.app` bundle.
        public let appPath: String?

        /// Path to the dSYM file.
        public let dsymPath: String?

        /// Exit code from xcodebuild.
        public let exitCode: Int

        /// Number of warnings emitted.
        public let warnings: Int

        /// Creates a `Result`.
        public init(appPath: String? = nil, dsymPath: String? = nil, exitCode: Int = 0, warnings: Int = 0) {
            self.appPath = appPath
            self.dsymPath = dsymPath
            self.exitCode = exitCode
            self.warnings = warnings
        }
    }

    /// Execute the build action.
    ///
    /// - Parameters:
    ///   - options: Build configuration options.
    ///   - context: Shared execution context.
    /// - Returns: Build result with artifact paths.
    /// - Throws: ``ShipItError/buildFailed`` if xcodebuild exits non-zero.
    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        guard let scheme else {
            throw ShipItError.invalidConfiguration(reason: "Build requires a scheme. Set app.scheme in Shipfile.yml or pass --scheme.")
        }

        let configuration = options.configuration?.rawValue ?? context.config.buildConfiguration
        logger.info("Building scheme '\(scheme)' (\(configuration))")

        var xcodeBuild = XcodeBuild(context: context.shell)
            .option(.scheme(scheme))
            .option(.configuration(configuration))

        if let workspace = options.workspace ?? context.config.appWorkspace {
            xcodeBuild = xcodeBuild.option(.workspace(workspace))
        } else if let project = options.project ?? context.config.appProject {
            xcodeBuild = xcodeBuild.option(.project(project))
        }

        if let derivedData = options.derivedDataPath ?? context.config.derivedDataPath {
            xcodeBuild = xcodeBuild.option(.derivedDataPath(derivedData))
        }

        if context.config.automaticCodeSigning {
            xcodeBuild = xcodeBuild.option(.allowProvisioningUpdates)
        }

        let allXcargs = context.config.xcargs.merging(options.xcargs ?? [:]) { _, new in new }
        for (key, value) in allXcargs {
            xcodeBuild = xcodeBuild.buildSetting(key, value)
        }

        if options.clean == true {
            xcodeBuild = xcodeBuild.trailingArgument("clean")
        }
        xcodeBuild = xcodeBuild.trailingArgument("build")

        let output = try await xcodeBuild.run()

        if output.exitCode != 0 {
            logger.error("Build failed with exit code \(output.exitCode)")
            throw ShipItError.buildFailed(exitCode: Int(output.exitCode), log: output.stderr)
        }

        logger.info("Build succeeded for scheme '\(scheme)'")

        let appPath = parseAppPath(from: output.stdout)
        let dsymPath = parseDsymPath(from: output.stdout)
        let warningCount = countWarnings(in: output.stdout)

        return Result(
            appPath: appPath,
            dsymPath: dsymPath,
            exitCode: Int(output.exitCode),
            warnings: warningCount
        )
    }

    // MARK: - Private Helpers

    private func parseAppPath(from output: String) -> String? {
        // Look for lines like: "Build/Products/Release-iphoneos/MyApp.app"
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains(".app") && !line.contains(".dSYM") {
                let components = line.components(separatedBy: " ")
                if let appComponent = components.first(where: { $0.hasSuffix(".app") }) {
                    return appComponent
                }
            }
        }
        return nil
    }

    private func parseDsymPath(from output: String) -> String? {
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains(".dSYM") {
                let components = line.components(separatedBy: " ")
                if let dsymComponent = components.first(where: { $0.hasSuffix(".dSYM") }) {
                    return dsymComponent
                }
            }
        }
        return nil
    }

    private func countWarnings(in output: String) -> Int {
        output.components(separatedBy: "\n")
            .filter { $0.contains("warning:") }
            .count
    }
}
