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
