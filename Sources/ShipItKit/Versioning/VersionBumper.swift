import Foundation
import Logging
import SwiftyShell

/// Reads and writes `CFBundleVersion` and `CFBundleShortVersionString`
/// using `plutil` and `xcrun agvtool`.
///
/// ## Usage
/// ```swift
/// let bumper = VersionBumper(context: context)
/// let result = try await bumper.bump(options: .init(bump: .build))
/// print("New build: \(result.buildNumber)")
/// ```
public struct VersionBumper: Sendable {
    private let context: ActionContext
    private let logger = Logger.forType(subsystem: "ShipItSwifty", VersionBumper.self)

    /// Creates a `VersionBumper` bound to the given action context.
    ///
    /// - Parameter context: Execution context providing shell and configuration.
    public init(context: ActionContext) {
        self.context = context
    }

    /// Preview what a version bump would produce without writing any files.
    ///
    /// Reads the current values, computes the new values, and returns both — identical
    /// to `bump(options:)` except no files are modified. Use this to implement dry-run
    /// previews or to validate options before committing a change.
    ///
    /// - Parameter options: Which component to bump and how.
    /// - Returns: A `Preview` containing the before and after values.
    public func preview(options: VersionAction.Options) async throws -> Preview {
        let effectiveSource = resolveVersioningSource(options: options)
        let currentVersion = try await readVersion(source: effectiveSource)
        let currentBuild = try await readBuildNumber(source: effectiveSource)

        logger.info("Preview version bump: current \(currentVersion) (\(currentBuild)), source: \(effectiveSource)")

        let (newVersion, newBuild) = try await computeNewValues(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            options: options
        )

        return Preview(
            currentVersion: currentVersion,
            currentBuildNumber: currentBuild,
            newVersion: newVersion,
            newBuildNumber: newBuild,
            source: effectiveSource
        )
    }

    /// A read-only snapshot of what `bump(options:)` would produce.
    public struct Preview: Sendable {
        /// The marketing version before the bump.
        public let currentVersion: String
        /// The build number before the bump.
        public let currentBuildNumber: String
        /// The marketing version that would be written.
        public let newVersion: String
        /// The build number that would be written.
        public let newBuildNumber: String
        /// The versioning source that would be used.
        public let source: String
    }

    /// Bump the version according to the given options.
    ///
    /// - Parameter options: Which component to bump and how.
    /// - Returns: The new version and build number strings.
    public func bump(options: VersionAction.Options) async throws -> VersionAction.Result {
        let effectiveSource = resolveVersioningSource(options: options)
        let currentVersion = try await readVersion(source: effectiveSource)
        let currentBuild = try await readBuildNumber(source: effectiveSource)

        logger.info("Current version: \(currentVersion), build: \(currentBuild) (source: \(effectiveSource))")

        let (newVersion, newBuild) = try await computeNewValues(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            options: options
        )

        // Write new values
        if newVersion != currentVersion {
            try await writeVersion(newVersion, source: effectiveSource)
        }

        if newBuild != currentBuild {
            try await writeBuildNumber(newBuild, source: effectiveSource)
        }

        logger.info("Version bumped: \(currentVersion) (\(currentBuild)) -> \(newVersion) (\(newBuild))")
        return VersionAction.Result(
            version: newVersion, buildNumber: newBuild, versionChanged: newVersion != currentVersion)
    }

    /// Resolve which versioning source to use based on options and config.
    private func resolveVersioningSource(options: VersionAction.Options) -> String {
        // Options target override takes highest priority
        if let target = options.target {
            switch target.lowercased() {
            case "source_of_truth", "project_spec":
                return "project_spec"
            case "xcodeproj":
                return "xcodeproj"
            case "kmp", "gradle_properties":
                return "kmp"
            case "gradle", "build_gradle":
                return "gradle"
            case "xcconfig", "xcconfig_file":
                return "xcconfig"
            default:
                return target
            }
        }
        return context.config.versioningSource
    }

    // MARK: - Read

    /// Read the current marketing version (`CFBundleShortVersionString`).
    public func readVersion() async throws -> String {
        try await readVersion(source: context.config.versioningSource)
    }

