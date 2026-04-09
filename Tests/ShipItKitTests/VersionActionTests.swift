import Foundation
import Testing
import SwiftyShell
@testable import ShipItKit

@Suite("VersionAction")
struct VersionActionTests {

    @Test("VersionAction bumps patch version through agvtool")
    func bumpsPatchVersion() async throws {
        nonisolated(unsafe) var executedCommands: [String] = []
        let executor = MockExecutor { command, _ in
            let description = command.description
            executedCommands.append(description)

            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.2.3\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "42\n", stderr: "", exitCode: 0)
            }
            if description.contains("new-marketing-version") {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }

            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        let result = try await VersionAction().run(with: .init(bump: .patch), context: context)

        #expect(result.version == "1.2.4")
        #expect(result.buildNumber == "42")
        #expect(executedCommands.contains { $0.contains("new-marketing-version 1.2.4") })
    }

    @Test("VersionAction uses commit count strategy for build bumps")
    func usesCommitCountStrategy() async throws {
        let executor = MockExecutor { command, _ in
            let description = command.description
            if description.contains("what-marketing-version") {
                return ShellOutput(stdout: "1.2.3\n", stderr: "", exitCode: 0)
            }
            if description.contains("what-version") {
                return ShellOutput(stdout: "41\n", stderr: "", exitCode: 0)
            }
            if description.contains("git rev-list --count HEAD") {
                return ShellOutput(stdout: "128\n", stderr: "", exitCode: 0)
            }
            if description.contains("new-version -all 128") {
                return ShellOutput(stdout: "", stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }

        let context = ActionContext.mock(executor: executor)
        let result = try await VersionAction().run(with: .init(bump: .build, strategy: .commitCount), context: context)

        #expect(result.version == "1.2.3")
        #expect(result.buildNumber == "128")
    }
}
