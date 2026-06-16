import Testing

@testable import ShipItKit

@Suite("XcodeBuildSummary.parse")
struct XcodeBuildSummaryTests {

    @Test("parses the ARCHIVE SUCCEEDED marker and warning/error counts")
    func parsesArchiveSucceeded() {
        let stdout = """
            CompileSwift normal arm64 /src/Foo.swift
            /src/Foo.swift:12:5: warning: variable 'x' was never used
            /src/Bar.swift:3:1: warning: deprecated API

            ** ARCHIVE SUCCEEDED **
            """

        let summary = XcodeBuildSummary.parse(stdout)

        #expect(summary.resultLine == "** ARCHIVE SUCCEEDED **")
        #expect(summary.warningCount == 2)
        #expect(summary.errorCount == 0)
        #expect(!summary.isEmpty)
    }

    @Test("parses the BUILD FAILED marker and counts errors")
    func parsesBuildFailed() {
        let stdout = """
            /src/Foo.swift:9:10: error: cannot find 'bar' in scope
            ** BUILD FAILED **
            """

        let summary = XcodeBuildSummary.parse(stdout)

        #expect(summary.resultLine == "** BUILD FAILED **")
        #expect(summary.errorCount == 1)
        #expect(summary.warningCount == 0)
    }

    @Test("recognizes the TEST SUCCEEDED marker")
    func parsesTestSucceeded() {
        let summary = XcodeBuildSummary.parse("** TEST SUCCEEDED **\n")
        #expect(summary.resultLine == "** TEST SUCCEEDED **")
    }

    @Test("returns an empty summary when no marker or diagnostics are present")
    func parsesEmptySummary() {
        let summary = XcodeBuildSummary.parse("Note: building target\nLinking binary\n")
        #expect(summary.resultLine == nil)
        #expect(summary.warningCount == 0)
        #expect(summary.errorCount == 0)
        #expect(summary.isEmpty)
    }

    @Test("keeps the first marker when output contains several lines")
    func keepsFirstMarker() {
        let stdout = """
            ** BUILD SUCCEEDED **
            ** ARCHIVE SUCCEEDED **
            """
        let summary = XcodeBuildSummary.parse(stdout)
        #expect(summary.resultLine == "** BUILD SUCCEEDED **")
    }

    @Test("empty stdout yields an empty summary, never throws")
    func parsesEmptyStdout() {
        #expect(XcodeBuildSummary.parse("").isEmpty)
    }
}
