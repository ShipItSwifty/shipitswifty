import Foundation

// MARK: - Deployment and UI inspection commands

extension AndroidCLI {

    /// `android install --apks=<a,b> [options]` — Install one or more APKs. **Mutating.**
    ///
    /// - Parameters:
    ///   - apks: APK paths (base plus any splits), joined with commas.
    ///   - device: Target device serial. Defaults to the only connected device.
    ///   - installOptions: Extra `adb install` options, e.g. `["-g", "-d"]`.
    ///   - useDeltaInstall: Pass `--use-delta-install` when `true`.
    ///   - verbose: Emit verbose output.
    public func install(
        apks: [String], device: String? = nil, installOptions: [String] = [],
        useDeltaInstall: Bool? = nil, verbose: Bool = false
    ) -> Self {
        rawArguments(
            deploymentArguments(
                command: "install", apks: apks, device: device, activity: nil, type: nil,
                installOptions: installOptions, useDeltaInstall: useDeltaInstall,
                debug: false, verbose: verbose
            ))
    }

    /// `android run --apks=<a,b> [options]` — Install APKs and launch a component. **Mutating.**
    ///
    /// - Parameters:
    ///   - apks: APK paths (base plus any splits), joined with commas.
    ///   - device: Target device serial. Defaults to the only connected device.
    ///   - activity: Component to launch, e.g. `".MainActivity"`.
    ///   - type: Component type (activity, Wear OS surfaces, …).
    ///   - installOptions: Extra `adb install` options, e.g. `["-g"]`.
    ///   - useDeltaInstall: Pass `--use-delta-install` when `true`.
    ///   - debug: Wait for a debugger to attach.
    ///   - verbose: Emit verbose output.
    public func run(
        apks: [String], device: String? = nil, activity: String? = nil,
        type: AndroidComponentType? = nil, installOptions: [String] = [],
        useDeltaInstall: Bool? = nil, debug: Bool = false, verbose: Bool = false
    ) -> Self {
        rawArguments(
            deploymentArguments(
                command: "run", apks: apks, device: device, activity: activity, type: type,
                installOptions: installOptions, useDeltaInstall: useDeltaInstall,
                debug: debug, verbose: verbose
            ))
    }

    /// `android layout [--diff] [--pretty] [--device=…] [--output=…]` — Dump the on-screen UI tree
    /// as JSON. Decode it with ``AndroidCLIOutputParser/layoutElements(from:)``.
    ///
    /// - Parameters:
    ///   - device: Target device serial.
    ///   - output: Write the JSON to this file instead of stdout.
    ///   - diff: Only report changes since the previous `layout` call.
    ///   - pretty: Pretty-print the JSON.
    public func layout(
        device: String? = nil, output: String? = nil, diff: Bool = false, pretty: Bool = false
    ) -> Self {
        var args = ["layout"]
        if diff { args.append("--diff") }
        if pretty { args.append("--pretty") }
        if let device { args.append("--device=\(device)") }
        if let output { args.append("--output=\(output)") }
        return rawArguments(args)
    }

    /// `android screen capture [--annotate] [--device=…] [--output=…]` — Capture a screenshot,
    /// optionally annotated with element bounds.
    public func screenCapture(device: String? = nil, output: String? = nil, annotate: Bool = false) -> Self {
        var args = ["screen", "capture"]
        if annotate { args.append("--annotate") }
        if let device { args.append("--device=\(device)") }
        if let output { args.append("--output=\(output)") }
        return rawArguments(args)
    }

    /// `android screen resolve --screenshot=<path> --string=<text>` — Locate on-screen text in a
    /// previously captured screenshot.
    public func screenResolve(screenshot: String, string: String) -> Self {
        rawArguments(["screen", "resolve", "--screenshot=\(screenshot)", "--string=\(string)"])
    }

    private func deploymentArguments(
        command: String, apks: [String], device: String?, activity: String?,
        type: AndroidComponentType?, installOptions: [String], useDeltaInstall: Bool?,
        debug: Bool, verbose: Bool
    ) -> [String] {
        var args = [command, "--apks=\(apks.joined(separator: ","))"]
        if let device { args.append("--device=\(device)") }
        if let activity { args.append("--activity=\(activity)") }
        if let type { args.append("--type=\(type.rawValue)") }
        if !installOptions.isEmpty { args.append("--install-options=\(installOptions.joined(separator: ","))") }
        if useDeltaInstall == true { args.append("--use-delta-install") }
        if debug { args.append("--debug") }
        if verbose { args.append("--verbose") }
        return args
    }
}
