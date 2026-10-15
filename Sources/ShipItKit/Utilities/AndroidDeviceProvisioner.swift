import AdbKit
import AndroidCLIKit
import EmulatorKit
import Foundation
import Logging
import MobileCore
import MobileDevices
import SwiftyShell

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Makes Android devices available for instrumented tests: detects connected devices, resolves
/// and boots named AVDs, waits for boot, and resets app installations between runs.
///
/// Extracted from `TestAction` so device orchestration can be reused (e.g. by screenshot or
/// UI-automation actions) and its `adb` / `emulator` output parsing unit-tested in isolation.
///
/// ## Usage
/// ```swift
/// let provisioner = AndroidDeviceProvisioner(context: context, logger: logger)
/// let spawned = try await provisioner.prepare(devices: devicesConfig)
/// defer { Task { await provisioner.teardown(spawned) } }  // or tear down explicitly
/// try await provisioner.resetAppInstallations(packageName: "com.example.app")
/// ```
struct AndroidDeviceProvisioner: Sendable {

    let context: ActionContext
    let logger: Logger
    let promptForEmulators: @Sendable ([String]) -> [String]
    let isInteractiveTerminal: @Sendable () -> Bool
    let bootTimeout: Duration
    let pollInterval: Duration

    init(
        context: ActionContext,
        logger: Logger,
        promptForEmulators: @escaping @Sendable ([String]) -> [String] = AndroidDeviceProvisioner.defaultPromptForEmulators,
        isInteractiveTerminal: @escaping @Sendable () -> Bool = AndroidDeviceProvisioner.defaultIsInteractiveTerminal,
        bootTimeout: Duration = .seconds(180),
        pollInterval: Duration = .seconds(2)
    ) {
        self.context = context
        self.logger = logger
        self.promptForEmulators = promptForEmulators
        self.isInteractiveTerminal = isInteractiveTerminal
        self.bootTimeout = bootTimeout
        self.pollInterval = pollInterval
    }

    private var shell: ShellContext { context.shell }

    private var devices: AndroidDeviceManager {
        AndroidDeviceManager(shell: shell) { [pollInterval] timeout in Poller(timeout: timeout, interval: pollInterval) }
    }

    private var emulators: AndroidEmulatorManager {
        AndroidEmulatorManager(shell: shell, devices: devices)
    }

    // MARK: - Lifecycle

    /// Ensures the devices described by `devices` are available, booting emulators as needed.
    ///
    /// - Returns: The emulators this call started. Pass them to ``teardown(_:)`` when the run
    ///   finishes; emulators that were already booted are reused and not returned.
    func prepare(devices: TestDeviceConfig) async throws -> [EmulatorInstance] {
        switch devices.strategy {
        case .none:
            return []
        case .connected:
            if try await !connectedDeviceSerials().isEmpty {
                return []
            }

            guard !context.configIsCI else {
                throw ShipItError.invalidConfiguration(
                    reason:
                        "Android instrumented tests require a connected device or emulator in CI. Configure `devices.strategy: named_emulators` or `managed`, or start a device before running the workflow."
                )
            }

            let available = try await availableEmulators()
            guard !available.isEmpty else {
                throw ShipItError.invalidConfiguration(
                    reason:
                        "Android instrumented tests require a connected device or available AVD. No connected devices were found and `emulator -list-avds` returned none."
                )
            }

            logger.info("No connected Android devices found; falling back to a local emulator selection")
            return try await prepare(
                devices: TestDeviceConfig(
                    strategy: .namedEmulators,
                    emulators: devices.emulators,
                    promptLocally: devices.promptLocally ?? true
                )
            )
        case .managed:
            // Gradle Managed Devices handle their own lifecycle — nothing to orchestrate.
            // The task name itself targets the managed device.
            return []
        case .namedEmulators:
            let desiredEmulators = try resolveEmulators(
                configured: devices.emulators,
                available: try await availableEmulators(),
                shouldPrompt: devices.promptLocally ?? true,
                allowInteractiveSelection: !context.configIsCI
            )

            var started: [EmulatorInstance] = []
            do {
                for emulator in desiredEmulators {
                    if let existingSerial = try await emulators.runningSerial(avd: emulator) {
                        logger.info("Using already booted emulator '\(emulator)' (\(existingSerial))")
                        continue
                    }

                    logger.info("Booting emulator '\(emulator)'\(context.configIsCI ? " (headless)" : "")")
                    // CI runners have no display: a windowed emulator exits immediately there.
                    // Attached, so the emulator ends with this process even if teardown never runs.
                    let instance = try await emulators.start(
                        avd: emulator, options: EmulatorBootOptions(headless: context.configIsCI, attached: true))
                    started.append(instance)
                    do {
                        try await emulators.waitUntilBooted(instance, timeout: bootTimeout)
                    } catch let error as MobileKitError {
                        throw ShipItError.invalidConfiguration(
                            reason: "Android emulator '\(emulator)' did not boot: \(error.localizedDescription)")
                    }
                    logger.info("Emulator '\(emulator)' booted as \(instance.serial)")
                }
            } catch {
                await teardown(started)
                throw error
            }

            return started
        }
    }

