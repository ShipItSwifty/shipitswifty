import Foundation
import Testing

@testable import ShipItKit

@Suite("JUnit XML Report Parsing")
struct JUnitXMLParserTests {

    @Test("Parses basic testsuite attributes")
    func parsesBasicTestsuite() {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <testsuite name="com.example.MyTest" tests="10" skipped="1" failures="2" errors="0" time="0.5">
              <testcase name="testA" classname="com.example.MyTest" time="0.01"/>
            </testsuite>
            """
        let parser = JUnitXMLParser(data: Data(xml.utf8))
        parser.parse()

        #expect(parser.tests == 10)
        #expect(parser.failures == 2)
        #expect(parser.errors == 0)
        #expect(parser.skipped == 1)
        #expect(parser.testCases.map(\.name) == ["com.example.MyTest.testA"])
    }

    @Test("Handles errors attribute")
    func parsesErrors() {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <testsuite name="com.example.ErrorTest" tests="5" skipped="0" failures="1" errors="2" time="1.0">
            </testsuite>
            """
        let parser = JUnitXMLParser(data: Data(xml.utf8))
        parser.parse()

        #expect(parser.tests == 5)
        #expect(parser.failures == 1)
        #expect(parser.errors == 2)
        #expect(parser.skipped == 0)
    }

    @Test("Returns zeros for empty or malformed XML")
    func handlesEmptyXML() {
        let parser = JUnitXMLParser(data: Data("not xml".utf8))
        parser.parse()

        #expect(parser.tests == 0)
        #expect(parser.failures == 0)
        #expect(parser.errors == 0)
        #expect(parser.skipped == 0)
    }

    @Test("Only reads first testsuite element")
    func onlyReadsFirstTestsuite() {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <testsuites>
              <testsuite name="First" tests="3" skipped="0" failures="1" errors="0">
              </testsuite>
              <testsuite name="Second" tests="99" skipped="99" failures="99" errors="99">
              </testsuite>
            </testsuites>
            """
        let parser = JUnitXMLParser(data: Data(xml.utf8))
        parser.parse()

        #expect(parser.tests == 3)
        #expect(parser.failures == 1)
    }

    @Test("Aggregate JUnit XML results from disk")
    func aggregateFromDisk() throws {
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
        let result = action.aggregateJUnitXMLResults(projectDir: tmpDir.path, task: "testDebugUnitTest")

        #expect(result.pass == 6)  // (5-0-1) + (3-1-0) = 4 + 2 = 6
        #expect(result.fail == 1)
        #expect(result.skip == 1)
        #expect(result.passedTests == ["com.a.Test1.testA"])
        #expect(result.failedTests == ["com.a.Test2.testB"])

        try FileManager.default.removeItem(at: tmpDir)
    }

    @Test("Aggregate returns zeros when no XML files found")
    func aggregateNoFiles() {
        let action = TestAction()
        let result = action.aggregateJUnitXMLResults(
            projectDir: "/nonexistent/path/that/doesnt/exist",
            task: "testDebugUnitTest"
        )

        #expect(result.pass == 0)
        #expect(result.fail == 0)
        #expect(result.skip == 0)
    }
}
