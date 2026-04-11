import ArgumentParser
import ShipItKit
import Foundation
import SwiftyShell

/// Diagnose common setup issues with the ShipItSwifty environment.
///
/// Runs a series of checks and prints a pass/fail table.
/// Exit code is `0` if all checks pass, `2` if any check fails.
struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose common setup issues for the selected Shipfile"
    )

    enum ASCDiagnosticsMode: Equatable {
        case required
        case optionalForLocalOnlyWorkflows
        case unknown
    }

    static let ascBackedActions: Set<String> = [
        "upload",
        "testflight",
        "metadata",
        "provision",
    ]

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )

            let shell = ShellContext()
            let formatter = makeHumanFormatter(global: global)
            let ascDiagnosticsMode = Self.ascDiagnosticsMode(for: config)

            formatter.printHeader("ShipItSwifty Doctor")

            var allPassed = true

            allPassed = await check(
                name: "Xcode installed",
                formatter: formatter
            ) {
                let output = try await Command("xcode-select", "-p").run(in: shell)
                return output.exitCode == 0
            } && allPassed

            allPassed = await check(
                name: "xcodebuild available",
                formatter: formatter
            ) {
                let output = try await Command("xcrun", "xcodebuild", "-version").run(in: shell)
                return output.exitCode == 0
            } && allPassed

            allPassed = await check(
                name: "git on PATH",
                formatter: formatter
            ) {
                let output = try await Command("git", "--version").run(in: shell)
                return output.exitCode == 0
            } && allPassed

            allPassed = await check(
                name: "security CLI available",
                formatter: formatter
            ) {
                let output = try await Command("security", "--version").run(in: shell)
                return output.exitCode == 0
            } && allPassed

            allPassed = await check(
                name: "xcrun simctl available",
                formatter: formatter
            ) {
                let output = try await Command("xcrun", "simctl", "list", "--json").run(in: shell)
                return output.exitCode == 0
            } && allPassed

            allPassed = await check(
                name: "Shipfile.yml parseable",
                formatter: formatter
            ) {
                true
            } && allPassed

            let ascCredentialsPresent = hasCompleteASCCredentials(config: config)
            switch ascDiagnosticsMode {
            case .optionalForLocalOnlyWorkflows:
                if ascCredentialsPresent {
                    formatter.printCheckmark("App Store Connect credentials present", passed: true)
                } else {
                    formatter.printWarning("App Store Connect credentials not configured (ok for local-only workflows)")
                    formatter.print("  Configured workflows only use local actions, so ASC setup can be skipped.")
                    formatter.print("  If you later add upload, testflight, metadata, or provision, set ASC_KEY_ID + ASC_ISSUER_ID + exactly one of ASC_PRIVATE_KEY or ASC_PRIVATE_KEY_PATH.")
                    formatter.print("  Find them in App Store Connect > Users and Access > Integrations > App Store Connect API")
                }
            case .required, .unknown:
                let credentialsCheckPassed = await check(
                    name: "App Store Connect credentials present",
                    formatter: formatter
                ) {
                    ascCredentialsPresent
                }
                allPassed = credentialsCheckPassed && allPassed

                if !credentialsCheckPassed {
                    printASCCredentialsGuidance(formatter: formatter)
                    if ascDiagnosticsMode == .unknown {
                        formatter.print("  No workflows clearly indicate whether ASC is optional, so doctor keeps this as a required check.")
                    }
                }
            }

            switch ascDiagnosticsMode {
            case .optionalForLocalOnlyWorkflows:
                formatter.printWarning("Skipping App Store Connect reachability check for local-only workflows")
            case .required, .unknown:
                allPassed = await check(
                    name: "Network: api.appstoreconnect.apple.com reachable",
                    formatter: formatter
                ) {
                    guard let url = URL(string: "https://api.appstoreconnect.apple.com/v1/apps") else { return false }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 5
                    let (_, response) = try await URLSession.shared.data(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    return statusCode > 0
                } && allPassed
            }

            formatter.printDivider()
            if allPassed {
                formatter.printSuccess("All doctor checks passed!")
            } else {
                formatter.printError("Some checks failed. Review the output above and fix the issues.")
                throw ExitCode(2)
            }
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }

    private func check(
        name: String,
        formatter: HumanFormatter,
        block: @escaping @Sendable () async throws -> Bool
    ) async -> Bool {
        do {
            let passed = try await block()
            if passed {
                formatter.printCheckmark(name, passed: true)
            } else {
                formatter.printCheckmark(name, passed: false)
            }
            return passed
        } catch {
            formatter.printCheckmark("\(name) [error: \(error.localizedDescription)]", passed: false)
            return false
        }
    }

    func hasCompleteASCCredentials(config: ResolvedConfig) -> Bool {
        config.ascKeyID != nil && config.ascIssuerID != nil && config.ascPrivateKeyData != nil
    }

    func printASCCredentialsGuidance(formatter: HumanFormatter) {
        formatter.printWarning("App Store Connect credentials are only required for ASC-backed actions like upload, testflight, metadata, and provision.")
        formatter.print("  If you only use build, test, archive, or export locally, you can ignore this check.")
        formatter.print("  Required values: ASC_KEY_ID + ASC_ISSUER_ID + exactly one of ASC_PRIVATE_KEY or ASC_PRIVATE_KEY_PATH")
        formatter.print("  Find them in App Store Connect > Users and Access > Integrations > App Store Connect API")
        formatter.print("  ASC_KEY_ID: the API key's Key ID")
        formatter.print("  ASC_ISSUER_ID: the page-level Issuer ID (not inside the .p8 file)")
        formatter.print("  ASC_PRIVATE_KEY / ASC_PRIVATE_KEY_PATH: the downloaded .p8 contents or file path")
    }

    static func ascDiagnosticsMode(for config: ResolvedConfig) -> ASCDiagnosticsMode {
        let actions = config.workflows.values.flatMap { workflow in
            workflow.map { $0.action.lowercased() }
        }

        guard !actions.isEmpty else {
            return .unknown
        }

        return actions.contains(where: { ascBackedActions.contains($0) })
            ? .required
            : .optionalForLocalOnlyWorkflows
    }
}
