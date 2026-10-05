import Foundation
import SwiftyShell
import Synchronization
import TestCommons
import Testing

@testable import ShipItKit

/// Replays artifacts captured from real tools (Gradle 9.8 with the `test-retry` plugin, `xcodebuild` and
/// `xcresulttool` on an iOS 27.2 simulator) instead of hand-written approximations. When a tool changes its
/// output, these fail first. See `Fixtures/real/README.md` for how each was captured.
@Suite("Real tool output")
struct RealFormatTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/real")

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: Gradle with the test-retry plugin

    @Test("Real Gradle test-retry XML folds attempts into one test each")
    func gradleTestRetry() async throws {
        let directory = Self.root.appendingPathComponent("gradle-test-retry/build/test-results/test")
        let run = try await ResultInspection(shell: .init()).read(directory.path, format: .junit, runner: .gradle)
        #expect(run.runner == .gradle)
        #expect(run.testCases.count == 4, "four tests, though the report holds seven entries (one per attempt)")
        func test(_ name: String) throws -> ParsedTestCase { try #require(run.testCases.first { $0.name == name }) }

        let flaky = try test("flaky()")
        #expect(flaky.status == .passed)
        #expect(flaky.attempts == 2)
        #expect(flaky.metadata?["flaky"] == "true")
        #expect(flaky.metadata?["first_failure"]?.contains("flaky first attempt") == true)

        let alwaysFails = try test("alwaysFails()")
        #expect(alwaysFails.status == .failed)
        #expect(alwaysFails.attempts == 3)
        #expect(alwaysFails.metadata?["flaky"] == nil)
        #expect(alwaysFails.stackTrace?.contains("ProbeTest.java:8") == true)
        #expect(alwaysFails.message?.contains("always fails") == true)

        #expect(try test("passes()").attempts == 1)
        #expect(try test("skipped()").status == .skipped)
        #expect(run.summary == .init(passed: 2, failed: 1, skipped: 1, flaky: 1, errored: 0))
        #expect(!run.diagnostics.contains { $0.severity == .warning }, "declared totals count attempts; the fold must account for that")
        #expect(run.destinations.map(\.platform) == [.jvm], "the plain `test` task of a JVM project")
        #expect(run.destinations.first?.scope == "test")
    }

    @Test("Gradle's console counts attempts, which is why the XML is authoritative")
    func gradleConsoleCountsAttempts() throws {
        let log = try Self.text("gradle-test-retry.console.log")
        let counts = TestAction().parseGradleCounts(from: log)
        #expect(counts.fail == 3, "the console reports `3 failed` for a run with one failing test")
        let xml = Self.root.appendingPathComponent("gradle-test-retry/build/test-results/test")
        #expect(try String(contentsOf: xml.appendingPathComponent("TEST-probe.ProbeTest.xml"), encoding: .utf8).contains("tests=\"7\""))
    }

    @Test("NO-SOURCE is recognized for the test task itself, not for other tasks")
    func gradleNoSource() throws {
        let noSource = try Self.text("gradle-no-source.console.log")
        let failing = try Self.text("gradle-test-retry.console.log")
        let action = TestAction()
        #expect(action.gradleTaskHadNothingToRun(noSource, task: "test"))
        #expect(action.gradleTaskHadNothingToRun(noSource, task: ":test"))
        #expect(!action.gradleTaskHadNothingToRun(failing, task: "test"), "`> Task :test FAILED` is not an empty run")
        // `compileJava` also says NO-SOURCE in the failing run's log; that says nothing about the tests.
        #expect(failing.contains("> Task :compileJava NO-SOURCE"))
        #expect(!action.gradleTaskHadNothingToRun(failing, task: "test"))
    }

    @Test("A real compile failure is not a failed test named after a Gradle task")
    func gradleCompileFailureIsNotAFailedTest() throws {
        let log = try Self.text("gradle-compile-failure.console.log")
        #expect(log.contains("> Task :compileTestJava FAILED"), "the captured log really is a compile failure")
        let parsed = TestAction().parseGradleCounts(from: log)
        #expect(parsed.failedTests.isEmpty, "`> Task ... FAILED` is a build step, not a test: \(parsed.failedTests)")
        #expect(parsed.fail == 0)
    }

    // MARK: xcodebuild and xcresulttool

    #if os(macOS)
    private func parse(_ directory: String) async throws -> ParsedTestRun {
        let summary = try Self.text("\(directory)/summary.json")
        let tests = try Self.text("\(directory)/tests.json")
        let executor = MockExecutor { command, _ in
            command.arguments.contains("summary")
                ? .init(stdout: summary, stderr: "", exitCode: 0) : .init(stdout: tests, stderr: "", exitCode: 0)
        }
        return try await IOSXCResultTestParser(shell: ShellContext(executor: executor)).parse(xcresultPath: "real.xcresult")
    }

    @Test("A real result bundle's device becomes a destination with its human name")
    func realXCResultDestination() async throws {
        let run = try await parse("xcresult-recovered")
        #expect(run.runner == .xcodebuild)
        #expect(run.testCases.map(\.name).sorted() == ["testArithmetic()", "testBundleIdentifier()"])
        #expect(run.summary.passed == 2)
        let destination = try #require(run.destinations.first)
        #expect(run.destinations.count == 1)
        #expect(destination.platform == .ios)
        #expect(destination.kind == .simulator, "`platform` is \"iOS Simulator\" in real output")
        #expect(destination.name == "iPhone 17")
        #expect(run.testCases.allSatisfy { $0.destinationID == destination.id })
    }

    @Test("A real simulator clone failure is one failed pseudo-test, and the classifier recognizes its log")
    func realCloneFailure() async throws {
        let run = try await parse("xcresult-clone-failure")
        let failure = try #require(run.testCases.first)
        #expect(run.testCases.count == 1)
        #expect(failure.name == "The test runner encountered an error")
        #expect(failure.status == .failed)
        #expect(failure.message?.contains("Failed to clone device named 'iPhone 17'") == true)

        let classifier = IOSInfrastructureClassifier()
        #expect(classifier.failureKind(log: try Self.text("xcresult-clone-failure/xcodebuild.log")) == .clone)
        #expect(classifier.failureKind(log: try Self.text("xcresult-recovered/xcodebuild.log")) != .clone)
    }

    @Test("The native workflow recovers from a real clone failure serially and reports the real device")
    func nativeWorkflowReplaysRealCloneFailure() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let failureLog = try Self.text("xcresult-clone-failure/xcodebuild.log")
        let recoveredLog = try Self.text("xcresult-recovered/xcodebuild.log")
        let attempts = Mutex(0)
        let executor = MockExecutor { command, _ in
            let args = command.arguments
            if args.contains("test-without-building") {
                let number = attempts.withLock {
                    $0 += 1
                    return $0
                }
                return number == 1
                    ? .init(stdout: "", stderr: failureLog, exitCode: 65) : .init(stdout: recoveredLog, stderr: "", exitCode: 0)
            }
            // xcresulttool: the first attempt's bundle is the clone failure, the second's is the recovery.
            if args.contains("summary") || args.contains("tests") {
                let directory =
                    (args.firstIndex(of: "--path").map { args[$0 + 1] } ?? "").contains("attempt-1")
                    ? "xcresult-clone-failure" : "xcresult-recovered"
                return .init(
                    stdout: try Self.text("\(directory)/\(args.contains("summary") ? "summary" : "tests").json"), stderr: "", exitCode: 0)
            }
            return .init(stdout: "", stderr: "", exitCode: 0)
        }
        var context = ActionContext.mock(executor: executor)
        context.evidenceRoot = scratch.url.path
        let result = try await TestAction().run(
            with: .init(scheme: "ios-sample", destination: "platform=iOS Simulator,id=91D4F57C-42BF-4630-8799-32B377B67A02"),
            context: context)
        let report = try #require(result.report)

        #expect(report.attempts.map(\.reason) == ["initial", "serial_fallback"])
        #expect(report.attempts.first?.metadata?["exit_code"] == "65")
        #expect(report.attempts.last?.metadata?["serial"] == "true")
        #expect(result.passCount == 2)
        #expect(report.summary.failed == 0)
        // The specifier names the simulator only by UDID, which differs per machine; the bundle knows it is an iPhone 17.
        #expect(report.destinations.map(\.id) == ["ios:simulator:iPhone 17"])
        #expect(report.testCases?.allSatisfy { $0.destinationID == "ios:simulator:iPhone 17" } == true)
    }
    #endif
}

