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

    /// Top-level subcommands that always mutate local state (SDK, emulators, projects).
    private static let mutatingCommands: Set<String> = ["install", "update", "run", "init"]

    /// Top-level subcommands where only some operations mutate local state.
    /// Value is the set of mutating second-level operations; any other operation is read-only.
    private static let conditionallyMutatingCommands: [String: Set<String>] = [
        "emulator": ["create", "start", "stop", "remove"],
        "sdk": ["install", "update", "remove"],
        "skills": ["add", "remove"],
    ]

    @Option(name: .long, help: "Path to config file. Defaults to ./Shipfile.yml when present")
    var shipfile: String = "./Shipfile.yml"

    @Option(name: .customLong("android-path"), help: "AndroidCLI executable name or path")
    var androidPath: String?

    @Option(name: .long, help: "Android SDK path forwarded through AndroidCLI --sdk")
    var sdk: String?

    @Option(name: .long, help: "Output format: human | json")
    var output: OutputFormat = .human

    @Flag(name: .long, help: "Print the command without executing it")
    var dryRun = false

    @Flag(name: .long, help: "Confirm commands that mutate local SDK, emulator, or project state")
    var allowMutation = false

    @Argument(parsing: .captureForPassthrough, help: "AndroidCLI command and arguments")
    var arguments: [String] = []

    static func isMutating(_ arguments: [String]) -> Bool {
        guard let head = arguments.first else { return false }
        if head == "create" {
            return !arguments.contains("--list")
        }
        if mutatingCommands.contains(head) {
            return true
        }
        if let mutatingOperations = conditionallyMutatingCommands[head] {
            guard let operation = arguments.dropFirst().first else { return true }
            return mutatingOperations.contains(operation)
        }
        return false
    }

    func run() async throws {
        guard !arguments.isEmpty else {
            throw ValidationError("Provide an AndroidCLI command. Run `shipit android-cli --help` for examples.")
        }
        if arguments.starts(with: ["screen", "capture"]),
            !arguments.contains(where: { $0 == "-o" || $0.hasPrefix("--output") })
        {
            throw ValidationError("`screen capture` requires --output through ShipIt to avoid writing binary PNG data to formatted stdout.")
        }
        if Self.isMutating(arguments), !allowMutation {
            throw ValidationError(
                "This AndroidCLI command may mutate local SDK, emulator, or project state. Rerun with --allow-mutation to confirm.")
        }

        let androidCLIConfig = try await resolveAndroidCLIConfig()
        let resolvedAndroidPath = androidPath ?? androidCLIConfig?.executablePath ?? "android"
        let resolvedSDK = sdk ?? androidCLIConfig?.sdkPath

        if dryRun {
            print(([resolvedAndroidPath] + (resolvedSDK.map { ["--sdk=\($0)"] } ?? []) + arguments).joined(separator: " "))
            return
        }

        let result = try await AndroidCLI(executablePath: resolvedAndroidPath, sdkPath: resolvedSDK)
            .rawArguments(arguments)
            .run()
        switch output {
        case .human:
            if !result.stdout.isEmpty { print(result.stdout, terminator: result.stdout.hasSuffix("\n") ? "" : "\n") }
            if !result.stderr.isEmpty { FileHandle.standardError.write(Data(result.stderr.utf8)) }
            if result.exitCode != 0 { throw ExitCode(result.exitCode) }
        case .json:
            let reporter = JSONReporter()
            print(
                try reporter.encode(
                    ActionResultEnvelope(
                        action: "android-cli",
                        status: result.exitCode == 0 ? "success" : "failure",
                        payload: .object([
                            "arguments": .array(arguments.map(JSONValue.string)),
                            "stdout": .string(result.stdout),
                            "stderr": .string(result.stderr),
                            "exitCode": .int(Int(result.exitCode)),
                        ])
                    )))
            if result.exitCode != 0 { throw ExitCode(result.exitCode) }
        }
    }

    private func resolveAndroidCLIConfig() async throws -> AndroidCLIConfig? {
        let shipfilePath = URL(fileURLWithPath: shipfile).path
        guard FileManager.default.fileExists(atPath: shipfilePath) else { return nil }
        let config = try await ConfigResolver().resolve(cliOptions: CLIOptions(), shipfilePath: shipfilePath)
        return config.androidCLI
    }
}
