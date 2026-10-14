import Foundation
import Testing

@testable import ShipItKit

@Suite("JUnit XML aggregation in TestAction")
struct JUnitXMLAggregationTests {
    @Test("Aggregate JUnit XML results from disk")
    func aggregateFromDisk() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipit-junit-test-\(UUID().uuidString)")
        let taskDir =
            tmpDir
            .appendingPathComponent("moduleA/build/test-results/testDebugUnitTest")
        try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)

        let xml1 = """
            <?xml version="1.0" encoding="UTF-8"?>
            <testsuite name="com.a.Test1" tests="5" skipped="1" failures="0" errors="0" time="0.1">
              <testcase name="testA" classname="com.a.Test1" time="0.01"/>
            </testsuite>
            """
        let xml2 = """
            <?xml version="1.0" encoding="UTF-8"?>
            <testsuite name="com.a.Test2" tests="3" skipped="0" failures="1" errors="0" time="0.2">
              <testcase name="testB" classname="com.a.Test2" time="0.02">
                <failure message="boom"/>
              </testcase>
            </testsuite>
            """
        try xml1.write(to: taskDir.appendingPathComponent("TEST-com.a.Test1.xml"), atomically: true, encoding: .utf8)
        try xml2.write(to: taskDir.appendingPathComponent("TEST-com.a.Test2.xml"), atomically: true, encoding: .utf8)

        let action = TestAction()
        let result = try await action.aggregateJUnitXMLResults(projectDir: tmpDir.path, task: "testDebugUnitTest")

        #expect(result.pass == 6)
        #expect(result.fail == 1)
        #expect(result.skip == 1)
        #expect(result.passedTests == ["Test1.testA"])
        #expect(result.failedTests == ["Test2.testB"])

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("Aggregate returns zeros when no XML files found")
    func aggregateNoFiles() async throws {
        let action = TestAction()
        let result = try await action.aggregateJUnitXMLResults(
            projectDir: "/nonexistent/path/that/doesnt/exist",
            task: "testDebugUnitTest"
        )

        #expect(result.pass == 0)
        #expect(result.fail == 0)
        #expect(result.skip == 0)
    }
}