@Suite("SwiftPM coverage")
struct SwiftPMCoverageTests {
    /// A scratch `.build/.../Products/Debug` layout: `codecov/` with raw profiles, and a test binary beside it.
    private func layout(
        _ scratch: TemporaryDirectory, json: Bool, profiles: [String] = ["a.profraw", "b.profraw"], binaries: [String] = ["T.xctest"]
    ) throws -> (codecov: URL, source: String, target: URL) {
        let products = scratch.url.appendingPathComponent("Products")
        let codecov = products.appendingPathComponent("codecov")
        try FileManager.default.createDirectory(at: codecov, withIntermediateDirectories: true)
        for name in profiles { try "raw".write(to: codecov.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        for name in binaries {
            #if os(macOS)
            let executable = products.appendingPathComponent("\(name)/Contents/MacOS/\(name.replacingOccurrences(of: ".xctest", with: ""))")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "bin".write(to: executable, atomically: true, encoding: .utf8)
            #else
            try "bin".write(to: products.appendingPathComponent(name), atomically: true, encoding: .utf8)
            #endif
        }
        if json {
            try "{\"data\":[\"from-swiftpm\"]}".write(to: codecov.appendingPathComponent("Pkg.json"), atomically: true, encoding: .utf8)
        }
        let output = scratch.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return (codecov, codecov.appendingPathComponent("Pkg.json").path, output.appendingPathComponent("coverage.json"))
    }

    /// Stands in for `llvm-profdata` and `llvm-cov`, reporting each call to `record`.
    private func llvmTools(record: @escaping @Sendable ([String]) -> Void) -> MockExecutor {
        MockExecutor { command, _ in
            record(command.arguments)
            return .init(stdout: command.arguments.contains("export") ? "{\"data\":[\"recomputed\"]}" : "", stderr: "", exitCode: 0)
        }
    }

    @Test("When SwiftPM wrote no JSON (a test failed), coverage is recomputed from the raw profiles")
    func recomputedFromRawProfiles() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let paths = try layout(scratch, json: false)
        let calls = Mutex([[String]]())
        try await saveSwiftPMCoverage(
            source: paths.source, target: paths.target,
            shell: ShellContext(executor: llvmTools { args in calls.withLock { $0.append(args) } }))
        #expect(try String(contentsOf: paths.target, encoding: .utf8).contains("recomputed"))
        let recorded = calls.withLock { $0 }
        let merge = try #require(recorded.first { $0.contains("merge") })
        #expect(merge.contains { $0.hasSuffix("a.profraw") } && merge.contains { $0.hasSuffix("b.profraw") })
        #expect(merge.last?.hasSuffix("initial.profdata") == true, "merged next to the saved coverage, not into SwiftPM's directory")
        let export = try #require(recorded.first { $0.contains("export") })
        #expect(export.contains { $0.hasSuffix("initial.profdata") })
    }

    @Test("When SwiftPM did write its JSON for a single test product, it is copied as is")
    func existingJSONIsCopied() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let paths = try layout(scratch, json: true)
        let calls = Mutex([[String]]())
        try await saveSwiftPMCoverage(
            source: paths.source, target: paths.target,
            shell: ShellContext(executor: llvmTools { args in calls.withLock { $0.append(args) } }))
        #expect(try String(contentsOf: paths.target, encoding: .utf8).contains("from-swiftpm"))
        #expect(calls.withLock { $0.isEmpty }, "no LLVM tools are needed")
    }

