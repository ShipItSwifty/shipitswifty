import Foundation
import MobileCore
import MobileDevices

/// Devices exclusively owned for an instrumented run. Keep the locks until teardown finishes.
struct AndroidDeviceRun: Sendable {
    let started: [EmulatorInstance]
    let serials: [String]?
    let store: DeviceClaimStore
    let claims: [DeviceClaim]
    let locks: [DeviceSessionLock]

    func release() {
        claims.forEach { store.release($0) }
        locks.forEach { $0.release() }
    }
}

extension AndroidDeviceProvisioner {
    /// Claims the run's selected devices before any app reset or instrumentation command.
    /// Connected discovery skips occupied devices; explicitly named emulators refuse an occupied one.
    func prepareRun(devices config: TestDeviceConfig, store override: DeviceClaimStore? = nil) async throws -> AndroidDeviceRun {
        let store =
            override ?? DeviceClaimStore(directory: DeviceClaimStore.sharedDirectory(environment: context.shell.environment), ttl: 86_400)
        if config.strategy == .managed {
            return AndroidDeviceRun(started: [], serials: nil, store: store, claims: [], locks: [])
        }
        var started: [EmulatorInstance] = []
        var claims: [DeviceClaim] = []
        var locks: [DeviceSessionLock] = []
        let requested = context.shell.environment["ANDROID_SERIAL"].flatMap {
            $0.isEmpty ? nil : Set($0.split(separator: ",").map(String.init))
        }
        do {
            let preparation = try await prepareDevices(devices: config) { serial in
                if config.strategy != .namedEmulators, let requested, !requested.contains(serial) { return false }
                if claims.contains(where: { $0.deviceID == serial }) { return true }
                guard let (claim, lock) = try Self.claim(serial: serial, store: store) else { return false }
                claims.append(claim)
                locks.append(lock)
                return true
            }
            started = preparation.started
            guard !claims.isEmpty else {
                throw ShipItError.invalidConfiguration(reason: "No unclaimed Android devices are available for instrumented tests.")
            }
            return AndroidDeviceRun(started: started, serials: claims.map(\.deviceID), store: store, claims: claims, locks: locks)
        } catch {
            await teardown(started)
            claims.forEach { store.release($0) }
            locks.forEach { $0.release() }
            throw error
        }
    }

    /// Refuse expired external claims too: their companions may still be alive.
    private static func claim(serial: String, store: DeviceClaimStore) throws -> (DeviceClaim, DeviceSessionLock)? {
        if store.allIncludingExpired().contains(where: { $0.deviceID == serial }) { return nil }
        do {
            let claim = try store.acquire(
                platform: .android, deviceID: serial, owner: "shipit", holderPID: ProcessInfo.processInfo.processIdentifier)
            do { return (claim, try DeviceSessionLock(deviceID: serial, store: store)) } catch {
                store.release(claim)
                throw error
            }
        } catch MobileKitError.deviceClaimed { return nil }
    }

    func teardown(_ run: AndroidDeviceRun) async {
        await teardown(run.started)
        run.release()
    }
}
