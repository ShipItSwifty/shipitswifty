import Foundation
import OSLog
import SwiftyShell

/// Parses iOS code coverage data from an `.xcresult` bundle using `xcrun xccov`.
///
/// ShipIt calls the Apple-native `xccov` tool (bundled with Xcode) to read
/// coverage from an existing `.xcresult`. No third-party tooling required.
///
/// `xccov view --report --json <path>` produces a stable JSON structure that
/// this parser decodes into typed ``CoverageTarget`` values.
struct IOSCoverageParser: Sendable {

    let shell: ShellContext
    let logger: Logger

    // MARK: - Parse

    /// Parse all targets from the given `.xcresult` bundle.
    ///
    /// - Parameter xcresultPath: Absolute or project-relative path to the bundle.
    /// - Returns: Array of ``CoverageTarget`` values (unsorted, unfiltered).
    /// - Throws: ``ShipItError/invalidConfiguration(reason:)`` when xccov returns an error;
    ///           ``ShipItError/missingTool(name:)`` if `xcrun` is not on PATH.
    func parse(xcresultPath: String) async throws -> [CoverageTarget] {
        logger.debug("Running xccov view --report --json on \(xcresultPath)")

        let output = try await runXccov(xcresultPath: xcresultPath)

        guard output.exitCode == 0 else {
            logger.error("xccov exited \(output.exitCode): \(output.stderr)")
            throw ShipItError.invalidConfiguration(
                reason: "xccov failed (exit \(output.exitCode)): \(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }

        return try decodeXccovReport(json: output.stdout)
    }

    // MARK: - Shell

    private func runXccov(xcresultPath: String) async throws -> ShellOutput {
        // xcrun xccov view --report --json <path>
        let cmd = Command("xcrun")
            .arg("xccov")
            .arg("view")
            .arg("--report")
            .arg("--json")
            .arg(xcresultPath)
            .stdout(.capture)
            .stderr(.capture)

        do {
            return try await cmd.run(in: shell)
        } catch let ShellError.commandNotFound(name) {
            throw ShipItError.missingTool(name: name)
        } catch let ShellError.exitFailure(_, output) {
            return output
        }
    }

    // MARK: - Decode

    /// Decode the JSON object produced by `xccov view --report --json`.
    ///
    /// The top-level structure is:
    /// ```json
    /// {
    ///   "targets": [
    ///     {
    ///       "name": "MyApp.app",
    ///       "lineCoverage": 0.784,
    ///       "coveredLines": 1240,
    ///       "executableLines": 1580,
    ///       "files": [
    ///         { "name": "MyFile.swift", "path": "/path/to/file.swift",
    ///           "lineCoverage": 0.9, "coveredLines": 45, "executableLines": 50,
    ///           "functions": [...] }
    ///       ]
    ///     }
    ///   ]
    /// }
    /// ```
    private func decodeXccovReport(json: String) throws -> [CoverageTarget] {
        guard let data = json.data(using: .utf8) else {
            throw ShipItError.invalidConfiguration(reason: "xccov output is not valid UTF-8")
        }

        let root: XccovRoot
        do {
            root = try JSONDecoder().decode(XccovRoot.self, from: data)
        } catch {
            throw ShipItError.invalidConfiguration(
                reason: "Failed to decode xccov JSON output: \(error.localizedDescription). " +
                "Run `xcrun xccov view --report --json <path>` manually to inspect the output."
            )
        }

        return root.targets.map { target in
            CoverageTarget(
                name: cleanTargetName(target.name),
                lineCoverage: (target.lineCoverage * 100.0).rounded(toDecimalPlaces: 1),
                coveredLines: target.coveredLines,
                executableLines: target.executableLines,
                files: target.files?.map { file in
                    CoverageFile(
                        path: file.path,
                        lineCoverage: (file.lineCoverage * 100.0).rounded(toDecimalPlaces: 1),
                        coveredLines: file.coveredLines,
                        executableLines: file.executableLines
                    )
                } ?? []
            )
        }
    }

    /// Strip `.app`, `.framework`, `.xctest` suffixes from xccov target names.
    private func cleanTargetName(_ raw: String) -> String {
        let suffixes = [".app", ".framework", ".xctest", ".appex"]
        for suffix in suffixes {
            if raw.hasSuffix(suffix) {
                return String(raw.dropLast(suffix.count))
            }
        }
        return raw
    }
}

// MARK: - Decodable Models

private struct XccovRoot: Decodable {
    let targets: [XccovTarget]
}

private struct XccovTarget: Decodable {
    let name: String
    let lineCoverage: Double
    let coveredLines: Int
    let executableLines: Int
    let files: [XccovFile]?
}

private struct XccovFile: Decodable {
    let name: String
    let path: String
    let lineCoverage: Double
    let coveredLines: Int
    let executableLines: Int
}

// MARK: - Double helper

private extension Double {
    func rounded(toDecimalPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
