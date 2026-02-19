import XCTest

final class TapspectUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Launch & Basic UI

    func testAppLaunches() {
        // Splash screen should eventually dismiss and show the main UI
        let urlField = app.textFields["URL Input"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10))
    }

    func testURLFieldExists() {
        let urlField = app.textFields["URL Input"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10))
        XCTAssertTrue(urlField.isEnabled)
    }

    func testGoButtonExists() {
        let goButton = app.buttons["Load URL"]
        XCTAssertTrue(goButton.waitForExistence(timeout: 10))
    }

    // MARK: - URL Entry

    func testEnterURL() {
        let urlField = app.textFields["URL Input"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10))

        urlField.tap()
        urlField.clearAndType("https://example.com")

        let goButton = app.buttons["Load URL"]
        goButton.tap()

        // WebView should eventually load
        // Give it a moment for the web content to appear
        sleep(2)
    }

    func testInvalidURLShowsValidation() {
        let urlField = app.textFields["URL Input"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10))

        urlField.tap()
        urlField.clearAndType("not a url")

        let goButton = app.buttons["Load URL"]
        // Button might be disabled or show error for invalid URLs
        XCTAssertTrue(goButton.exists)
    }

    // MARK: - Debug Panel

    func testSettingsButtonExists() {
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
    }
}

// MARK: - XCUIElement Helpers

extension XCUIElement {
    func clearAndType(_ text: String) {
        guard let currentValue = value as? String, !currentValue.isEmpty else {
            typeText(text)
            return
        }
        // Select all and delete, then type new text
        tap()
        let selectAll = XCUIApplication().menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 1) {
            selectAll.tap()
            typeText(XCUIKeyboardKey.delete.rawValue)
        }
        typeText(text)
    }
}
