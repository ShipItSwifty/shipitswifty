import ArgumentParser
import ShipItKit

/// Manage App IDs, devices, and provisioning profiles.
struct ProvisionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "provision",
        abstract: "Manage App IDs, devices, and provisioning profiles"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Operation: create-app-id | register-devices | list-devices | list-bundle-ids")
    var operation: String = "list-bundle-ids"

    @Option(name: .long, help: "Bundle ID to create")
    var bundleId: String?

    @Option(name: .long, help: "App name for new bundle ID")
    var appName: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Device UDIDs to register")
    var deviceUdids: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Device names for registration")
    var deviceNames: [String] = []

    func run() async throws {
        do {
            let config = try await resolveRequiredConfig(
                global: global,
                cliOptions: CLIOptions(ci: global.ci, dryRun: global.dryRun, platform: global.platform)
            )
            let context = try await buildActionContext(config: config)

            let opMap: [String: ProvisionAction.ProvisionOperation] = [
                "create-app-id": .createAppId,
                "register-devices": .registerDevices,
                "list-devices": .listDevices,
                "list-bundle-ids": .listBundleIds,
            ]

            guard let op = opMap[operation] else {
                throw ShipItError.invalidConfiguration(reason: "Invalid operation '\(operation)'.")
            }

            let options = ProvisionAction.Options(
                operation: op,
                bundleId: bundleId,
                appName: appName,
                deviceUDIDs: deviceUdids.isEmpty ? nil : deviceUdids,
                deviceNames: deviceNames.isEmpty ? nil : deviceNames
            )

            let result = try await ProvisionAction().run(with: options, context: context)
            outputResult(action: "provision", result: result, format: global.output, colorMode: global.effectiveColorMode)
        } catch let error as ShipItError {
            outputError(error: error, format: global.output, colorMode: global.effectiveColorMode)
            throw ExitCode(error.exitCode)
        }
    }
}