    @Test("With neither JSON nor profiles there is no coverage, and saying so is an error rather than an empty file")
    func nothingToSave() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let paths = try layout(scratch, json: false, profiles: [])
        await #expect(throws: ShipItError.self) {
            try await saveSwiftPMCoverage(
                source: paths.source, target: paths.target, shell: ShellContext(executor: llvmTools { _ in }))
        }
        #expect(!FileManager.default.fileExists(atPath: paths.target.path))
    }

    @Test("Several test products are exported together")
    func severalProductsExportedTogether() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let paths = try layout(scratch, json: false, binaries: ["A.xctest", "B.xctest"])
        let calls = Mutex([[String]]())
        try await saveSwiftPMCoverage(
            source: paths.source, target: paths.target,
            shell: ShellContext(executor: llvmTools { args in calls.withLock { $0.append(args) } }))
        let export = try #require(calls.withLock { $0 }.first { $0.contains("export") })
        #expect(export.contains("-object"), "the second product is passed with -object")
    }
}

@Suite("Real Flutter machine output")
struct RealFlutterTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/real/flutter-machine")

    private func parse(_ name: String) async throws -> ParsedTestRun {
        let events = try String(contentsOf: Self.directory.appendingPathComponent(name), encoding: .utf8)
        return try await FlutterMachineOutputParser().parse(machineOutput: events)
    }

    private func status(_ run: ParsedTestRun, _ name: String) throws -> TestCaseStatus {
        try #require(run.testCases.first { $0.name == name }, "no test named \(name)").status
    }

    @Test("A real failing run: failures keep their message and stack, the skip is a skip, the loading pseudo-test is hidden")
    func realFirstAttempt() async throws {
        let run = try await parse("first-attempt.jsonl")
        #expect(run.runner == .flutterTest)
        #expect(run.buildSystem == .flutter)
        #expect(run.testCases.count == 4, "the hidden `loading <file>` test is not a test")
        #expect(try status(run, "Scripted passes") == .passed)
        #expect(try status(run, "Scripted skipped on purpose") == .skipped, "`skipped: true` arrives with `result: success`")
        #expect(try status(run, "Scripted flaky") == .failed)
        #expect(try status(run, "Scripted always fails when asked") == .failed)
        #expect(run.summary == .init(passed: 1, failed: 2, skipped: 1, flaky: 0, errored: 0))
        let flaky = try #require(run.testCases.first { $0.name == "Scripted flaky" })
        #expect(flaky.message?.contains("fails on the first attempt only") == true)
        #expect(flaky.message?.contains("scripted_test.dart") == true, "the stack trace from the error event is kept")
        #expect(flaky.attempts == 1)
    }

    @Test("Real output is not pure JSONL: text before the events and JSON arrays are tolerated")
    func realOutputHasNoise() throws {
        let lines = try String(contentsOf: Self.directory.appendingPathComponent("first-attempt.jsonl"), encoding: .utf8)
            .components(separatedBy: .newlines).filter { !$0.isEmpty }
        let objects = lines.filter { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) is [String: Any] }
        #expect(lines.count > objects.count, "the capture really contains non-event lines")
        #expect(lines.contains { !$0.hasPrefix("{") && !$0.hasPrefix("[") }, "plain text from `flutter pub get`")
        #expect(lines.contains { $0.hasPrefix("[") }, "VM-service events arrive as JSON arrays")
    }

    @Test("A rerun by name renumbers every event ID, yet each test keeps the stable ID it had before")
    func realRerunKeepsIdentity() async throws {
        let first = try await parse("first-attempt.jsonl")
        let rerun = try await parse("rerun-by-name.jsonl")
        #expect(rerun.testCases.count == 2)
        #expect(try status(rerun, "Scripted flaky") == .passed, "its marker exists now")
        #expect(try status(rerun, "Scripted always fails when asked") == .failed)
        for name in ["Scripted flaky", "Scripted always fails when asked"] {
            let before = try #require(first.testCases.first { $0.name == name })
            let after = try #require(rerun.testCases.first { $0.name == name })
            #expect(before.stableID == after.stableID, "\(name) must reconcile across attempts")
        }
        // The rerun selector is the name, matching what `flutter test --name` needs.
        let flaky = try #require(first.testCases.first { $0.name == "Scripted flaky" })
        #expect(flaky.rerunSelector == .flutter(name: "Scripted flaky"))
    }

    @Test("A real all-passing run, and a flaky-only run, summarize correctly")
    func realPassingAndFlakyOnly() async throws {
        let passing = try await parse("all-passing.jsonl")
        #expect(passing.summary == .init(passed: 3, failed: 0, skipped: 1, flaky: 0, errored: 0))
        let flakyOnly = try await parse("flaky-only-first-attempt.jsonl")
        #expect(flakyOnly.summary == .init(passed: 2, failed: 1, skipped: 1, flaky: 0, errored: 0))
    }

    @Test("Saved real events are detected and read the same through the shared reader")
    func realFileThroughSharedReader() async throws {
        let path = Self.directory.appendingPathComponent("first-attempt.jsonl").path
        let run = try await ResultInspection(shell: .init()).read(path)
        #expect(run.runner == .flutterTest)
        #expect(run.testCases.count == 4)
        #expect(run.destinations.isEmpty, "saved events do not say where the tests ran")
    }
}

