import Foundation
import Logging
import SwiftyShell

/// Archives the app for distribution.
///
/// - **iOS**: Uses `xcodebuild archive`, producing a `.xcarchive`.
///   The resulting archive is consumed by `ExportAction` to produce an IPA.
/// - **Android**: Uses `./gradlew bundle<Variant>`, producing a signed `.aab` (Android App Bundle).
///   For APK-only builds use `BuildAction` instead. Gradle output is streamed live to the parent
///   process (so a 15-minute build shows progress in CI), and a concise build summary
///   (`BUILD SUCCESSFUL …`, the `actionable tasks: … from cache …` line, and any build-scan URL)
///   is always printed at info level — even without `--verbose`. When `outputPath` is set, the
///   produced `.aab` is copied to that deterministic path.
///
/// ## Usage
/// ```swift
/// // iOS
/// let result = try await ArchiveAction().run(
///     with: .init(scheme: "MyApp", exportMethod: "app-store"),
///     context: context
/// )
/// print("Archive: \(result.archivePath)")
///
/// // Android
/// let result = try await ArchiveAction().run(
///     with: .init(buildVariant: "release"),
///     context: androidContext
/// )
/// print("AAB: \(result.aabPath ?? "N/A")")
/// ```
public struct ArchiveAction: Action {
    public static let name = "archive"
    public static let description = "Archive the app (iOS: xcodebuild archive, Android: gradlew bundle)"

    private let logger = Logger.forType(subsystem: "ShipItSwifty", ArchiveAction.self)

    /// Creates an `ArchiveAction`.
    public init() {}

    /// Configuration for the archive action.
    public struct Options: Codable, Sendable {
        // MARK: iOS options

        /// Xcode scheme to archive. (iOS only)
        public var scheme: String?

        /// Build configuration. Default: `Release`.
        public var configuration: String?

        /// Export method: `app-store`, `ad-hoc`, `development`, or `enterprise`. (iOS only)
        public var exportMethod: String?

        /// Output path for the produced artifact.
        ///
        /// - iOS: path for the `.xcarchive`. Default: `./build/<scheme>.xcarchive`.
        /// - Android: when set, the produced `.aab` is copied to this path (intermediate
        ///   directories are created, existing files overwritten) and the copied path is
        ///   returned as `aabPath`. Enables clean build-in-one-job / upload-in-another-job
        ///   splits (mirrors `play-store --aab`). When unset, the Gradle output location is used.
        public var outputPath: String?

        /// Whether to include debug symbols. (iOS only)
        public var includeSymbols: Bool?

        /// Whether to include bitcode. (iOS only)
        public var includeBitcode: Bool?

        // MARK: Android options

        /// Gradle module name (e.g. `"app"`). Defaults to `config.androidModule`. (Android only)
        public var module: String?

        /// Build variant (e.g. `"release"`, `"debug"`). Defaults to `config.androidBuildVariant`. (Android only)
        public var buildVariant: String?

        /// Product flavor (e.g. `"free"`, `"paid"`). Combined with `buildVariant`. (Android only)
        public var flavor: String?

        /// Additional Gradle `-P` properties. (Android only)
        public var gradleProperties: [String: String]?

        /// Gradle task scope — `module` (default) or `root`. (Android only)
        public var scope: GradleTaskScope?

        /// Retry policy for transient infrastructure failures. (iOS only)
        ///
        /// Covers transient Apple provisioning-server and network failures that occur
        /// when `-allowProvisioningUpdates` contacts Apple's servers during archive.
        /// Permanent failures (missing certificate, invalid team ID) are never retried.
        public var infrastructureRetry: InfrastructureRetryScheduler.Options?

        /// Creates `Options` for the archive action.
        ///
        /// All parameters are optional; unset values fall back to `ResolvedConfig`.
        public init(
            scheme: String? = nil,
            configuration: String? = nil,
            exportMethod: String? = nil,
            outputPath: String? = nil,
            includeSymbols: Bool? = nil,
            includeBitcode: Bool? = nil,
            module: String? = nil,
            buildVariant: String? = nil,
            flavor: String? = nil,
            gradleProperties: [String: String]? = nil,
            scope: GradleTaskScope? = nil,
            infrastructureRetry: InfrastructureRetryScheduler.Options? = nil
        ) {
            self.scheme = scheme
            self.configuration = configuration
            self.exportMethod = exportMethod
            self.outputPath = outputPath
            self.includeSymbols = includeSymbols
            self.includeBitcode = includeBitcode
            self.module = module
            self.buildVariant = buildVariant
            self.flavor = flavor
            self.gradleProperties = gradleProperties
            self.scope = scope
            self.infrastructureRetry = infrastructureRetry
        }
    }

