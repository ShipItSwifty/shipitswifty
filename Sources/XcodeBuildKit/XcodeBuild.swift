#if os(macOS)
import Foundation
import SwiftyShell

/// A fluent wrapper for the `xcodebuild` command.
///
/// Prefer the operation methods such as ``build(clean:)``, ``test()``, and
/// ``exportArchive(archivePath:exportPath:exportOptionsPlist:)``. The generic
/// ``option(_:)`` and ``trailingArgument(_:)`` methods remain available for
/// options and operations not modeled by this package.
public struct XcodeBuild: RunnableCommandFamily {
    /// Shared configuration applied to commands produced by this client.
    public let config: ToolConfiguration
    /// The stdout handling strategy for built commands.
    public let stdoutDestination: OutputDestination
    /// The stderr handling strategy for built commands.
    public let stderrDestination: OutputDestination
    /// Typed `xcodebuild` options applied before build settings and trailing arguments.
    public let options: [XcodeBuildOption]
    /// Additional trailing arguments passed to `xcodebuild`.
    public let trailingArguments: [String]
    let buildSettings: [XcodeBuildBuildSetting]
    let operation: XcodeBuildOperation?

    /// The shell context used when running this command family.
    public var context: ShellContext { config.context }

    /// Creates an `xcodebuild` command family bound to a shell context.
    public init(context: ShellContext = .init()) {
        self.config = ToolConfiguration(context: context)
        self.stdoutDestination = .capture
        self.stderrDestination = .capture
        self.options = []
        self.trailingArguments = []
        self.buildSettings = []
        self.operation = nil
    }

    private init(
        config: ToolConfiguration,
        stdoutDestination: OutputDestination,
        stderrDestination: OutputDestination,
        options: [XcodeBuildOption],
        trailingArguments: [String],
        buildSettings: [XcodeBuildBuildSetting],
        operation: XcodeBuildOperation?
    ) {
        self.config = config
        self.stdoutDestination = stdoutDestination
        self.stderrDestination = stderrDestination
        self.options = options
        self.trailingArguments = trailingArguments
        self.buildSettings = buildSettings
        self.operation = operation
    }

    /// Returns a new value with updated shared tool configuration.
    public func updatingConfiguration(
        _ update: (ToolConfiguration) -> ToolConfiguration
    ) -> Self {
        copy(config: update(config))
    }

    /// Redirects stdout for the built `xcodebuild` command.
    public func settingStdoutDestination(_ destination: OutputDestination) -> Self {
        copy(stdoutDestination: destination)
    }

    /// Redirects stderr for the built `xcodebuild` command.
    public func settingStderrDestination(_ destination: OutputDestination) -> Self {
        copy(stderrDestination: destination)
    }

    /// Appends a typed `xcodebuild` option.
    public func option(_ option: XcodeBuildOption) -> Self {
        copy(options: options + [option])
    }

    /// Appends multiple typed `xcodebuild` options.
    public func options(_ values: [XcodeBuildOption]) -> Self {
        copy(options: options + values)
    }

    /// Selects an Xcode project or workspace, replacing any previously selected typed container.
    public func container(_ container: XcodeBuildContainer) -> Self {
        copy(options: options.filter { !$0.isContainerOption } + [container.option])
    }

    /// Selects an Xcode project, replacing any previously selected typed project or workspace.
    public func project(_ path: String) -> Self {
        container(.project(path))
    }

    /// Selects an Xcode workspace, replacing any previously selected typed project or workspace.
    public func workspace(_ path: String) -> Self {
        container(.workspace(path))
    }

    /// Appends a trailing argument.
    public func trailingArgument(_ value: String) -> Self {
        copy(trailingArguments: trailingArguments + [value])
    }

    /// Appends multiple trailing arguments.
    public func trailingArguments(_ values: [String]) -> Self {
        copy(trailingArguments: trailingArguments + values)
    }

    /// Adds a build setting in `NAME=VALUE` form.
    public func buildSetting(_ name: String, _ value: String) -> Self {
        copy(buildSettings: buildSettings + [XcodeBuildBuildSetting(name: name, value: value)])
    }

