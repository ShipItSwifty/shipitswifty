#if os(macOS)
import Darwin
import Foundation
import SwiftyShell

/// Coordinates ShipIt and amoo through amoo's existing atomic lease protocol.
struct SimulatorLease: Sendable {
    let id: String
    let file: URL
    private static func formatter() -> ISO8601DateFormatter {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }
    static func acquire(device: String, shell: ShellContext, directory: URL? = nil) async throws -> Self {
        let root =
            directory ?? shell.environment["AMOO_LEASE_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".amoo/leases")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let safe = String(device.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" })
        let file = root.appendingPathComponent(safe + ".json")
        // Uncooperative runners do not use a lease. Refuse an explicit destination held by xcodebuild.
        let processes = try await Command("ps").args(["-axo", "pid=,args="]).run(in: shell)
        if let holder = processes.stdout.components(separatedBy: .newlines).first(where: {
            $0.contains("xcodebuild") && $0.contains(device) && ($0.contains(" test") || $0.contains("test-without-building"))
        }) {
            throw ShipItError.invalidConfiguration(reason: "Simulator \(device) is held by \(holder.trimmingCharacters(in: .whitespaces))")
        }
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            let existing = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let holder = existing?["owner"] as? String ?? "another session"
            let pid = (existing?["holderPID"] as? NSNumber)?.stringValue ?? "unknown"
            // Do not reap another tool's expired lease: its companion may still be running.
            throw ShipItError.invalidConfiguration(reason: "Simulator \(device) is leased by \(holder), pid \(pid). Lease: \(file.path)")
        }
        defer { close(descriptor) }
        let id = "lease-" + UUID().uuidString.lowercased()
        let now = Date()
        let data = try JSONSerialization.data(
            withJSONObject: [
                "id": id, "platform": "ios", "deviceID": device,
                "holderPID": ProcessInfo.processInfo.processIdentifier, "bootedByLease": false,
                "owner": "shipit pid \(ProcessInfo.processInfo.processIdentifier)",
                "createdAt": formatter().string(from: now), "expiresAt": formatter().string(from: now.addingTimeInterval(86400)),
            ], options: [.prettyPrinted, .sortedKeys])
        do { try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).write(contentsOf: data) } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return .init(id: id, file: file)
    }
    func release() {
        guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["id"] as? String == id
        else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
#endif
