import Foundation
import Logging
import MobileBuild
import MobileCore
import MobileTesting
import SwiftyShell

/// Runs a JavaScript project's `package.json` scripts with the project's own package manager
/// (MobileBuild's `JavaScriptProject`), adding ShipIt's evidence recording and error contract.
///
/// ## Usage
/// ```swift
/// try await JSScriptRunner(context: context.shell, projectRoot: ".").run(script: "lint")
/// ```
public struct JSScriptRunner: Sendable {
    private let project: JavaScriptProject
    private let logger = Logger.forType(subsystem: "ShipItSwifty", JSScriptRunner.self)

    public init(context: ShellContext, projectRoot: String = ".", packageManager: JSPackageManager? = nil) {
        self.project = JavaScriptProject(root: projectRoot, shell: context, packageManager: packageManager)
    }

    /// The package manager the project's lockfile selects (`pnpm`, `yarn`, `bun`, else `npm`).
    public var resolvedPackageManager: JSPackageManager { project.packageManager }

    /// Whether the script invokes Jest.
    public func scriptUsesJest(_ script: String) -> Bool {
        project.scriptUsesJest(script)
    }

    /// Runs `script` with `arguments`, installing dependencies first when `node_modules` is missing.
    ///
    /// - Throws: ``ShipItError/invalidConfiguration(reason:)`` when `package.json` has no such
    ///   script; ``ShipItError/buildFailed(exitCode:log:)`` when installing fails, or when the
    ///   script fails and `failOnNonZeroExit` is set.
    @discardableResult
    public func run(
        script: String, arguments: [String] = [], evidence: TestEvidenceRecorder? = nil, reason: String = "initial",
        failOnNonZeroExit: Bool = true
    ) async throws -> ShellOutput {
        let output: ShellOutput
        do {
            output = try await project.run(script: script, arguments: arguments)
        } catch MobileKitError.notFound {
            throw ShipItError.invalidConfiguration(
                reason: "No '\(script)' script found in package.json. Add a '\(script)' script entry to package.json, or skip this step.")
        } catch MobileKitError.commandFailed(_, let exitCode, let log) {
            logger.error("JavaScript dependency install failed", metadata: ["exitCode": "\(exitCode)"])
            throw ShipItError.buildFailed(exitCode: Int(exitCode), log: log)
        }
        if let evidence {
            // Evidence never changes the outcome: if it cannot be saved, the run still stands.
            if let (index, directory) = try? await evidence.allocate() {
                let path = arguments.firstIndex(of: "--outputFile").flatMap { index in
                    index + 1 < arguments.count ? arguments[index + 1] : nil
                }
                var run: ParsedTestRun?
                var parseFailure: String?
                if let path {
                    do { run = try await JestJSONTestParser().parse(jsonFilePath: path, framework: .reactNative) } catch {
                        parseFailure = String(describing: error)
                    }
                    if run == nil && parseFailure == nil { parseFailure = "no Jest results were written" }
                }
                let command = [project.packageManager.rawValue, "run", script] + (arguments.isEmpty ? [] : ["--"] + arguments)
                try? await evidence.record(
                    run, index: index, directory: directory, output: output, arguments: Array(command.dropFirst()), reason: reason,
                    parseFailure: parseFailure)
                if let path, FileManager.default.fileExists(atPath: path) {
                    try? FileManager.default.copyItem(atPath: path, toPath: directory.appendingPathComponent("jest.json").path)
                }
            }
        }
        if output.exitCode != 0, failOnNonZeroExit {
            throw ShipItError.buildFailed(
                exitCode: Int(output.exitCode), log: [output.stdout, output.stderr].filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        return output
    }
}
