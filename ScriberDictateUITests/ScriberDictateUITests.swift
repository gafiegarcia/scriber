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

    func testUpdateKeyForegroundsSettingsAndFocusesAPIKeyField() async {
        let app = await launchApp(additionalArguments: pillLifecycleArguments)
        defer { app.terminate() }
        guard let scriber = runningApplication(bundleIdentifier: "com.gafiegarcia.scriber-dictate"),
              let finder = runningApplication(bundleIdentifier: "com.apple.finder") else {
            XCTFail("Scriber Dictate and Finder should both be running.")
            return
        }

        let updateKey = app.buttons["Update Key"].firstMatch
        let updateKeyAppeared = await waitForExistence(updateKey, timeout: 3)
        XCTAssertTrue(updateKeyAppeared)
        guard updateKeyAppeared else { return }

        app.typeKey("w", modifierFlags: .command)
        let becameAccessory = await waitUntil(timeout: 3) { scriber.activationPolicy == .accessory }
        XCTAssertTrue(becameAccessory)
        XCTAssertTrue(finder.activate(options: [.activateAllWindows]))
        let finderBecameActive = await waitUntil(timeout: 3) { finder.isActive }
        XCTAssertTrue(finderBecameActive)

        updateKey.click()

        let scriberBecameActive = await waitUntil(timeout: 3) {
            scriber.activationPolicy == .regular && scriber.isActive
        }
        XCTAssertTrue(scriberBecameActive)
        let settingsAppeared = await waitForExistence(settingsView(in: app), timeout: 3)
        XCTAssertTrue(settingsAppeared)
        let apiKeyField = app.secureTextFields["ElevenLabs API key"].firstMatch
        let apiKeyFieldAppeared = await waitForExistence(apiKeyField, timeout: 3)
        XCTAssertTrue(apiKeyFieldAppeared)
        app.typeText("focus-check")
        let apiKeyFieldValue = apiKeyField.value as? String
        XCTAssertFalse(
            apiKeyFieldValue?.isEmpty ?? true,
            "The API-key field should receive typing immediately."
        )
        let pillDismissed = await waitUntil(timeout: 3) { !updateKey.exists }
        XCTAssertTrue(pillDismissed, "Opening Settings should dismiss the pill.")
    }

    func testReturnSubmitsAPIKeyFromSettings() async {
        let app = await launchApp()
        defer { app.terminate() }

        let settingsRow = element(in: app, identifier: "sidebar-settings")
        let settingsRowAppeared = await waitForExistence(settingsRow, timeout: 3)
        XCTAssertTrue(settingsRowAppeared)
        settingsRow.click()
        let settingsAppeared = await waitForExistence(settingsView(in: app), timeout: 3)
        XCTAssertTrue(settingsAppeared)

        let apiKeyField = app.secureTextFields["ElevenLabs API key"].firstMatch
        let apiKeyFieldAppeared = await waitForExistence(apiKeyField, timeout: 3)
        XCTAssertTrue(apiKeyFieldAppeared)
        apiKeyField.click()
        apiKeyField.typeText("ui-test-api-key")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])

        let feedback = element(in: app, identifier: "api-key-save-feedback")
        let feedbackAppeared = await waitForExistence(feedback, timeout: 3)
        XCTAssertTrue(
            feedbackAppeared,
            "Return in the API-key field should run the same save action as the button."
        )
    }

    private var pillLifecycleArguments: [String] {
        [
            "--ui-testing-accessory-lifecycle",
            "--ui-testing-invalid-key-pill",
            "--ui-testing-persistent-pill",
        ]
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

    private func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .max(by: { $0.processIdentifier < $1.processIdentifier })
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
