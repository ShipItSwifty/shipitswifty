import Foundation
import Testing

@testable import ShipItCLI

@Suite("Documentation command examples")
struct DocumentationCommandTests {
    @Test("Every Android quickstart command parses")
    func androidQuickstartCommandsParse() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let quickstartURL = repositoryRoot.appendingPathComponent("docs/android-quickstart.md")
        let contents = try String(contentsOf: quickstartURL, encoding: .utf8)
        let commands = contents.split(separator: "\n").filter { $0.hasPrefix("shipit ") }

        try #require(commands.isEmpty == false)
        for command in commands {
            let arguments = command.split(whereSeparator: \Character.isWhitespace).dropFirst().map(String.init)
            do {
                _ = try ShipItCLI.parseAsRoot(arguments)
            } catch {
                Issue.record("Documented command does not parse: \(command) — \(error)")
            }
        }
    }
}
