#if os(macOS)
import Foundation
import Testing

@testable import ShipItKit

struct CommandFamilyTests {
    @Test func buildsWhichCommand() {
        #expect(Which().tool("frameit").command().arguments == ["frameit"])
    }

    @Test func buildsBashScriptCommand() {
        let command = Bash().script("echo ok").command()

        #expect(command.executableName == "/bin/bash")
        #expect(command.arguments == ["-c", "echo ok"])
    }
}
#endif
