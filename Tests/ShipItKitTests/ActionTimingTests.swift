import Foundation
import SwiftyShell
import Testing

@testable import ShipItKit

@Suite("Action timing & duration formatting")
struct ActionTimingTests {

    // A minimal action used to exercise the descriptor's timing wrapper.
    private struct SleepyAction: Action {
        static let name = "sleepy"
        static let description = "Sleeps briefly, for timing tests."

        struct Options: Codable, Sendable {}
        struct Result: Codable, Sendable { let ok: Bool }

        func run(with options: Options, context: ActionContext) async throws -> Result {
            try await Task.sleep(for: .milliseconds(20))
            return Result(ok: true)
        }
    }

    @Test("descriptor.runJSON records a non-nil, plausible durationSeconds")
    func descriptorRecordsDuration() async throws {
        let descriptor = SleepyAction.descriptor(for: SleepyAction())
        let context = ActionContext.mock(
            executor: MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
        )

        let envelope = try await descriptor.runJSON(nil, context)

        #expect(envelope.status == "success")
        let duration = try #require(envelope.durationSeconds)
        #expect(duration >= 0.02)  // slept 20ms
        #expect(duration < 5.0)  // sanity upper bound
    }

    @Test("durationSeconds round-trips through the envelope's JSON encoding")
    func durationSurvivesJSON() throws {
        let envelope = ActionResultEnvelope(
            action: "build", status: "success", payload: nil, durationSeconds: 12.5)
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ActionResultEnvelope.self, from: data)
        #expect(decoded.durationSeconds == 12.5)
    }

    @Test("skipped/void envelopes default durationSeconds to nil")
    func defaultsToNil() {
        let envelope = ActionResultEnvelope(action: "x", status: "skipped", payload: nil)
        #expect(envelope.durationSeconds == nil)
    }

    @Test(
        "formatDurationSeconds renders sub-minute as seconds and longer as m/s",
        arguments: [
            (1.23, "1.2s"),
            (42.0, "42.0s"),
            (59.9, "59.9s"),
            (60.0, "1m 0s"),
            (90.0, "1m 30s"),
            (901.0, "15m 1s"),
        ])
    func formatsDuration(_ seconds: Double, _ expected: String) {
        #expect(formatDurationSeconds(seconds) == expected)
    }

    @Test("Duration.totalSeconds combines whole seconds and fractional attoseconds")
    func durationTotalSeconds() {
        #expect(Duration.seconds(3).totalSeconds == 3.0)
        #expect(abs(Duration.milliseconds(1500).totalSeconds - 1.5) < 1e-9)
    }

    @Test("streamingGradle streams (.tee) in human mode but captures in JSON-output mode")
    func streamingGradleRespectsJSONOutput() {
        let executor = MockExecutor { _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }

        let humanContext = ActionContext.mock(executor: executor, platform: .android, jsonOutput: false)
        #expect(humanContext.streamingGradle().stdoutDestination == .tee)
        #expect(humanContext.streamingGradle().stderrDestination == .tee)

        let jsonContext = ActionContext.mock(executor: executor, platform: .android, jsonOutput: true)
        // In JSON mode it must not stream to stdout — fall back to capture so the JSON result is clean.
        #expect(jsonContext.streamingGradle().stdoutDestination == .capture)
        #expect(jsonContext.streamingGradle().stderrDestination == .capture)
    }
}
