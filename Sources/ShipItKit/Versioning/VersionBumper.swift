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
        // Try agvtool first (most reliable for Xcode projects).
        // Command.run() throws ShellError.exitFailure on non-zero exit, so wrap
        // in do-catch to fall through to the plutil fallback when agvtool is
        // unavailable or fails.
        do {
            let output = try await Command("xcrun", "agvtool", "what-marketing-version", "-terse").run(in: context.shell)
            let version = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty { return version }
        } catch {
            logger.debug("agvtool what-marketing-version failed, falling back to plutil: \(error.localizedDescription)")
        }

        // Fall back to plutil on Info.plist
        return try await readPlistValue(key: "CFBundleShortVersionString")
    }

    /// Read the current build number (`CFBundleVersion`).
    public func readBuildNumber() async throws -> String {
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
        do {
            _ = try await Command("xcrun", "agvtool", "new-marketing-version", version).run(in: context.shell)
        } catch {
            logger.warning("agvtool failed, falling back to plutil: \(error.localizedDescription)")
            try await writePlistValue(key: "CFBundleShortVersionString", value: version)
        }
        logger.info("Set marketing version to: \(version)")
    }

    private func writeBuildNumber(_ build: String) async throws {
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
