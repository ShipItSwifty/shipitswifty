import Foundation
import SwiftyShell
import TestCommons
import Testing

@testable import ShipItKit

@Suite("Portable result inspection")
struct ResultInspectionTests {
    @Test("JUnit preserves error, stack, duration and output; malformed XML fails")
    func junitDetails() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let path = scratch.url.appendingPathComponent("results.xml")
        try """
        <testsuite name="Suite"><testcase classname="C" name="method" time="1.25"><error message="boom">stack</error></testcase><system-out>console</system-out></testsuite>
        """.write(to: path, atomically: true, encoding: .utf8)
        let run = try await ResultInspection(shell: .init()).read(path.path, runner: .gradle, buildSystem: .kmp)
        let test = try #require(run.testCases.first)
        #expect(run.runner == .gradle)
        #expect(run.buildSystem == .kmp)
        #expect(run.summary.errored == 1)
        #expect(run.summary.failed == 0)
        #expect(test.durationSeconds == 1.25)
        #expect(test.message == "boom")
        #expect(test.stackTrace == "stack")
        #expect(run.diagnostics.first?.message == "console")
        try "<testsuite><testcase".write(to: path, atomically: true, encoding: .utf8)
        await #expect(throws: ShipItError.self) { _ = try await ResultInspection(shell: .init()).read(path.path) }
    }

    @Test("Flutter IDs survive event renumbering and incomplete runs remain errors")
    func flutterIdentity() async throws {
        let first = try await FlutterMachineOutputParser().parse(
            machineOutput: """
                {"type":"testStart","test":{"id":1,"name":"checkout"}}
                {"type":"error","testID":1,"error":"offline","stackTrace":"stack"}
                """)
        let second = try await FlutterMachineOutputParser().parse(
            machineOutput: """
                {"type":"testStart","test":{"id":7,"name":"checkout"}}
                {"type":"testDone","testID":7,"result":"success"}
                """)
        #expect(first.testCases.first?.stableID == second.testCases.first?.stableID)
        #expect(first.summary.errored == 1)
        #expect(first.testCases.first?.message == "offline\nstack")
    }

    @Test("LCOV merges overlapping lines and portable export survives relocation")
    func coverageAndExport() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let input = scratch.url.appendingPathComponent("lcov.info")
        try "SF:lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\nSF:lib/a.dart\nDA:1,2\nend_of_record\n".write(
            to: input, atomically: true, encoding: .utf8)
        let coverage = try await PortableCoverageReader().read(input.path, format: .lcov)
        #expect(coverage.executableLines == 2)
        #expect(coverage.overallLineCoverage == 50)
        let output = scratch.url.appendingPathComponent("export")
        let manifest = try await EvidenceExporter(shell: .init()).export(runs: [], sources: [], coverage: [coverage], to: output.path)
        let moved = scratch.url.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: output, to: moved)
        for entry in manifest.entries { #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent(entry.path).path)) }
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("index.md").path))
        await #expect(throws: ShipItError.self) {
            _ = try await EvidenceExporter(shell: .init()).export(runs: [], sources: [], to: moved.path)
        }
    }

    @Test("Filtering does not change full-run summary")
    func filtering() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let path = scratch.url.appendingPathComponent("results.xml")
        try "<testsuite><testcase name=\"pass\"/><testcase name=\"fail\"><failure/></testcase></testsuite>".write(
            to: path, atomically: true, encoding: .utf8)
        let result = try await TestResultsAction().run(
            with: .init(inputs: [path.path], failedOnly: true),
            context: .mock(executor: MockExecutor { _, _ in .init(stdout: "", stderr: "", exitCode: 0) }))
        #expect(result.parsedRun.testCases.count == 1)
        #expect(result.report.summary.passed == 1)
        #expect(result.report.summary.failed == 1)
    }
    @Test("LLVM line coverage counts the closing line and excludes skipped regions")
    func llvmLines() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let path = scratch.url.appendingPathComponent("coverage.json")
        try """
        {"data":[{"files":[{"filename":"Sources/Feature/a.swift","segments":[[1,1,3,true,true,false],[3,2,0,false,false,false],[4,1,0,false,true,false],[6,1,0,true,true,false],[6,5,0,false,false,false]]}]}]}
        """.write(to: path, atomically: true, encoding: .utf8)
        let coverage = try await PortableCoverageReader().read(path.path, format: .swift, sourceRoots: ["Sources/Feature"])
        #expect(coverage.executableLines == 4)
        #expect(coverage.coveredLines == 3)
        #expect(coverage.overallLineCoverage == 75)
    }

    @Test("JaCoCo package totals do not include duplicate class/method counters")
    func jacocoCounters() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let path = scratch.url.appendingPathComponent("coverage.xml")
        try """
        <report><package name="com/example/feature"><class name="C"><method name="m"><counter type="LINE" covered="3" missed="1"/></method><counter type="LINE" covered="3" missed="1"/></class><sourcefile name="C.kt"><counter type="LINE" covered="3" missed="1"/></sourcefile><counter type="LINE" covered="3" missed="1"/></package><counter type="LINE" covered="3" missed="1"/></report>
        """.write(to: path, atomically: true, encoding: .utf8)
        let coverage = try await PortableCoverageReader().read(path.path, format: .kover)
        #expect(coverage.executableLines == 4)
        #expect(coverage.coveredLines == 3)
    }

    @Test("Portable normalized results remain readable through a relocated manifest")
    func relocatedManifest() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let report = ParsedTestRun(
            runner: .flutterTest, buildSystem: .flutter, source: "events.jsonl", summary: .init(passed: 1),
            testCases: [.init(stableID: "case", name: "test", status: .passed)])
        let output = scratch.url.appendingPathComponent("export")
        _ = try await EvidenceExporter(shell: .init()).export(runs: [report], sources: [], to: output.path)
        let moved = scratch.url.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: output, to: moved)
        let run = try await ResultInspection(shell: .init()).read(moved.appendingPathComponent("manifest.json").path)
        #expect(run.summary.passed == 1)
        #expect(run.testCases.first?.name == "test")
    }

}

