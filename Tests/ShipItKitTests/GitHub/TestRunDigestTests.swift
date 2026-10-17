import Foundation
import MobileTesting
import TestCommons
import Testing

@testable import ShipItKit

@Suite("Test fingerprints and digests")
struct TestRunDigestTests {
    @Test("A fingerprint ignores the plan and destination position ShipIt prefixes to a stable ID")
    func fingerprintIgnoresPosition() {
        let first = xcodeCase("AppTests/CartTests/testTotal()", position: "plan-1:destination-1:")
        let reordered = xcodeCase("AppTests/CartTests/testTotal()", position: "plan-3:destination-2:")
        #expect(TestFingerprint.make(for: first, runner: .xcodebuild) == TestFingerprint.make(for: reordered, runner: .xcodebuild))
    }

    @Test("A fingerprint separates tests, plans and runners")
    func fingerprintSeparates() {
        let base = xcodeCase("AppTests/CartTests/testTotal()")
        let other = xcodeCase("AppTests/CartTests/testTax()")
        let otherPlan = xcodeCase("AppTests/CartTests/testTotal()", plan: "UITests")
        let keys = [
            TestFingerprint.make(for: base, runner: .xcodebuild), TestFingerprint.make(for: other, runner: .xcodebuild),
            TestFingerprint.make(for: otherPlan, runner: .xcodebuild), TestFingerprint.make(for: base, runner: .gradle),
        ]
        #expect(Set(keys).count == 4)
        #expect(keys[0].count == 16)
    }

    @Test("Without a rerun selector the identity is the stable ID minus its position")
    func identityFallsBackToStableID() {
        let bare = ParsedTestCase(stableID: "plan-2:destination-1:com.example.FooTest.bar", name: "bar", status: .failed)
        #expect(TestFingerprint.identity(of: bare) == "com.example.FooTest.bar")
    }

    @Test("Consistent failures, flaky tests and clean passes are told apart")
    func classifies() {
        let digest = TestRunDigest(
            reports: [
                makeReport(
                    failing: [xcodeCase("A/B/testBroken()", file: "/work/App/BTests.swift", line: 42, attempts: 3)],
                    flaky: [xcodeCase("A/B/testSometimes()", attempts: 2)], passed: [xcodeCase("A/B/testFine()", status: .passed)])
            ])
        #expect(digest.consistentFailures.map(\.id) == ["A/B/testBroken()"])
        #expect(digest.consistentFailures.first?.attempts == 3)
        #expect(digest.consistentFailures.first?.line == 42)
        #expect(digest.flakyTests.map(\.id) == ["A/B/testSometimes()"])
        #expect(digest.passedFingerprints == [TestFingerprint.make(for: xcodeCase("A/B/testFine()", status: .passed), runner: .xcodebuild)])
        #expect(digest.attempts.map(\.reason) == ["initial", "failed_tests"])
        #expect(digest.runErrors == 0)
    }

    @Test("A failure reports the executions of every attempt, not just the first one")
    func attemptsComeFromReconciledCases() {
        let firstSight = xcodeCase("A/B/testBroken()", attempts: 1)
        let reconciled = firstSight.copy(attempts: .some(3))
        let report = TestRunReport(
            runner: .xcodebuild, source: "x", persistentFailedTests: [firstSight], summary: TestSummary(failed: 1), testCases: [reconciled])
        #expect(TestRunDigest(reports: [report]).consistentFailures.first?.attempts == 3)
    }

    @Test("Only the first line of a failure message is kept, never the stack trace")
    func messageIsBounded() {
        let long = "first line\n   at Foo.swift:1\n   at Bar.swift:2"
        let digest = TestRunDigest(reports: [makeReport(failing: [xcodeCase("A/B/t()", message: long)])])
        #expect(digest.consistentFailures.first?.message == "first line")
        let huge = TestRunDigest(reports: [makeReport(failing: [xcodeCase("A/B/t()", message: String(repeating: "x", count: 900))])])
        #expect((huge.consistentFailures.first?.message?.count ?? 0) <= 301)
    }