    /// Stops the emulators ``prepare(devices:)`` started.
    func teardown(_ instances: [EmulatorInstance]) async {
        for instance in instances {
            await emulators.stop(instance)
        }
    }

    /// Uninstalls `packageName` from every connected device so each run starts from a clean
    /// install. Failures (e.g. the app is not installed) are logged and ignored.
    func resetAppInstallations(packageName: String?) async throws {
        guard let packageName, !packageName.isEmpty else { return }

        for serial in try await connectedDeviceSerials() {
            logger.info("Uninstalling existing Android app '\(packageName)' from '\(serial)' before test run")
            do {
                _ = try await Adb(context: shell)
                    .serial(serial)
                    .uninstall(package: packageName)
                    .run()
            } catch let ShellError.exitFailure(_, shellOutput) {
                let combinedLog = [shellOutput.stdout, shellOutput.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                logger.debug("Android uninstall skipped for '\(serial)': \(combinedLog)")
            } catch {
                logger.debug("Android uninstall skipped for '\(serial)': \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Emulator selection

    /// Chooses which AVDs to boot: the configured ones that exist locally, otherwise (when
    /// interactive selection is allowed) the ones the user picks.
    func resolveEmulators(
        configured: [String]?,
        available: [String],
        shouldPrompt: Bool,
        allowInteractiveSelection: Bool
    ) throws -> [String] {
        let availableSet = Set(available)
        let canPrompt = { allowInteractiveSelection && shouldPrompt && isInteractiveTerminal() }

        if let configured, !configured.isEmpty {
            let validConfigured = configured.filter { availableSet.contains($0) }
            if !validConfigured.isEmpty {
                return validConfigured
            }

            let configuredList = configured.joined(separator: ", ")
            guard !available.isEmpty else {
                throw ShipItError.invalidConfiguration(
                    reason: "Configured Android emulator(s) not found locally: \(configuredList). `emulator -list-avds` returned none."
                )
            }

            guard canPrompt() else {
                throw ShipItError.invalidConfiguration(
                    reason:
                        "Configured Android emulator(s) not found locally: \(configuredList). Available AVDs: \(available.joined(separator: ", "))."
                )
            }

            logger.info("Configured Android emulators not found locally; prompting for local selection")
            return promptForEmulators(available)
        }

        guard canPrompt(), !available.isEmpty else { return [] }

        logger.info("No emulators configured for instrumented tests; prompting for local selection")
        return promptForEmulators(available)
    }

    /// Lists local AVD names via AndroidCLI (when enabled) or `emulator -list-avds`.
    func availableEmulators() async throws -> [String] {
        guard context.config.androidCLI.enabled == true else { return try await emulators.listAVDs() }
        let executable = context.config.androidCLI.executablePath ?? "android"
        let cli = AndroidCLI(
            context: shell,
            executablePath: executable,
            sdkPath: context.config.androidCLI.sdkPath
        )
        let output: ShellOutput
        do {
            try await AndroidCLIVersionGate.ensureSupported(cli)
            output = try await cli.emulatorList().run()
        } catch let error as ShipItError {
            throw error
        } catch {
            throw ShipItError.invalidConfiguration(
                reason: "AndroidCLI command failed using '\(executable)': \(error.localizedDescription)"
            )
        }
        return Self.parseAVDNames(output.stdout)
    }

    // MARK: - Device state

    /// Serials of attached devices in the `device` state (not `offline` / `unauthorized`).
    func connectedDeviceSerials(emulatorOnly: Bool = false) async throws -> [String] {
        try await devices.list()
            .filter { $0.state == .device && (!emulatorOnly || $0.kind == .emulator) }
            .map(\.serial)
    }

    // MARK: - Output parsing

    /// Parses AVD names from `emulator -list-avds` (one bare name per line) or AndroidCLI's
    /// tabular `name  status` output, dropping an obvious header row and emulator log noise.
    static func parseAVDNames(_ output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { line -> String? in
                // `emulator -list-avds` can print diagnostics such as
                // "INFO    | Storing crashdata in: ..." before the AVD names.
                guard !line.contains("|") else { return nil }
                let name = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? line
                guard !["name", "avd", "avd name", "device"].contains(name.lowercased()) else { return nil }
                return name
            }
    }

    // MARK: - Interactive defaults

    static func defaultPromptForEmulators(available: [String]) -> [String] {
        print("\nAvailable Android emulators:")
        for (index, name) in available.enumerated() {
            print("  \(index + 1). \(name)")
        }
        print("Select emulator numbers separated by commas (blank skips): ", terminator: "")

        let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !answer.isEmpty else { return [] }

        let indexes =
            answer
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 >= 1 && $0 <= available.count }

        return indexes.map { available[$0 - 1] }
    }

    static func defaultIsInteractiveTerminal() -> Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    }
}
