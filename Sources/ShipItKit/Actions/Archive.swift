import FlutterKit
import Foundation
import GradleKit
import Logging
import MobileBuild
import MobileCore
import ReactNativeKit
import SwiftyShell
import XcodeBuildKit

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
        let buildSystem: AppFramework =
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
            let flutter = Flutter(context: context.shell).buildIPA(flavor: flavor)
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
            let flutter = Flutter(context: context.shell).buildAppBundle(flavor: flavor)
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
        let task = GradleTask.bundle(variant: variant).name
        logger.info("Archiving React Native Android app (npx react-native build-android --mode=\(variant) --tasks \(task))")

        let rn = ReactNative(context: context.shell).buildAndroid(mode: variant, task: task)

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
        let module = context.reactNativeAndroidModule
        let variant = options.buildVariant ?? context.config.androidBuildVariant
        let task: GradleTask = variant.lowercased() == "debug" ? .bundleDebug : .bundleRelease

        let outcome = try await context.runReactNativeGradleTask(
            task.qualified(module: module),
            extraProperties: options.gradleProperties,
            failed: { exitCode, log in .archiveFailed(exitCode: exitCode, log: log) }
        )

        // `aabPath` is already RN-root-relative (it's prefixed with "android/" by
        // `CrossPlatformArtifactPaths.reactNativeAAB`), so it anchors against the shell's
        // working directory (the RN project root), not the Gradle project directory the
        // build actually ran in.
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

        return Result(aabPath: aabPath, exitCode: Int(outcome.output.exitCode))
    }

    private func anchoredGradleArtifactPath(_ path: String, projectDir: String, context: ActionContext) -> String {
        if (path as NSString).isAbsolutePath { return path }

        let shellDir = context.shell.workingDirectory ?? FileManager.default.currentDirectoryPath
        let anchoredProjectDir =
            (projectDir as NSString).isAbsolutePath
            ? projectDir
            : (shellDir as NSString).appendingPathComponent(projectDir)
        return (anchoredProjectDir as NSString).appendingPathComponent(path)
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

        var buildSettings: [String: String] = [:]
        var additionalOptions: [XcodeBuildOption] = []
        if context.config.automaticCodeSigning {
            additionalOptions = [.allowProvisioningUpdates] + (ascAuth?.options ?? [])
            if let teamID = context.config.teamID { buildSettings["DEVELOPMENT_TEAM"] = teamID }
        }
        // Explicit xcargs win over the team ID.
        buildSettings.merge(context.config.xcargs) { _, explicit in explicit }

        let container: XcodeContainer?
        if let workspace = context.config.appWorkspace {
            container = .workspace(workspace)
        } else if let project = context.config.appProject {
            container = .project(project)
        } else {
            container = nil
        }

        let request = XcodeBuildRequest(
            container: container,
            scheme: scheme,
            configuration: configuration,
            derivedDataPath: context.config.derivedDataPath,
            buildSettings: buildSettings,
            additionalOptions: additionalOptions
        )

        let attempt = makeArchiveAttempt(request: request, archivePath: archivePath, context: context)
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
        request: XcodeBuildRequest,
        archivePath: String,
        context: ActionContext
    ) -> @Sendable () async throws -> Result {
        { [logger] in
            let outcome = try await mappingBuildFailures(
                { exitCode, log in
                    logger.error("Archive failed with exit code \(exitCode)")
                    return .archiveFailed(exitCode: exitCode, log: log)
                },
                {
                    try await XcodeBuilder(shell: context.shell, output: context.buildOutput)
                        .archive(request, archivePath: archivePath)
                })
            logger.info("Archive succeeded: \(archivePath)")
            if let line = outcome.resultLine { logger.info("\(line)") }
            if outcome.warnings > 0 || outcome.errors > 0 {
                logger.info("\(outcome.warnings) warning(s), \(outcome.errors) error(s)")
            }
            return Result(archivePath: archivePath, exitCode: Int(outcome.output.exitCode))
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
        let task = GradleTask.variantTask(prefix: "bundle", flavor: flavor, variant: variant)

        // Qualify based on scope
        let scopedTask: GradleTask
        switch scope {
        case .root:
            scopedTask = task
        case .module:
            scopedTask = task.qualified(module: module)
        }

        logger.info("Bundling Android module '\(module)' with task '\(scopedTask.name)'")

        let outcome = try await mappingBuildFailures(
            { exitCode, log in
                logger.error("Android bundle failed with exit code \(exitCode)")
                return .archiveFailed(exitCode: exitCode, log: log)
            },
            {
                try await context.gradleBuilder().run(
                    [scopedTask],
                    in: context.gradleProject(extraProperties: options.gradleProperties),
                    modules: scope == .module ? [module] : [])
            })

        logger.info("Android bundle succeeded for module '\(module)'")
        // Output already streamed live via the build output policy — no debug re-dump.

        // Always surface the build summary at info level (not gated on --verbose) so the
        // cache-effectiveness signal is visible in CI. Best-effort: missing lines are skipped.
        logBuildSummary(from: outcome.output.stdout)

        var aabPath = recordedAAB(from: outcome, module: module)
        if let resolvedAabPath = aabPath {
            logger.info("Android AAB path: \(resolvedAabPath)")

            // Verify the AAB file actually exists on disk — Gradle may report success
            // even when no artifact is produced (e.g. UP-TO-DATE with stale cache).
            let baseDir = context.shell.workingDirectory ?? FileManager.default.currentDirectoryPath
            let anchoredPath = anchoredGradleArtifactPath(
                resolvedAabPath, projectDir: context.config.gradleProjectDir, context: context)
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

        return Result(aabPath: aabPath, exitCode: Int(outcome.output.exitCode))
    }

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

    /// The bundle Gradle recorded for `module`, including a task's cached outputs.
    private func recordedAAB(from outcome: BuildOutcome, module: String) -> String? {
        let bundles = outcome.artifacts(.aab)
        let moduleDirectory = "/" + module.replacingOccurrences(of: ":", with: "/") + "/build/outputs/"
        return bundles.first { $0.contains(moduleDirectory) } ?? bundles.first
    }
}