    /// Adds multiple build settings.
    public func buildSettings(_ values: KeyValuePairs<String, String>) -> Self {
        copy(buildSettings: buildSettings + values.map { XcodeBuildBuildSetting(name: $0.0, value: $0.1) })
    }

    /// Configures the command to build, optionally cleaning before the build.
    public func build(clean: Bool = false) -> Self {
        copy(operation: .build(clean: clean), replaceOperation: true)
    }

    /// Configures the command to run the test action.
    public func test() -> Self {
        copy(operation: .test, replaceOperation: true)
    }

    /// Configures the command to archive build products.
    /// - Parameter path: Optional destination path for the created `.xcarchive`.
    public func archive(path: String? = nil) -> Self {
        copy(operation: .archive(path: path), replaceOperation: true)
    }

    /// Configures the command to export an existing archive.
    /// - Parameters:
    ///   - archivePath: Path to the `.xcarchive` to export.
    ///   - exportPath: Optional destination directory for exported products.
    ///   - exportOptionsPlist: Path to the export options property list.
    public func exportArchive(
        archivePath: String,
        exportPath: String? = nil,
        exportOptionsPlist: String
    ) -> Self {
        copy(
            operation: .exportArchive(
                archivePath: archivePath,
                exportPath: exportPath,
                exportOptionsPlist: exportOptionsPlist
            ),
            replaceOperation: true
        )
    }

    /// Configures the command to display build settings.
    /// - Parameter json: Whether to request JSON output. `xcodebuild` also enables quiet output for JSON.
    public func showBuildSettings(json: Bool = false) -> Self {
        copy(operation: .showBuildSettings(json: json), replaceOperation: true)
    }

    /// Configures the command to display destinations valid for the selected scheme.
    public func showDestinations() -> Self {
        copy(operation: .showDestinations, replaceOperation: true)
    }

    /// Configures the command to create an XCFramework from prebuilt inputs.
    /// - Parameters:
    ///   - inputs: Frameworks and libraries to package. Library headers and debug symbols remain grouped with their input.
    ///   - output: Destination path for the `.xcframework`.
    ///   - allowInternalDistribution: Whether the result may contain metadata unsuitable for public distribution.
    public func createXCFramework(
        inputs: [XcodeBuildXCFrameworkInput],
        output: String,
        allowInternalDistribution: Bool = false
    ) -> Self {
        precondition(!inputs.isEmpty, "Creating an XCFramework requires at least one input.")
        return copy(
            operation: .createXCFramework(
                inputs: inputs,
                output: output,
                allowInternalDistribution: allowInternalDistribution
            ),
            replaceOperation: true
        )
    }

    /// Builds the raw `xcodebuild` command.
    public func command() -> Command {
        let base = Command("xcodebuild")
            .args(operation?.prefixArguments ?? [])
            .args(options.flatMap(\.arguments))
            .args(operation?.argumentsAfterOptions ?? [])
            .args(buildSettings.map(\.argument))
            .args(operation?.buildActions ?? [])
            .args(trailingArguments)
            .stdout(stdoutDestination)
            .stderr(stderrDestination)

        return config.apply(to: base)
    }

    private func copy(
        config: ToolConfiguration? = nil,
        stdoutDestination: OutputDestination? = nil,
        stderrDestination: OutputDestination? = nil,
        options: [XcodeBuildOption]? = nil,
        trailingArguments: [String]? = nil,
        buildSettings: [XcodeBuildBuildSetting]? = nil,
        operation: XcodeBuildOperation? = nil,
        replaceOperation: Bool = false
    ) -> Self {
        Self(
            config: config ?? self.config,
            stdoutDestination: stdoutDestination ?? self.stdoutDestination,
            stderrDestination: stderrDestination ?? self.stderrDestination,
            options: options ?? self.options,
            trailingArguments: trailingArguments ?? self.trailingArguments,
            buildSettings: buildSettings ?? self.buildSettings,
            operation: replaceOperation ? operation : self.operation
        )
    }
}

struct XcodeBuildBuildSetting: Sendable, Equatable {
    let name: String
    let value: String

    var argument: String {
        "\(name)=\(value)"
    }
}
#endif
