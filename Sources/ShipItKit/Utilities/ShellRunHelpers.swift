import Foundation
import SwiftyShell

/// Shared helpers that reduce boilerplate when running shell commands and mapping
/// failures to ``ShipItError`` cases.
enum ShellRunHelpers {

    /// Runs a `RunnableCommandFamily` command, catching `ShellError.exitFailure` and
    /// mapping it (and non-zero exit codes) to the supplied `mapError` closure.
    ///
    /// This eliminates the duplicated `do { output = try await … } catch let ShellError.exitFailure …`
    /// pattern that appears throughout the action layer.
    ///
    /// - Parameters:
    ///   - command: A configured `RunnableCommandFamily` ready to execute.
    ///   - mapError: Converts an `(exitCode: Int, log: String)` pair into a ``ShipItError``.
    /// - Returns: The successful `ShellOutput`.
    /// - Throws: Whatever ``ShipItError`` the `mapError` closure produces on failure.
    static func run<C: RunnableCommandFamily>(
        _ command: C,
        mapError: (_ exitCode: Int, _ log: String) -> ShipItError
    ) async throws -> ShellOutput {
        let output: ShellOutput
        do {
            output = try await command.run()
        } catch let ShellError.exitFailure(_, shellOutput) {
            let log = combinedLog(shellOutput)
            throw mapError(Int(shellOutput.exitCode), log)
        }

        if output.exitCode != 0 {
            let log = combinedLog(output)
            throw mapError(Int(output.exitCode), log)
        }

        return output
    }

    /// Combines stdout and stderr into a single log string, dropping empty parts.
    static func combinedLog(_ output: ShellOutput) -> String {
        [output.stdout, output.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
