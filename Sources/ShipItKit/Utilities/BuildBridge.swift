import Foundation
import GradleKit
import MobileBuild
import MobileCore

extension ActionContext {
    /// How a long build's output is handled: echoed live while it is captured, to stderr in
    /// `--output json` mode so stdout stays free for the JSON document.
    var buildOutput: BuildOutput {
        jsonOutput ? .streamingToStderr : .streaming
    }

    /// The Gradle project ShipIt's resolved config describes: its directory, wrapper, `--no-daemon`
    /// plus the Shipfile's flags, and its `-P` properties merged with `extraProperties`.
    ///
    /// - Parameter extraProperties: Per-call properties; they win over the Shipfile's.
    func gradleProject(extraProperties: [String: String]? = nil) -> GradleProject {
        GradleProject(
            directory: config.gradleProjectDir,
            gradlewPath: config.gradlewPath,
            flags: [.noDaemon] + config.androidGradleFlags.filter { $0 != "--no-daemon" }.map(GradleFlag.custom),
            properties: config.androidGradleProperties.merging(extraProperties ?? [:]) { _, new in new }
        )
    }

    /// A builder that streams to the terminal, for builds a person is watching.
    func gradleBuilder(output: BuildOutput? = nil) -> GradleBuilder {
        GradleBuilder(shell: shell, output: output ?? buildOutput)
    }
}

extension ActionContext {
    /// A Gradle invocation for a test task in the configured project.
    ///
    /// Test tasks do not take the Shipfile's `-P` properties (`android.gradle_properties` configures
    /// builds). Streaming tests echo live output with the capture cap lifted, so a long run cannot
    /// fail by exceeding it.
    func gradleTestCommand(streaming: Bool) -> Gradle {
        var project = gradleProject()
        project.properties = [:]
        let command = gradleBuilder(output: streaming ? buildOutput : .init()).command(for: project)
        return streaming ? command.outputLimit(0) : command
    }
}

extension ActionContext {
    /// The Gradle module a React Native app's Android project builds.
    var reactNativeAndroidModule: String {
        config.androidModule.isEmpty ? "app" : config.androidModule
    }

    /// The React Native `android/` Gradle project: the configured directory, or `./android` when
    /// none was set apart from the project root.
    func reactNativeGradleProject(extraProperties: [String: String]? = nil) -> GradleProject {
        var project = gradleProject(extraProperties: extraProperties)
        if config.gradleProjectDir == config.projectRoot { project.directory = "./android" }
        project.gradlewPath = config.gradlewPath ?? "\(project.directory)/gradlew"
        return project
    }

    /// Runs `task` in the React Native Gradle project, mapping a failed build with `failed`.
    func runReactNativeGradleTask(
        _ task: GradleTask,
        extraProperties: [String: String]?,
        failed: (_ exitCode: Int, _ log: String) -> ShipItError
    ) async throws -> BuildOutcome {
        let outcome = try await mappingBuildFailures(failed) {
            try await gradleBuilder(output: .init()).run([task], in: reactNativeGradleProject(extraProperties: extraProperties))
        }
        logShellOutput(outcome.output, label: "gradlew react-native fallback")
        return outcome
    }
}

/// Runs `body`, translating a mobile-kits ``BuildFailure`` into the ``ShipItError`` `failed`
/// builds, so exit-code mapping, suggestions, and the infrastructure-retry classifiers keep
/// reading the same `ShipItError` cases and logs.
///
/// A tool that is not installed becomes ``ShipItError/missingTool(name:)``.
func mappingBuildFailures<T>(
    _ failed: (_ exitCode: Int, _ log: String) -> ShipItError,
    _ body: () async throws -> T
) async throws -> T {
    do {
        return try await body()
    } catch let failure as BuildFailure {
        throw failed(Int(failure.exitCode), failure.log)
    } catch MobileKitError.toolNotFound(let tool) {
        throw ShipItError.missingTool(name: tool)
    }
}
