import Foundation
import SwiftyShell
import Synchronization
import TestCommons
import Testing

@testable import ShipItKit

@Suite("Test destinations")
struct TestDestinationTests {
    // MARK: Vocabulary

    @Test("Known values decode to cases and unknown ones are kept, not rejected")
    func openEnums() throws {
        func decode<T: Decodable>(_ type: T.Type, _ raw: String) throws -> T {
            try JSONDecoder().decode([T].self, from: Data("[\"\(raw)\"]".utf8))[0]
        }
        #expect(try decode(TestPlatform.self, "ios") == .ios)
        #expect(try decode(TestPlatform.self, "tvos") == .other("tvos"))
        #expect(try decode(TestRunner.self, "swift-test") == .swiftTest)
        #expect(try decode(TestRunner.self, "bazel") == .other("bazel"), "a plugin or newer ShipIt's runner still decodes")
        let encoded = try JSONEncoder().encode([TestRunner.other("bazel"), .flutterTest])
        #expect(String(decoding: encoded, as: UTF8.self) == "[\"bazel\",\"flutter-test\"]")
    }

    @Test("Destination IDs come from what identifies the environment, never from paths or processes")
    func destinationIDs() {
        let phone = TestDestination(platform: .ios, kind: .simulator, name: "iPhone 16")
        #expect(phone.id == "ios:simulator:iPhone 16")
        #expect(phone == TestDestination(platform: .ios, kind: .simulator, name: "iPhone 16"))
        #expect(phone.id != TestDestination(platform: .ios, kind: .simulator, name: "iPhone 16", scope: "Smoke").id, "a plan is part of it")
        #expect(TestDestination.host().platform == TestPlatform.host)
        #expect(TestDestination.host().kind == .host)
    }

    // MARK: Gradle

    @Test(
        "A Gradle task names its destination",
        arguments: [
            ("testDebugUnitTest", TestPlatform.android, TestDestinationKind.host),
            ("testProdReleaseUnitTest", .android, .host),
            ("iosSimulatorArm64Test", .ios, .simulator),
            ("iosX64Test", .ios, .simulator),
            ("iosArm64Test", .ios, .device),
            ("macosArm64Test", .macos, .host),
            ("linuxX64Test", .linux, .host),
            ("mingwX64Test", .windows, .host),
            ("jsTest", .js, .host),
            ("wasmJsTest", .js, .host),
            ("jvmTest", .jvm, .host),
            ("desktopTest", .jvm, .host),
            ("test", .jvm, .host),
            (":shared:iosSimulatorArm64Test", .ios, .simulator),
        ])
    func gradleTasks(task: String, platform: TestPlatform, kind: TestDestinationKind) {
        let destination = TestDestination.gradle(task: task)
        #expect(destination.platform == platform)
        #expect(destination.kind == kind)
        #expect(destination.scope == task.split(separator: ":").last.map(String.init))
    }

    @Test("Connected tests are an emulator or a device depending on what AGP reports, and unknown tasks stay unknown")
    func gradleConnectedAndUnknown() {
        #expect(TestDestination.gradle(task: "connected", device: "Pixel_6(AVD) - 13").kind == .emulator)
        #expect(TestDestination.gradle(task: "connected", device: "SM-S918B - 14").kind == .device)
        #expect(TestDestination.gradle(task: "connected").kind == nil, "no device information, no claim")
        #expect(TestDestination.gradle(task: "connected").platform == .android)
        #expect(TestDestination.gradle(task: "somethingCustom").platform == .unknown)
    }

    @Test("One Kotlin Multiplatform run spans iOS and JVM, and each test knows where it ran")
    func kotlinMultiplatformSpansTargets() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        try "".write(to: scratch.url.appendingPathComponent("settings.gradle.kts"), atomically: true, encoding: .utf8)
        for task in ["iosSimulatorArm64Test", "jvmTest"] {
            let directory = scratch.url.appendingPathComponent("shared/build/test-results/\(task)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "<testsuite name=\"S\"><testcase classname=\"GreeterTest\" name=\"greets\"/></testsuite>".write(
                to: directory.appendingPathComponent("TEST-GreeterTest.xml"), atomically: true, encoding: .utf8)
        }
        let run = try await ResultInspection(shell: .init()).read(scratch.url.path, format: .junit, runner: .gradle, buildSystem: .kmp)
        #expect(run.runner == .gradle)
        #expect(run.buildSystem == .kmp)
        #expect(Set(run.platforms) == [.ios, .jvm])
        #expect(run.testCases.count == 2, "the same test on two targets stays two tests")
        let ios = try #require(run.destinations.first { $0.platform == .ios })
        let jvm = try #require(run.destinations.first { $0.platform == .jvm })
        let iosTest = try #require(run.testCases.first { $0.destinationID == ios.id })
        let jvmTest = try #require(run.testCases.first { $0.destinationID == jvm.id })
        #expect(iosTest.stableID != jvmTest.stableID)
        #expect(iosTest.rerunSelector == .unsupported(rawIdentifier: "GreeterTest.greets"), "Kotlin/Native cannot be filtered by Gradle")
        #expect(jvmTest.rerunSelector == .gradleTestFilter("GreeterTest.greets"))
    }

