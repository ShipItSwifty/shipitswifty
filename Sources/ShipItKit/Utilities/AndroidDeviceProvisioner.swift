import Foundation
import Logging
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

    // MARK: - Lifecycle

    /// Ensures the devices described by `devices` are available, booting emulators as needed.
    ///
    /// - Returns: The emulator processes this call spawned. Pass them to ``teardown(_:)`` when the
    ///   run finishes; emulators that were already booted are reused and not returned.
    func prepare(devices: TestDeviceConfig) async throws -> [any SpawnedProcess] {
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

            var spawned: [any SpawnedProcess] = []
            for emulator in desiredEmulators {
                if let existingSerial = try await bootedEmulatorSerial(avdName: emulator) {
                    logger.info("Using already booted emulator '\(emulator)' (\(existingSerial))")
                    continue
                }

                let serialsBeforeBoot = try await connectedDeviceSerials(emulatorOnly: true)
                logger.info("Booting emulator '\(emulator)'\(context.configIsCI ? " (headless)" : "")")
                // CI runners have no display: a windowed emulator exits immediately there.
                let process = try await Emulator(context: shell)
                    .start(avd: emulator, headless: context.configIsCI)
                    .spawn(teardown: .graceful)

                spawned.append(process)
                let serial = try await waitForBoot(avdName: emulator, excluding: Set(serialsBeforeBoot))
                logger.info("Emulator '\(emulator)' booted as \(serial)")
            }

            return spawned
        }
    }

    /// Gracefully shuts down emulators spawned by ``prepare(devices:)``.
    func teardown(_ emulators: [any SpawnedProcess]) async {
        for emulator in emulators {
            _ = await emulator.teardownAndWait()
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
        let output: ShellOutput
        if context.config.androidCLI.enabled == true {
            let executable = context.config.androidCLI.executablePath ?? "android"
            let cli = AndroidCLI(
                context: shell,
                executablePath: executable,
                sdkPath: context.config.androidCLI.sdkPath
            )
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
        } else {
            output = try await Emulator(context: shell).list().run()
        }
        return Self.parseAVDNames(output.stdout)
    }

    // MARK: - Device state

    /// Serials of attached devices in the `device` state (not `offline` / `unauthorized`).
    func connectedDeviceSerials(emulatorOnly: Bool = false) async throws -> [String] {
        let output = try await Adb(context: shell).devices().run()
        return Self.parseDeviceSerials(output.stdout, emulatorOnly: emulatorOnly)
    }

    /// The serial of a running emulator for `avdName`, if any.
    func bootedEmulatorSerial(avdName: String) async throws -> String? {
        let output = try await Adb(context: shell).devices(long: true).run()
        return Self.parseEmulatorSerial(output.stdout, avdName: avdName)
    }

    /// Whether `sys.boot_completed` reports `1` for the device.
    func isBooted(serial: String) async -> Bool {
        let boot = try? await Adb(context: shell)
            .serial(serial)
            .getprop("sys.boot_completed")
            .run()
        return boot?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Polls until the emulator for `avdName` (or any newly attached emulator not in
    /// `knownSerials`) has finished booting, then returns its serial.
    func waitForBoot(avdName: String, excluding knownSerials: Set<String> = []) async throws -> String {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: bootTimeout)

        while clock.now < deadline {
            if let serial = try await bootedEmulatorSerial(avdName: avdName), await isBooted(serial: serial) {
                return serial
            }

            let newSerials = try await connectedDeviceSerials(emulatorOnly: true).filter { !knownSerials.contains($0) }
            for serial in newSerials {
                if await isBooted(serial: serial) { return serial }
            }

            try await Task.sleep(for: pollInterval)
        }

        throw ShipItError.invalidConfiguration(
            reason: "Timed out waiting for Android emulator '\(avdName)' to boot."
        )
    }

    // MARK: - Output parsing

    /// Parses `adb devices` output into serials whose state is `device`.
    static func parseDeviceSerials(_ output: String, emulatorOnly: Bool = false) -> [String] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("List of devices attached") else { return nil }
            let columns = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard columns.count >= 2, columns[1] == "device" else { return nil }
            let serial = columns[0]
            guard !emulatorOnly || serial.hasPrefix("emulator-") else { return nil }
            return serial
        }
    }

    /// Parses `adb devices -l` output for the emulator serial running `avdName`.
    ///
    /// Matches the `avd:<name>` token exactly, so `Pixel_7` does not match `Pixel_7_Pro`.
    static func parseEmulatorSerial(_ output: String, avdName: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let columns = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard let serial = columns.first, serial.hasPrefix("emulator-") else { continue }
            if columns.contains("avd:\(avdName)") {
                return serial
            }
        }
        return nil
    }

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
