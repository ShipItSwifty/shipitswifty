import Foundation
import Logging
import SwiftyShell

/// Compiles the app.
///
/// - **iOS**: Uses `xcodebuild build`. Produces compiled products in the derived data directory.
///   Does not create an `.xcarchive` or `.ipa` — use `ArchiveAction` for distribution builds.
/// - **Android**: Uses `./gradlew assemble<Variant>`. Produces a debug or release APK.
///   For production AAB builds, use `ArchiveAction` with `buildType: .aab`.
///
/// ## Usage
/// ```swift
/// // iOS
/// let result = try await BuildAction().run(
///     with: .init(scheme: "MyApp", configuration: .release),
///     context: context
/// )
/// print("App path: \(result.appPath ?? "N/A")")
///
/// // Android
/// let result = try await BuildAction().run(
///     with: .init(module: "app", buildVariant: "release"),
///     context: androidContext
/// )
/// print("APK path: \(result.apkPath ?? "N/A")")
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
    public static let description = "Compile the app (iOS: xcodebuild build, Android: gradlew assemble)"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", BuildAction.self)

    /// Creates a `BuildAction`.
    public init() {}

    /// Configuration options for the build action.
    public struct Options: Codable, Sendable {
        // MARK: iOS options

        /// Xcode scheme to build. Overrides `config.appScheme`. (iOS only)
        public var scheme: String?

        /// Build configuration (e.g. `Release`, `Debug`). Default: `Release`.
        public var configuration: BuildConfiguration?

        /// Path to the Xcode workspace. (iOS only)
        public var workspace: String?

        /// Path to the Xcode project (used if `workspace` is nil). (iOS only)
        public var project: String?

        /// Path to derived data directory. (iOS only)
        public var derivedDataPath: String?

        /// Additional xcargs (key=value pairs). (iOS only)
        public var xcargs: [String: String]?

        /// Whether to clean before building.
        public var clean: Bool?

        // MARK: Android options

        /// Gradle module name (e.g. `"app"`). Overrides `config.androidModule`. (Android only)
        /// For KMP iOS, this is the shared framework module. Defaults to `config.kmpSharedModule`.
        public var module: String?

        /// Gradle build variant (e.g. `"release"`, `"debug"`). (Android only)
        public var buildVariant: String?

        /// Product flavor (e.g. `"free"`, `"paid"`). Combined with `buildVariant`. (Android only)
        public var flavor: String?

        /// Additional Gradle `-P` properties. (Android only)
        public var gradleProperties: [String: String]?

        /// Gradle task scope — `module` (default) qualifies the task with the module name,
        /// `root` runs the task at the project root across all modules. (Android only)
        public var scope: GradleTaskScope?

        /// Creates `Options` for the build action.
        public init(
            scheme: String? = nil,
            configuration: BuildConfiguration? = nil,
            workspace: String? = nil,
            project: String? = nil,
            derivedDataPath: String? = nil,
            xcargs: [String: String]? = nil,
            clean: Bool? = nil,
            module: String? = nil,
            buildVariant: String? = nil,
            flavor: String? = nil,
            gradleProperties: [String: String]? = nil,
            scope: GradleTaskScope? = nil
        ) {
            self.scheme = scheme
            self.configuration = configuration
            self.workspace = workspace
            self.project = project
            self.derivedDataPath = derivedDataPath
            self.xcargs = xcargs
            self.clean = clean
            self.module = module
            self.buildVariant = buildVariant
            self.flavor = flavor
            self.gradleProperties = gradleProperties
            self.scope = scope
        }
    }

    /// Build configuration preset (iOS).
    public enum BuildConfiguration: String, Codable, Sendable {
        case debug = "Debug"
        case release = "Release"
    }

    /// Result of a successful build.
    public struct Result: Codable, Sendable {
        // MARK: iOS result fields

        /// Path to the compiled `.app` bundle. (iOS)
        public let appPath: String?

        /// Path to the dSYM file. (iOS)
        public let dsymPath: String?

        // MARK: Android result fields

        /// Path to the output APK file. (Android)
        public let apkPath: String?

        /// Exit code from the build tool.
        public let exitCode: Int

        /// Number of warnings emitted.
        public let warnings: Int

        /// Creates a `Result`.
        public init(
            appPath: String? = nil,
            dsymPath: String? = nil,
            apkPath: String? = nil,
            exitCode: Int = 0,
            warnings: Int = 0
        ) {
            self.appPath = appPath
            self.dsymPath = dsymPath
            self.apkPath = apkPath
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
    /// - Throws: ``ShipItError/buildFailed(exitCode:log:)`` if the build exits non-zero.
    public func run(with options: Options, context: ActionContext) async throws -> Result {
        let buildSystem: BuildSystem =
            context.platform == .ios
            ? context.config.iosBuildSystem
            : context.config.androidBuildSystem

        switch (context.platform, buildSystem) {
        case (.ios, .native):
            #if os(macOS)
            return try await runIOS(options: options, context: context)
            #else
            throw ShipItError.invalidConfiguration(reason: "iOS builds require macOS.")
            #endif
        case (.android, .native):
            return try await runAndroid(options: options, context: context)
        case (.ios, .kmp):
            #if os(macOS)
            return try await runKMPiOSBuild(options: options, context: context)
            #else
            throw ShipItError.invalidConfiguration(reason: "KMP iOS builds require macOS.")
            #endif
        case (.android, .kmp):
            // KMP's Android target is a regular Android Gradle module — reuse the native path.
            return try await runAndroid(options: options, context: context)
        case (.ios, .flutter):
            #if os(macOS)
            return try await runFlutterIOS(options: options, context: context)
            #else
            throw ShipItError.invalidConfiguration(reason: "Flutter iOS builds require macOS.")
            #endif
        case (.android, .flutter):
            return try await runFlutterAndroid(options: options, context: context)
        case (.ios, .reactNative):
            #if os(macOS)
            return try await runReactNativeIOS(options: options, context: context)
            #else
            throw ShipItError.invalidConfiguration(reason: "React Native iOS builds require macOS.")
            #endif
        case (.android, .reactNative):
            return try await runReactNativeAndroid(options: options, context: context)
        }
    }

    // MARK: - Flutter iOS Build

    #if os(macOS)
    /// Runs `flutter build ios --release` to compile and validate the Flutter iOS app.
    ///
    /// Unlike `ArchiveAction` (which runs `flutter build ipa`), the build step uses
    /// `flutter build ios` — a lighter compile-only check that does not produce an IPA.
    /// This avoids running the full IPA export twice when a workflow has both `build` and
    /// `archive` steps.
    private func runFlutterIOS(options: Options, context: ActionContext) async throws -> Result {
        let flavor = options.flavor
        logger.info("Building Flutter iOS app (flutter build ios\(flavor.map { " --flavor \($0)" } ?? ""))")

        let flutter = FlutterCLI(context: context.shell)
            .buildIOS(flavor: flavor)

        let output = try await ShellRunHelpers.run(flutter) { exitCode, log in
            logger.error("Flutter iOS build failed with exit code \(exitCode)")
            return .buildFailed(exitCode: exitCode, log: log)
        }

        logger.info("Flutter iOS build succeeded")
        return Result(exitCode: Int(output.exitCode), warnings: countWarnings(in: output.stdout))
    }
    #endif

    // MARK: - Flutter Android Build

    /// Runs `flutter build apk --release` to produce a release APK.
    private func runFlutterAndroid(options: Options, context: ActionContext) async throws -> Result {
        let flavor = options.flavor
        logger.info("Building Flutter Android APK\(flavor.map { " (flavor: \($0))" } ?? "")")

        let flutter = FlutterCLI(context: context.shell)
            .buildAPK(flavor: flavor)

        let output = try await ShellRunHelpers.run(flutter) { exitCode, log in
            logger.error("Flutter Android build failed with exit code \(exitCode)")
            return .buildFailed(exitCode: exitCode, log: log)
        }

        logger.info("Flutter Android build succeeded")
        return Result(
            apkPath: CrossPlatformArtifactPaths.flutterAPK(flavor: flavor),
            exitCode: Int(output.exitCode),
            warnings: countWarnings(in: output.stdout)
        )
    }

    // MARK: - React Native iOS Build

    #if os(macOS)
    /// Runs `npx react-native build-ios --mode Release` to validate the iOS bundle.
    ///
    /// This step confirms the React Native JS bundle and native compilation succeed.
    /// For App Store-grade archives, `ArchiveAction` runs `xcodebuild archive` afterward.
    private func runReactNativeIOS(options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        let configuration = options.configuration?.rawValue ?? context.config.buildConfiguration
        logger.info("Building React Native iOS (npx react-native build-ios --mode \(configuration))")

        let rn = ReactNativeCLI(context: context.shell)
            .buildIOS(mode: configuration, scheme: scheme)

        do {
            let output = try await rn.run()
            guard output.exitCode == 0 else {
                let log = ShellRunHelpers.combinedLog(output)
                if shouldFallbackFromReactNativeBuildCommand(log: log) {
                    logger.warning("React Native build-ios command unavailable; falling back to xcodebuild build")
                    return try await runIOS(options: options, context: context)
                }
                logger.error("React Native iOS build failed with exit code \(output.exitCode)")
                throw ShipItError.buildFailed(exitCode: Int(output.exitCode), log: log)
            }

            logger.info("React Native iOS build succeeded")
            return Result(exitCode: Int(output.exitCode), warnings: countWarnings(in: output.stdout))
        } catch let ShellError.exitFailure(_, shellOutput) {
            let log = ShellRunHelpers.combinedLog(shellOutput)
            if shouldFallbackFromReactNativeBuildCommand(log: log) {
                logger.warning("React Native build-ios command unavailable; falling back to xcodebuild build")
                return try await runIOS(options: options, context: context)
            }

            logger.error("React Native iOS build failed with exit code \(shellOutput.exitCode)")
            throw ShipItError.buildFailed(exitCode: Int(shellOutput.exitCode), log: log)
        }
    }
    #endif

    // MARK: - React Native Android Build

    /// Runs `npx react-native build-android --mode=release` to produce a release APK.
    private func runReactNativeAndroid(
        options: Options, context: ActionContext
    ) async throws -> Result {
        let variant = options.buildVariant ?? context.config.androidBuildVariant
        logger.info("Building React Native Android (npx react-native build-android --mode=\(variant))")

        let rn = ReactNativeCLI(context: context.shell)
            .buildAndroid(mode: variant)

        do {
            let output = try await rn.run()
            guard output.exitCode == 0 else {
                let log = ShellRunHelpers.combinedLog(output)
                if shouldFallbackFromReactNativeBuildCommand(log: log) {
                    logger.warning("React Native build-android command unavailable; falling back to Gradle assemble")
                    return try await runReactNativeAndroidGradleBuild(options: options, context: context)
                }
                logger.error("React Native Android build failed with exit code \(output.exitCode)")
                throw ShipItError.buildFailed(exitCode: Int(output.exitCode), log: log)
            }

            logger.info("React Native Android build succeeded")
            return Result(
                apkPath: CrossPlatformArtifactPaths.reactNativeAPK(variant: variant),
                exitCode: Int(output.exitCode),
                warnings: countWarnings(in: output.stdout)
            )
        } catch let ShellError.exitFailure(_, shellOutput) {
            let log = ShellRunHelpers.combinedLog(shellOutput)
            if shouldFallbackFromReactNativeBuildCommand(log: log) {
                logger.warning("React Native build-android command unavailable; falling back to Gradle assemble")
                return try await runReactNativeAndroidGradleBuild(options: options, context: context)
            }

            logger.error("React Native Android build failed with exit code \(shellOutput.exitCode)")
            throw ShipItError.buildFailed(exitCode: Int(shellOutput.exitCode), log: log)
        }
    }

    private func runReactNativeAndroidGradleBuild(
        options: Options,
        context: ActionContext
    ) async throws -> Result {
        let module = reactNativeAndroidModule(context: context)
        let variant = options.buildVariant ?? context.config.androidBuildVariant
        let task: GradleTask = variant.lowercased() == "debug" ? .assembleDebug : .assembleRelease

        let output = try await runReactNativeGradleTask(
            task: task.qualified(module: module),
            gradleProperties: options.gradleProperties,
            context: context,
            failureMapper: { exitCode, log in
                .buildFailed(exitCode: exitCode, log: log)
            }
        )

        return Result(
            apkPath: CrossPlatformArtifactPaths.reactNativeAPK(variant: variant),
            exitCode: Int(output.exitCode),
            warnings: countWarnings(in: output.stdout)
        )
    }

    private func runReactNativeGradleTask(
        task: GradleTask,
        gradleProperties: [String: String]?,
        context: ActionContext,
        failureMapper: (Int, String) -> ShipItError
    ) async throws -> ShellOutput {
        var gradle = Gradle(context: context.shell)
            .projectDir(reactNativeGradleProjectDir(context: context))
            .flag(.noDaemon)
            .task(task)

        if let gradlewPath = reactNativeGradlewPath(context: context) {
            gradle = gradle.settingGradlewPath(gradlewPath)
        }

        for flag in context.config.androidGradleFlags where flag != "--no-daemon" {
            gradle = gradle.flag(.custom(flag))
        }

        let allProps = context.config.androidGradleProperties.merging(gradleProperties ?? [:]) { _, new in new }
        for (key, value) in allProps {
            gradle = gradle.property(.custom(key: key, value: value))
        }

        do {
            let output = try await gradle.run()
            if output.exitCode != 0 {
                throw failureMapper(Int(output.exitCode), ShellRunHelpers.combinedLog(output))
            }
            context.logShellOutput(output, label: "gradlew react-native fallback")
            return output
        } catch let ShellError.exitFailure(_, shellOutput) {
            throw failureMapper(Int(shellOutput.exitCode), ShellRunHelpers.combinedLog(shellOutput))
        }
    }

    private func reactNativeAndroidModule(context: ActionContext) -> String {
        let module = context.config.androidModule
        return module.isEmpty ? "app" : module
    }

    private func reactNativeGradleProjectDir(context: ActionContext) -> String {
        context.config.gradleProjectDir == context.config.projectRoot ? "./android" : context.config.gradleProjectDir
    }

    private func reactNativeGradlewPath(context: ActionContext) -> String? {
        if let gradlewPath = context.config.gradlewPath {
            return gradlewPath
        }
        return "\(reactNativeGradleProjectDir(context: context))/gradlew"
    }

    private func shouldFallbackFromReactNativeBuildCommand(log: String) -> Bool {
        let normalized = log.lowercased()
        return normalized.contains("unknown command 'build-ios'")
            || normalized.contains("unknown command 'build-android'")
            || normalized.contains("depends on @react-native-community/cli for cli commands")
            || normalized.contains("is not a recognized command")
    }

    // MARK: - KMP iOS Build

    #if os(macOS)
    /// Links the KMP shared framework via Gradle, then runs `xcodebuild build` against the
    /// wrapper Xcode project. The Gradle link task is determined by `options.module` (default
    /// `"shared"`) and the resolved `BuildConfiguration`.
    ///
    /// This path assumes the project follows the standard KMP layout where the Xcode wrapper
    /// lives alongside `gradlew` (e.g. `./iosApp/iosApp.xcworkspace`).
    private func runKMPiOSBuild(options: Options, context: ActionContext) async throws -> Result {
        guard (options.scheme ?? context.config.appScheme) != nil else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "KMP iOS build requires a scheme for the Xcode wrapper. Set app.scheme in Shipfile.yml or pass --scheme."
            )
        }

        // The KMP framework link must use the same Build Configuration that the upcoming
        // xcodebuild step will use. Pass the action's effective configuration so a Debug
        // build doesn't get paired with a Release framework (and vice-versa).
        let effectiveConfiguration =
            options.configuration?.rawValue ?? context.config.buildConfiguration

        try await context.ensureProjectGenerated()
        try await context.linkKMPFramework(
            buildConfiguration: effectiveConfiguration,
            target: context.config.kmpBuildTarget,
            module: options.module
        )

        // Continue with the regular xcodebuild path against the Xcode wrapper.
        return try await runIOS(options: options, context: context)
    }
    #endif

    // MARK: - iOS Build

    #if os(macOS)
    private func runIOS(options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        guard let scheme else {
            throw ShipItError.invalidConfiguration(reason: "Build requires a scheme. Set app.scheme in Shipfile.yml or pass --scheme.")
        }

        let configuration = options.configuration?.rawValue ?? context.config.buildConfiguration
        logger.info("Building iOS scheme '\(scheme)' (\(configuration))")

        // Materialize ASC API key flags so `-allowProvisioningUpdates` can authenticate
        // to Apple in headless CI. Resolved only for automatic signing.
        let ascAuth =
            context.config.automaticCodeSigning
            ? try ASCAuthenticationKey.resolve(config: context.config)
            : nil
        defer { ascAuth?.cleanup() }

        var xcodeBuild = context.streamingXcodeBuild()
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
            for option in ascAuth?.options ?? [] {
                xcodeBuild = xcodeBuild.option(option)
            }
        }

        let allXcargs = context.config.xcargs.merging(options.xcargs ?? [:]) { _, new in new }
        for (key, value) in allXcargs {
            xcodeBuild = xcodeBuild.buildSetting(key, value)
        }

        if options.clean == true {
            xcodeBuild = xcodeBuild.trailingArgument("clean")
        }
        xcodeBuild = xcodeBuild.trailingArgument("build")

        let output: ShellOutput
        do {
            output = try await xcodeBuild.run()
        } catch let ShellError.exitFailure(_, output) {
            logger.error("Build failed with exit code \(output.exitCode)")
            throw ShipItError.buildFailed(
                exitCode: Int(output.exitCode),
                log: [output.stdout, output.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
        }

        if output.exitCode != 0 {
            logger.error("Build failed with exit code \(output.exitCode)")
            throw ShipItError.buildFailed(exitCode: Int(output.exitCode), log: output.stderr)
        }

        logger.info("Build succeeded for scheme '\(scheme)'")
        context.logShellOutput(output, label: "xcodebuild build")
        logXcodeBuildSummary(from: output.stdout)

        return Result(
            appPath: parseAppPath(from: output.stdout),
            dsymPath: parseDsymPath(from: output.stdout),
            exitCode: Int(output.exitCode),
            warnings: countWarnings(in: output.stdout)
        )
    }

    #endif

    // MARK: - Android Build

    private func runAndroid(options: Options, context: ActionContext) async throws -> Result {
        let module = options.module ?? context.config.androidModule
        let variant = options.buildVariant ?? context.config.androidBuildVariant
        let flavor = options.flavor ?? context.config.androidGradleProperties["flavor"]
        let scope = options.scope ?? context.config.androidScope

        // Determine task: assembleFreeRelease or assembleRelease
        let task: GradleTask
        if let flavor {
            task = GradleTask.assemble(flavor: flavor, variant: variant)
        } else {
            task = GradleTask(name: CrossPlatformArtifactPaths.gradleTaskName(prefix: "assemble", variant: variant))
        }

        // Qualify based on scope
        let scopedTask: GradleTask
        switch scope {
        case .root:
            scopedTask = task
        case .module:
            scopedTask = task.qualified(module: module)
        }

        logger.info("Building Android module '\(module)' with task '\(scopedTask.name)'")

        var gradle = context.streamingGradle()
            .task(scopedTask)

        if options.clean == true {
            gradle = context.streamingGradle()
                .task(.clean)
                .task(scopedTask)
        }

        // Apply config-level Gradle properties after the optional clean rebuild so they are not dropped.
        let allProps = context.config.androidGradleProperties.merging(options.gradleProperties ?? [:]) { _, new in new }
        for (key, value) in allProps {
            gradle = gradle.property(.custom(key: key, value: value))
        }

        let output: ShellOutput
        do {
            output = try await gradle.run()
        } catch let ShellError.exitFailure(_, output) {
            logger.error("Android build failed with exit code \(output.exitCode)")
            throw ShipItError.buildFailed(
                exitCode: Int(output.exitCode),
                log: [output.stdout, output.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
        }

        if output.exitCode != 0 {
            logger.error("Android build failed with exit code \(output.exitCode)")
            throw ShipItError.buildFailed(exitCode: Int(output.exitCode), log: output.stderr)
        }

        logger.info("Android build succeeded for module '\(module)'")
        context.logShellOutput(output, label: "gradlew assemble")

        // Always surface the build summary at info level (not gated on --verbose).
        let summary = GradleBuildSummary.parse(output.stdout)
        if let line = summary.buildResultLine { logger.info("\(line)") }
        if let line = summary.actionableTasksLine { logger.info("\(line)") }
        if let url = summary.buildScanURL { logger.info("Build scan: \(url)") }

        let apkPath = parseApkPath(from: output.stdout, module: module, variant: variant)
        return Result(
            apkPath: apkPath,
            exitCode: Int(output.exitCode),
            warnings: countWarnings(in: output.stdout)
        )
    }

    // MARK: - Private Helpers

    #if os(macOS)
    /// Logs the xcodebuild result marker and warning/error counts at info level. Never throws.
    private func logXcodeBuildSummary(from stdout: String) {
        let summary = XcodeBuildSummary.parse(stdout)
        if let line = summary.resultLine { logger.info("\(line)") }
        if summary.warningCount > 0 || summary.errorCount > 0 {
            logger.info("\(summary.warningCount) warning(s), \(summary.errorCount) error(s)")
        }
    }

    private func parseAppPath(from output: String) -> String? {
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

    #endif

    private func parseApkPath(from output: String, module: String, variant: String) -> String? {
        // Gradle outputs: "app/build/outputs/apk/release/app-release.apk"
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains(".apk") && line.contains(variant) {
                let components = line.components(separatedBy: " ")
                if let apkComponent = components.first(where: { $0.hasSuffix(".apk") }) {
                    return apkComponent
                }
            }
        }
        // Fallback: well-known default path
        return "\(module)/build/outputs/apk/\(variant)/\(module)-\(variant).apk"
    }

    private func countWarnings(in output: String) -> Int {
        output.components(separatedBy: "\n")
            .filter { $0.contains("warning:") || $0.contains("w:") }
            .count
    }
}
