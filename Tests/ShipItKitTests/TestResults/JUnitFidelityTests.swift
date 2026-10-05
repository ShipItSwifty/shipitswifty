import Foundation
import SwiftyShell
import TestCommons
import Testing

@testable import ShipItKit

@Suite("JUnit fidelity")
struct JUnitFidelityTests {
    private func parse(_ xml: String, runner: TestRunner = .gradle, file: String = "TEST-S.xml") async throws -> ParsedTestRun {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let url = scratch.url.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return try await AndroidJUnitTestParser().parse(
            reportDirectory: url.path, runner: runner, identityRoot: scratch.url.path)
    }

    // MARK: Message and stack trace

    @Test("The message attribute and the stack trace body stay separate")
    func messageAndStackSeparate() async throws {
        let run = try await parse(
            """
            <testsuite name="S" tests="1" failures="1"><testcase classname="C" name="m"><failure message="expected 1 but was 2" type="java.lang.AssertionError">java.lang.AssertionError: expected 1 but was 2
            \tat C.m(C.kt:7)</failure></testcase></testsuite>
            """)
        let test = try #require(run.testCases.first)
        #expect(test.message == "expected 1 but was 2")
        #expect(test.stackTrace?.contains("at C.m(C.kt:7)") == true)
        #expect(test.metadata?["failure_type"] == "java.lang.AssertionError")
    }

    @Test("Without a message attribute the first line is the message and a multi-line body is the trace")
    func bodyOnlyFailure() async throws {
        let run = try await parse(
            """
            <testsuite name="S" tests="2" failures="2"><testcase classname="C" name="a"><failure>boom
            at C.a(C.kt:1)</failure></testcase><testcase classname="C" name="b"><failure>only a message</failure></testcase></testsuite>
            """)
        #expect(run.testCases[0].message == "boom")
        #expect(run.testCases[0].stackTrace == "boom\nat C.a(C.kt:1)")
        #expect(run.testCases[1].message == "only a message")
        #expect(run.testCases[1].stackTrace == nil)
    }

    // MARK: Retries

    @Test("Surefire flakyFailure marks a recovered test as flaky; rerunFailure records retries on a persistent failure")
    func surefireRetries() async throws {
        let run = try await parse(
            """
            <testsuite name="S" tests="2" failures="1"><testcase classname="C" name="recovers"><flakyFailure message="first try"><stackTrace>trace</stackTrace><system-out>earlier output</system-out></flakyFailure></testcase><testcase classname="C" name="stays"><failure message="boom"/><rerunFailure message="again"/></testcase></testsuite>
            """)
        let recovers = try #require(run.testCases.first { $0.name == "recovers" })
        #expect(recovers.status == .passed)
        #expect(recovers.metadata?["flaky"] == "true")
        #expect(recovers.attempts == 2, "one failed attempt plus the passing one")
        let stays = try #require(run.testCases.first { $0.name == "stays" })
        #expect(stays.status == .failed)
        #expect(stays.message == "boom", "a retry's message must not replace the final failure")
        #expect(stays.attempts == 2)
        #expect(run.summary.flaky == 1)
        #expect(run.diagnostics.allSatisfy { !$0.message.contains("earlier output") }, "retry output is not suite output")
    }

    // MARK: Retry plugins (one testcase per attempt)

    @Test("A test that failed then passed is one flaky test that keeps its attempt count")
    func retryThenPassIsFlaky() async throws {
        let run = try await parse(
            """
            <testsuite name="S" tests="2" failures="1"><testcase classname="C" name="m" time="0.5"><failure message="timeout waiting for element">at C.m(C.kt:7)</failure></testcase><testcase classname="C" name="m" time="0.25"/></testsuite>
            """)
        #expect(run.testCases.count == 1)
        let test = try #require(run.testCases.first)
        #expect(test.status == .passed)
        #expect(test.attempts == 2)
        #expect(test.metadata?["flaky"] == "true")
        #expect(test.metadata?["first_failure"] == "timeout waiting for element")
        #expect(test.durationSeconds == 0.25, "the deciding attempt")
        #expect(test.totalDurationSeconds == 0.75, "what the retries cost is visible")
        #expect(test.message == nil, "a recovered test carries no failure")
        #expect(test.stableID.hasSuffix("C.m"), "the plain ID, so a one-test rerun still lines up")
        #expect(run.summary.passed == 1)
        #expect(run.summary.failed == 0, "declared totals count attempts; the folded view must not")
        #expect(run.summary.flaky == 1)
        #expect(!run.diagnostics.contains { $0.message.contains("declare") })
    }

