import Foundation
import SwiftyShell
import Synchronization
import TestCommons
import Testing

@testable import ShipItKit

@Suite("Shared test lanes")
struct TestLaneTests {
    @Test("SwiftPM commands retain argument boundaries and strict format options")
    func swiftCommandArguments() {
        let tool = SwiftPMCLI()
        #expect(
            tool.test(
                package: "package path", scratch: "scratch path", events: "events.jsonl",
                attachments: "attachments", coverage: true, skipBuild: true, filter: "Suite/test", skip: "Integration",
                junit: "xctest.xml"
            ).command().arguments == [
                "test", "--package-path", "package path", "--parallel",
                "--event-stream-output-path", "events.jsonl", "--xunit-output", "xctest.xml", "--scratch-path", "scratch path",
                "--attachments-path", "attachments", "--enable-code-coverage", "--skip-build", "--filter", "Suite/test", "--skip",
                "Integration",
            ])
        #expect(
            tool.formatLint(paths: ["Sources"], configuration: ".swift-format").command().arguments == [
                "format", "lint", "--recursive", "--strict", "--configuration", ".swift-format", "Sources",
            ])
    }

    @Test("Interrupted Swift tests preserve partial logs and an error report")
    func interruptedSwiftEvidence() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let executor = MockExecutor { command, _ in
            throw ShellError.canceled(
                command: CommandSnapshot(command), partialOutput: .init(stdout: "partial output", stderr: "partial error", exitCode: 130))
        }
        let root = scratch.url.appendingPathComponent("run")
        do {
            _ = try await SwiftTestAction().run(with: .init(outputDirectory: root.path), context: .mock(executor: executor))
            Issue.record("Cancellation must propagate")
        } catch ShellError.canceled {}
        #expect(try String(contentsOf: root.appendingPathComponent("attempt-1/stdout.log"), encoding: .utf8) == "partial output")
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: root.appendingPathComponent("report.json")))
        #expect(report.summary.errored == 1)
    }

    @Test("SwiftPM reruns reuse products, retain logs, and report recovery as flaky")
    func swiftRecovery() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let calls = Mutex([[String]]())
        let executor = MockExecutor { command, _ in
            calls.withLock { $0.append(command.arguments) }
            let args = command.arguments
            guard let flag = args.firstIndex(of: "--event-stream-output-path") else { return .init(stdout: "", stderr: "", exitCode: 0) }
            let failed = !args.contains("--skip-build")
            let path = args[flag + 1]
            let issue =
                failed
                ? "{\"kind\":\"event\",\"payload\":{\"kind\":\"issueRecorded\",\"testID\":\"Tests.Suite/test()\",\"messages\":[{\"text\":\"boom\"}]}}\n"
                : ""
            let events = """
                {"kind":"test","payload":{"kind":"function","id":"Tests.Suite/test()","name":"test"}}
                {"kind":"event","payload":{"kind":"testStarted","testID":"Tests.Suite/test()","instant":{"absolute":1}}}
                \(issue){"kind":"event","payload":{"kind":"testEnded","testID":"Tests.Suite/test()","instant":{"absolute":2}}}
                """
            try events.write(toFile: path, atomically: true, encoding: .utf8)
            return .init(stdout: "output", stderr: failed ? "test failed" : "", exitCode: failed ? 1 : 0)
        }
        let output = scratch.url.appendingPathComponent("run")
        let result = try await SwiftTestAction().run(
            with: .init(outputDirectory: output.path, rerunFailedTests: .init(enabled: true, maxAttempts: 2)),
            context: .mock(executor: executor))
        #expect(result.succeeded)
        #expect(result.report.summary.flaky == 1)
        #expect(result.report.attempts.map(\.reason) == ["initial", "failed_tests"])
        #expect(calls.withLock { $0.count } == 2)
        #expect(calls.withLock { $0[1].contains("--skip-build") })
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("attempt-1/stderr.log").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("attempt-2/events.jsonl").path))
    }

    @Test("Failed steps collect evidence and independent steps continue")
    func workflowFailureArtifacts() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let file = scratch.url.appendingPathComponent("failure.log")
        try "failure evidence".write(to: file, atomically: true, encoding: .utf8)
        let registry = ActionRegistry()
        try await registry.register(
            ActionDescriptor(
                name: "broken", description: "",
                runJSON: { _, _ in
                    throw ShipItError.testFailed(exitCode: 1, failureCount: 1, log: "failed")
                }))
        try await registry.register(
            ActionDescriptor(
                name: "later", description: "",
                runJSON: { _, _ in
                    ActionResultEnvelope(action: "later", status: "success", payload: nil)
                }))
        let lane = Workflow(
            "test",
            steps: [
                .init(action: "broken", artifacts: [.init(name: "logs", paths: [file.path])]), .init(action: "later"),
            ], continueOnFailure: true)
        let result = try await lane.run(
            context: .mock(executor: MockExecutor { _, _ in .init(stdout: "", stderr: "", exitCode: 0) }), registry: registry)
        #expect(!result.succeeded)
        #expect(result.stepResults.map(\.status) == ["failure", "success"])
    }

    @Test("Provider exports failure-safe uploads and quotes shell arguments")
    func providerExport() throws {
        let yaml = try GitHubActionsProvider().export(
            workflow: "tests",
            config: .init(steps: [
                .init(action: "swift-test", artifacts: [.init(name: "results", paths: ["build/test-runs/**"], retentionDays: 7)])
            ]), job: .init(runner: "macos-26", setupCommands: ["swift build"], executable: "./shipit"))
        #expect(yaml.contains("always()"))
        #expect(yaml.contains("actions/upload-artifact@v7"))
        #expect(yaml.contains("retention-days: 7"))
        #expect(yaml.contains("step-1/results"))
    }

    #if os(macOS)
    @Test("An unreadable native rerun retains the original failures and passing counts")
    func unreadableNativeRerun() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let count = Mutex(0)
        let executor = MockExecutor { command, _ in
            let args = command.arguments
            if args.contains("test-without-building") {
                count.withLock { $0 += 1 }
                return .init(stdout: "test failed", stderr: "", exitCode: 65)
            }
            if args.contains("summary") { return .init(stdout: "{}", stderr: "", exitCode: 0) }
            if args.contains("tests") {
                let json =
                    count.withLock { $0 } == 1
                    ? "{\"testNodes\":[{\"nodeType\":\"Test Case\",\"nodeIdentifier\":\"AppTests/C/failing()\",\"result\":\"Failed\"},{\"nodeType\":\"Test Case\",\"nodeIdentifier\":\"AppTests/C/passing()\",\"result\":\"Passed\"}]}"
                    : "{\"testNodes\":[]}"
                return .init(stdout: json, stderr: "", exitCode: 0)
            }
            return .init(stdout: "", stderr: "", exitCode: 0)
        }
        let reportPath = scratch.url.appendingPathComponent("report.json")
        do {
            _ = try await TestAction().run(
                with: .init(
                    scheme: "App", destination: "platform=macOS",
                    rerunFailedTests: .init(enabled: true, maxAttempts: 2), reportPath: reportPath.path), context: .mock(executor: executor)
            )
            Issue.record("An unreadable rerun must fail")
        } catch ShipItError.testFailed {}
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: reportPath))
        #expect(report.summary.passed == 1)
        #expect(report.summary.failed == 1)
        #expect(report.summary.errored == 1)
        #expect(report.persistentFailedTests.count == 1)
    }

    @Test("Two plans share one build and cloning switches remaining execution to serial")
    func nativeCloneFallback() async throws {
        let commands = Mutex([[String]]())
        let testCount = Mutex(0)
        let executor = MockExecutor { command, _ in
            let args = command.arguments
            commands.withLock { $0.append(args) }
            if args.contains("test-without-building") {
                let count = testCount.withLock {
                    $0 += 1
                    return $0
                }
                if count == 1 {
                    return .init(
                        stdout: "", stderr: "Failed to clone device named 'Phone'. device remained in Creating state after fixup completed",
                        exitCode: 65)
                }
                return .init(stdout: "Test passed", stderr: "", exitCode: 0)
            }
            if args.contains("summary") { return .init(stdout: "{\"metrics\":{\"testsCount\":1}}", stderr: "", exitCode: 0) }
            if args.contains("tests") {
                return .init(
                    stdout: "{\"testNodes\":[{\"nodeType\":\"Test Case\",\"nodeIdentifier\":\"AppTests/C/test()\",\"result\":\"Passed\"}]}",
                    stderr: "", exitCode: 0)
            }
            return .init(stdout: "", stderr: "", exitCode: 0)
        }
        let result = try await TestAction().run(
            with: .init(scheme: "App", destination: "platform=iOS Simulator,id=mock", testPlans: ["A", "B"]),
            context: .mock(executor: executor))
        let recorded = commands.withLock { $0 }
        #expect(recorded.filter { $0.contains("build-for-testing") }.count == 1)
        let tests = recorded.filter { $0.contains("test-without-building") }
        #expect(tests.count == 3)
        #expect(!tests[0].contains("-parallel-testing-enabled"))
        #expect(tests[1].contains("NO"))
        #expect(tests[2].contains("NO"))
        #expect(result.report?.attempts.contains { $0.reason == "serial_fallback" } == true)
        #expect(result.passCount == 2)
    }
    #endif
    @Test("SwiftPM infrastructure retries have separate evidence and a bounded budget")
    func swiftInfrastructure() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let count = Mutex(0)
        let executor = MockExecutor { command, _ in
            let number = count.withLock {
                $0 += 1
                return $0
            }
            if number == 1 { return .init(stdout: "", stderr: "Connection reset by peer", exitCode: 1) }
            let args = command.arguments
            let flag = try #require(args.firstIndex(of: "--event-stream-output-path"))
            try """
            {"kind":"test","payload":{"kind":"function","id":"Tests.Suite/test()","name":"test"}}
            {"kind":"event","payload":{"kind":"testStarted","testID":"Tests.Suite/test()","instant":{"absolute":1}}}
            {"kind":"event","payload":{"kind":"testEnded","testID":"Tests.Suite/test()","instant":{"absolute":2}}}
            """.write(toFile: args[flag + 1], atomically: true, encoding: .utf8)
            return .init(stdout: "", stderr: "", exitCode: 0)
        }
        let result = try await SwiftTestAction().run(
            with: .init(
                outputDirectory: scratch.url.appendingPathComponent("run").path,
                infrastructureRetry: .init(maxAttempts: 2, initialDelaySeconds: 0, maxDelaySeconds: 0)), context: .mock(executor: executor))
        #expect(result.succeeded)
        #expect(result.report.summary.flaky == 0)
        #expect(result.report.attempts.map(\.reason) == ["initial", "infrastructure"])
        #expect(count.withLock { $0 } == 2)
    }

    @Test("Missing SwiftPM structured results fail and retain a final error report")
    func missingSwiftResults() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let directory = scratch.url.appendingPathComponent("run")
        await #expect(throws: ShipItError.self) {
            _ = try await SwiftTestAction().run(
                with: .init(outputDirectory: directory.path),
                context: .mock(executor: MockExecutor { _, _ in .init(stdout: "passed", stderr: "", exitCode: 0) }))
        }
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: directory.appendingPathComponent("report.json")))
        #expect(report.summary.errored == 1)
    }

    @Test("Flutter retries match stable names and preserve machine events")
    func flutterRecovery() async throws {
        let count = Mutex(0)
        let commands = Mutex([[String]]())
        let executor = MockExecutor { command, _ in
            commands.withLock { $0.append(command.arguments) }
            let number = count.withLock {
                $0 += 1
                return $0
            }
            return .init(
                stdout: """
                    {"type":"testStart","test":{"id":\(number),"name":"checkout"}}
                    {"type":"testDone","testID":\(number),"result":"\(number == 1 ? "failure" : "success")"}
                    """, stderr: "", exitCode: number == 1 ? 1 : 0)
        }
        let context = ActionContext.mock(
            executor: executor, platform: .android, config: ResolvedConfig(platform: .android, androidBuildSystem: .flutter))
        let result = try await TestAction().run(with: .init(rerunFailedTests: .init(enabled: true, maxAttempts: 2)), context: context)
        #expect(result.report?.summary.flaky == 1)
        #expect(result.report?.persistentFailedTests.isEmpty == true)
        #expect(commands.withLock { $0.last?.contains("--name") } == true)
    }

    #if os(macOS)
    @Test("Lease ownership is exclusive and compatible with amoo's JSON")
    func simulatorLeaseOwnership() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let shell = ShellContext(executor: MockExecutor { _, _ in .init(stdout: "", stderr: "", exitCode: 0) })
        let lease = try await SimulatorLease.acquire(device: "device", shell: shell, directory: scratch.url)
        defer { lease.release() }
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: lease.file)) as? [String: Any])
        #expect(object["deviceID"] as? String == "device")
        #expect(object["platform"] as? String == "ios")
        await #expect(throws: ShipItError.self) {
            _ = try await SimulatorLease.acquire(device: "device", shell: shell, directory: scratch.url)
        }
        lease.release()
        #expect(!FileManager.default.fileExists(atPath: lease.file.path))
    }

    @Test("Native success without result data is an execution failure, not a passing zero-test run")
    func missingNativeResults() async throws {
        await #expect(throws: ShipItError.self) {
            _ = try await TestAction().run(
                with: .init(scheme: "App", destination: "platform=iOS Simulator,id=mock"),
                context: .mock(executor: MockExecutor { _, _ in .init(stdout: "", stderr: "", exitCode: 0) }))
        }
    }
    #endif

}
