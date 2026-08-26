import Foundation
import SwiftyShell

/// A typed, immutable wrapper around Google's preview `android` command-line tool.
///
/// AndroidCLI complements Gradle and ADB; it does not currently build release artifacts.
/// All execution is delegated to the injected ``ShellContext``.
public struct AndroidCLI: RunnableCommandFamily {
    public let config: ToolConfiguration
    public let stdoutDestination: OutputDestination
    public let stderrDestination: OutputDestination
    public let arguments: [String]
    public let executablePath: String
    public let sdkPath: String?

    public var context: ShellContext { config.context }

    public init(
        context: ShellContext = .init(),
        executablePath: String = "android",
        sdkPath: String? = nil
    ) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.arguments = []
        self.executablePath = executablePath
        self.sdkPath = sdkPath
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        arguments: [String],
        executablePath: String,
        sdkPath: String?
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.arguments = arguments
        self.executablePath = executablePath
        self.sdkPath = sdkPath
    }

    public func updatingConfiguration(_ update: (ToolConfiguration) -> ToolConfiguration) -> Self {
        copy(config: update(config))
    }

    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    public func settingExecutablePath(_ path: String) -> Self { copy(executablePath: path) }
    public func settingSDKPath(_ path: String?) -> Self { copy(sdkPath: path) }

    public func command() -> Command {
        var allArguments: [String] = []
        if let sdkPath { allArguments.append("--sdk=\(sdkPath)") }
        allArguments += arguments
        return config.apply(
            to: Command(executablePath)
                .args(allArguments)
                .stdout(stdoutDestination)
                .stderr(stderrDestination)
        )
    }

    public func rawArguments(_ arguments: [String]) -> Self { copy(arguments: arguments) }
    public func version() -> Self { rawArguments(["--version"]) }
    public func help(command: [String] = []) -> Self { rawArguments(["help"] + command) }

    public func create(
        name: String,
        output: String = ".",
        template: String? = nil,
        minSDK: Int? = nil,
        verbose: Bool = false
    ) -> Self {
        var args = ["create", "--name=\(name)", "--output=\(output)"]
        if let minSDK { args.append("--minSdk=\(minSDK)") }
        if verbose { args.append("--verbose") }
        if let template { args.append(template) }
        return rawArguments(args)
    }

    public func listTemplates() -> Self { rawArguments(["create", "--list"]) }
    public func describe(projectDirectory: String? = nil) -> Self {
        rawArguments(["describe"] + (projectDirectory.map { ["--project_dir=\($0)"] } ?? []))
    }
    public func docsSearch(_ query: String) -> Self { rawArguments(["docs", "search", query]) }
    public func docsFetch(_ url: String) -> Self { rawArguments(["docs", "fetch", url]) }

    public func emulatorCreate(profile: String) -> Self { rawArguments(["emulator", "create", profile]) }
    public func emulatorListProfiles() -> Self { rawArguments(["emulator", "create", "--list-profiles"]) }
    public func emulatorStart(device: String, cold: Bool = false) -> Self {
        rawArguments(["emulator", "start"] + (cold ? ["--cold"] : []) + [device])
    }
    public func emulatorStop(device: String) -> Self { rawArguments(["emulator", "stop", device]) }
    public func emulatorList(long: Bool = false) -> Self {
        rawArguments(["emulator", "list"] + (long ? ["--long"] : []))
    }
    public func emulatorRemove(device: String, force: Bool = false) -> Self {
        rawArguments(["emulator", "remove"] + (force ? ["--force"] : []) + [device])
    }

    public func info(field: String? = nil) -> Self { rawArguments(["info"] + (field.map { [$0] } ?? [])) }
    public func initialize() -> Self { rawArguments(["init"]) }

    public func install(
        apks: [String], device: String? = nil, installOptions: [String] = [],
        useDeltaInstall: Bool? = nil, verbose: Bool = false
    ) -> Self {
        rawArguments(deploymentArguments(
            command: "install", apks: apks, device: device, activity: nil, type: nil,
            installOptions: installOptions, useDeltaInstall: useDeltaInstall,
            debug: false, verbose: verbose
        ))
    }

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

    public func run(
        apks: [String], device: String? = nil, activity: String? = nil,
        type: AndroidComponentType? = nil, installOptions: [String] = [],
        useDeltaInstall: Bool? = nil, debug: Bool = false, verbose: Bool = false
    ) -> Self {
        rawArguments(deploymentArguments(
            command: "run", apks: apks, device: device, activity: activity, type: type,
            installOptions: installOptions, useDeltaInstall: useDeltaInstall,
            debug: debug, verbose: verbose
        ))
    }

    public func screenCapture(device: String? = nil, output: String? = nil, annotate: Bool = false) -> Self {
        var args = ["screen", "capture"]
        if annotate { args.append("--annotate") }
        if let device { args.append("--device=\(device)") }
        if let output { args.append("--output=\(output)") }
        return rawArguments(args)
    }
    public func screenResolve(screenshot: String, string: String) -> Self {
        rawArguments(["screen", "resolve", "--screenshot=\(screenshot)", "--string=\(string)"])
    }

    public func sdkInstall(
        packages: [String], beta: Bool = false, canary: Bool = false,
        force: Bool = false, platform: String? = nil
    ) -> Self { rawArguments(sdkArguments(operation: "install", values: packages, beta: beta, canary: canary, force: force, platform: platform)) }
    public func sdkUpdate(
        package: String? = nil, beta: Bool = false, canary: Bool = false,
        force: Bool = false, platform: String? = nil
    ) -> Self { rawArguments(sdkArguments(operation: "update", values: package.map { [$0] } ?? [], beta: beta, canary: canary, force: force, platform: platform)) }
    public func sdkRemove(packages: [String]) -> Self { rawArguments(["sdk", "remove"] + packages) }
    public func sdkList(pattern: String? = nil, all: Bool = false, allVersions: Bool = false, beta: Bool = false, canary: Bool = false) -> Self {
        var args = ["sdk", "list"]
        if all { args.append("--all") }
        if allVersions { args.append("--all-versions") }
        if beta { args.append("--beta") }
        if canary { args.append("--canary") }
        if let pattern { args.append(pattern) }
        return rawArguments(args)
    }

    public func skillsAdd(skill: String? = nil, all: Bool = false, agents: [String] = [], project: String? = nil) -> Self {
        rawArguments(skillsArguments(operation: "add", skill: skill, all: all, agents: agents, project: project))
    }
    public func skillsRemove(skill: String, agents: [String] = [], project: String? = nil) -> Self {
        rawArguments(skillsArguments(operation: "remove", skill: skill, all: false, agents: agents, project: project))
    }
    public func skillsList(long: Bool = false, project: String? = nil) -> Self {
        var args = ["skills", "list"]
        if long { args.append("--long") }
        if let project { args.append("--project=\(project)") }
        return rawArguments(args)
    }
    public func skillsFind(_ keyword: String) -> Self { rawArguments(["skills", "find", keyword]) }

    public func studioCheck() -> Self { rawArguments(["studio", "check"]) }
    public func studioAnalyzeFile(path: String, pid: Int? = nil, project: String? = nil) -> Self {
        rawArguments(studioArguments(operation: "analyze-file", pid: pid, project: project) + [path])
    }
    public func studioFindDeclaration(symbol: String, contextFile: String? = nil, short: Bool = false, pid: Int? = nil, project: String? = nil) -> Self {
        var args = studioArguments(operation: "find-declaration", pid: pid, project: project)
        if short { args.append("--short") }
        if let contextFile { args.append("--context-file=\(contextFile)") }
        return rawArguments(args + [symbol])
    }
    public func studioFindUsages(symbol: String, short: Bool = false, pid: Int? = nil, project: String? = nil) -> Self {
        var args = studioArguments(operation: "find-usages", pid: pid, project: project)
        if short { args.append("--short") }
        return rawArguments(args + [symbol])
    }
    public func studioOpenFile(path: String, pid: Int? = nil, project: String? = nil) -> Self {
        rawArguments(studioArguments(operation: "open-file", pid: pid, project: project) + [path])
    }
    public func studioRenderComposePreview(
        path: String, composable: String, outputImageFile: String? = nil,
        printSemantics: Bool = false, pid: Int? = nil, project: String? = nil
    ) -> Self {
        var args = studioArguments(operation: "render-compose-preview", pid: pid, project: project)
        if printSemantics { args.append("--print-semantics") }
        if let outputImageFile { args.append("--output-image-file=\(outputImageFile)") }
        return rawArguments(args + [path, composable])
    }
    public func studioVersionLookup(artifacts: [String], pid: Int? = nil, project: String? = nil) -> Self {
        rawArguments(studioArguments(operation: "version-lookup", pid: pid, project: project) + artifacts)
    }

    public func update(url: String? = nil) -> Self {
        rawArguments(["update"] + (url.map { ["--url=\($0)"] } ?? []))
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

    private func sdkArguments(operation: String, values: [String], beta: Bool, canary: Bool, force: Bool, platform: String?) -> [String] {
        var args = ["sdk", operation]
        if beta { args.append("--beta") }
        if canary { args.append("--canary") }
        if force { args.append("--force") }
        if let platform { args.append("--platform=\(platform)") }
        return args + values
    }

    private func skillsArguments(operation: String, skill: String?, all: Bool, agents: [String], project: String?) -> [String] {
        var args = ["skills", operation]
        if all { args.append("--all") }
        if !agents.isEmpty { args.append("--agent=\(agents.joined(separator: ","))") }
        if let project { args.append("--project=\(project)") }
        if let skill { args.append(skill) }
        return args
    }

    private func studioArguments(operation: String, pid: Int?, project: String?) -> [String] {
        var args = ["studio", operation]
        if let pid { args.append("--pid=\(pid)") }
        if let project { args.append("--project=\(project)") }
        return args
    }

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        arguments: [String]? = nil,
        executablePath: String? = nil,
        sdkPath: String?? = .none
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            arguments: arguments ?? self.arguments,
            executablePath: executablePath ?? self.executablePath,
            sdkPath: sdkPath != .none ? sdkPath! : self.sdkPath
        )
    }
}

