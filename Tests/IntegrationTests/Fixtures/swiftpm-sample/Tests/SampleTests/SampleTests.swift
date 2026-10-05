import Foundation
import Testing
import XCTest

@testable import Sample

/// Test outcomes are scripted through the environment so one package can play every role:
///
/// - `SHIPIT_SAMPLE_FAIL=1`: `alwaysFailsWhenAsked` (and its XCTest twin) fail.
/// - `SHIPIT_SAMPLE_FLAKY_DIR=<dir>`: `flaky` fails the first time and passes after, remembered by a marker
///   file in that directory (reruns are separate processes, so a file is the only state they share).
enum Script {
    static var asked: Bool { ProcessInfo.processInfo.environment["SHIPIT_SAMPLE_FAIL"] == "1" }

    /// `true` the first time it is asked for a given name, `false` afterwards.
    static func firstAttempt(_ name: String) -> Bool {
        guard let directory = ProcessInfo.processInfo.environment["SHIPIT_SAMPLE_FLAKY_DIR"] else { return false }
        let marker = URL(fileURLWithPath: directory).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: marker.path) { return false }
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        return true
    }
}

@Suite("Swift Testing")
struct SwiftTestingTests {
    @Test func passes() { #expect(Sample.add(1, 2) == 3) }

    @Test func alsoPasses() { #expect(Sample.unreachableInTests(1) == "small") }

    @Test(.disabled("skipped on purpose")) func skipped() {}

    @Test func flaky() { #expect(!Script.firstAttempt("swift-testing-flaky"), "fails on the first attempt only") }

    @Test func alwaysFailsWhenAsked() { #expect(!Script.asked, "asked to fail") }
}

final class XCTestCases: XCTestCase {
    func testPasses() { XCTAssertEqual(Sample.add(2, 2), 4) }

    func testFlakyXCTest() { XCTAssertFalse(Script.firstAttempt("xctest-flaky"), "fails on the first attempt only") }

    func testAlwaysFailsWhenAsked() { XCTAssertFalse(Script.asked, "asked to fail") }
}