    @Test("A test that fails on every attempt is one failure with its attempt count")
    func retriesExhausted() async throws {
        let run = try await parse(
            """
            <testsuite name="S" tests="3" failures="3"><testcase classname="C" name="m" time="1"><failure message="a"/></testcase><testcase classname="C" name="m" time="1"><failure message="b"/></testcase><testcase classname="C" name="m" time="1"><failure message="c"/></testcase></testsuite>
            """)
        let test = try #require(run.testCases.first)
        #expect(run.testCases.count == 1)
        #expect(test.status == .failed)
        #expect(test.attempts == 3)
        #expect(test.message == "c", "the deciding attempt's failure")
        #expect(test.metadata?["first_failure"] == "a")
        #expect(test.metadata?["flaky"] == nil)
        #expect(test.totalDurationSeconds == 3)
        #expect(run.summary.failed == 1)
        #expect(run.summary.flaky == 0)
    }

    @Test("Several failed attempts before a pass are counted")
    func manyAttemptsThenPass() async throws {
        let run = try await parse(
            """
            <testsuite name="S" tests="3" failures="1" errors="1"><testcase classname="C" name="m"><failure message="a"/></testcase><testcase classname="C" name="m"><error message="b"/></testcase><testcase classname="C" name="m"/></testsuite>
            """)
        #expect(run.testCases.first?.attempts == 3)
        #expect(run.testCases.first?.status == .passed)
        #expect(run.summary.passed == 1)
        #expect(run.summary.failed == 0)
        #expect(run.summary.errored == 0)
    }

    @Test("Only the retried test is folded; others in the file are untouched")
    func foldingIsPerTest() async throws {
        let run = try await parse(
            """
            <testsuite name="S" tests="3" failures="1"><testcase classname="C" name="stable"/><testcase classname="C" name="flaky"><failure message="x"/></testcase><testcase classname="C" name="flaky"/></testsuite>
            """)
        #expect(run.testCases.map(\.name) == ["stable", "flaky"])
        #expect(run.testCases.map(\.attempts) == [1, 2])
        #expect(Set(run.suites.flatMap(\.testCaseIDs)) == Set(run.testCases.map(\.stableID)))
    }

    @Test("A name that repeats with every occurrence passing is a duplicate, not a retry")
    func passingDuplicatesStaySeparate() async throws {
        let run = try await parse(
            """
            <testsuite name="S" tests="3"><testcase classname="C" name="m"/><testcase classname="C" name="m"/><testcase classname="C" name="other"/></testsuite>
            """)
        let ids = run.testCases.map(\.stableID)
        #expect(run.testCases.count == 3)
        #expect(Set(ids).count == 3)
        #expect(ids[0].hasSuffix("C.m"))
        #expect(ids[1].hasSuffix("C.m#2"))
        #expect(run.testCases[0].metadata?["occurrence"] == "1/2")
        #expect(run.testCases[1].metadata?["occurrence"] == "2/2")
        #expect(run.testCases.allSatisfy { $0.attempts == 1 })
        #expect(run.summary.flaky == 0)
        #expect(run.summary.passed == 3)
    }

    @Test("Every test reports how many times it ran")
    func singleRunReportsOneAttempt() async throws {
        let run = try await parse("<testsuite name=\"S\" tests=\"1\"><testcase classname=\"C\" name=\"m\" time=\"0.1\"/></testsuite>")
        #expect(run.testCases.first?.attempts == 1)
        #expect(run.testCases.first?.totalDurationSeconds == nil, "no retries, nothing extra to report")
    }

    // MARK: Where a result came from

    @Test("Module, task and report location are recorded from the Gradle layout")
    func unitMetadata() async throws {
        let run = try await parse(
            "<testsuite name=\"S\"><testcase classname=\"C\" name=\"m\"/></testsuite>",
            file: "feature/home/build/test-results/testDebugUnitTest/TEST-C.xml")
        let metadata = try #require(run.testCases.first?.metadata)
        #expect(metadata["module"] == "feature/home")
        #expect(metadata["gradle_task"] == "testDebugUnitTest")
        #expect(metadata["report"] == "feature/home/build/test-results/testDebugUnitTest/TEST-C.xml")
    }

