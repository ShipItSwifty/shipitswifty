import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("ActionContext configured Gradle")
struct ConfiguredGradleTests {

    @Test("Applies project directory wrapper path and flags")
    func appliesResolvedGradleSettings() async throws {
        let (executor, commands) = makeCaptureExecutor { _, _ in
            ShellOutput(stdout: "BUILD SUCCESSFUL", stderr: "", exitCode: 0)
        }
        let config = ResolvedConfig(
            platform: .android,
            projectRoot: "/repo",
            androidModule: "androidApp",
            gradlewPath: "/repo/gradlew",
            gradleProjectDir: "/repo",
            androidGradleFlags: ["--configuration-cache", "--stacktrace"]
        )
        let context = makeTestActionContext(executor: executor, config: config, platform: .android)

        _ = try await BuildAction().run(
            with: BuildAction.Options(module: "androidApp", buildVariant: "release"),
            context: context
        )

        let command = try #require(commands().first)
        #expect(command.contains("/repo/gradlew"))
        #expect(command.contains("--configuration-cache"))
        #expect(command.contains("--stacktrace"))
        #expect(command.contains(":androidApp:assembleRelease"))
    }
}
