import Testing

@testable import ShipItKit

@Suite("FlutterMachineOutputParser")
struct FlutterMachineOutputParserTests {

    @Test("Parses flutter machine output events into normalized test cases")
    func parsesMachineOutput() async throws {
        let output = """
            {"type":"testStart","test":{"id":1,"name":"login success"}}
            {"type":"testDone","testID":1,"result":"success"}
            {"type":"testStart","test":{"id":2,"name":"login offline"}}
            {"type":"testDone","testID":2,"result":"failure","message":"boom"}
            {"type":"testStart","test":{"id":3,"name":"legacy path"}}
            {"type":"testDone","testID":3,"skipped":true}
            """

        let parsed = try await FlutterMachineOutputParser().parse(machineOutput: output)

        #expect(parsed.summary.passed == 1)
        #expect(parsed.summary.failed == 1)
        #expect(parsed.summary.skipped == 1)
        #expect(parsed.testCases.first(where: { $0.name == "login offline" })?.rerunSelector == .flutter(name: "login offline"))
    }
}
