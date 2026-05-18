#if os(macOS)
import SwiftyShell
import Testing

@testable import ShipItCLI
@testable import ShipItKit

@Suite("DoctorCommand")
struct DoctorCommandTests {

    @Test("ASC diagnostics are optional for local-only workflows")
    func ascDiagnosticsOptionalForLocalOnlyWorkflows() {
        let config = ResolvedConfig(
            workflows: [
                "local": WorkflowConfig(steps: [
                    WorkflowStepConfig(action: "build"),
                    WorkflowStepConfig(action: "test"),
                    WorkflowStepConfig(action: "archive"),
                    WorkflowStepConfig(action: "export"),
                ])
            ]
        )

        #expect(DoctorCommand.ascDiagnosticsMode(for: config) == .optionalForLocalOnlyWorkflows)
    }

    @Test("ASC diagnostics are required for ASC-backed workflows")
    func ascDiagnosticsRequiredForASCBackedWorkflows() {
        let config = ResolvedConfig(
            workflows: [
                "beta": WorkflowConfig(steps: [
                    WorkflowStepConfig(action: "archive"),
                    WorkflowStepConfig(action: "testflight"),
                ])
            ]
        )

        #expect(DoctorCommand.ascDiagnosticsMode(for: config) == .required)
    }

    @Test("ASC diagnostics stay unknown when no workflows are defined")
    func ascDiagnosticsUnknownWithoutWorkflows() {
        #expect(DoctorCommand.ascDiagnosticsMode(for: ResolvedConfig()) == .unknown)
    }

    @Test("doctor iOS tool checks include Xcode toolchain")
    func doctorIOSToolChecksIncludeXcodeToolchain() {
        let commands = DoctorCommand.toolCheckCommands(shell: ShellContext(), platform: .ios)

        #expect(
            commands.map(\.name) == [
                "git on PATH",
                "Xcode installed",
                "xcodebuild available",
                "security CLI available",
                "xcrun simctl available",
            ])

        #expect(
            commands.map { $0.command.executableName } == [
                "git",
                "xcode-select",
                "xcrun",
                "security",
                "xcrun",
            ])

        #expect(
            commands.map { $0.command.arguments } == [
                ["--version"],
                ["-p"],
                ["xcodebuild", "-version"],
                ["help"],
                ["simctl", "list", "--json"],
            ])
    }

    @Test("doctor Android tool checks omit Xcode toolchain")
    func doctorAndroidToolChecksOmitXcodeToolchain() {
        let commands = DoctorCommand.toolCheckCommands(shell: ShellContext(), platform: .android)

        #expect(
            commands.map(\.name) == [
                "git on PATH",
                "java on PATH (for Gradle)",
            ])

        #expect(
            commands.map { $0.command.executableName } == [
                "git",
                "java",
            ])
    }
}
#endif
