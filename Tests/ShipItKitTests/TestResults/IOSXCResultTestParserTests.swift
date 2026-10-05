#if os(macOS)
import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("IOSXCResultTestParser")
struct IOSXCResultTestParserTests {

    @Test("Parses xcresulttool summary and tests JSON into normalized test cases")
    func parsesXCResultToolJSON() async throws {
        let summaryJSON = """
            {
              "metrics": {
                "testsCount": 3,
                "testsFailedCount": 1,
                "testsSkippedCount": 1
              }
            }
            """

        let testsJSON = """
            {
              "name": "Root",
              "subtests": [
                {
                  "name": "MyAppTests/LoginTests",
                  "subtests": [
                    {
                      "identifier": "MyAppTests/LoginTests/testSuccessfulLogin()",
                      "name": "testSuccessfulLogin()",
                      "testStatus": "Success",
                      "duration": 0.5
                    },
                    {
                      "identifier": "MyAppTests/LoginTests/testFailedLogin()",
                      "name": "testFailedLogin()",
                      "testStatus": "Failure",
                      "duration": 0.7,
                      "failureText": "XCTAssertEqual failed"
                    },
                    {
                      "identifier": "MyAppTests/LoginTests/testLegacyLogin()",
                      "name": "testLegacyLogin()",
                      "testStatus": "Skipped"
                    }
                  ]
                }
              ]
            }
            """

        let executor = MockExecutor { command, _ in
            let description = command.description
            if description.contains("xcresulttool get test-results summary") {
                return ShellOutput(stdout: summaryJSON, stderr: "", exitCode: 0)
            }
            if description.contains("xcresulttool get test-results tests") {
                return ShellOutput(stdout: testsJSON, stderr: "", exitCode: 0)
            }
            return ShellOutput(stdout: "", stderr: "unexpected command", exitCode: 1)
        }
        let shell = ShellContext(executor: executor)
        let parser = IOSXCResultTestParser(shell: shell)

        let run = try await parser.parse(xcresultPath: "/tmp/MyApp-tests.xcresult")

        #expect(run.runner == .xcodebuild)
        #expect(run.summary.passed == 1)
        #expect(run.summary.failed == 1)
        #expect(run.summary.skipped == 1)
        #expect(run.testCases.count == 3)
        #expect(
            run.testCases.first(where: { $0.name == "testFailedLogin()" })?.rerunSelector
                == .xcodeOnlyTesting("MyAppTests/LoginTests/testFailedLogin()"))
    }

    @Test("Surfaces xcresulttool failures as invalid configuration")
    func surfacesXCResultToolFailures() async throws {
        let executor = MockExecutor { _, _ in
            throw ShellError.exitFailure(
                command: "xcrun xcresulttool",
                output: ShellOutput(stdout: "", stderr: "bundle not found", exitCode: 64)
            )
        }
        let parser = IOSXCResultTestParser(shell: ShellContext(executor: executor))

        do {
            _ = try await parser.parse(xcresultPath: "/tmp/missing.xcresult")
            Issue.record("Expected IOSXCResultTestParser to throw")
        } catch let error as ShipItError {
            guard case .invalidConfiguration = error else {
                Issue.record("Expected invalidConfiguration, got \(error)")
                return
            }
        }
    }
    @Test("Modern configuration leaves retain independent outcomes, target selectors and messages")
    func modernConfigurations() async throws {
        let executor = MockExecutor { command, _ in
            if command.arguments.contains("summary") {
                return .init(stdout: "{\"failedTests\":1,\"passedTests\":0}", stderr: "", exitCode: 0)
            }
            if command.arguments.contains("test-details") {
                return .init(
                    stdout: """
                        {"testRuns":[{"nodeType":"Test Plan Configuration","name":"English","result":"Passed"},{"nodeType":"Test Plan Configuration","name":"German","result":"Failed","children":[{"nodeType":"Failure Message","name":"XCTAssertEqual failed"}]}]}
                        """, stderr: "", exitCode: 0)
            }
            return .init(
                stdout: """
                    {"devices":[{"deviceName":"Phone","deviceId":"UDID","osVersion":"27.2"}],"testPlanConfigurations":[{"configurationName":"English"},{"configurationName":"German"}],"testNodes":[{"nodeType":"UI test bundle","name":"AppUITests","children":[{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Failed"}]}]}
                    """, stderr: "", exitCode: 0)
        }
        let run = try await IOSXCResultTestParser(shell: ShellContext(executor: executor)).parse(xcresultPath: "sample.xcresult")
        #expect(run.testCases.count == 2)
        #expect(run.summary.passed == 1)
        #expect(run.summary.failed == 1)
        let failure = try #require(run.testCases.first(where: { $0.status == .failed }))
        #expect(failure.metadata?["configuration"] == "German")
        #expect(failure.metadata?["runtime"] == "27.2")
        #expect(failure.message == "XCTAssertEqual failed")
        #expect(failure.rerunSelector == .xcodeOnlyTesting("AppUITests/Suite/test()"))
    }

    @Test("Each result-bundle device becomes a destination and its tests point at it")
    func devicesBecomeDestinations() async throws {
        func parse(device: String) async throws -> ParsedTestRun {
            let executor = MockExecutor { command, _ in
                if command.arguments.contains("summary") {
                    return .init(stdout: "{\"failedTests\":0,\"passedTests\":1}", stderr: "", exitCode: 0)
                }
                return .init(
                    stdout: """
                        {"devices":[\(device)],"testNodes":[{"nodeType":"Unit test bundle","name":"AppTests","children":[{"nodeType":"Test Case","nodeIdentifier":"Suite/test()","result":"Passed"}]}]}
                        """, stderr: "", exitCode: 0)
            }
            return try await IOSXCResultTestParser(shell: ShellContext(executor: executor)).parse(xcresultPath: "sample.xcresult")
        }
        let simulator = try await parse(
            device: "{\"deviceName\":\"iPhone 16\",\"deviceId\":\"UDID\",\"osVersion\":\"18.2\",\"platform\":\"iOS Simulator\"}")
        let phone = try #require(simulator.destinations.first)
        #expect(simulator.destinations.count == 1)
        #expect(phone.platform == .ios)
        #expect(phone.kind == .simulator)
        #expect(phone.name == "iPhone 16")
        #expect(simulator.testCases.first?.destinationID == phone.id)

        let mac = try await parse(device: "{\"deviceName\":\"My Mac\",\"deviceId\":\"MAC\",\"platform\":\"macOS\"}")
        #expect(mac.destinations.first?.platform == .macos)
        #expect(mac.destinations.first?.kind == .host)

        let unlabeled = try await parse(device: "{\"deviceName\":\"Phone\",\"deviceId\":\"UDID\"}")
        #expect(unlabeled.destinations.first?.platform == .unknown, "a device that does not say its platform is not guessed")
        #expect(unlabeled.destinations.first?.name == "Phone")
    }

}
#endif
