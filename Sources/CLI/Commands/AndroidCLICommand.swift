import AndroidCLIKit
import ArgumentParser
import Foundation
import ShipItKit

/// Mirrors Google's AndroidCLI while retaining ShipIt's output and dry-run conventions.
struct AndroidCLICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "android-cli",
        abstract: "Run Google's AndroidCLI through ShipItSwifty",
        discussion: """
            Mirrors: create, describe, docs, emulator, info, init, install, layout,
            run, screen, sdk, skills, studio, update, help, and --version.

            Examples:
              shipit android-cli emulator list
              shipit android-cli layout --pretty
              shipit android-cli skills list --long
            """)

    @Option(name: .customLong("android-path"), help: "AndroidCLI executable name or path")
    var androidPath: String = "android"

    @Option(name: .long, help: "Android SDK path forwarded through AndroidCLI --sdk")
    var sdk: String?

    @Option(name: .long, help: "Output format: human | json")
    var output: OutputFormat = .human

    @Flag(name: .long, help: "Print the command without executing it")
    var dryRun = false

    @Argument(parsing: .captureForPassthrough, help: "AndroidCLI command and arguments")
    var arguments: [String] = []

    func run() async throws {
        guard !arguments.isEmpty else {
            throw ValidationError("Provide an AndroidCLI command. Run `shipit android-cli --help` for examples.")
        }
        if arguments.starts(with: ["screen", "capture"]),
            !arguments.contains(where: { $0 == "-o" || $0.hasPrefix("--output") })
        {
            throw ValidationError("`screen capture` requires --output through ShipIt to avoid writing binary PNG data to formatted stdout.")
        }

        if dryRun {
            print(([androidPath] + (sdk.map { ["--sdk=\($0)"] } ?? []) + arguments).joined(separator: " "))
            return
        }

        let result = try await AndroidCLI(executablePath: androidPath, sdkPath: sdk)
            .rawArguments(arguments)
            .run()
        switch output {
        case .human:
            if !result.stdout.isEmpty { print(result.stdout, terminator: result.stdout.hasSuffix("\n") ? "" : "\n") }
            if !result.stderr.isEmpty { FileHandle.standardError.write(Data(result.stderr.utf8)) }
        case .json:
            let reporter = JSONReporter()
            print(try reporter.encode(ActionResultEnvelope(
                action: "android-cli",
                status: result.exitCode == 0 ? "success" : "failure",
                payload: .object([
                    "arguments": .array(arguments.map(JSONValue.string)),
                    "stdout": .string(result.stdout),
                    "stderr": .string(result.stderr),
                    "exitCode": .int(Int(result.exitCode)),
                ])
            )))
        }
    }
}
