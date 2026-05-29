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
            {"type":"testDone","testID":3,"result":"success","skipped":true}
            """

        let parsed = try await FlutterMachineOutputParser().parse(machineOutput: output)

        #expect(parsed.summary.passed == 1)
        #expect(parsed.summary.failed == 1)
        #expect(parsed.summary.skipped == 1)
        #expect(parsed.testCases.first(where: { $0.name == "login offline" })?.rerunSelector == .flutter(name: "login offline"))
    }

    @Test("A skipped test reported as result:success with skipped:true counts as skipped, not passed")
    func skippedTestWithSuccessResultIsNotCountedAsPassed() async throws {
        // Real `flutter test --machine` output marks a skipped test with BOTH
        // result:"success" and skipped:true. The parser must classify it as
        // skipped, never passed.
        let output = """
            {"type":"testStart","test":{"id":1,"name":"ran normally"}}
            {"type":"testDone","testID":1,"result":"success"}
            {"type":"testStart","test":{"id":2,"name":"explicitly skipped"}}
            {"type":"testDone","testID":2,"result":"success","skipped":true}
            """

        let parsed = try await FlutterMachineOutputParser().parse(machineOutput: output)

        #expect(parsed.summary.passed == 1)
        #expect(parsed.summary.skipped == 1)
        #expect(parsed.summary.failed == 0)
        #expect(parsed.testCases.first(where: { $0.name == "explicitly skipped" })?.status == .skipped)
    }
}
