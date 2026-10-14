#if os(macOS)
import Foundation
import MobileCore
import MobileDevices
import SwiftyShell

/// Claims a simulator in the device-claim directory ShipIt shares with amoo (MobileDevices'
/// `DeviceClaimStore`), so the two never drive the same simulator at once.
///
/// ShipIt's policy on top of the store: refuse a simulator an uncooperative `xcodebuild test`
/// already uses, hold the claim for a day, and never take over another tool's claim, even an
/// expired one, because its companion may still be running.
struct SimulatorLease: Sendable {
    let id: String
    let file: URL
    private let claim: DeviceClaim
    private let store: DeviceClaimStore

    static func acquire(device: String, shell: ShellContext, directory: URL? = nil) async throws -> Self {
        let store = DeviceClaimStore(
            directory: directory ?? DeviceClaimStore.sharedDirectory(environment: shell.environment), ttl: 86_400)
        // Uncooperative runners do not use a lease. Refuse an explicit destination held by xcodebuild.
        let processes = try await Command("ps").args(["-axo", "pid=,args="]).run(in: shell)
        if let holder = processes.stdout.components(separatedBy: .newlines).first(where: {
            $0.contains("xcodebuild") && $0.contains(device) && ($0.contains(" test") || $0.contains("test-without-building"))
        }) {
            throw ShipItError.invalidConfiguration(reason: "Simulator \(device) is held by \(holder.trimmingCharacters(in: .whitespaces))")
        }
        if let existing = store.allIncludingExpired().first(where: { $0.deviceID == device }) {
            throw ShipItError.invalidConfiguration(reason: refusal(existing, file: store.fileURL(deviceID: device)))
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        do {
            let claim = try store.acquire(platform: .ios, deviceID: device, owner: "shipit pid \(pid)", holderPID: pid)
            return Self(id: claim.id, file: store.fileURL(deviceID: device), claim: claim, store: store)
        } catch MobileKitError.deviceClaimed(_, let holder) {
            throw ShipItError.invalidConfiguration(
                reason: "Simulator \(device) is leased by \(holder). Lease: \(store.fileURL(deviceID: device).path)")
        }
    }

    private static func refusal(_ claim: DeviceClaim, file: URL) -> String {
        "Simulator \(claim.deviceID) is leased by \(claim.owner ?? "another session"), "
            + "pid \(claim.holderPID.map(String.init) ?? "unknown"). Lease: \(file.path)"
    }

    func release() {
        store.release(claim)
    }
}
#endif
