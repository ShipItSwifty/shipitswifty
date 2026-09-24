import Foundation

// MARK: - Emulator commands

extension AndroidCLI {

    /// `android emulator create <profile>` — Create an emulator from a device profile. **Mutating.**
    public func emulatorCreate(profile: String) -> Self { rawArguments(["emulator", "create", profile]) }

    /// `android emulator create --list-profiles` — List device profiles usable with
    /// ``emulatorCreate(profile:)``.
    public func emulatorListProfiles() -> Self { rawArguments(["emulator", "create", "--list-profiles"]) }

    /// `android emulator start [--cold] <device>` — Boot an emulator. **Mutating.**
    ///
    /// - Parameters:
    ///   - device: The emulator name.
    ///   - cold: Cold boot, ignoring any saved snapshot.
    public func emulatorStart(device: String, cold: Bool = false) -> Self {
        rawArguments(["emulator", "start"] + (cold ? ["--cold"] : []) + [device])
    }

    /// `android emulator stop <device>` — Shut down a running emulator. **Mutating.**
    public func emulatorStop(device: String) -> Self { rawArguments(["emulator", "stop", device]) }

    /// `android emulator list [--long]` — List emulators (one name per line, or a table with
    /// status when `long` is `true`).
    public func emulatorList(long: Bool = false) -> Self {
        rawArguments(["emulator", "list"] + (long ? ["--long"] : []))
    }

    /// `android emulator remove [--force] <device>` — Delete an emulator. **Mutating.**
    public func emulatorRemove(device: String, force: Bool = false) -> Self {
        rawArguments(["emulator", "remove"] + (force ? ["--force"] : []) + [device])
    }
}
