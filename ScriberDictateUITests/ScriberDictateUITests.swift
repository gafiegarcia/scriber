import AppKit
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

    func testClosingFinalWindowUsesAccessoryActivationPolicy() async {
        let app = await launchApp(additionalArguments: ["--ui-testing-accessory-lifecycle"])
        defer { app.terminate() }
        guard let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.gafiegarcia.scriber-dictate")
            .max(by: { $0.processIdentifier < $1.processIdentifier }) else {
            XCTFail("The launched app should have a running application instance.")
            return
        }

        let beganRegular = await waitUntil(timeout: 3) {
            runningApplication.activationPolicy == NSApplication.ActivationPolicy.regular
        }
        XCTAssertTrue(beganRegular, "The visible main window should begin with a regular activation policy.")
        guard beganRegular else { return }

        app.typeKey("w", modifierFlags: .command)

        let becameAccessory = await waitUntil(timeout: 3) {
            runningApplication.activationPolicy == NSApplication.ActivationPolicy.accessory
        }
        XCTAssertTrue(
            becameAccessory,
            "Closing the final app window should remove Scriber Dictate from the Dock and app switcher."
        )
        XCTAssertFalse(runningApplication.isTerminated, "Accessory mode must leave background services running.")
    }

    private func launchApp(additionalArguments: [String] = []) async -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + additionalArguments
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

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }
}
