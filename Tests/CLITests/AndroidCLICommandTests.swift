import Testing

@testable import ShipItCLI

@Suite("AndroidCLICommand mutation gate")
struct AndroidCLICommandTests {
    @Test("read-only commands are never flagged as mutating", arguments: [
        ["info"],
        ["describe"],
        ["docs"],
        ["layout", "--pretty"],
        ["emulator", "list"],
        ["sdk", "list"],
        ["skills", "list", "--long"],
        ["skills", "find", "testing-setup"],
        ["studio", "check"],
        ["create", "--list"],
    ])
    func readOnlyCommandsAreSafe(arguments: [String]) {
        #expect(AndroidCLICommand.isMutating(arguments) == false)
    }

    @Test("known mutating commands require confirmation", arguments: [
        ["install", "app.apk"],
        ["update"],
        ["run", "app.apk"],
        ["init"],
        ["create", "--template", "compose-app"],
        ["emulator", "create", "Pixel_7"],
        ["emulator", "start", "Pixel_7"],
        ["emulator", "stop", "Pixel_7"],
        ["emulator", "remove", "Pixel_7"],
        ["sdk", "install", "platforms/android-36"],
        ["sdk", "update"],
        ["sdk", "remove", "platforms/android-30"],
        ["skills", "add", "testing-setup"],
        ["skills", "remove", "testing-setup"],
    ])
    func mutatingCommandsRequireConfirmation(arguments: [String]) {
        #expect(AndroidCLICommand.isMutating(arguments) == true)
    }

    @Test("an ambiguous conditional command fails closed as mutating")
    func ambiguousConditionalCommandFailsClosed() {
        #expect(AndroidCLICommand.isMutating(["emulator"]) == true)
        #expect(AndroidCLICommand.isMutating(["sdk"]) == true)
    }
}