    /// Result of a successful archive.
    public struct Result: Codable, Sendable {
        /// Path to the created `.xcarchive`. (iOS native/KMP/RN)
        /// For Flutter iOS, this contains the IPA path instead (Flutter skips xcarchive).
        public let archivePath: String?

        /// Path to the generated `.aab` file. (Android)
        public let aabPath: String?

        /// Path to the generated `.ipa` file. Set for Flutter iOS where no xcarchive is created.
        public let ipaPath: String?

        /// Exit code from the underlying tool.
        public let exitCode: Int

        /// Creates an iOS xcarchive `Result`.
        public init(archivePath: String, exitCode: Int = 0) {
            self.archivePath = archivePath
            self.aabPath = nil
            self.ipaPath = nil
            self.exitCode = exitCode
        }

        /// Creates an Android `Result`.
        public init(aabPath: String?, exitCode: Int = 0) {
            self.archivePath = nil
            self.aabPath = aabPath
            self.ipaPath = nil
            self.exitCode = exitCode
        }

        /// Creates a Flutter iOS `Result` where the IPA is produced directly (no xcarchive).
        public init(ipaPath: String?, exitCode: Int = 0) {
            self.archivePath = nil
            self.aabPath = nil
            self.ipaPath = ipaPath
            self.exitCode = exitCode
        }
    }

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
            throw ShipItError.invalidConfiguration(reason: "iOS archives require macOS.")
            #endif
        case (.ios, .kmp):
            #if os(macOS)
            return try await runKMPIOSArchive(options: options, context: context)
            #else
            throw ShipItError.invalidConfiguration(reason: "KMP iOS archives require macOS.")
            #endif
        case (.android, .native), (.android, .kmp):
            return try await runAndroid(options: options, context: context)
        case (_, .flutter):
            return try await runFlutterArchive(options: options, context: context)
        case (.ios, .reactNative):
            #if os(macOS)
            return try await runReactNativeIOSArchive(options: options, context: context)
            #else
            throw ShipItError.invalidConfiguration(reason: "React Native iOS archives require macOS.")
            #endif
        case (.android, .reactNative):
            return try await runReactNativeAndroidArchive(options: options, context: context)
        }
    }

    // MARK: - Flutter Archive

    /// Flutter iOS: `flutter build ipa` → IPA at `build/ios/ipa/*.ipa` (no xcarchive).
    /// Flutter Android: `flutter build appbundle` → AAB at `build/app/outputs/bundle/release/app-release.aab`.
    private func runFlutterArchive(options: Options, context: ActionContext) async throws -> Result {
        let flavor = options.flavor
        switch context.platform {
        case .ios:
            #if os(macOS)
            logger.info("Archiving Flutter iOS app (flutter build ipa\(flavor.map { " --flavor \($0)" } ?? ""))")
            let flutter = FlutterCLI(context: context.shell).buildIPA(flavor: flavor)
            let output = try await ShellRunHelpers.run(flutter) { exitCode, log in
                logger.error("Flutter iOS archive failed with exit code \(exitCode)")
                return .archiveFailed(exitCode: exitCode, log: log)
            }
            let ipaPath = "build/ios/ipa"
            logger.info("Flutter iOS archive succeeded. IPA directory: \(ipaPath)")
            return Result(ipaPath: ipaPath, exitCode: Int(output.exitCode))
            #else
            throw ShipItError.invalidConfiguration(reason: "Flutter iOS archives require macOS.")
            #endif
        case .android:
            logger.info("Archiving Flutter Android app (flutter build appbundle\(flavor.map { " --flavor \($0)" } ?? ""))")
            let flutter = FlutterCLI(context: context.shell).buildAppBundle(flavor: flavor)
            let output = try await ShellRunHelpers.run(flutter) { exitCode, log in
                logger.error("Flutter Android archive failed with exit code \(exitCode)")
                return .archiveFailed(exitCode: exitCode, log: log)
            }
            let aabPath = CrossPlatformArtifactPaths.flutterAAB(flavor: flavor)
            logger.info("Flutter Android archive succeeded. AAB: \(aabPath)")
            return Result(aabPath: aabPath, exitCode: Int(output.exitCode))
        }
    }

    // MARK: - React Native iOS Archive (xcodebuild archive)

    #if os(macOS)
    /// React Native iOS archive runs standard `xcodebuild archive` on the generated Xcode project.
    ///
    /// Unlike Flutter, the RN CLI does not produce an App Store-ready IPA — `xcodebuild archive`
    /// and `xcodebuild -exportArchive` (via `ExportAction`) are required.
    private func runReactNativeIOSArchive(
        options: Options, context: ActionContext
    ) async throws -> Result {
        logger.info("Archiving React Native iOS app via xcodebuild archive")
        return try await runIOS(options: options, context: context)
    }
    #endif

    // MARK: - React Native Android Archive (npx react-native build-android)

    /// React Native Android archive uses the RN CLI which wraps Gradle.
    ///
    /// The RN CLI correctly bundles the JS layer before invoking Gradle, producing
    /// `android/app/build/outputs/bundle/release/app-release.aab`.
    private func runReactNativeAndroidArchive(
        options: Options, context: ActionContext
    ) async throws -> Result {
        let variant = options.buildVariant ?? context.config.androidBuildVariant
        let task = CrossPlatformArtifactPaths.gradleTaskName(prefix: "bundle", variant: variant)
        logger.info("Archiving React Native Android app (npx react-native build-android --mode=\(variant) --tasks \(task))")

        let rn = ReactNativeCLI(context: context.shell).buildAndroid(mode: variant, task: task)

        do {
            let output = try await rn.run()
            guard output.exitCode == 0 else {
                let log = ShellRunHelpers.combinedLog(output)
                if shouldFallbackFromReactNativeBuildCommand(log: log) {
                    logger.warning("React Native build-android archive command unavailable; falling back to Gradle bundle")
                    return try await runReactNativeAndroidGradleArchive(options: options, context: context)
                }
                logger.error("React Native Android archive failed with exit code \(output.exitCode)")
                throw ShipItError.archiveFailed(exitCode: Int(output.exitCode), log: log)
            }

            let aabPath = CrossPlatformArtifactPaths.reactNativeAAB(variant: variant)
            logger.info("React Native Android archive succeeded. AAB: \(aabPath)")
            return Result(aabPath: aabPath, exitCode: Int(output.exitCode))
        } catch let ShellError.exitFailure(_, shellOutput) {
            let log = ShellRunHelpers.combinedLog(shellOutput)
            if shouldFallbackFromReactNativeBuildCommand(log: log) {
                logger.warning("React Native build-android archive command unavailable; falling back to Gradle bundle")
                return try await runReactNativeAndroidGradleArchive(options: options, context: context)
            }
            logger.error("React Native Android archive failed with exit code \(shellOutput.exitCode)")
            throw ShipItError.archiveFailed(exitCode: Int(shellOutput.exitCode), log: log)
        }
    }

    private func runReactNativeAndroidGradleArchive(
        options: Options,
        context: ActionContext
    ) async throws -> Result {
        let module = reactNativeAndroidModule(context: context)
        let variant = options.buildVariant ?? context.config.androidBuildVariant
        let task: GradleTask = variant.lowercased() == "debug" ? .bundleDebug : .bundleRelease

        let output = try await runReactNativeGradleTask(
            task: task.qualified(module: module),
            gradleProperties: options.gradleProperties,
            context: context,
            failureMapper: { exitCode, log in
                .archiveFailed(exitCode: exitCode, log: log)
            }
        )

        let aabPath = CrossPlatformArtifactPaths.reactNativeAAB(variant: variant)
        let baseDir = context.shell.workingDirectory ?? FileManager.default.currentDirectoryPath
        let anchoredPath: String
        if (aabPath as NSString).isAbsolutePath {
            anchoredPath = aabPath
        } else {
            anchoredPath = (baseDir as NSString).appendingPathComponent(aabPath)
        }
        guard FileManager.default.fileExists(atPath: anchoredPath) else {
            throw ShipItError.archiveFailed(
                exitCode: 0,
                log: "Gradle reported success but AAB was not produced at '\(anchoredPath)'."
            )
        }

        return Result(aabPath: aabPath, exitCode: Int(output.exitCode))
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

    #if os(macOS)
    private func runKMPIOSArchive(options: Options, context: ActionContext) async throws -> Result {
        let configuration = options.configuration ?? context.config.buildConfiguration
        try await context.ensureProjectGenerated()
        try await context.linkKMPFramework(
            buildConfiguration: configuration,
            target: context.config.kmpArchiveTarget,
            module: options.module
        )
        return try await runIOS(options: options, context: context)
    }
    #endif

    // MARK: - iOS Archive

    #if os(macOS)
    private func runIOS(options: Options, context: ActionContext) async throws -> Result {
        let scheme = options.scheme ?? context.config.appScheme
        guard let scheme else {
            throw ShipItError.invalidConfiguration(reason: "Archive requires a scheme. Set app.scheme in Shipfile.yml or pass --scheme.")
        }

        let configuration = options.configuration ?? context.config.buildConfiguration
        let archivePath =
            options.outputPath
            ?? context.config.archiveOutputPath
            ?? "./build/\(scheme).xcarchive"

        logger.info("Archiving scheme '\(scheme)' (\(configuration)) -> \(archivePath)")

        // Materialize ASC API key flags so `-allowProvisioningUpdates` can authenticate
        // to Apple in headless CI. Resolved only for automatic signing; cleaned up after
        // all retry attempts complete.
        let ascAuth =
            context.config.automaticCodeSigning
            ? try ASCAuthenticationKey.resolve(config: context.config)
            : nil
        defer { ascAuth?.cleanup() }

        var xcodeBuild = context.streamingXcodeBuild()
            .option(.scheme(scheme))
            .option(.configuration(configuration))
            .option(.archivePath(archivePath))
            .trailingArgument("archive")

        if let workspace = context.config.appWorkspace {
            xcodeBuild = xcodeBuild.option(.workspace(workspace))
        } else if let project = context.config.appProject {
            xcodeBuild = xcodeBuild.option(.project(project))
        }

        if let derivedData = context.config.derivedDataPath {
            xcodeBuild = xcodeBuild.option(.derivedDataPath(derivedData))
        }

        if context.config.automaticCodeSigning {
            xcodeBuild = xcodeBuild.option(.allowProvisioningUpdates)
            if let teamID = context.config.teamID {
                xcodeBuild = xcodeBuild.buildSetting("DEVELOPMENT_TEAM", teamID)
            }
            for option in ascAuth?.options ?? [] {
                xcodeBuild = xcodeBuild.option(option)
            }
        }

        let allXcargs = context.config.xcargs
        for (key, value) in allXcargs {
            xcodeBuild = xcodeBuild.buildSetting(key, value)
        }

        let attempt = makeArchiveAttempt(xcodeBuild: xcodeBuild, archivePath: archivePath)
        return try await InfrastructureRetryScheduler.executeIfConfigured(
            options: options.infrastructureRetry,
            classifier: IOSArchiveInfrastructureClassifier(),
            label: "\(scheme) archive",
            operation: attempt
        ) { error in
            if let shipItError = error as? ShipItError,
                case .archiveFailed(_, let log) = shipItError
            {
                return .init(log: log)
            }
            return nil
        }
    }

    private func makeArchiveAttempt(
        xcodeBuild: XcodeBuild,
        archivePath: String
    ) -> @Sendable () async throws -> Result {
        { [logger] in
            do {
                let output = try await xcodeBuild.run()
                if output.exitCode != 0 {
                    let log = [output.stdout, output.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
                    logger.error("Archive failed with exit code \(output.exitCode)")
                    throw ShipItError.archiveFailed(exitCode: Int(output.exitCode), log: log)
                }
                logger.info("Archive succeeded: \(archivePath)")
                let summary = XcodeBuildSummary.parse(output.stdout)
                if let line = summary.resultLine { logger.info("\(line)") }
                if summary.warningCount > 0 || summary.errorCount > 0 {
                    logger.info("\(summary.warningCount) warning(s), \(summary.errorCount) error(s)")
                }
                return Result(archivePath: archivePath, exitCode: Int(output.exitCode))
            } catch let ShellError.exitFailure(_, shellOutput) {
                let log = [shellOutput.stdout, shellOutput.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
                logger.error("Archive failed with exit code \(shellOutput.exitCode)")
                throw ShipItError.archiveFailed(exitCode: Int(shellOutput.exitCode), log: log)
            }
        }
    }

    #endif

    // MARK: - Android Archive (gradlew bundle)

    private func runAndroid(options: Options, context: ActionContext) async throws -> Result {
        let module = options.module ?? context.config.androidModule
        let variant = options.buildVariant ?? context.config.androidBuildVariant
        let flavor = options.flavor ?? context.config.androidGradleProperties["flavor"]
        let scope = options.scope ?? context.config.androidScope

        // Determine task: bundleFreeRelease or bundleRelease
        let task: GradleTask
        if let flavor {
            task = GradleTask.bundle(flavor: flavor, variant: variant)
        } else {
            task = GradleTask(name: CrossPlatformArtifactPaths.gradleTaskName(prefix: "bundle", variant: variant))
        }

        // Qualify based on scope
        let scopedTask: GradleTask
        switch scope {
        case .root:
            scopedTask = task
        case .module:
            scopedTask = task.qualified(module: module)
        }

        logger.info("Bundling Android module '\(module)' with task '\(scopedTask.name)'")

        var gradle = context.streamingGradle()
            .task(scopedTask)

        let allProps = context.config.androidGradleProperties.merging(options.gradleProperties ?? [:]) { _, new in new }
        for (key, value) in allProps {
            gradle = gradle.property(.custom(key: key, value: value))
        }

        let output: ShellOutput
        do {
            output = try await gradle.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            logger.error("Android bundle failed with exit code \(shellOutput.exitCode)")
            throw ShipItError.archiveFailed(
                exitCode: Int(shellOutput.exitCode),
                log: [shellOutput.stdout, shellOutput.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
        }

        if output.exitCode != 0 {
            logger.error("Android bundle failed with exit code \(output.exitCode)")
            throw ShipItError.archiveFailed(exitCode: Int(output.exitCode), log: output.stderr)
        }

        logger.info("Android bundle succeeded for module '\(module)'")
        context.logShellOutput(output, label: "gradlew bundle")

        // Always surface the build summary at info level (not gated on --verbose) so the
        // cache-effectiveness signal is visible in CI. Best-effort: missing lines are skipped.
        logBuildSummary(from: output.stdout)

        var aabPath = parseAabPath(from: output.stdout, module: module, variant: variant)
        if let resolvedAabPath = aabPath {
            logger.info("Android AAB path: \(resolvedAabPath)")

            // Verify the AAB file actually exists on disk — Gradle may report success
            // even when no artifact is produced (e.g. UP-TO-DATE with stale cache).
            let baseDir = context.shell.workingDirectory ?? FileManager.default.currentDirectoryPath
            let anchoredPath: String
            if (resolvedAabPath as NSString).isAbsolutePath {
                anchoredPath = resolvedAabPath
            } else {
                anchoredPath = (baseDir as NSString).appendingPathComponent(resolvedAabPath)
            }
            if !FileManager.default.fileExists(atPath: anchoredPath) {
                logger.error("AAB file not found at expected path: \(anchoredPath)")
                throw ShipItError.archiveFailed(
                    exitCode: 0,
                    log:
                        "Gradle reported success but AAB was not produced at '\(anchoredPath)'. Check build variant and module configuration."
                )
            }

            // Copy the AAB to a deterministic path when --output is set, so a build job can
            // hand a stable artifact path to a separate upload job (mirrors `play-store --aab`).
            if let outputPath = options.outputPath {
                aabPath = try copyAAB(from: anchoredPath, to: outputPath, baseDir: baseDir)
            }
        }

        return Result(aabPath: aabPath, exitCode: Int(output.exitCode))
    }

    /// Copies the produced AAB to `outputPath`, creating intermediate directories and overwriting
    /// any existing file. Relative destinations are anchored to the shell working directory.
    ///
    /// - Returns: The destination path (absolute if `outputPath` was relative).
    private func copyAAB(from sourcePath: String, to outputPath: String, baseDir: String) throws -> String {
        let destination: String =
            (outputPath as NSString).isAbsolutePath
            ? outputPath
            : (baseDir as NSString).appendingPathComponent(outputPath)

        let destURL = URL(fileURLWithPath: destination)
        let fm = FileManager.default
        try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination) {
            try fm.removeItem(atPath: destination)
        }
        try fm.copyItem(atPath: sourcePath, toPath: destination)
        logger.info("Copied AAB to output path: \(destination)")
        return destination
    }

    /// Logs the highest-signal lines of a Gradle build at info level. Never throws.
    private func logBuildSummary(from stdout: String) {
        let summary = GradleBuildSummary.parse(stdout)
        if let line = summary.buildResultLine { logger.info("\(line)") }
        if let line = summary.actionableTasksLine { logger.info("\(line)") }
        if let url = summary.buildScanURL { logger.info("Build scan: \(url)") }
    }

    // MARK: - Private Helpers

    private func parseAabPath(from output: String, module: String, variant: String) -> String? {
        // Gradle output: "module/build/outputs/bundle/release/module-release.aab"
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains(".aab") && line.contains(variant) {
                let components = line.components(separatedBy: " ")
                if let aabComponent = components.first(where: { $0.hasSuffix(".aab") }) {
                    return aabComponent
                }
            }
        }
        return CrossPlatformArtifactPaths.nativeAAB(module: module, variant: variant)
    }
}
