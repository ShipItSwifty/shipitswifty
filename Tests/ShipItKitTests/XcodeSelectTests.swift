import Testing

@testable import ShipItKit

struct XcodeSelectTests {
    @Test func buildsPrintPathCommand() {
        let command = XcodeSelect()
            .printPath()
            .command()

        #expect(command.executableName == "xcode-select")
        #expect(command.arguments == ["-p"])
    }
}
