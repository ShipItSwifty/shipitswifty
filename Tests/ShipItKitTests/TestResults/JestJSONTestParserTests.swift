import Foundation
import Testing

@testable import ShipItKit

@Suite("JestJSONTestParser")
struct JestJSONTestParserTests {

    @Test("Parses Jest JSON output into normalized test cases")
    func parsesJestJSON() async throws {
        let temp = try makeTempDirectory(prefix: "JestJSON")
        defer { try? FileManager.default.removeItem(at: temp) }

        let file = temp.appendingPathComponent("jest-results.json")
        let json = """
            {
              "numFailedTests": 1,
              "numPassedTests": 1,
              "numPendingTests": 1,
              "numRuntimeErrorTestSuites": 0,
              "testResults": [
                {
                  "name": "src/login.test.ts",
                  "assertionResults": [
                    { "title": "logs in", "fullName": "login logs in", "status": "passed", "failureMessages": [] },
                    { "title": "handles offline", "fullName": "login handles offline", "status": "failed", "failureMessages": ["boom"] },
                    { "title": "todo path", "fullName": "login todo path", "status": "pending", "failureMessages": [] }
                  ]
                }
              ]
            }
            """
        try json.write(to: file, atomically: true, encoding: .utf8)

        let parsed = try await JestJSONTestParser().parse(jsonFilePath: file.path)

        #expect(parsed.summary.passed == 1)
        #expect(parsed.summary.failed == 1)
        #expect(parsed.summary.skipped == 1)
        #expect(
            parsed.testCases.first(where: { $0.name == "handles offline" })?.rerunSelector
                == .jest(file: "src/login.test.ts", fullName: "login handles offline"))
    }
}
