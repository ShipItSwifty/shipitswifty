import Foundation
import OSLog
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

    /// Bump the version according to the given options.
    ///
    /// - Parameter options: Which component to bump and how.
    /// - Returns: The new version and build number strings.
    public func bump(options: VersionAction.Options) async throws -> VersionAction.Result {
        let currentVersion = try await readVersion()
        let currentBuild = try await readBuildNumber()

        logger.info("Current version: \(currentVersion), build: \(currentBuild)")

        let (newVersion, newBuild) = try await computeNewValues(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            options: options
        )

        // Write new values
        if newVersion != currentVersion {
            try await writeVersion(newVersion)
        }

        if newBuild != currentBuild {
            try await writeBuildNumber(newBuild)
        }

        logger.info("Version bumped: \(currentVersion) -> \(newVersion), build: \(currentBuild) -> \(newBuild)")
        return VersionAction.Result(version: newVersion, buildNumber: newBuild)
    }

    // MARK: - Read

    /// Read the current marketing version (`CFBundleShortVersionString`).
    public func readVersion() async throws -> String {
        // When source is "xcodeproj", read MARKETING_VERSION directly from Xcode
        // build settings. This is the canonical approach for .xcodeproj-backed
        // projects and avoids the fragile Info.plist search entirely.
        if context.config.versioningSource == "xcodeproj" {
            if let v = try await readBuildSetting("MARKETING_VERSION"), !v.isEmpty {
                return v
            }
            // MARKETING_VERSION may not be set if the project still uses a
            // legacy Info.plist variable reference; fall through to agvtool.
        }

        // Try agvtool next (works when VERSIONING_SYSTEM = apple-generic is set).
        do {
            let output = try await Command("xcrun", "agvtool", "what-marketing-version", "-terse").run(in: context.shell)
            let version = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { return version }
        } catch {
            logger.debug("agvtool what-marketing-version failed, falling back to plutil: \(error.localizedDescription)")
        }

        // Last resort: plutil on Info.plist.
        return try await readPlistValue(key: "CFBundleShortVersionString")
    }

    /// Read the current build number (`CFBundleVersion`).
    public func readBuildNumber() async throws -> String {
        if context.config.versioningSource == "xcodeproj" {
            if let v = try await readBuildSetting("CURRENT_PROJECT_VERSION"), !v.isEmpty {
                return v
            }
        }

        do {
            let output = try await Command("xcrun", "agvtool", "what-version", "-terse").run(in: context.shell)
            let build = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !build.isEmpty { return build }
        } catch {
            logger.debug("agvtool what-version failed, falling back to plutil: \(error.localizedDescription)")
        }

        return try await readPlistValue(key: "CFBundleVersion")
    }

    // MARK: - Write

    private func writeVersion(_ version: String) async throws {
        if context.config.versioningSource == "xcodeproj" {
            do {
                try await writeBuildSetting("MARKETING_VERSION", value: version)
                logger.info("Set marketing version to: \(version)")
                return
            } catch {
                logger.warning("xcodebuild set MARKETING_VERSION failed, falling back to agvtool: \(error.localizedDescription)")
            }
        }

        do {
            _ = try await Command("xcrun", "agvtool", "new-marketing-version", version).run(in: context.shell)
        } catch {
            logger.warning("agvtool failed, falling back to plutil: \(error.localizedDescription)")
            try await writePlistValue(key: "CFBundleShortVersionString", value: version)
        }
        logger.info("Set marketing version to: \(version)")
    }

    private func writeBuildNumber(_ build: String) async throws {
        if context.config.versioningSource == "xcodeproj" {
            do {
                try await writeBuildSetting("CURRENT_PROJECT_VERSION", value: build)
                logger.info("Set build number to: \(build)")
                return
            } catch {
                logger.warning("xcodebuild set CURRENT_PROJECT_VERSION failed, falling back to agvtool: \(error.localizedDescription)")
            }
        }

        do {
            _ = try await Command("xcrun", "agvtool", "new-version", "-all", build).run(in: context.shell)
        } catch {
            logger.warning("agvtool failed, falling back to plutil: \(error.localizedDescription)")
            try await writePlistValue(key: "CFBundleVersion", value: build)
        }
        logger.info("Set build number to: \(build)")
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
                let output = try await Command("git", "rev-list", "--count", "HEAD").run(in: context.shell)
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
            output = try await Command("xcodebuild", "-showBuildSettings")
                .args(extraArgs)
                .run(in: context.shell)
        } catch let ShellError.exitFailure(command, shellOutput) {
            // xcodebuild can exit non-zero (e.g. 74) when packages haven't been
            // resolved yet, when a custom TOOLCHAINS env var interferes, or when
            // the project needs a destination hint.  These are not fatal for the
            // version-reading step — log the failure and let callers fall back to
            // agvtool / plutil.
            let stderr = shellOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = stderr.isEmpty ? "(no stderr)" : stderr
            logger.warning("xcodebuild -showBuildSettings exited with status \(shellOutput.exitCode) for '\(command)'; falling back to agvtool/plutil")
            logger.warning("xcodebuild -showBuildSettings stderr: \(detail)")
            return nil
        } catch {
            logger.warning("xcodebuild -showBuildSettings failed unexpectedly: \(error.localizedDescription); falling back to agvtool/plutil")
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
            _ = try await Command("xcrun", "agvtool", "new-marketing-version", value).run(in: context.shell)
        case "CURRENT_PROJECT_VERSION":
            _ = try await Command("xcrun", "agvtool", "new-version", "-all", value).run(in: context.shell)
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
            let output = try await Command("plutil", "-extract", key, "raw", plistPath).run(in: context.shell)
            return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.debug("plutil -extract failed, falling back to NSDictionary: \(error.localizedDescription)")
        }

        // Fall back to NSDictionary parsing
        guard let dict = NSDictionary(contentsOfFile: plistPath),
              let value = dict[key] as? String else {
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
        _ = try await Command("plutil", "-replace", key, "-string", value, plistPath).run(in: context.shell)
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
}
