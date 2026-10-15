import AdbKit
import Foundation

/// Best-effort snapshots are bounded and never replace the runner's failure.
func captureAndroidFailure(context: ActionContext, directory: URL) async {
    // Host-only and managed-device tests own no adb devices to inspect.
    guard let selectedDevices = context.androidTestSerials, !selectedDevices.isEmpty else { return }
    let adb = Adb(context: context.shell)
    for (index, serial) in selectedDevices.enumerated() {
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
