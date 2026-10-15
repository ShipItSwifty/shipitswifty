import Foundation
import MobileCore
import MobileDevices
import SwiftyShell
import TestCommons
import Testing

@testable import ShipItKit

@Suite("Android run claims")
struct AndroidDeviceClaimTests {
    @Test("Connected runs skip active and expired claims and reset only owned devices", arguments: [false, true])
    func skipsOtherClaims(expired: Bool) async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let store = DeviceClaimStore(directory: scratch.url)
        let other = try store.acquire(platform: .android, deviceID: "emulator-5554", now: expired ? .distantPast : Date())
        let executor = MockExecutor { _, _ in
            ShellOutput(stdout: "List of devices attached\nemulator-5554\tdevice\nUSB\tdevice\n", exitCode: 0)
        }
        let context = makeTestActionContext(executor: executor, config: ResolvedConfig(platform: .android))
        let provisioner = AndroidDeviceProvisioner(context: context, logger: context.logger)
        let run = try await provisioner.prepareRun(devices: TestDeviceConfig(strategy: .connected), store: store)
        #expect(run.serials == ["USB"])
        #expect(store.claim(forDevice: "USB") != nil)
        #expect(throws: MobileKitError.self) { try DeviceSessionLock(deviceID: "USB", store: store) }
        try await provisioner.resetAppInstallations(packageName: "com.example", serials: run.serials ?? [])
        #expect(
            executor.recordedCommands.filter { $0.arguments.contains("uninstall") }.map(\.arguments) == [
                ["-s", "USB", "uninstall", "com.example"]
            ])
        await provisioner.teardown(run)
        #expect(store.claim(forDevice: "USB") == nil)
        #expect(store.allIncludingExpired() == [other])
    }

    @Test("Named emulators refuse a claim without uninstalling or stopping the other session")
    func namedRefusesClaim() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let store = DeviceClaimStore(directory: scratch.url)
        let other = try store.acquire(platform: .android, deviceID: "emulator-5554")
        let executor = MockExecutor { command, _ in
            if command.arguments.contains("-list-avds") { return ShellOutput(stdout: "Pixel\n", exitCode: 0) }
            if command.arguments.contains("name") { return ShellOutput(stdout: "Pixel\nOK\n", exitCode: 0) }
            if command.arguments.contains("getprop") { return ShellOutput(stdout: "1\n", exitCode: 0) }
            return ShellOutput(stdout: "List of devices attached\nemulator-5554\tdevice\n", exitCode: 0)
        }
        let context = makeTestActionContext(executor: executor, config: ResolvedConfig(platform: .android))
        let provisioner = AndroidDeviceProvisioner(context: context, logger: context.logger)
        await #expect(throws: ShipItError.self) {
            try await provisioner.prepareRun(devices: TestDeviceConfig(strategy: .namedEmulators, emulators: ["Pixel"]), store: store)
        }
        #expect(store.all() == [other])
        #expect(!executor.recordedCommands.contains { $0.arguments.contains("uninstall") || $0.arguments.contains("kill") })
    }

    @Test("Test execution targets claimed serials and releases claims after success or failure", arguments: [false, true])
    func executionIsScoped(failing: Bool) async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let store = DeviceClaimStore(directory: scratch.url)
        let other = try store.acquire(platform: .android, deviceID: "BUSY")
        let executor = MockExecutor { command, _ in
            if command.arguments.contains("devices") {
                return ShellOutput(stdout: "List of devices attached\nBUSY\tdevice\nFREE\tdevice\n", exitCode: 0)
            }
            if command.arguments.contains(where: { $0.contains("connected") }) {
                #expect(command.environmentOverrides["ANDROID_SERIAL"] == "FREE")
                #expect(store.claim(forDevice: "FREE") != nil)
                return ShellOutput(
                    stdout: failing ? "1 tests completed, 1 failed\n" : "1 tests completed, 0 failed\n", exitCode: failing ? 1 : 0)
            }
            #expect(!command.arguments.contains("BUSY"))
            return ShellOutput(exitCode: 0)
        }
        let context = makeTestActionContext(
            shell: ShellContext(executor: executor, environment: ["AMOO_LEASE_DIR": scratch.url.path]),
            config: ResolvedConfig(platform: .android))
        do {
            _ = try await TestAction().run(
                with: .init(kind: .instrumented, devices: TestDeviceConfig(strategy: .connected)), context: context)
            #expect(!failing)
        } catch { #expect(failing) }
        #expect(store.all() == [other])
    }
    @Test("A new emulator is claimed before its boot wait, and failed boot releases the claim", arguments: [false, true])
    func claimsBeforeBoot(failing: Bool) async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let store = DeviceClaimStore(directory: scratch.url)
        let executor = MockExecutor { command, _ in
            if command.arguments.contains("-list-avds") { return ShellOutput(stdout: "Pixel\n", exitCode: 0) }
            if command.arguments.contains("getprop") {
                #expect(store.claim(forDevice: "emulator-5554") != nil)
                return ShellOutput(stdout: failing ? "0\n" : "1\n", exitCode: 0)
            }
            return ShellOutput(exitCode: 0)
        }
        let context = makeTestActionContext(executor: executor, config: ResolvedConfig(platform: .android))
        let provisioner = AndroidDeviceProvisioner(context: context, logger: context.logger, bootTimeout: .zero)
        do {
            let run = try await provisioner.prepareRun(
                devices: TestDeviceConfig(strategy: .namedEmulators, emulators: ["Pixel"]), store: store)
            #expect(!failing)
            await provisioner.teardown(run)
        } catch { #expect(failing) }
        #expect(store.allIncludingExpired().isEmpty)
        #expect(executor.recordedCommands.contains { $0.arguments == ["-s", "emulator-5554", "emu", "kill"] })
    }

    @Test("Host-only failure evidence never inspects an unclaimed device")
    func hostEvidenceDoesNotDriveDevices() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let executor = MockExecutor(stdout: "List of devices attached\nBUSY\tdevice\n")
        let context = makeTestActionContext(executor: executor, config: ResolvedConfig(platform: .android))
        await captureAndroidFailure(context: context, directory: scratch.url)
        #expect(executor.recordedCommands.isEmpty)
    }

}
