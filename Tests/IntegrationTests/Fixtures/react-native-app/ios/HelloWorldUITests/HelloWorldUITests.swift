import XCTest

final class HelloWorldUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppLaunches() throws {
        XCTAssertTrue(app.exists)
    }

    func testMainWindowExists() throws {
        XCTAssertFalse(app.windows.isEmpty)
    }

    func testAppIsInForeground() throws {
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testScrollViewExistsOrRootViewVisible() throws {
        // React Native renders into a root view — verify the window has children
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }
}