    @Test("Policy: flaky passes unless asked to fail, a failing test or a broken run never passes")
    func policy() {
        let flakyOnly = TestRunDigest(reports: [makeReport(flaky: [xcodeCase("A/B/t()")])])
        #expect(flakyOnly.passes())
        #expect(!flakyOnly.passes(failOnFlaky: true))

        let failing = TestRunDigest(reports: [makeReport(failing: [xcodeCase("A/B/t()")])])
        #expect(!failing.passes())

        let broken = TestRunDigest(reports: [makeReport(errored: 1)])
        #expect(broken.runErrors == 1)
        #expect(broken.consistentFailures.isEmpty)
        #expect(!broken.passes())

        #expect(TestRunDigest(reports: [makeReport(passed: [xcodeCase("A/B/t()", status: .passed)])]).passes(failOnFlaky: true))
    }

    @Test("An errored test is a failure, not a run error")
    func erroredTestIsNotARunError() {
        let digest = TestRunDigest(reports: [makeReport(failing: [xcodeCase("A/B/t()", status: .errored)])])
        #expect(digest.consistentFailures.count == 1)
        #expect(digest.runErrors == 0)
    }

    @Test("Shard reports merge, and a test failing in two shards is listed once")
    func merges() {
        let shardOne = makeReport(failing: [xcodeCase("A/B/shared()", attempts: 2)], passed: [xcodeCase("A/B/one()", status: .passed)])
        let shardTwo = makeReport(
            failing: [xcodeCase("A/B/shared()", position: "plan-1:destination-2:", attempts: 3)],
            passed: [xcodeCase("A/B/two()", status: .passed)])
        let digest = TestRunDigest(reports: [shardOne, shardTwo])
        #expect(digest.reportCount == 2)
        #expect(digest.passed == 2)
        #expect(digest.consistentFailures.count == 1)
        #expect(digest.consistentFailures.first?.attempts == 3)
        #expect(digest.passedFingerprints.count == 2)
    }

    @Test("A test that failed in one shard is never counted as a clean pass from another")
    func failureBeatsPass() {
        let failed = makeReport(failing: [xcodeCase("A/B/t()")])
        let passed = makeReport(passed: [xcodeCase("A/B/t()", status: .passed)])
        let digest = TestRunDigest(reports: [failed, passed])
        #expect(digest.passedFingerprints.isEmpty)
    }

    @Test("Loading rejects a missing file, a non-report and an unsupported schema")
    func loadRejects() throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        #expect(throws: ShipItError.self) { try TestRunDigest.load(reportPaths: []) }
        #expect(throws: ShipItError.self) { try TestRunDigest.load(reportPaths: [scratch.url.appendingPathComponent("none.json").path]) }

        let garbage = scratch.url.appendingPathComponent("garbage.json")
        try "{\"hello\":1}".write(to: garbage, atomically: true, encoding: .utf8)
        #expect(throws: ShipItError.self) { try TestRunDigest.load(reportPaths: [garbage.path]) }

        let old = scratch.url.appendingPathComponent("old.json")
        let report = makeReport(passed: [xcodeCase("A/B/t()", status: .passed)])
        let legacy = TestRunReport(schemaVersion: 1, runner: .xcodebuild, source: "x", summary: report.summary)
        try JSONEncoder().encode(legacy).write(to: old)
        #expect {
            _ = try TestRunDigest.load(reportPaths: [old.path])
        } throws: { error in
            guard case ShipItError.invalidConfiguration(let reason) = error else { return false }
            return reason.contains("schema 1")
        }
    }

    @Test("Loading reads what the test command writes")
    func loadRoundTrip() throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let path = scratch.url.appendingPathComponent("report.json")
        try writeJSON(makeReport(failing: [xcodeCase("A/B/t()")]), to: path)
        let digest = try TestRunDigest.load(reportPaths: [path.path])
        #expect(digest.consistentFailures.count == 1)
    }
}
