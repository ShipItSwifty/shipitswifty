import Foundation
import SwiftyShell

/// The JavaScript/Node.js package manager to use for running scripts.
///
/// Detected automatically from lockfiles in the project directory. The detection
/// order (pnpm → yarn → npm) matches standard convention — more specific lockfiles
/// take priority over the generic `package-lock.json`.
public enum JSPackageManager: String, Sendable, CaseIterable {
    /// pnpm — detected from `pnpm-lock.yaml`.
    case pnpm
    /// Yarn — detected from `yarn.lock`.
    case yarn
    /// npm — detected from `package-lock.json` or as the fallback.
    case npm

    /// Auto-detects the package manager from lockfiles in the given directory.
    ///
    /// Detection order: `pnpm-lock.yaml` → `yarn.lock` → `package-lock.json` → `.npm` fallback.
    ///
    /// - Parameters:
    ///   - root: Directory to inspect. Defaults to the current working directory.
    ///   - fileManager: `FileManager` instance (injectable for testing).
    /// - Returns: The detected package manager, or `.npm` when no lockfile is found.
    public static func detect(
        in root: String = ".",
        fileManager: FileManager = .default
    ) -> JSPackageManager {
        let url = URL(fileURLWithPath: root)
        if fileManager.fileExists(atPath: url.appendingPathComponent("pnpm-lock.yaml").path) {
            return .pnpm
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent("yarn.lock").path) {
            return .yarn
        }
        return .npm
    }

    /// The base command used to run scripts (`pnpm`, `yarn`, or `npm`).
    public var runCommand: String {
        rawValue
    }

    /// Returns the arguments to run a named script (e.g. `["run", "test"]`).
    ///
    /// - Parameter script: The script name from `package.json` `scripts:`.
    public func scriptArguments(for script: String) -> [String] {
        ["run", script]
    }
}

/// Runs a named script from `package.json` using the detected package manager.
///
/// Validates that the script exists before invoking the package manager.
///
/// ## Usage
/// ```swift
/// let runner = JSScriptRunner(context: context.shell, projectRoot: ".")
/// let output = try await runner.run(script: "test")
/// ```
public struct JSScriptRunner: Sendable {
    private let shell: ShellContext
    private let projectRoot: String
    private let packageManager: JSPackageManager

    /// Creates a `JSScriptRunner` using the auto-detected package manager.
    ///
    /// - Parameters:
    ///   - context: Shell context used to execute commands.
    ///   - projectRoot: Directory containing `package.json`.
    ///   - fileManager: `FileManager` instance (injectable for testing).
    public init(
        context: ShellContext,
        projectRoot: String = ".",
        fileManager: FileManager = .default
    ) {
        self.shell = context
        self.projectRoot = projectRoot
        self.packageManager = JSPackageManager.detect(in: projectRoot, fileManager: fileManager)
    }

    /// Creates a `JSScriptRunner` with an explicit package manager (for testing).
    ///
    /// - Parameters:
    ///   - context: Shell context used to execute commands.
    ///   - projectRoot: Directory containing `package.json`.
    ///   - packageManager: Package manager to use.
    public init(context: ShellContext, projectRoot: String, packageManager: JSPackageManager) {
        self.shell = context
        self.projectRoot = projectRoot
        self.packageManager = packageManager
    }

    /// The resolved package manager for this runner.
    public var resolvedPackageManager: JSPackageManager { packageManager }

    /// Runs a named script from `package.json`.
    ///
    /// Validates that the script exists in `package.json` before invoking the package
    /// manager. Throws ``ShipItError/invalidConfiguration(reason:)`` when the script is
    /// absent, giving clear guidance for cross-platform projects where test/lint scripts
    /// may not be defined.
    ///
    /// - Parameter script: The script name (e.g. `"test"`, `"lint"`).
    /// - Returns: Shell output from the script run.
    /// - Throws: ``ShipItError/invalidConfiguration(reason:)`` if the script is not
    ///   declared in `package.json`.
    ///   ``ShipItError/buildFailed(exitCode:log:)`` if the script exits non-zero.
    @discardableResult
    public func run(script: String) async throws -> ShellOutput {
        // Validate that the script exists in package.json before invoking
        guard packageJSONHasScript(named: script) else {
            throw ShipItError.invalidConfiguration(
                reason:
                    "No '\(script)' script found in package.json. "
                    + "Add a '\(script)' script entry to package.json, or skip this step."
            )
        }

        let args = packageManager.scriptArguments(for: script)
        let command = Command(packageManager.runCommand)
            .args(args)
            .workingDirectory(projectRoot)
            .stdout(.capture)
            .stderr(.capture)

        let output: ShellOutput
        do {
            output = try await command.run(in: shell)
        } catch let ShellError.exitFailure(_, shellOutput) {
            throw ShipItError.buildFailed(
                exitCode: Int(shellOutput.exitCode),
                log: [shellOutput.stdout, shellOutput.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
        }

        if output.exitCode != 0 {
            throw ShipItError.buildFailed(
                exitCode: Int(output.exitCode),
                log: [output.stdout, output.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
        }

        return output
    }

    // MARK: - Private Helpers

    private func packageJSONHasScript(named name: String) -> Bool {
        let url = URL(fileURLWithPath: projectRoot).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = json["scripts"] as? [String: Any]
        else {
            // If we cannot read package.json, allow the script to run and let the
            // package manager emit its own error.
            return true
        }
        return scripts[name] != nil
    }
}
