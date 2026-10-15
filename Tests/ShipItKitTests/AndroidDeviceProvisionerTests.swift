import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("AndroidDeviceProvisioner")
struct AndroidDeviceProvisionerTests {

    private func makeProvisioner(
        handler: (@Sendable (Command, ShellContext) async throws -> ShellOutput)? = nil,
        ci: Bool = false,
        prompt: @escaping @Sendable ([String]) -> [String] = { _ in [] },
        interactive: Bool = false
    ) -> (AndroidDeviceProvisioner, @Sendable () -> [String]) {
        let (executor, commands) = makeCaptureExecutor(handler: handler)
        let context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(platform: .android, ci: ci),
            platform: .android
        )
        let provisioner = AndroidDeviceProvisioner(
            context: context,
            logger: context.logger,
            promptForEmulators: prompt,
            isInteractiveTerminal: { interactive },
            bootTimeout: .milliseconds(50),
            pollInterval: .milliseconds(5)
        )
        return (provisioner, commands)
    }

    // MARK: - Parsing

    @Test("parseAVDNames handles bare names, tabular output, headers, and emulator log noise")
    func parseAVDNames() {
        let native = """
            INFO    | Storing crashdata in: /tmp/android-user/emu-crash-35.1.db
            Pixel_7_API_34
            Medium_Phone
            """
        #expect(AndroidDeviceProvisioner.parseAVDNames(native) == ["Pixel_7_API_34", "Medium_Phone"])

        let tabular = """
            Name            Status
            Pixel_7_API_34  stopped
            """
        #expect(AndroidDeviceProvisioner.parseAVDNames(tabular) == ["Pixel_7_API_34"])
    }

    // MARK: - Emulator selection

    @Test("Configured AVDs that exist locally are used without prompting")
    func resolveConfiguredEmulators() throws {
        let (provisioner, _) = makeProvisioner(
            prompt: { _ in
                Issue.record("should not prompt")
                return []
            }, interactive: true)
        let resolved = try provisioner.resolveEmulators(
            configured: ["Missing", "Pixel_7"],
            available: ["Pixel_7", "Pixel_8"],
            shouldPrompt: true,
            allowInteractiveSelection: true
        )
        #expect(resolved == ["Pixel_7"])
    }

    @Test("Missing configured AVDs throw when prompting is not possible")
    func resolveMissingConfiguredEmulatorsThrows() {
        let (provisioner, _) = makeProvisioner(interactive: false)
        #expect(throws: ShipItError.self) {
            try provisioner.resolveEmulators(
                configured: ["Missing"],
                available: ["Pixel_7"],
                shouldPrompt: true,
                allowInteractiveSelection: true
            )
        }
    }

    @Test("Missing configured AVDs fall back to an interactive prompt locally")
    func resolveMissingConfiguredEmulatorsPrompts() throws {
        let (provisioner, _) = makeProvisioner(prompt: { available in [available[1]] }, interactive: true)
        let resolved = try provisioner.resolveEmulators(
            configured: ["Missing"],
            available: ["Pixel_7", "Pixel_8"],
            shouldPrompt: true,
            allowInteractiveSelection: true
        )
        #expect(resolved == ["Pixel_8"])
    }

    @Test("No configured AVDs and no interactive terminal selects nothing")
    func resolveNoConfiguredEmulators() throws {
        let (provisioner, _) = makeProvisioner(interactive: false)
        let resolved = try provisioner.resolveEmulators(
            configured: nil,
            available: ["Pixel_7"],
            shouldPrompt: true,
            allowInteractiveSelection: true
        )
        #expect(resolved.isEmpty)
    }

    // MARK: - Lifecycle

    @Test("connected strategy with an attached device spawns nothing")
    func connectedStrategyWithDevice() async throws {
        let (provisioner, commands) = makeProvisioner { command, _ in
            if command.description.contains("adb devices") {
                return ShellOutput(stdout: "List of devices attached\nemulator-5554\tdevice\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let spawned = try await provisioner.prepare(devices: TestDeviceConfig(strategy: .connected))
        #expect(spawned.isEmpty)
        #expect(!commands().contains { $0.contains("-list-avds") })
    }

    @Test("connected strategy in CI without a device throws")
    func connectedStrategyInCIThrows() async {
        let (provisioner, _) = makeProvisioner(
            handler: { _, _ in ShellOutput(stdout: "List of devices attached\n", stderr: "", exitCode: 0) },
            ci: true
        )
        await #expect(throws: ShipItError.self) {
            _ = try await provisioner.prepare(devices: TestDeviceConfig(strategy: .connected))
        }
    }

    @Test("connectedDeviceSerials keeps only devices in the `device` state")
    func connectedDeviceSerials() async throws {
        let (provisioner, _) = makeProvisioner { _, _ in
            ShellOutput(
                stdout: "List of devices attached\nemulator-5554\tdevice\nR5CT2074MZ\tdevice\nemulator-5556\toffline\n",
                stderr: "", exitCode: 0)
        }
        #expect(try await provisioner.connectedDeviceSerials() == ["emulator-5554", "R5CT2074MZ"])
        #expect(try await provisioner.connectedDeviceSerials(emulatorOnly: true) == ["emulator-5554"])
    }

    private func namedEmulators(bootCompleted: String) -> (AndroidDeviceProvisioner, @Sendable () -> [String]) {
        makeProvisioner { command, _ in
            let description = command.description
            if description.contains("-list-avds") { return ShellOutput(stdout: "Pixel_7\n", stderr: "", exitCode: 0) }
            if description.contains("emu avd name") { return ShellOutput(stdout: "Pixel_7\nOK\n", stderr: "", exitCode: 0) }
            if description.contains("getprop sys.boot_completed") {
                return ShellOutput(stdout: bootCompleted, stderr: "", exitCode: 0)
            }
            if description.contains("adb") && description.contains("devices") {
                // The emulator shows up only once it has been started.
                return ShellOutput(stdout: "List of devices attached\n", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }

    @Test("named emulators boot attached, and a boot that never completes throws and leaves nothing running")
    func namedEmulatorBootTimesOut() async {
        let (provisioner, commands) = namedEmulators(bootCompleted: "")
        await #expect(throws: ShipItError.self) {
            _ = try await provisioner.prepare(
                devices: TestDeviceConfig(strategy: .namedEmulators, emulators: ["Pixel_7"], promptLocally: false))
        }
        #expect(commands().contains { $0.contains("-avd Pixel_7") })
        #expect(commands().contains { $0.contains("emu kill") }, "A failed boot stops the emulator it started")
    }

    @Test("named emulators return the started instance once sys.boot_completed is 1")
    func namedEmulatorBoots() async throws {
        let (provisioner, _) = namedEmulators(bootCompleted: "1\n")
        let started = try await provisioner.prepare(
            devices: TestDeviceConfig(strategy: .namedEmulators, emulators: ["Pixel_7"], promptLocally: false))
        #expect(started.map(\.avd) == ["Pixel_7"])
        #expect(started.first?.process != nil, "Attached, so the emulator ends with this process")
        await provisioner.teardown(started)
    }

    @Test("resetAppInstallations uninstalls only from selected devices and tolerates failures")
    func resetAppInstallations() async throws {
        let (provisioner, commands) = makeProvisioner { command, _ in
            let description = command.description
            if description.contains("adb devices") {
                return ShellOutput(stdout: "List of devices attached\nemulator-5554\tdevice\nR5CT\tdevice\n", stderr: "", exitCode: 0)
            }
            if description.contains("R5CT") {
                return ShellOutput(stdout: "", stderr: "Failure [DELETE_FAILED_INTERNAL_ERROR]", exitCode: 1)
            }
            return ShellOutput(stdout: "Success", stderr: "", exitCode: 0)
        }
        try await provisioner.resetAppInstallations(packageName: "com.example.app", serials: ["emulator-5554", "R5CT"])
        let uninstalls = commands().filter { $0.contains("uninstall com.example.app") }
        #expect(uninstalls.count == 2)
    }

    @Test("resetAppInstallations is a no-op without a package name")
    func resetAppInstallationsWithoutPackage() async throws {
        let (provisioner, commands) = makeProvisioner()
        try await provisioner.resetAppInstallations(packageName: nil, serials: [])
        #expect(commands().isEmpty)
    }
}
