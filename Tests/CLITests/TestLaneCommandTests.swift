import ArgumentParser
import Testing

@testable import ShipItCLI

@Suite("Test lane commands")
struct TestLaneCommandTests {
    @Test("Swift package command accepts evidence, environment and retry options")
    func swiftCommand() throws {
        let command =
            try SwiftTestCommand.parseAsRoot([
                "--package-path", "Library", "--env", "SNAPSHOT_RECORD_MODE=never", "--code-coverage", "--rerun-failed-tests",
                "--infrastructure-attempts", "3",
            ]) as! SwiftTestCommand
        #expect(command.packagePath == "Library")
        #expect(command.environment == ["SNAPSHOT_RECORD_MODE=never"])
        #expect(command.infrastructureAttempts == 3)
    }
    @Test("Native command accepts named plans and explicit serial execution")
    func nativeCommand() throws {
        let command =
            try TestCommand.parseAsRoot(["--test-plans", "Default", "--test-plans", "Locales", "--serial", "--skip-macro-validation"])
            as! TestCommand
        #expect(command.testPlans == ["Default", "Locales"])
        #expect(command.serial)
    }
    @Test("Offline parser accepts repeated inputs and portable exports")
    func offlineCommand() throws {
        let command =
            try TestResultsCommand.parseAsRoot([
                "--input", "one.xml", "--input", "two.xml", "--input-format", "junit", "--runner", "kmp", "--export-directory", "evidence",
            ]) as! TestResultsCommand
        #expect(command.inputs.count == 2)
        #expect(command.exportDirectory == "evidence")
    }
    @Test("Provider export requires an explicit runner")
    func providerRequiresRunner() {
        #expect(throws: Error.self) { try CIExportCommand.parseAsRoot(["--workflow", "tests"]) }
    }
}
