import Foundation
import Testing
import SwiftyShell
import ShipItKit
@testable import BuildTimingPlugin

@Test
func recordsDurationOfShellCommand() async throws {
    let executor = MockExecutor { _, _ in
        ShellOutput(stdout: "Build Succeeded\n", stderr: "", exitCode: 0)
    }
    let context = ActionContext.mock(executor: executor)

    let result = try await BuildTimingAction().run(
        with: .init(command: "swift build"),
        context: context
    )

    #expect(result.command == "swift build")
    #expect(result.exitCode == 0)
    #expect(result.durationSeconds >= 0)
}
