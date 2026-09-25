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

    @Test("parseDeviceSerials keeps only devices in the `device` state")
    func parseDeviceSerials() {
        let output = """
            List of devices attached
            emulator-5554\tdevice
            R5CT2074MZ\tdevice
            emulator-5556\toffline
            0123456789\tunauthorized

            """
        #expect(AndroidDeviceProvisioner.parseDeviceSerials(output) == ["emulator-5554", "R5CT2074MZ"])
        #expect(AndroidDeviceProvisioner.parseDeviceSerials(output, emulatorOnly: true) == ["emulator-5554"])
    }

    @Test("parseEmulatorSerial matches the AVD name exactly")
    func parseEmulatorSerialExactMatch() {
        let output = """
            List of devices attached
            emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 avd:Pixel_7_Pro transport_id:1
            emulator-5556          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 avd:Pixel_7 transport_id:2
            """
        #expect(AndroidDeviceProvisioner.parseEmulatorSerial(output, avdName: "Pixel_7") == "emulator-5556")
        #expect(AndroidDeviceProvisioner.parseEmulatorSerial(output, avdName: "Pixel_7_Pro") == "emulator-5554")
        #expect(AndroidDeviceProvisioner.parseEmulatorSerial(output, avdName: "Pixel_8") == nil)
    }

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

    @Test("waitForBoot times out when no emulator reports boot completion")
    func waitForBootTimesOut() async {
        let (provisioner, _) = makeProvisioner { _, _ in
            ShellOutput(stdout: "List of devices attached\n", stderr: "", exitCode: 0)
        }
        await #expect(throws: ShipItError.self) {
            _ = try await provisioner.waitForBoot(avdName: "Pixel_7")
        }
    }

    @Test("waitForBoot returns a newly attached emulator once sys.boot_completed is 1")
    func waitForBootReturnsNewSerial() async throws {
        let (provisioner, _) = makeProvisioner { command, _ in
            let description = command.description
            if description.contains("getprop sys.boot_completed") {
                return ShellOutput(stdout: "1\n", stderr: "", exitCode: 0)
            }
            if description.contains("adb devices") {
                return ShellOutput(
                    stdout: "List of devices attached\nemulator-5554\tdevice\nemulator-5556\tdevice\n",
                    stderr: "",
                    exitCode: 0
                )
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        let serial = try await provisioner.waitForBoot(avdName: "Pixel_7", excluding: ["emulator-5554"])
        #expect(serial == "emulator-5556")
    }

    @Test("resetAppInstallations uninstalls from every connected device and tolerates failures")
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
        try await provisioner.resetAppInstallations(packageName: "com.example.app")
        let uninstalls = commands().filter { $0.contains("uninstall com.example.app") }
        #expect(uninstalls.count == 2)
    }

    @Test("resetAppInstallations is a no-op without a package name")
    func resetAppInstallationsWithoutPackage() async throws {
        let (provisioner, commands) = makeProvisioner()
        try await provisioner.resetAppInstallations(packageName: nil)
        #expect(commands().isEmpty)
    }
}
