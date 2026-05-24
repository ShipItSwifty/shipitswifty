import Foundation
import Testing

@testable import ShipItKit

@Suite("AndroidJUnitTestParser")
struct AndroidJUnitTestParserTests {

    @Test("Parses Gradle JUnit XML files into normalized suites and test cases")
    func parsesJUnitDirectory() async throws {
        let root = try makeTempDirectory(prefix: "AndroidJUnitTestParser")
        defer { try? FileManager.default.removeItem(at: root) }

        let reportDirectory = root.appendingPathComponent("app/build/test-results/testDebugUnitTest", isDirectory: true)
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <testsuite name="com.example.CheckoutTests" tests="3" skipped="1" failures="1" errors="0">
              <testcase name="testHappyPath" classname="com.example.CheckoutTests" time="0.01"/>
              <testcase name="testNetworkError" classname="com.example.CheckoutTests" time="0.02">
                <failure message="boom"/>
              </testcase>
              <testcase name="testLegacyMode" classname="com.example.CheckoutTests" time="0.03">
                <skipped/>
              </testcase>
            </testsuite>
            """
        try xml.write(
            to: reportDirectory.appendingPathComponent("TEST-com.example.CheckoutTests.xml"),
            atomically: true,
            encoding: .utf8
        )

        let parser = AndroidJUnitTestParser()
        let run = try await parser.parse(reportDirectory: reportDirectory.path)

        #expect(run.platform == "android")
        #expect(run.runner == "gradle")
        #expect(run.summary.passed == 1)
        #expect(run.summary.failed == 1)
        #expect(run.summary.skipped == 1)
        #expect(run.suites.count == 1)
        #expect(run.suites.first?.name == "com.example.CheckoutTests")
        #expect(run.testCases.count == 3)
        #expect(
            run.testCases.first(where: { $0.name == "testNetworkError" })?.rerunSelector
                == .gradleTestFilter("com.example.CheckoutTests.testNetworkError"))
    }

    @Test("Throws when the report directory has no JUnit XML files")
    func throwsWhenNoXMLFilesExist() async throws {
        let root = try makeTempDirectory(prefix: "AndroidJUnitMissing")
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try await AndroidJUnitTestParser().parse(reportDirectory: root.path)
            Issue.record("Expected AndroidJUnitTestParser to throw for an empty directory")
        } catch let error as ShipItError {
            guard case .invalidConfiguration = error else {
                Issue.record("Expected invalidConfiguration, got \(error)")
                return
            }
        }
    }
}