    /// Read the current marketing version from the specified source.
    private func readVersion(source: String) async throws -> String {
        // KMP source — read directly from gradle.properties
        if source == "kmp" {
            return try KMPVersionSource(context: context).readVersion()
        }

        // Gradle source — read directly from build.gradle.kts / build.gradle
        if source == "gradle" {
            return try GradleVersionSource(context: context).readVersion()
        }

        // xcconfig source — read directly from the .xcconfig file
        if source == "xcconfig" {
            return try XcconfigVersionSource(context: context).readVersion()
        }

        #if !os(macOS)
        throw ShipItError.invalidConfiguration(
            reason: "Version source '\(source)' requires macOS. Use versioning.source: kmp for Linux-compatible versioning."
        )
        #else

        // Project spec source — read directly from YAML
        if source == "project_spec" {
            let specSource = ProjectSpecVersionSource(context: context)
            return try specSource.readVersion()
        }

        // When source is "xcodeproj", read MARKETING_VERSION directly from Xcode
        // build settings. This is the canonical approach for .xcodeproj-backed
        // projects and avoids the fragile Info.plist search entirely.
        if source == "xcodeproj" {
            if let v = try await readBuildSetting("MARKETING_VERSION"), !v.isEmpty {
                return v
            }
            // MARKETING_VERSION may not be set if the project still uses a
            // legacy Info.plist variable reference; fall through to agvtool.
        }

        // Try agvtool next (works when VERSIONING_SYSTEM = apple-generic is set).
        do {
            let output = try await Agvtool(context: context.shell).whatMarketingVersionTerse().run()
            let version = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { return version }
        } catch {
            logger.debug("agvtool what-marketing-version failed, falling back to plutil: \(error.localizedDescription)")
        }

        // Last resort: plutil on Info.plist.
        return try await readPlistValue(key: "CFBundleShortVersionString")
        #endif
    }

    /// Read the current build number (`CFBundleVersion`).
    public func readBuildNumber() async throws -> String {
        try await readBuildNumber(source: context.config.versioningSource)
    }

    /// Read the current build number from the specified source.
    private func readBuildNumber(source: String) async throws -> String {
        if source == "kmp" {
            return try KMPVersionSource(context: context).readBuildNumber()
        }

        // Gradle source — read directly from build.gradle.kts / build.gradle
        if source == "gradle" {
            return try GradleVersionSource(context: context).readBuildNumber()
        }

        // xcconfig source — read directly from the .xcconfig file
        if source == "xcconfig" {
            return try XcconfigVersionSource(context: context).readBuildNumber()
        }

        #if !os(macOS)
        throw ShipItError.invalidConfiguration(
            reason: "Version source '\(source)' requires macOS. Use versioning.source: kmp for Linux-compatible versioning."
        )
        #else

        if source == "project_spec" {
            let specSource = ProjectSpecVersionSource(context: context)
            return try specSource.readBuildNumber()
        }

        if source == "xcodeproj" {
            if let v = try await readBuildSetting("CURRENT_PROJECT_VERSION"), !v.isEmpty {
                return v
            }
        }

        do {
            let output = try await Agvtool(context: context.shell).whatVersionTerse().run()
            let build = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !build.isEmpty { return build }
        } catch {
            logger.debug("agvtool what-version failed, falling back to plutil: \(error.localizedDescription)")
        }

        return try await readPlistValue(key: "CFBundleVersion")
        #endif
    }

    // MARK: - Write

    private func writeVersion(_ version: String, source: String) async throws {
        if source == "kmp" {
            try KMPVersionSource(context: context).writeVersion(version)
            return
        }

        if source == "gradle" {
            try GradleVersionSource(context: context).writeVersion(version)
            return
        }

        if source == "xcconfig" {
            try XcconfigVersionSource(context: context).writeVersion(version)
            return
        }

        #if !os(macOS)
        throw ShipItError.invalidConfiguration(
            reason: "Version source '\(source)' requires macOS. Use versioning.source: kmp for Linux-compatible versioning."
        )
        #else

        if source == "project_spec" {
            let specSource = ProjectSpecVersionSource(context: context)
            try specSource.writeVersion(version)
            logger.info("Set marketing version to: \(version) (project spec)")
            return
        }

        if source == "xcodeproj" {
            do {
                try await writeBuildSetting("MARKETING_VERSION", value: version)
                logger.info("Set marketing version to: \(version)")
                return
            } catch {
                logger.warning("xcodebuild set MARKETING_VERSION failed, falling back to agvtool: \(error.localizedDescription)")
            }
        }

        do {
            _ = try await Agvtool(context: context.shell).newMarketingVersion(version).run()
        } catch {
            logger.warning("agvtool failed, falling back to plutil: \(error.localizedDescription)")
            try await writePlistValue(key: "CFBundleShortVersionString", value: version)
        }
        logger.info("Set marketing version to: \(version)")
        #endif
    }