    // MARK: Xcode

    @Test("An xcodebuild destination specifier names its destination")
    func xcodeSpecifiers() {
        let simulator = TestDestination.xcode(specifier: "platform=iOS Simulator,name=iPhone 16,OS=18.2", plan: "Smoke")
        #expect(simulator.platform == .ios)
        #expect(simulator.kind == .simulator)
        #expect(simulator.name == "iPhone 16")
        #expect(simulator.scope == "Smoke")
        #expect(TestDestination.xcode(specifier: "platform=iOS,id=00008110-001").kind == .device)
        #expect(TestDestination.xcode(specifier: "platform=macOS").platform == .macos)
        #expect(TestDestination.xcode(specifier: "platform=macOS").kind == .host)
        #expect(TestDestination.xcode(specifier: "platform=tvOS Simulator,name=Apple TV").platform == .other("tvos"))
        #expect(TestDestination.xcode(specifier: "generic/platform=iOS Simulator").platform == .ios)
        #expect(TestDestination.xcode(specifier: "nonsense").platform == .unknown)
    }

    // MARK: Merging

    @Test("Merged runs keep a runner only when they agree, unite destinations, and keep identities distinct")
    func merging() {
        let ios = TestDestination(platform: .ios, kind: .simulator, name: "iPhone 16")
        let jvm = TestDestination.gradle(task: "jvmTest")
        func run(_ runner: TestRunner, _ destination: TestDestination) -> ParsedTestRun {
            ParsedTestRun(
                runner: runner, buildSystem: .native, source: "s", destinations: [destination], summary: .init(passed: 1),
                testCases: [.init(stableID: "t", name: "t", status: .passed, destinationID: destination.id)])
        }
        let mixed = ParsedTestRun.merging([run(.xcodebuild, ios), run(.gradle, jvm)], source: "a, b")
        #expect(mixed.runner == .multiple)
        #expect(mixed.buildSystem == .native)
        #expect(mixed.destinations == [ios, jvm])
        #expect(mixed.testCases.map(\.stableID) == ["input-1:t", "input-2:t"])
        #expect(mixed.testCases.map(\.destinationID) == [ios.id, jvm.id])
        #expect(mixed.summary.passed == 2)

        let same = ParsedTestRun.merging([run(.gradle, jvm), run(.gradle, jvm)], source: "a, b")
        #expect(same.runner == .gradle)
        #expect(same.destinations == [jvm], "the same environment seen twice is one destination")

        let single = ParsedTestRun.merging([run(.gradle, jvm)], source: "a")
        #expect(single.testCases.map(\.stableID) == ["t"], "a single input keeps its IDs")
    }

    // MARK: Wire format

