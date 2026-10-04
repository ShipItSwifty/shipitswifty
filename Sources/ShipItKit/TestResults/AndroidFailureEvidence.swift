import Foundation

/// Best-effort snapshots are bounded and never replace the runner's failure.
func captureAndroidFailure(context: ActionContext, directory: URL) async {
    let adb = Adb(context: context.shell)
    guard let listed = try? await adb.devices().timeout(.seconds(10)).run() else { return }
    let devices = listed.stdout.components(separatedBy: .newlines).compactMap { line -> String? in
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        return parts.count >= 2 && parts[1] == "device" ? String(parts[0]) : nil
    }
    for (index, serial) in devices.enumerated() {
        let root = directory.appendingPathComponent("device-\(index + 1)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let selected = adb.serial(serial)
        let remote = "/sdcard/shipit-failure-\(UUID().uuidString).png"
        if (try? await selected.screencap(remotePath: remote).timeout(.seconds(10)).run()) != nil {
            _ = try? await selected.pull(remote: remote, local: root.appendingPathComponent("failure.png").path).timeout(.seconds(10)).run()
            _ = try? await selected.shell("rm -f \(remote)").timeout(.seconds(10)).run()
        }
        let log = try? await selected.logcat(filters: ["-d", "-t", "1000"]).timeout(.seconds(10)).run()
        try? (log?.stdout ?? "Device logs unavailable").write(
            to: root.appendingPathComponent("logcat.log"), atomically: true, encoding: .utf8)
        try? writeJSON(
            ["device": serial, "orientation": "unknown", "app_running": "unknown", "capture": "after_attempt_failure"],
            to: root.appendingPathComponent("device-state.json"))
    }
}
