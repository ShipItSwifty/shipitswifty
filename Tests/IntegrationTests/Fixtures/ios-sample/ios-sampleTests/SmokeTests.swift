import XCTest

/// Trivial XCTest suite in the iOS fixture project.
///
/// These tests exist so `xcodebuild test -scheme ios-sample` has something to run.
/// They are not part of the ShipItSwifty Swift package test suite.
final class SmokeTests: XCTestCase {
    func testArithmetic() {
        XCTAssertEqual(1 + 1, 2)
    }

    func testBundleIdentifier() {
        XCTAssertEqual(
            Bundle.main.bundleIdentifier,
            "com.shipitswifty.integration"
        )
    }
}

/// Outcomes scripted through the environment, so integration tests can drive every role from one project.
/// `xcodebuild` forwards variables prefixed `TEST_RUNNER_` to the test process with the prefix removed:
///
/// - `TEST_RUNNER_SHIPIT_SAMPLE_FAIL=1`: `testAlwaysFailsWhenAsked` fails.
/// - `TEST_RUNNER_SHIPIT_SAMPLE_FLAKY_DIR=<dir>`: `testFlaky` fails the first time *per language* and passes after,
///   remembered by a marker file (a rerun is a separate process, and each test plan runs in its own language, so
///   each plan flakes independently).
final class ScriptedTests: XCTestCase {
    private var language: String {
        Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "und"
    }

    func testPasses() {
        XCTAssertEqual(2 * 3, 6)
    }

    func testFlaky() throws {
        guard let directory = ProcessInfo.processInfo.environment["SHIPIT_SAMPLE_FLAKY_DIR"] else { return }
        let marker = URL(fileURLWithPath: directory).appendingPathComponent("flaky-\(language)")
        if FileManager.default.fileExists(atPath: marker.path) { return }
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        XCTFail("fails on the first attempt only (\(language))")
    }

    func testAlwaysFailsWhenAsked() {
        XCTAssertNotEqual(ProcessInfo.processInfo.environment["SHIPIT_SAMPLE_FAIL"], "1", "asked to fail")
    }
}
