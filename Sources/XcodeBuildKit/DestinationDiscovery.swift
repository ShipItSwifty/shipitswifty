#if os(macOS)
import Foundation
import OSLog
import SwiftyShell

/// A discovered xcodebuild destination for running tests.
public struct XcodebuildDestination: Codable, Sendable, Hashable {
    /// Platform identifier, e.g. `"iOS Simulator"`, `"iOS"`, `"macOS"`.
    public let platform: String
    /// Human-readable device or simulator name, e.g. `"iPhone 16 Pro"`.
    public let name: String
    /// Operating system version string, e.g. `"18.2"`.
    public let os: String?
    /// Device UDID (present for physical devices and booted simulators).
    public let udid: String?
    /// Whether this is a simulator (`true`) or a physical device (`false`).
    public var isSimulator: Bool { platform.contains("Simulator") }

    /// The full xcodebuild `-destination` string for this destination.
    public var destinationString: String {
        var parts = ["platform=\(platform)", "name=\(name)"]
        if let os {
            parts.append("OS=\(os)")
        }
        return parts.joined(separator: ",")
    }

    public init(platform: String, name: String, os: String? = nil, udid: String? = nil) {
        self.platform = platform
        self.name = name
        self.os = os
        self.udid = udid
    }
}

/// Discovers available xcodebuild destinations for a given scheme and Xcode container.
///
/// Uses `xcodebuild -showdestinations` to enumerate all destinations that are valid
/// for the specified scheme. The output is parsed into typed `XcodebuildDestination`
/// values that can be presented to the user or saved into workflow config.
///
/// ## Usage
/// ```swift
/// let discoverer = DestinationDiscovery(shell: context.shell)
/// let destinations = try await discoverer.availableDestinations(
///     scheme: "MyApp",
///     workspace: "MyApp.xcworkspace"
/// )
/// let simulators = destinations.filter(\.isSimulator)
/// ```
public struct DestinationDiscovery: Sendable {
    private let shell: ShellContext
    private let logger = Logger(subsystem: "XcodeBuildKit", category: "DestinationDiscovery")

    public init(shell: ShellContext) {
        self.shell = shell
    }

    /// Returns all available destinations for the given scheme and Xcode container.
    ///
    /// - Parameters:
    ///   - scheme: The Xcode scheme to query destinations for.
    ///   - workspace: Path to the `.xcworkspace` (preferred when present).
    ///   - project: Path to the `.xcodeproj` (used when no workspace is given).
    /// - Returns: Array of available destinations, sorted simulators first then devices.
    /// - Throws: `ShipItError` when xcodebuild cannot be invoked.
    public func availableDestinations(
        scheme: String,
        workspace: String? = nil,
        project: String? = nil
    ) async throws -> [XcodebuildDestination] {
        logger.info("Discovering destinations for scheme '\(scheme)'")

        var xcodeBuild = XcodeBuild(context: shell)
            .option(.scheme(scheme))
            .option(.showDestinations)
            .trailingArgument("-quiet")

        if let workspace {
            xcodeBuild = xcodeBuild.option(.workspace(workspace))
        } else if let project {
            xcodeBuild = xcodeBuild.option(.project(project))
        }

        let output: ShellOutput
        do {
            output = try await xcodeBuild.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            // xcodebuild -showdestinations exits non-zero on some Xcode versions even
            // when it successfully lists destinations; try to parse whatever we got.
            let combined = [shellOutput.stdout, shellOutput.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let parsed = parseDestinations(from: combined)
            if !parsed.isEmpty {
                logger.info("Parsed \(parsed.count) destination(s) from non-zero exit output")
                return parsed
            }
            logger.error("xcodebuild -showdestinations failed: \(combined)")
            return []
        }

        let combined = [output.stdout, output.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let destinations = parseDestinations(from: combined)
        logger.info("Found \(destinations.count) destination(s) for scheme '\(scheme)'")
        return destinations
    }

    // MARK: - Parsing

    /// Parses `xcodebuild -showdestinations` output into typed destination values.
    ///
    /// The output format is a series of lines like:
    /// ```
    ///     { platform:iOS Simulator, id:..., OS:18.2, name:iPhone 16 Pro }
    ///     { platform:iOS, id:..., name:My iPhone }
    /// ```
    /// Each `{ ... }` block represents one destination.
    func parseDestinations(from output: String) -> [XcodebuildDestination] {
        var destinations: [XcodebuildDestination] = []

        // Match each { ... } destination block (may span one line)
        // xcodebuild writes them one per line in the form:
        //   { platform:iOS Simulator, id:..., OS:18.2, name:iPhone 16 Pro }
        let blockPattern = #"\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: blockPattern) else {
            return []
        }

        let range = NSRange(output.startIndex..., in: output)
        let matches = regex.matches(in: output, range: range)

        for match in matches {
            guard let matchRange = Range(match.range(at: 1), in: output) else { continue }
            let block = String(output[matchRange])
            if let destination = parseBlock(block) {
                destinations.append(destination)
            }
        }

        // Simulators first, then physical devices, both sorted by name
        return destinations.sorted { lhs, rhs in
            if lhs.isSimulator != rhs.isSimulator { return lhs.isSimulator }
            return lhs.name < rhs.name
        }
    }

    /// Parses a single `key:value, key:value` block into an `XcodebuildDestination`.
    private func parseBlock(_ block: String) -> XcodebuildDestination? {
        // Split on ", " but be careful: values themselves may contain spaces.
        // Keys are: platform, id, OS, name, error (invalid destinations)
        // Strategy: split on ", <known-key>:" boundaries.
        var kvPairs: [String: String] = [:]
        let knownKeys = ["platform", "id", "OS", "name", "variant", "arch", "error"]

        // Build a pattern that splits on ", <knownKey>:"
        let keyAlternation = knownKeys.joined(separator: "|")
        let splitPattern = ",\\s*(?=\(keyAlternation):)"
        guard let splitRegex = try? NSRegularExpression(pattern: splitPattern) else { return nil }

        let nsBlock = block as NSString
        let splitRanges = splitRegex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length))

        var segments: [String] = []
        var lastEnd = block.startIndex
        for match in splitRanges {
            guard let range = Range(match.range, in: block) else { continue }
            segments.append(String(block[lastEnd..<range.lowerBound]))
            lastEnd = range.upperBound
        }
        segments.append(String(block[lastEnd...]))

        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            kvPairs[key] = value
        }

        guard let platform = kvPairs["platform"], !platform.isEmpty,
            let name = kvPairs["name"], !name.isEmpty
        else { return nil }

        // Skip destinations that have an error marker (invalid/unavailable)
        if kvPairs["error"] != nil { return nil }

        return XcodebuildDestination(
            platform: platform,
            name: name,
            os: kvPairs["OS"],
            udid: kvPairs["id"]
        )
    }
}
#endif
