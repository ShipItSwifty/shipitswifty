#if os(macOS)
import ArgumentParser
import Foundation
import ShipItKit

/// Code signing subcommands.
///
/// ## Usage
/// ```
/// shipit sign init --git-url git@github.com:myteam/certs.git
/// shipit sign sync --type appstore
/// shipit sign import --p12-path cert.p12 --profile-path MyApp.mobileprovision
/// shipit sign cleanup
/// ```
struct SignCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sign",
        abstract: "Code signing subcommands (init, sync, import, cleanup)",
        subcommands: [
            SignInitCommand.self,
            SignSyncCommand.self,
            SignImportCommand.self,
            SignCleanupCommand.self,
        ]
    )
}

/// Initialize the encrypted certificate repository.
struct SignInitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize an encrypted certificate repository"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Git URL of the certificate repository")
    var gitUrl: String?

    func run() async throws {
        do {
            let config = try await resolveOptionalSignConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config, verbose: global.verbose)
            let options = SignAction.Options(operation: .`init`, gitUrl: gitUrl)

            let result = try await SignAction().run(with: options, context: context)
            outputResult(
                action: "sign init", result: result, format: global.output,
                colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}

/// Sync certificates and provisioning profiles from storage.
struct SignSyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync certificates and profiles from encrypted storage"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Profile type: development | adhoc | appstore | enterprise")
    var type: String = "development"

    @Option(name: .long, help: "Git URL of the certificate repository")
    var gitUrl: String?

    func run() async throws {
        do {
            let config = try await resolveOptionalSignConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config, verbose: global.verbose)

            let options = SignAction.Options(
                operation: .sync, type: type, ci: global.ci ? true : nil, gitUrl: gitUrl)

            if global.dryRun {
                try outputDryRun(action: "sign sync", message: "Would sync \(type) certificates", global: global)
                return
            }

            let result = try await SignAction().run(with: options, context: context)
            outputResult(
                action: "sign sync", result: result, format: global.output,
                colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}

/// Import an existing certificate into encrypted storage.
struct SignImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import a .p12 certificate and .mobileprovision into storage"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Path to the .p12 certificate file")
    var p12Path: String

    @Option(name: .long, help: "Path to the .mobileprovision file")
    var profilePath: String

    @Option(name: .long, help: "Git URL of the certificate repository")
    var gitUrl: String?

    func run() async throws {
        do {
            let config = try await resolveOptionalSignConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config, verbose: global.verbose)

            let options = SignAction.Options(
                operation: .`import`,
                gitUrl: gitUrl,
                p12Path: p12Path,
                provisioningProfilePath: profilePath
            )

            let result = try await SignAction().run(with: options, context: context)
            outputResult(
                action: "sign import", result: result, format: global.output,
                colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}

/// Clean up temporary keychain and installed profiles.
struct SignCleanupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Remove temporary keychain and profiles created during sync --ci"
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        do {
            let context = try await buildFallbackActionContext(platform: global.platform ?? .ios, verbose: global.verbose)
            let options = SignAction.Options(operation: .cleanup)

            let result = try await SignAction().run(with: options, context: context)
            outputResult(
                action: "sign cleanup", result: result, format: global.output,
                colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}

private func resolveOptionalSignConfig(
    global: GlobalOptions, cliOptions: CLIOptions
) async throws
    -> ResolvedConfig
{
    let shipfilePath = configuredShipfilePath(from: global)
    if FileManager.default.fileExists(atPath: shipfilePath) {
        return try await ConfigResolver().resolve(cliOptions: cliOptions, shipfilePath: shipfilePath)
    }
    return try await ConfigResolver().resolve(
        cliOptions: cliOptions, shipfilePath: "/tmp/shipit-no-shipfile.yml")
}
#endif
