import AppKit
import XCTest

@MainActor
final class ScriberUITests: XCTestCase {
    func testInitialFocusStartsInSelectedSidebarRow() async {
        let app = await launchApp()
        defer { app.terminate() }
        let dictationAppeared = await waitForExistence(dictationHistoryView(in: app), timeout: 3)
        XCTAssertTrue(dictationAppeared)

        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])

        let settingsAppeared = await waitForExistence(settingsView(in: app), timeout: 3)
        XCTAssertTrue(
            settingsAppeared,
            "Down Arrow should move the focused sidebar selection from Dictation to Settings."
        )
    }

    func testCommandFFocusesDictationSearch() async {
        let app = await launchApp()
        defer { app.terminate() }
        let dictationAppeared = await waitForExistence(dictationHistoryView(in: app), timeout: 3)
        XCTAssertTrue(dictationAppeared)

        app.typeKey("f", modifierFlags: .command)
        app.typeText("launch query")

        XCTAssertEqual(dictationSearchField(in: app).value as? String, "launch query")
    }

    func testCommandFFromSettingsRoutesToDictationSearch() async {
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

        let dictationAppeared = await waitForExistence(dictationHistoryView(in: app), timeout: 3)
        XCTAssertTrue(dictationAppeared)
        XCTAssertEqual(dictationSearchField(in: app).value as? String, "settings query")
    }

    func testClosingFinalWindowUsesAccessoryActivationPolicy() async {
        let app = await launchApp(additionalArguments: ["--ui-testing-accessory-lifecycle"])
        defer { app.terminate() }
        guard let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.gafiegarcia.scriber")
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
            "Closing the final app window should remove Scriber from the Dock and app switcher."
        )
        XCTAssertFalse(runningApplication.isTerminated, "Accessory mode must leave background services running.")
    }

    func testShowAppInDockKeepsRegularActivationPolicyAfterClosingWindows() async {
        let app = await launchApp(additionalArguments: ["--ui-testing-accessory-lifecycle"])
        defer { app.terminate() }
        guard let runningApplication = runningApplication(bundleIdentifier: "com.gafiegarcia.scriber") else {
            XCTFail("The launched app should have a running application instance.")
            return
        }

        let settingsRow = element(in: app, identifier: "sidebar-settings")
        let settingsRowAppeared = await waitForExistence(settingsRow, timeout: 3)
        XCTAssertTrue(settingsRowAppeared)
        settingsRow.click()

        let showAppInDock = element(in: app, identifier: "show-app-in-dock-toggle")
        app.scrollViews.firstMatch.swipeUp()
        let showAppInDockAppeared = await waitForExistence(showAppInDock, timeout: 3)
        XCTAssertTrue(showAppInDockAppeared)
        showAppInDock.click()
        app.typeKey("w", modifierFlags: .command)

        let stayedRegular = await waitUntil(timeout: 3) {
            !app.windows.firstMatch.exists && runningApplication.activationPolicy == .regular
        }
        XCTAssertTrue(stayedRegular, "The Dock preference should keep Scriber in the Dock and app switcher.")
        XCTAssertFalse(runningApplication.isTerminated)
    }

    func testDisablingShowAppInDockKeepsVisibleWindowOpen() async {
        let app = await launchApp(additionalArguments: ["--ui-testing-accessory-lifecycle"])
        defer { app.terminate() }
        guard let runningApplication = runningApplication(bundleIdentifier: "com.gafiegarcia.scriber") else {
            XCTFail("The launched app should have a running application instance.")
            return
        }

        let settingsRow = element(in: app, identifier: "sidebar-settings")
        let settingsRowAppeared = await waitForExistence(settingsRow, timeout: 3)
        XCTAssertTrue(settingsRowAppeared)
        settingsRow.click()

        let showAppInDock = element(in: app, identifier: "show-app-in-dock-toggle")
        app.scrollViews.firstMatch.swipeUp()
        let showAppInDockAppeared = await waitForExistence(showAppInDock, timeout: 3)
        XCTAssertTrue(showAppInDockAppeared)
        showAppInDock.click()
        showAppInDock.click()

        XCTAssertTrue(app.windows.firstMatch.exists, "Disabling the Dock preference must not close the visible window.")
        XCTAssertEqual(runningApplication.activationPolicy, .regular)

        app.typeKey("w", modifierFlags: [.command, .shift])
        let becameAccessory = await waitUntil(timeout: 3) {
            runningApplication.activationPolicy == .accessory
        }
        XCTAssertTrue(becameAccessory, "Close All Windows should close the visible window and return to accessory mode.")
    }

    func testUpdateKeyForegroundsSettingsAndFocusesAPIKeyField() async {
        let app = await launchApp(additionalArguments: pillLifecycleArguments)
        defer { app.terminate() }
        guard let scriber = runningApplication(bundleIdentifier: "com.gafiegarcia.scriber"),
              let finder = runningApplication(bundleIdentifier: "com.apple.finder") else {
            XCTFail("Scriber and Finder should both be running.")
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

    func testEscapeDismissesPersistentPill() async {
        let app = await launchApp(
            additionalArguments: pillLifecycleArguments + ["--ui-testing-global-shortcuts"]
        )
        defer { app.terminate() }

        let updateKey = app.buttons["Update Key"].firstMatch
        let updateKeyAppeared = await waitForExistence(updateKey, timeout: 3)
        XCTAssertTrue(updateKeyAppeared)
        guard updateKeyAppeared else { return }

        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        let pillDismissed = await waitUntil(timeout: 3) { !updateKey.exists }
        XCTAssertTrue(pillDismissed, "Escape should dismiss a visible persistent pill.")
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

    func testRecordingFeedbackDefaultsCanBeDisabled() async {
        let app = await launchApp()
        defer { app.terminate() }

        let settingsRow = element(in: app, identifier: "sidebar-settings")
        let settingsAppeared = await waitForExistence(settingsRow, timeout: 3)
        XCTAssertTrue(settingsAppeared)
        settingsRow.click()

        // Query the switches directly. A `descendants(matching: .any)` lookup resolves
        // to the enclosing container, whose `value` is nil rather than the toggle state.
        let soundToggle = app.switches["recording-feedback-sounds-toggle"].firstMatch
        let muteToggle = app.switches["mute-other-audio-toggle"].firstMatch
        app.scrollViews.firstMatch.swipeUp()

        let soundToggleAppeared = await waitForExistence(soundToggle, timeout: 3)
        let muteToggleAppeared = await waitForExistence(muteToggle, timeout: 3)
        XCTAssertTrue(soundToggleAppeared)
        XCTAssertTrue(muteToggleAppeared)
        XCTAssertEqual(isOn(soundToggle), true)
        XCTAssertEqual(isOn(muteToggle), true)

        soundToggle.click()
        muteToggle.click()

        XCTAssertEqual(isOn(soundToggle), false)
        XCTAssertEqual(isOn(muteToggle), false)
    }

    /// A macOS checkbox reports its state as a boxed `Int` or `Bool`, not the `String`
    /// an iOS switch returns, so `value as? String` is always nil here.
    private func isOn(_ element: XCUIElement) -> Bool? {
        switch element.value {
        case let flag as Bool: return flag
        case let number as Int: return number != 0
        case let text as String: return text == "1"
        default: return nil
        }
    }

    func testMissingPermissionsAreVisibleAndPillRoutesToSettings() async {
        let app = await launchApp(additionalArguments: [
            "--ui-testing-missing-permissions",
            "--ui-testing-persistent-pill",
        ])
        defer { app.terminate() }

        let banner = app.buttons["Review Permissions"].firstMatch
        let bannerAppeared = await waitForExistence(banner, timeout: 3)
        XCTAssertTrue(bannerAppeared, "The Dictation view should explain why shortcuts are unavailable.")

        let review = app.buttons["Review"].firstMatch
        let pillAppeared = await waitForExistence(review, timeout: 3)
        XCTAssertTrue(pillAppeared, "Missing permissions should also produce an actionable pill.")
        guard pillAppeared else { return }

        review.click()

        let settingsAppeared = await waitForExistence(settingsView(in: app), timeout: 3)
        XCTAssertTrue(settingsAppeared, "The permission pill should open Scriber's Settings page.")
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

    private func dictationHistoryView(in app: XCUIApplication) -> XCUIElement {
        element(in: app, identifier: "dictation-history-view")
    }

    private func settingsView(in app: XCUIApplication) -> XCUIElement {
        element(in: app, identifier: "settings-view")
    }

    private func dictationSearchField(in app: XCUIApplication) -> XCUIElement {
        app.searchFields["Search past transcripts (⌘F)"].firstMatch
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