@Suite("Result integrity")
struct ResultIntegrityTests {
    private let idle = MockExecutor { _, _ in .init(stdout: "", stderr: "", exitCode: 0) }

    // MARK: Missing results are never a passing zero-test run

    @Test("A result that cannot be parsed is recorded as an error even when the process exited 0")
    func recorderFlagsUnparsableResults() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        var context = ActionContext.mock(executor: idle)
        let recorder = TestEvidenceRecorder(root: scratch.url.appendingPathComponent("evidence"))
        context.testEvidence = recorder
        struct Unreadable: Error {}
        _ = try await executeRecordedTest(
            SwiftPMCLI(context: context.shell).formatLint(paths: ["Sources"]), context: context,
            parse: { _ in throw Unreadable() })
        try await recorder.writeProvisionalReport(executionError: false)
        let report = try JSONDecoder().decode(
            TestRunReport.self, from: Data(contentsOf: scratch.url.appendingPathComponent("evidence/report.json")))
        #expect(report.summary.errored == 1)
        #expect(report.summary.passed == 0)
        let run = try JSONDecoder().decode(
            ParsedTestRun.self, from: Data(contentsOf: scratch.url.appendingPathComponent("evidence/attempt-1/results.json")))
        #expect(run.diagnostics.first?.severity == .error)
        #expect(run.diagnostics.first?.message.contains("Unreadable") == true)
    }

    @Test("A parser that finds nothing is recorded as an error, not as zero tests")
    func recorderFlagsMissingResults() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        var context = ActionContext.mock(executor: idle)
        let recorder = TestEvidenceRecorder(root: scratch.url.appendingPathComponent("evidence"))
        context.testEvidence = recorder
        _ = try await executeRecordedTest(
            SwiftPMCLI(context: context.shell).formatLint(paths: ["Sources"]), context: context, parse: { _ in nil })
        try await recorder.writeProvisionalReport(executionError: false)
        let report = try JSONDecoder().decode(
            TestRunReport.self, from: Data(contentsOf: scratch.url.appendingPathComponent("evidence/report.json")))
        #expect(report.summary.errored == 1)
    }

    @Test("A Flutter run that reports no tests fails and writes an error report")
    func flutterSilentSuccessFails() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let reportPath = scratch.url.appendingPathComponent("report.json").path
        let context = ActionContext.mock(
            executor: MockExecutor { _, _ in .init(stdout: "", stderr: "", exitCode: 0) }, platform: .android,
            config: ResolvedConfig(platform: .android, androidBuildSystem: .flutter))
        await #expect(throws: ShipItError.self) {
            _ = try await TestAction().run(with: .init(reportPath: reportPath), context: context)
        }
        let report = try JSONDecoder().decode(TestRunReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
        #expect(report.summary.errored == 1)
    }

    @Test("Offline inspection rejects artifacts without outcomes")
    func offlineEmptyResultsFail() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let inspection = ResultInspection(shell: .init())
        let empty = scratch.url.appendingPathComponent("empty.xml")
        try "<testsuite name=\"S\" tests=\"0\"/>".write(to: empty, atomically: true, encoding: .utf8)
        await #expect(throws: ShipItError.self) { _ = try await inspection.read(empty.path) }
        let events = scratch.url.appendingPathComponent("events.jsonl")
        try "{\"type\":\"start\"}\n{\"type\":\"error\",\"error\":\"compile failed\"}\n".write(to: events, atomically: true, encoding: .utf8)
        await #expect(throws: ShipItError.self) { _ = try await inspection.read(events.path) }
    }

    // MARK: Stale Gradle results

    @Test("Results from an earlier run are cleared, so a run that executes nothing cannot reuse them")
    func staleResultsAreCleared() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let reports = scratch.url.appendingPathComponent("app/build/test-results/testDebugUnitTest")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        try "<testsuite name=\"S\"><testcase classname=\"C\" name=\"old\"><failure message=\"stale\"/></testcase></testsuite>".write(
            to: reports.appendingPathComponent("TEST-C.xml"), atomically: true, encoding: .utf8)
        var context = ActionContext.mock(
            executor: MockExecutor { _, _ in .init(stdout: "Compilation failed", stderr: "", exitCode: 1) })
        context.testEvidence = TestEvidenceRecorder(root: scratch.url.appendingPathComponent("evidence"))
        let action = TestAction()
        let project = scratch.url.path
        _ = try await executeRecordedTest(
            SwiftPMCLI(context: context.shell).formatLint(paths: []), context: context,
            parse: { _ in try await action.parseJUnitReports(projectDir: project, task: "testDebugUnitTest") },
            staleResults: { junitReportDirectories(projectDir: project, task: "testDebugUnitTest") })
        #expect(junitReportDirectories(projectDir: project, task: "testDebugUnitTest").isEmpty)
        let run = try JSONDecoder().decode(
            ParsedTestRun.self, from: Data(contentsOf: scratch.url.appendingPathComponent("evidence/attempt-1/results.json")))
        #expect(run.testCases.isEmpty)
        #expect(run.summary.errored == 1)
    }

    @Test("Gradle discovery reads exact modules and skips build outputs and dependency trees")
    func gradleDiscovery() throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        for path in [
            "app/build/test-results/testDebugUnitTest", "feature/home/build/test-results/testDebugUnitTest",
            "app/build/test-results/testReleaseUnitTest", "node_modules/pkg/build/test-results/testDebugUnitTest",
            "app/build/intermediates/nested/build/test-results/testDebugUnitTest",
            "app/build/outputs/androidTest-results/connected",
        ] { try FileManager.default.createDirectory(at: scratch.url.appendingPathComponent(path), withIntermediateDirectories: true) }
        let root = scratch.url.path
        // The system temp directory sits behind a /var -> /private/var symlink; compare from the unique leaf.
        func relative(_ urls: [URL]) -> [String] {
            urls.map { $0.path.components(separatedBy: scratch.url.lastPathComponent + "/").last ?? $0.path }
        }
        #expect(
            relative(junitReportDirectories(projectDir: root, task: "testDebugUnitTest")) == [
                "app/build/test-results/testDebugUnitTest", "feature/home/build/test-results/testDebugUnitTest",
            ])
        #expect(
            relative(junitReportDirectories(projectDir: root, task: ":feature:home:testDebugUnitTest")) == [
                "feature/home/build/test-results/testDebugUnitTest"
            ])
        #expect(
            relative(junitReportDirectories(projectDir: root, task: ":app:connectedDebugAndroidTest")) == [
                "app/build/outputs/androidTest-results/connected"
            ])
    }

    // MARK: Live and offline identities agree

    @Test("Live runs and offline inspection assign the same machine-independent test IDs")
    func identitiesMatchAcrossLiveAndOffline() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        try "".write(to: scratch.url.appendingPathComponent("settings.gradle"), atomically: true, encoding: .utf8)
        for module in ["app", "feature"] {
            let reports = scratch.url.appendingPathComponent("\(module)/build/test-results/testDebugUnitTest")
            try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
            try "<testsuite name=\"S\"><testcase classname=\"Same\" name=\"works\"/></testsuite>".write(
                to: reports.appendingPathComponent("TEST-Same.xml"), atomically: true, encoding: .utf8)
        }
        let live = try #require(
            await TestAction().parseJUnitReports(projectDir: scratch.url.path, task: "testDebugUnitTest", buildSystem: .kmp))
        #expect(live.buildSystem == .kmp)
        #expect(live.destinations.map(\.platform) == [.android], "a unit-test task is Android on the host JVM")
        let liveIDs = live.testCases.map(\.stableID)
        #expect(Set(liveIDs).count == 2, "the same test in two modules must stay distinct")
        #expect(!liveIDs.contains { $0.contains(scratch.url.lastPathComponent) }, "IDs must not embed machine-specific paths")
        let offline = try await ResultInspection(shell: .init()).read(
            scratch.url.appendingPathComponent("app/build/test-results/testDebugUnitTest").path)
        #expect(Set(offline.testCases.map(\.stableID)).isSubset(of: Set(liveIDs)))
    }

    // MARK: JUnit CDATA

    @Test("Stack traces and output delivered as CDATA are preserved")
    func junitCDATA() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let path = scratch.url.appendingPathComponent("TEST-C.xml")
        try """
        <testsuite name="S" tests="1" failures="1"><testcase classname="C" name="m"><failure message="boom"><![CDATA[at C.m(C.kt:7)]]></failure></testcase><system-out><![CDATA[console line]]></system-out></testsuite>
        """.write(to: path, atomically: true, encoding: .utf8)
        let run = try await ResultInspection(shell: .init()).read(path.path)
        #expect(run.testCases.first?.message == "boom")
        #expect(run.testCases.first?.stackTrace == "at C.m(C.kt:7)")
        #expect(run.diagnostics.first?.message == "console line")
    }

    // MARK: Workflow artifact collection

    @Test("Automatic collection takes reports but never build products or paths already in the evidence root")
    func automaticCollectionIsEvidenceOnly() throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let ipa = scratch.url.appendingPathComponent("App.ipa")
        let report = scratch.url.appendingPathComponent("tests.json")
        let evidence = scratch.url.appendingPathComponent("evidence")
        let inside = evidence.appendingPathComponent("test-runs/swift-1")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try "signed".write(to: ipa, atomically: true, encoding: .utf8)
        try "{}".write(to: report, atomically: true, encoding: .utf8)
        try collectWorkflowArtifacts(
            step: "step-1", action: "export", declarations: [],
            payload: .object([
                "ipaPath": .string(ipa.path), "archivePath": .string(ipa.path), "reportPath": .string(report.path),
                "outputDirectory": .string(inside.path),
            ]), status: "success", root: evidence.path)
        let manifest = try JSONDecoder().decode(
            WorkflowArtifactRecord.self, from: Data(contentsOf: evidence.appendingPathComponent("step-1/manifest.json")))
        #expect(manifest.entries.map { URL(fileURLWithPath: $0.source).lastPathComponent } == ["tests.json"])
    }

    @Test("Declared artifacts still collect build products, and one unreadable file does not abort the rest")
    func declaredArtifactsAreExplicit() throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let ipa = scratch.url.appendingPathComponent("App.ipa")
        try "signed".write(to: ipa, atomically: true, encoding: .utf8)
        let evidence = scratch.url.appendingPathComponent("evidence")
        try collectWorkflowArtifacts(
            step: "step-1", action: "export", declarations: [.init(name: "binaries", paths: [ipa.path])], payload: nil,
            status: "success", root: evidence.path)
        let manifest = try JSONDecoder().decode(
            WorkflowArtifactRecord.self, from: Data(contentsOf: evidence.appendingPathComponent("step-1/manifest.json")))
        #expect(manifest.entries.count == 1)
    }

    @Test("A glob walks only its literal directory prefix")
    func globSearchRoot() throws {
        #expect(artifactSearchRoot(for: "/work/proj/build/*.log").path == "/work/proj/build")
        #expect(artifactSearchRoot(for: "/work/proj/*.log").path == "/work/proj")
        #expect(artifactSearchRoot(for: "/work/proj/build/ci/*/unit").path == "/work/proj/build/ci")
        #expect(artifactSearchRoot(for: "/work/**/x?.txt").path == "/work")
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        for file in ["build/a.log", "build/b.txt", "build/nested/c.log", "other/d.log"] {
            let url = scratch.url.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x".write(to: url, atomically: true, encoding: .utf8)
        }
        let direct = try artifactMatches(scratch.url.appendingPathComponent("build/*.log").path)
        #expect(direct.map(\.lastPathComponent) == ["a.log"])
        let recursive = try artifactMatches(scratch.url.appendingPathComponent("build/**/*.log").path)
        #expect(recursive.map(\.lastPathComponent).sorted() == ["a.log", "c.log"])
    }
}
