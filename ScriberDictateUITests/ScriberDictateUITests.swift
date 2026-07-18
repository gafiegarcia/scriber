import XCTest

@MainActor
final class ScriberDictateUITests: XCTestCase {
    func testInitialFocusStartsInSelectedSidebarRow() async {
        let app = await launchApp()
        defer { app.terminate() }
        let historyAppeared = await waitForExistence(historyView(in: app), timeout: 3)
        XCTAssertTrue(historyAppeared)

        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])

        let settingsAppeared = await waitForExistence(settingsView(in: app), timeout: 3)
        XCTAssertTrue(
            settingsAppeared,
            "Down Arrow should move the focused sidebar selection from History to Settings."
        )
    }

    func testCommandFFocusesHistorySearch() async {
        let app = await launchApp()
        defer { app.terminate() }
        let historyAppeared = await waitForExistence(historyView(in: app), timeout: 3)
        XCTAssertTrue(historyAppeared)

        app.typeKey("f", modifierFlags: .command)
        app.typeText("launch query")

        XCTAssertEqual(historySearchField(in: app).value as? String, "launch query")
    }

    func testCommandFFromSettingsRoutesToHistorySearch() async {
        let app = await launchApp()
        defer { app.terminate() }
        let settingsRow = element(in: app, identifier: "sidebar-settings")
        let settingsRowAppeared = await waitForExistence(settingsRow, timeout: 3)
        XCTAssertTrue(settingsRowAppeared)
        settingsRow.click()
        let settingsAppeared = await waitForExistence(settingsView(in: app), timeout: 3)
        XCTAssertTrue(settingsAppeared)

        app.typeKey("f", modifierFlags: .command)
        app.typeText("settings query")

        let historyAppeared = await waitForExistence(historyView(in: app), timeout: 3)
        XCTAssertTrue(historyAppeared)
        XCTAssertEqual(historySearchField(in: app).value as? String, "settings query")
    }

    private func launchApp() async -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let windowAppeared = await waitForExistence(app.windows.firstMatch, timeout: 5)
        XCTAssertTrue(windowAppeared, "The isolated main window should open without onboarding.")
        return app
    }

    private func historyView(in app: XCUIApplication) -> XCUIElement {
        element(in: app, identifier: "history-view")
    }

    private func settingsView(in app: XCUIApplication) -> XCUIElement {
        element(in: app, identifier: "settings-view")
    }

    private func historySearchField(in app: XCUIApplication) -> XCUIElement {
        app.searchFields["Search dictations"].firstMatch
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForExistence(_ element: XCUIElement, timeout: TimeInterval) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if element.exists { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return element.exists
    }
}