    @Test("Connected-test device, flavor and project come from the properties AGP writes")
    func connectedMetadata() async throws {
        let run = try await parse(
            """
            <testsuite name="S"><properties><property name="device" value="Pixel_6(AVD) - 13"/><property name="flavor" value="prod"/><property name="project" value=":app"/></properties><testcase classname="C" name="m"/></testsuite>
            """, file: "app/build/outputs/androidTest-results/connected/prod/TEST-pixel.xml")
        let metadata = try #require(run.testCases.first?.metadata)
        #expect(metadata["device"] == "Pixel_6(AVD) - 13")
        #expect(metadata["flavor"] == "prod")
        #expect(metadata["project"] == ":app")
        #expect(metadata["gradle_task"] == "connected")
        #expect(metadata["module"] == "app")
    }

    @Test("The same test on two devices stays distinct")
    func sameTestTwoDevices() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let directory = scratch.url.appendingPathComponent("app/build/outputs/androidTest-results/connected")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for device in ["pixel", "tablet"] {
            try
                "<testsuite name=\"S\"><properties><property name=\"device\" value=\"\(device)\"/></properties><testcase classname=\"C\" name=\"m\"/></testsuite>"
                .write(to: directory.appendingPathComponent("TEST-\(device).xml"), atomically: true, encoding: .utf8)
        }
        let run = try await AndroidJUnitTestParser().parse(reportDirectory: directory.path, identityRoot: scratch.url.path)
        #expect(Set(run.testCases.map(\.stableID)).count == 2)
        #expect(Set(run.testCases.compactMap { $0.metadata?["device"] }) == ["pixel", "tablet"])
    }

    // MARK: Totals

    @Test("A disagreement between declared and listed tests is reported, not hidden")
    func declaredVersusListed() async throws {
        let run = try await parse("<testsuite name=\"S\" tests=\"3\"><testcase classname=\"C\" name=\"only\"/></testsuite>")
        #expect(run.diagnostics.contains { $0.severity == .warning && $0.message.contains("declare 3") })
        #expect(run.summary.passed == 3, "declared counts still win so a report that omits passing cases is not under-counted")
    }

    @Test("A consistent report produces no totals warning")
    func consistentTotals() async throws {
        let run = try await parse("<testsuite name=\"S\" tests=\"1\"><testcase classname=\"C\" name=\"only\"/></testsuite>")
        #expect(!run.diagnostics.contains { $0.message.contains("declare") })
    }

    // MARK: The stack trace survives every path that rebuilds a test case

    @Test("stackTrace survives export, relocation, multi-input aggregation and reconciliation")
    func stackTraceSurvivesCopies() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let xml =
            "<testsuite name=\"S\" tests=\"1\" failures=\"1\"><testcase classname=\"C\" name=\"m\"><failure message=\"boom\">trace</failure></testcase></testsuite>"
        let first = scratch.url.appendingPathComponent("a.xml")
        let second = scratch.url.appendingPathComponent("b.xml")
        try xml.write(to: first, atomically: true, encoding: .utf8)
        try xml.write(to: second, atomically: true, encoding: .utf8)

        let aggregated = try await TestResultsAction().run(
            with: .init(inputs: [first.path, second.path]),
            context: .mock(executor: MockExecutor { _, _ in .init(stdout: "", stderr: "", exitCode: 0) }))
        #expect(aggregated.parsedRun.testCases.count == 2)
        #expect(aggregated.parsedRun.testCases.allSatisfy { $0.stackTrace == "trace" })

        let run = try await ResultInspection(shell: .init()).read(first.path)
        let output = scratch.url.appendingPathComponent("export")
        _ = try await EvidenceExporter(shell: .init()).export(runs: [run], sources: [], to: output.path)
        let moved = scratch.url.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: output, to: moved)
        let restored = try await ResultInspection(shell: .init()).read(moved.path)
        #expect(restored.testCases.first?.stackTrace == "trace")

        let reconciled = finalTestCases(run.testCases, remaining: [], flaky: run.testCases)
        #expect(reconciled.first?.stackTrace == "trace")
        #expect(reconciled.first?.attempts == 1)
        #expect(reconciled.first?.status == .passed)
    }
}