    private func writeBuildNumber(_ build: String, source: String) async throws {
        if source == "kmp" {
            try KMPVersionSource(context: context).writeBuildNumber(build)
            return
        }

        if source == "gradle" {
            try GradleVersionSource(context: context).writeBuildNumber(build)
            return
        }

        if source == "xcconfig" {
            try XcconfigVersionSource(context: context).writeBuildNumber(build)
            return
        }

        #if !os(macOS)
        throw ShipItError.invalidConfiguration(
            reason: "Version source '\(source)' requires macOS. Use versioning.source: kmp for Linux-compatible versioning."
        )
        #else

        if source == "project_spec" {
            let specSource = ProjectSpecVersionSource(context: context)
            try specSource.writeBuildNumber(build)
            logger.info("Set build number to: \(build) (project spec)")
            return
        }

        if source == "xcodeproj" {
            do {
                try await writeBuildSetting("CURRENT_PROJECT_VERSION", value: build)
                logger.info("Set build number to: \(build)")
                return
            } catch {
                logger.warning("xcodebuild set CURRENT_PROJECT_VERSION failed, falling back to agvtool: \(error.localizedDescription)")
            }
        }

        do {
            _ = try await Agvtool(context: context.shell).newVersionAll(build).run()
        } catch {
            logger.warning("agvtool failed, falling back to plutil: \(error.localizedDescription)")
            try await writePlistValue(key: "CFBundleVersion", value: build)
        }
        logger.info("Set build number to: \(build)")
        #endif
    }

    // MARK: - Compute New Values

    private func computeNewValues(
        currentVersion: String,
        currentBuild: String,
        options: VersionAction.Options
    ) async throws -> (version: String, build: String) {
        switch options.bump {
        case .build:
            let strategy = options.strategy ?? BuildNumberStrategy(rawValue: context.config.versioningStrategy) ?? .sequential
            let newBuild = try await computeNewBuildNumber(
                current: currentBuild,
                strategy: strategy
            )
            return (currentVersion, newBuild)

        case .patch:
            return (bumpSemver(currentVersion, component: .patch), currentBuild)

        case .minor:
            return (bumpSemver(currentVersion, component: .minor), currentBuild)

        case .major:
            return (bumpSemver(currentVersion, component: .major), currentBuild)

        case .set:
            let newVersion = options.version ?? currentVersion
            let newBuild = options.buildNumber ?? currentBuild
            return (newVersion, newBuild)
        }
    }

    private func computeNewBuildNumber(current: String, strategy: BuildNumberStrategy) async throws -> String {
        switch strategy {
        case .sequential:
            let current = Int(current) ?? 0
            return String(current + 1)

        case .timestamp:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMddHHmm"
            return formatter.string(from: Date())

        case .commitCount:
            do {
                let output = try await GitCLI(context: context.shell).revisionCount().run()
                return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                logger.warning("git rev-list failed, keeping current build number: \(error.localizedDescription)")
                return current
            }
        }
    }

    private enum SemverComponent {
        case major, minor, patch
    }

    private func bumpSemver(_ version: String, component: SemverComponent) -> String {
        let parts = version.components(separatedBy: ".")
        var major = Int(parts.count > 0 ? parts[0] : "0") ?? 0
        var minor = Int(parts.count > 1 ? parts[1] : "0") ?? 0
        var patch = Int(parts.count > 2 ? parts[2] : "0") ?? 0

        switch component {
        case .major:
            major += 1
            minor = 0
            patch = 0
        case .minor:
            minor += 1
            patch = 0
        case .patch:
            patch += 1
        }

        return "\(major).\(minor).\(patch)"
    }

    // MARK: - Xcode Build Settings Helpers