public enum AndroidComponentType: String, Codable, Sendable, CaseIterable {
    case activity = "ACTIVITY"
    case watchFace = "WATCH_FACE"
    case tile = "TILE"
    case complication = "COMPLICATION"
    case declarativeWatchFace = "DECLARATIVE_WATCH_FACE"
    case wearWidget = "WEAR_WIDGET"
}

/// A UI element returned by `android layout`. Unknown fields are intentionally ignored.
public struct AndroidLayoutElement: Codable, Sendable, Equatable {
    public let text: String?
    public let resourceId: String?
    public let contentDesc: String?
    public let interactions: [String]?
    public let state: [String]?
    public let bounds: String?
    public let center: String?
    public let offScreen: Bool?

    public init(text: String? = nil, resourceId: String? = nil, contentDesc: String? = nil, interactions: [String]? = nil, state: [String]? = nil, bounds: String? = nil, center: String? = nil, offScreen: Bool? = nil) {
        self.text = text
        self.resourceId = resourceId
        self.contentDesc = contentDesc
        self.interactions = interactions
        self.state = state
        self.bounds = bounds
        self.center = center
        self.offScreen = offScreen
    }

    enum CodingKeys: String, CodingKey {
        case text, resourceId, contentDesc, interactions, state, bounds, center
        case offScreen = "off-screen"
    }
}

public enum AndroidCLIOutputParser {
    public static func layoutElements(from json: String) throws -> [AndroidLayoutElement] {
        try JSONDecoder().decode([AndroidLayoutElement].self, from: Data(json.utf8))
    }

    public static func keyValues(from output: String) -> [String: String] {
        output.split(separator: "\n").reduce(into: [:]) { result, line in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return }
            result[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
    }
}
