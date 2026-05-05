#if os(macOS)
import SwiftyShell
import Testing

@testable import CLI
@testable import ShipItKit

@Suite("DoctorCommand")
struct DoctorCommandTests {

    @Test("ASC diagnostics are optional for local-only workflows")
    func ascDiagnosticsOptionalForLocalOnlyWorkflows() {
        let config = ResolvedConfig(
            workflows: [
                "local": [
                    WorkflowStepConfig(action: "build"),
                    WorkflowStepConfig(action: "test"),
                    WorkflowStepConfig(action: "archive"),
                    WorkflowStepConfig(action: "export"),
                ]
            ]
        )

        #expect(DoctorCommand.ascDiagnosticsMode(for: config) == .optionalForLocalOnlyWorkflows)
    }

    @Test("ASC diagnostics are required for ASC-backed workflows")
    func ascDiagnosticsRequiredForASCBackedWorkflows() {
        let config = ResolvedConfig(
            workflows: [
                "beta": [
                    WorkflowStepConfig(action: "archive"),
                    WorkflowStepConfig(action: "testflight"),
                ]
            ]
        )

        #expect(DoctorCommand.ascDiagnosticsMode(for: config) == .required)
    }

    @Test("ASC diagnostics stay unknown when no workflows are defined")
    func ascDiagnosticsUnknownWithoutWorkflows() {
        #expect(DoctorCommand.ascDiagnosticsMode(for: ResolvedConfig()) == .unknown)
    }

    @Test("doctor tool checks use typed supported commands")
    func doctorToolChecksUseTypedSupportedCommands() {
        let commands = DoctorCommand.toolCheckCommands(shell: ShellContext())

        #expect(
            commands.map(\.name) == [
                "Xcode installed",
                "xcodebuild available",
                "git on PATH",
                "security CLI available",
                "xcrun simctl available",
            ])

        #expect(
            commands.map { $0.command.executableName } == [
                "xcode-select",
                "xcrun",
                "git",
                "security",
                "xcrun",
            ])

        #expect(
            commands.map { $0.command.arguments } == [
                ["-p"],
                ["xcodebuild", "-version"],
                ["--version"],
                ["help"],
                ["simctl", "list", "--json"],
            ])
    }
}
#endif