    #if os(macOS)
    /// Read a single build setting value using `xcodebuild -showBuildSettings`.
    ///
    /// Returns `nil` (rather than throwing) when the setting is absent **or** when
    /// `xcodebuild` exits with a non-zero status (e.g. exit 74 during package
    /// resolution or when a custom toolchain is active). Callers fall through to
    /// the agvtool / plutil strategy chain in that case.
    private func readBuildSetting(_ setting: String) async throws -> String? {
        var extraArgs: [String] = []
        if let project = context.config.appProject {
            extraArgs += ["-project", project]
        } else if let workspace = context.config.appWorkspace {
            extraArgs += ["-workspace", workspace]
        }
        if let scheme = context.config.appScheme {
            extraArgs += ["-scheme", scheme]
        }

        let output: ShellOutput
        do {
            output = try await XcodeBuild(context: context.shell)
                .trailingArgument("-showBuildSettings")
                .trailingArguments(extraArgs)
                .run()
        } catch let ShellError.exitFailure(command, shellOutput) {
            // xcodebuild can exit non-zero (e.g. 74) when packages haven't been
            // resolved yet, when a custom TOOLCHAINS env var interferes, or when
            // the project needs a destination hint.  These are not fatal for the
            // version-reading step — log the failure and let callers fall back to
            // agvtool / plutil.
            let stderr = shellOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = stderr.isEmpty ? "(no stderr)" : stderr
            logger.warning(
                "xcodebuild -showBuildSettings exited with status \(shellOutput.exitCode) for '\(command)'; falling back to agvtool/plutil")
            logger.warning("xcodebuild -showBuildSettings stderr: \(detail)")
            return nil
        } catch {
            logger.warning(
                "xcodebuild -showBuildSettings failed unexpectedly: \(error.localizedDescription); falling back to agvtool/plutil")
            return nil
        }

        // Output is one "    KEY = VALUE" pair per line.
        let prefix = "\(setting) = "
        for line in output.stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.hasPrefix(prefix) {
                let value = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Write a build setting into the .xcodeproj using `xcodebuild` xcconfig
    /// override, then commit with `plutil` on the project.pbxproj.
    ///
    /// Strategy: use `xcodebuild` with `-xcconfig` isn't viable for persistent
    /// writes. Instead we use `agvtool` for settings it understands
    /// (MARKETING_VERSION, CURRENT_PROJECT_VERSION) and let the caller fall
    /// back to agvtool/plutil when this fails.
    private func writeBuildSetting(_ setting: String, value: String) async throws {
        // Map the canonical build-setting name to the agvtool subcommand.
        switch setting {
        case "MARKETING_VERSION":
            _ = try await Agvtool(context: context.shell).newMarketingVersion(value).run()
        case "CURRENT_PROJECT_VERSION":
            _ = try await Agvtool(context: context.shell).newVersionAll(value).run()
        default:
            throw ShipItError.invalidConfiguration(reason: "No write strategy for build setting '\(setting)'")
        }
    }

    // MARK: - Plist Helpers

    private func readPlistValue(key: String) async throws -> String {
        let plistPath = findInfoPlist()
        guard let plistPath else {
            throw ShipItError.invalidConfiguration(reason: "Could not find Info.plist")
        }

        // plutil exits 0 on success; fall through to NSDictionary on failure.
        do {
            let output = try await Plutil(context: context.shell)
                .extractRaw(key: key, plistPath: plistPath)
                .run()
            return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.debug("plutil -extract failed, falling back to NSDictionary: \(error.localizedDescription)")
        }

        // Fall back to NSDictionary parsing
        guard let dict = NSDictionary(contentsOfFile: plistPath),
            let value = dict[key] as? String
        else {
            throw ShipItError.invalidConfiguration(reason: "Key '\(key)' not found in Info.plist")
        }
        return value
    }

    private func writePlistValue(key: String, value: String) async throws {
        let plistPath = findInfoPlist()
        guard let plistPath else {
            throw ShipItError.invalidConfiguration(reason: "Could not find Info.plist")
        }

        // Command.run() throws on non-zero exit; propagate plutil failures directly.
        _ = try await Plutil(context: context.shell)
            .replaceString(key: key, value: value, plistPath: plistPath)
            .run()
    }

    private func findInfoPlist() -> String? {
        // Common locations for Info.plist
        let candidates = [
            "./\(context.config.appScheme ?? "App")/Info.plist",
            "./Sources/Info.plist",
            "./Info.plist",
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        // Search in current directory
        let fm = FileManager.default
        if let enumerator = fm.enumerator(atPath: ".") {
            while let path = enumerator.nextObject() as? String {
                if path.hasSuffix("Info.plist") && !path.contains("DerivedData") {
                    return path
                }
            }
        }

        return nil
    }
    #endif
}