    @Test("The JSON has typed runner and destinations and no run-level platform string")
    func jsonShape() throws {
        let run = ParsedTestRun(
            runner: .gradle, buildSystem: .kmp, source: "s", destinations: [TestDestination.gradle(task: "jvmTest")],
            summary: .init(passed: 1), testCases: [.init(stableID: "t", name: "t", status: .passed, destinationID: "jvm:host:jvmTest")])
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any])
        #expect(object["platform"] == nil)
        #expect(object["runner"] as? String == "gradle")
        #expect(object["buildSystem"] as? String == "kmp")
        let destinations = try #require(object["destinations"] as? [[String: Any]])
        #expect(destinations.first?["platform"] as? String == "jvm")
        #expect(destinations.first?["kind"] as? String == "host")
        #expect((object["testCases"] as? [[String: Any]])?.first?["destinationID"] as? String == "jvm:host:jvmTest")
        #expect(TestRunReport.currentSchemaVersion == 2)
    }

    // MARK: Coverage

    @Test("Coverage carries a typed platform and the runner whose format it is")
    func coveragePlatformAndRunner() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let lcov = scratch.url.appendingPathComponent("lcov.info")
        try "SF:lib/a.dart\nDA:1,1\nend_of_record\n".write(to: lcov, atomically: true, encoding: .utf8)
        let flutter = try await PortableCoverageReader().read(lcov.path, format: .lcov)
        #expect(flutter.runner == .flutterTest)
        #expect(flutter.platform == .unknown, "LCOV does not say where the tests ran")

        let jacoco = scratch.url.appendingPathComponent("jacoco.xml")
        try
            "<report><package name=\"p\"><counter type=\"LINE\" covered=\"1\" missed=\"1\"/></package><counter type=\"LINE\" covered=\"1\" missed=\"1\"/></report>"
            .write(to: jacoco, atomically: true, encoding: .utf8)
        let jvm = try await PortableCoverageReader().read(jacoco.path, format: .jacoco)
        #expect(jvm.runner == .gradle)
        #expect(jvm.platform == .jvm)
        #expect(TestPlatform.ios.displayName == "iOS")
        #expect(TestPlatform.other("tvos").displayName == "tvos")
    }

    // MARK: Live reports

    @Test("A Flutter run records the host as its destination and the Flutter build system")
    func liveFlutter() async throws {
        let executor = MockExecutor { _, _ in
            .init(
                stdout: """
                    {"type":"testStart","test":{"id":1,"name":"checkout"}}
                    {"type":"testDone","testID":1,"result":"success"}
                    """, stderr: "", exitCode: 0)
        }
        let context = ActionContext.mock(
            executor: executor, platform: .android, config: ResolvedConfig(platform: .android, androidBuildSystem: .flutter))
        let report = try #require(try await TestAction().run(with: .init(), context: context).report)
        #expect(report.runner == .flutterTest)
        #expect(report.buildSystem == .flutter)
        #expect(report.destinations == [TestDestination.host()])
        #expect(report.testCases?.first?.destinationID == TestDestination.host().id)
    }

    @Test("A SwiftPM run records the host as its destination")
    func liveSwiftTest() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let executor = MockExecutor { command, _ in
            guard let flag = command.arguments.firstIndex(of: "--event-stream-output-path") else {
                return .init(stdout: "", stderr: "", exitCode: 0)
            }
            try """
            {"kind":"test","payload":{"kind":"function","id":"Tests.Suite/test()","name":"test"}}
            {"kind":"event","payload":{"kind":"testStarted","testID":"Tests.Suite/test()","instant":{"absolute":1}}}
            {"kind":"event","payload":{"kind":"testEnded","testID":"Tests.Suite/test()","instant":{"absolute":2}}}
            """.write(toFile: command.arguments[flag + 1], atomically: true, encoding: .utf8)
            return .init(stdout: "", stderr: "", exitCode: 0)
        }
        let result = try await SwiftTestAction().run(
            with: .init(outputDirectory: scratch.url.appendingPathComponent("run").path), context: .mock(executor: executor))
        #expect(result.report.runner == .swiftTest)
        #expect(result.report.buildSystem == .native)
        #expect(result.report.destinations == [TestDestination.host()])
        #expect(result.report.testCases?.allSatisfy { $0.destinationID == TestDestination.host().id } == true)
    }

    @Test("An Android unit-test run reports where it ran, taken from the Gradle task")
    func liveAndroid() async throws {
        let scratch = try TemporaryDirectory()
        defer { try? scratch.remove() }
        let reports = scratch.url.appendingPathComponent("app/build/test-results/testDebugUnitTest")
        let (executor, _) = makeCaptureExecutor { _, _ in
            try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
            try "<testsuite name=\"S\"><testcase classname=\"C\" name=\"m\"/></testsuite>".write(
                to: reports.appendingPathComponent("TEST-C.xml"), atomically: true, encoding: .utf8)
            return ShellOutput(stdout: "", stderr: "", exitCode: 0)
        }
        var context = makeTestActionContext(
            executor: executor,
            config: ResolvedConfig(
                platform: .android, androidModule: "app", androidBuildVariant: "debug", gradleProjectDir: scratch.url.path),
            platform: .android)
        context.evidenceRoot = scratch.url.appendingPathComponent("evidence").path
        let report = try #require(try await TestAction().run(with: .init(legacyCombinedTest: true, kind: .unit), context: context).report)
        #expect(report.runner == .gradle)
        #expect(report.buildSystem == .native)
        #expect(report.destinations.map(\.platform) == [.android])
        #expect(report.destinations.first?.kind == .host)
        #expect(report.testCases?.first?.destinationID == report.destinations.first?.id)
    }
}