@Suite("Real Jest output")
struct RealJestTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/real/jest")

    private func parse(_ name: String) async throws -> ParsedTestRun {
        try await JestJSONTestParser().parse(
            jsonFilePath: Self.directory.appendingPathComponent(name).path, buildSystem: .reactNative, identityRoot: "/project")
    }

    private func test(_ name: String, in run: ParsedTestRun) throws -> ParsedTestCase {
        try #require(run.testCases.first { $0.name == name }, "no test named \(name)")
    }

    @Test("A real Jest run: identities are relative to the project, and every test records where it ran")
    func realFirstAttempt() async throws {
        let run = try await parse("first-attempt.json")
        #expect(run.runner == .jest)
        #expect(run.buildSystem == .reactNative)
        #expect(run.destinations == [TestDestination(platform: .js, kind: .host)])
        #expect(run.testCases.count == 40)
        #expect(run.summary.failed == 2)
        #expect(run.summary.skipped == 1)
        #expect(run.summary.passed == 37)
        let flaky = try test("flaky", in: run)
        #expect(flaky.status == .failed)
        #expect(flaky.stableID == "jest-case:__tests__/scripted.test.js::Scripted flaky", "no machine-specific path")
        #expect(flaky.rerunSelector == .jest(file: "__tests__/scripted.test.js", fullName: "Scripted flaky"))
        #expect(flaky.message?.contains("Expected: false") == true)
        #expect(run.testCases.allSatisfy { !$0.stableID.hasPrefix("jest-case:/") }, "no absolute paths in any identity")
        #expect(run.testCases.allSatisfy { $0.attempts == 1 && $0.destinationID == "js:host" })
        #expect(run.suites.allSatisfy { !$0.name.hasPrefix("/") })
    }

    @Test("A rerun by name reports the unselected tests as skipped, so they resolve nothing")
    func realRerun() async throws {
        let first = try await parse("first-attempt.json")
        let rerun = try await parse("rerun-by-name.json")
        #expect(try test("flaky", in: rerun).status == .passed, "its marker exists now")
        #expect(try test("always fails when asked", in: rerun).status == .failed)
        #expect(try test("passes", in: rerun).status == .skipped, "not selected by the pattern")
        for name in ["flaky", "always fails when asked"] {
            #expect(try test(name, in: first).stableID == (try test(name, in: rerun).stableID), "\(name) reconciles across attempts")
        }
    }

    @Test("Saved Jest JSON read offline gets the same identities as a live run, by finding the project's package.json")
    func realJestOffline() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let project = scratch.url.appendingPathComponent("app")
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("build/test-runs/attempt-1"), withIntermediateDirectories: true)
        try "{}".write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        // The same Jest JSON, but with this scratch project as its root: paths are rewritten from the scrubbed `/project/`.
        let json = try String(contentsOf: Self.directory.appendingPathComponent("first-attempt.json"), encoding: .utf8)
            .replacingOccurrences(of: "/project/", with: project.resolvingSymlinksInPath().path + "/")
        let saved = project.appendingPathComponent("build/test-runs/attempt-1/jest.json")
        try json.write(to: saved, atomically: true, encoding: .utf8)
        let run = try await ResultInspection(shell: .init()).read(saved.path, format: .jest)
        #expect(run.testCases.contains { $0.stableID == "jest-case:__tests__/scripted.test.js::Scripted flaky" })
        #expect(run.testCases.allSatisfy { !$0.stableID.hasPrefix("jest-case:/") })
    }
}
