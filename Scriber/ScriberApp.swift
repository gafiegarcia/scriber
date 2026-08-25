import AppKit
import Combine
import os
import SwiftData
import SwiftUI

enum AppLaunchConfiguration {
    static var isUITesting: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
#else
        false
#endif
    }

    static var keepsRegularActivationPolicy: Bool {
        isUITesting
            && !ProcessInfo.processInfo.arguments.contains("--ui-testing-accessory-lifecycle")
            && !launchesWithoutActivating
    }

    static var presentsInvalidKeyPill: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-invalid-key-pill")
    }

    static var simulatesMissingPermissions: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-missing-permissions")
    }

    /// Fills the in-memory history so the Dictation list can be checked without
    /// touching Gaf's real entries. See `UITestingHistoryFixture`.
    static var seedsDictationHistory: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-history")
    }

    /// Fills the in-memory history with several hundred synthetic records spread
    /// across many days, for reproducing and measuring scroll performance with a
    /// history far longer than the curated fixture provides. Mutually exclusive in
    /// practice with `seedsDictationHistory` — pass only one seeding flag.
    static var seedsLargeDictationHistory: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-history-large")
    }

    /// Opens onboarding under `--ui-testing`, which otherwise marks setup
    /// complete so every other check starts in the app proper.
    static var showsOnboarding: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-onboarding")
    }

    /// Lets every setup step be advanced past without satisfying its gate, so the
    /// later steps can be reached without granting permissions to a Debug build —
    /// which writes that build's identity into the Mac's privacy lists. The gates
    /// still render; only the Continue button stops obeying them.
    static var unlocksOnboardingSteps: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-onboarding-unlocked")
    }

    /// Shows the menu bar item on a `--ui-testing` launch, which otherwise never
    /// does. Its mark is identical to the installed app's and nothing in the menu
    /// says which is which, so **quit the installed Scriber first** — and never
    /// drag a test build's item out of the menu bar, because the list macOS keeps
    /// is per bundle identifier and shared with the real app.
    static var showsMenuBarWhileUITesting: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-menu-bar")
    }

    /// A version to run as, so the update-available state can be reached without
    /// a release newer than this build. `--ui-testing-pretend-version 0.8.0` makes
    /// the live 0.9.0 read as an update; a value above the latest release proves
    /// the opposite case. Until a second release existed there was no way to see
    /// either, and the running version is what the check compares.
    ///
    /// Reads the argument after the flag, so it carries a value where every other
    /// `--ui-testing` flag is a switch. Gated on `isUITesting`, which is false in
    /// Release, so the shipped app always reports its real version.
    static var pretendedVersion: String? {
        guard isUITesting else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--ui-testing-pretend-version"),
              arguments.index(after: flag) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: flag)]
    }

    /// The launch smoke check's flag. The app still builds and renders its window —
    /// that is the path the check exists to exercise — but never activates, so it
    /// does not steal the front from whatever Gaf is doing. Only the smoke check
    /// passes it; a visual-inspection launch wants the real activation behaviour.
    static var launchesWithoutActivating: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-no-activate")
    }

    /// Treats the launch as one macOS made at login, so the background start can
    /// be checked without restarting the Mac. Deliberately not gated on
    /// `isUITesting`: the smoke check has to be able to launch this path with the
    /// app otherwise behaving normally. Debug builds only.
    static var simulatesLoginLaunch: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--simulate-login-launch")
#else
        false
#endif
    }

    /// A login launch the user asked to stay out of the way: no window, no
    /// activation, menu bar and dictation services only. Deliberately false for
    /// a launch the user made themselves, so double-clicking Scriber always
    /// opens something. Incomplete setup always wins — onboarding has to be
    /// reachable.
    @MainActor
    static var startsInBackground: Bool {
        // Ahead of the preference reads, so the check does not depend on how Gaf
        // has these set at the time.
        if simulatesLoginLaunch { return true }
        // Nothing here asks whether the login item is registered: macOS starting
        // Scriber at login is the proof, and `isLoginItemLaunch` is how that
        // arrives.
        guard !isUITesting, LoginItemLaunch.isLoginItemLaunch else { return false }
        return Preferences.optInFlag("startInBackground")
            && UserDefaults.standard.bool(forKey: "onboardingComplete")
    }

    /// Whether this launch begins in setup.
    ///
    /// A `--ui-testing` launch never does: its throwaway defaults suite has no
    /// `onboardingComplete`, which would otherwise start every automated run in
    /// setup. `--show-onboarding` forces it either way.
    @MainActor
    static var launchesIntoOnboarding: Bool {
        if showsOnboarding { return true }
        if isUITesting { return false }
        return !UserDefaults.standard.bool(forKey: "onboardingComplete")
    }

    /// Whether SwiftUI should build and show the main window at launch. Suppressed
    /// during setup so the two do not stack; `finish()` opens it once setup is done.
    @MainActor
    static var presentsMainWindowAtLaunch: Bool { !startsInBackground && !launchesIntoOnboarding }

    static var permissionReadinessOverride: PermissionReadiness? {
        simulatesMissingPermissions
            ? PermissionReadiness(missingPermissions: [.microphone, .accessibility])
            : nil
    }
}

/// Where the rest of the app borrows SwiftUI's window-opening action. Only a
/// SwiftUI view holds it, and a login launch has no window whose view could offer
/// it — so it comes from the menu bar icon, the one piece of Scriber macOS draws
/// at login.
@MainActor
final class SceneOpeners {
    static let shared = SceneOpeners()

    var openMainWindow: (() -> Void)?
    /// How the launch poller reaches setup, which no main window is around to open.
    var openOnboardingWindow: (() -> Void)?
}

/// Carries `openWindow` out of SwiftUI, beside drawing the icon. A plain `Image`
/// cannot: the action lives in the view environment, which only a view type can
/// read.
private struct MenuBarLabel: View {
    let image: NSImage
    let accessibilityLabel: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: image)
            .accessibilityLabel(accessibilityLabel)
            .task {
                SceneOpeners.shared.openMainWindow = { openWindow(id: "main") }
                SceneOpeners.shared.openOnboardingWindow = { openWindow(id: "onboarding") }
            }
    }
}

@MainActor
enum AppWindowIdentity {
    static let mainTitle = "Scriber"
    static let onboardingTitle = "Set Up Scriber"
    static let settingsTitle = "Settings"
    private static let mainWindowTitles: Set<String> = [mainTitle]

    static func isMainWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.styleMask.contains(.titled) else { return false }
        return window.identifier?.rawValue == "main" || mainWindowTitles.contains(window.title)
    }

    /// Scene identifier first, title second, matching `isMainWindow`. A tabbed
    /// pane is free to retitle its window after the selected tab the way Safari's
    /// does, so the title alone is not enough to match Settings on.
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.styleMask.contains(.titled) else { return false }
        return window.identifier?.rawValue == "settings" || window.title == settingsTitle
    }

    static func isManagedWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.styleMask.contains(.titled) else { return false }
        return isMainWindow(window)
            || isSettingsWindow(window)
            || window.title == onboardingTitle
    }
}

/// Keep Scriber's history isolated from other SwiftData apps. The framework's
/// default URL is the generic `~/Library/Application Support/default.store`, so
/// multiple unsandboxed apps can otherwise attempt to open the same database.
@MainActor
private enum DictationHistoryStore {
    private static let retryDelays: [TimeInterval] = [0, 0.2, 0.5, 1]

    /// Known and unfixed: the retry delay sleeps on the main thread. It only
    /// runs between failed store-open attempts, and making it asynchronous
    /// requires redesigning `AppRuntime` initialization.
    static func makePersistentContainer() throws -> ModelContainer {
        var lastError: Error?

        for delay in retryDelays {
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            do {
                let container = try ModelContainer(
                    for: DictationRecord.self,
                    configurations: try persistentConfiguration()
                )
                var readinessCheck = FetchDescriptor<DictationRecord>()
                readinessCheck.fetchLimit = 1
                _ = try container.mainContext.fetch(readinessCheck)
                return container
            } catch {
                lastError = error
            }
        }

        throw lastError!
    }

    private static func persistentConfiguration() throws -> ModelConfiguration {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Scriber", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ModelConfiguration(url: directory.appendingPathComponent("History.store"))
    }
}

@MainActor
final class AppRuntime: ObservableObject {
    let container: ModelContainer
    var preferences: Preferences
    let coordinator: AppCoordinator
    private var cancellables = Set<AnyCancellable>()

    init() {
        let isUITesting = AppLaunchConfiguration.isUITesting
        let persistenceAvailable: Bool
        if isUITesting {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: DictationRecord.self, configurations: configuration)
            persistenceAvailable = true
        } else {
            do {
                container = try DictationHistoryStore.makePersistentContainer()
                persistenceAvailable = true
            } catch {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try! ModelContainer(for: DictationRecord.self, configurations: configuration)
                persistenceAvailable = false
            }
        }

        // Seed synchronously, before anything renders. Deferring to a
        // `Task { @MainActor … }` inserts into a context `@Query` has already read
        // from, which is a value changing inside an update — AttributeGraph aborts
        // the process for that.
#if DEBUG
        if AppLaunchConfiguration.seedsDictationHistory {
            UITestingHistoryFixture.seed(into: container.mainContext)
        }
        if AppLaunchConfiguration.seedsLargeDictationHistory {
            UITestingLargeHistoryFixture.seed(into: container.mainContext)
        }
#endif

        if isUITesting {
            let suiteName = "com.gafiegarcia.scriber.ui-testing"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            preferences = Preferences(defaults: defaults, defaultAudioInputSelection: .automatic)
        } else {
            let inputDevices = AudioRecorder.availableInputDevices()
            preferences = Preferences(defaultAudioInputSelection: .initialSelection(from: inputDevices))
        }

        coordinator = AppCoordinator(
            preferences: preferences,
            modelContext: container.mainContext,
            persistenceAvailable: persistenceAvailable,
            permissionReadinessOverride: AppLaunchConfiguration.permissionReadinessOverride,
            servicesAllowed: !isUITesting
        )
        if isUITesting {
            preferences.onboardingComplete = !AppLaunchConfiguration.showsOnboarding
            if AppLaunchConfiguration.presentsInvalidKeyPill {
                Task { @MainActor [coordinator] in
                    try? await Task.sleep(for: .milliseconds(100))
                    coordinator.presentInvalidAPIKeyPillForUITesting()
                }
            }
            if AppLaunchConfiguration.simulatesMissingPermissions {
                Task { @MainActor [coordinator] in
                    // Later than initial window construction on purpose, so this
                    // runs after SwiftUI has installed its toolbar observers.
                    try? await Task.sleep(for: .seconds(1))
                    coordinator.presentPermissionRecoveryPillForUITesting()
                }
            }
        }
        // Nested `ObservableObject`s do not propagate, so views reading
        // `runtime.coordinator.x` need this fan-out to update at all.
        //
        // Known and unfixed: any coordinator change therefore invalidates this
        // whole `App` body, so SwiftUI reinstalls the main menu — starting a
        // dictation with the Window menu open prunes the items AppKit contributes
        // from the key window. Undoing the fan-out means every view observing the
        // coordinator directly, which risks views that silently stop updating.
        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // Deferred by one main-actor turn, never called directly. `@StateObject`
        // builds this object in the middle of SwiftUI's scene-graph update, and
        // `startServices` can present the recovery pill, which resizes an AppKit
        // panel and provokes a nested render — a value set mid-update, which
        // AttributeGraph aborts the process for. Only reproduces when a permission
        // is genuinely missing. `startServices` is re-entrant, so the wait is free.
        if !isUITesting {
            Task { @MainActor [coordinator] in coordinator.startServices() }
        } else if AppLaunchConfiguration.pretendedVersion != nil {
            // `startServices` is what checks for updates, and a `--ui-testing`
            // launch never runs it. Ask directly, so the offer is already on
            // screen when the window opens rather than waiting for a button.
            Task { @MainActor [coordinator] in coordinator.checkForUpdates() }
        }
    }
}

@main
struct ScriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime()

    var body: some Scene {
        Window("Scriber", id: "main") {
            MainWindowView()
                .environmentObject(runtime)
                .modelContainer(runtime.container)
                .task { await promoteApplicationForVisibleWindow(isStartupWindow: true) }
        }
        // Said outright rather than waited for: left to itself SwiftUI creates this
        // window at launch only when there is a saved one to restore, so a session
        // that ended with the window closed comes up with no window at all.
        .defaultLaunchBehavior(AppLaunchConfiguration.presentsMainWindowAtLaunch ? .presented : .suppressed)
        .defaultSize(width: 900, height: 640)
        // Hides the title text only. `window.title` and `.titled` both survive,
        // which every `AppWindowIdentity` check depends on, and SwiftUI sets
        // `fullSizeContentView` itself so content runs under the toolbar.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            MainWindowCommands(runtime: runtime)
            CommandGroup(replacing: .appTermination) {
                Button("Quit Scriber") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Close All Windows") { closeAllNormalWindows() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }

        Window("Settings", id: "settings") {
            SettingsView(
                onShortcutConfigurationCaptureChanged: runtime.coordinator.setShortcutConfigurationCaptureActive
            )
            .environmentObject(runtime)
            .modelContainer(runtime.container)
            .task { await promoteApplicationForVisibleWindow() }
        }
        // Fixed, so every tab is seen at the size it was designed at and a tab
        // taller than the window scrolls. SwiftUI persists a frame per scene id
        // and a persisted frame wins, so a Mac that resized this window before
        // it was fixed keeps that size until the stored frame is cleared.
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Scriber") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }

        Window("Set Up Scriber", id: "onboarding") {
            OnboardingView()
                .environmentObject(runtime)
                .modelContainer(runtime.container)
                .task { await promoteApplicationForVisibleWindow() }
        }
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Scriber") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra(
            isInserted: Binding(
                // A `--ui-testing` launch shows no menu bar icon unless asked: it
                // would otherwise sit as a second mark beside the real app's, with
                // nothing to tell them apart.
                get: {
                    runtime.preferences.showInMenuBar
                        && (!AppLaunchConfiguration.isUITesting
                            || AppLaunchConfiguration.showsMenuBarWhileUITesting)
                },
                set: { isInserted in
                    Task { @MainActor in
                        guard runtime.preferences.showInMenuBar != isInserted else { return }
                        runtime.preferences.showInMenuBar = isInserted
                    }
                }
            )
        ) {
            MenuBarContent().environmentObject(runtime)
        } label: {
            menuBarLabel
        }
    }

    /// The icon reports configuration problems and nothing else. It does not track
    /// the dictation phase — the pill and the sounds already narrate that.
    private var menuBarLabel: some View {
        MenuBarLabel(
            image: needsAttention ? Self.warningImage : Self.markImage,
            accessibilityLabel: needsAttention ? "Scriber needs attention" : "Scriber"
        )
    }

    /// Height of the mark in the menu bar. The single knob worth turning: the mark
    /// is tall and narrow, so matching a square symbol's 17 makes it read as the
    /// biggest thing in the bar. Two points down sits it in the row.
    private static let menuBarIconHeight: CGFloat = 15

    /// **A menu bar item measures `NSImage.size`, not the SwiftUI frame around it.**
    /// Setting a frame does nothing; the item takes the image's own size, and the
    /// asset's intrinsic size is 414 x 602, wide enough to push every other status
    /// item into the overflow. So set the size on the image, once, here.
    ///
    /// The width is left fractional so the ratio matches the source exactly — the
    /// asset is vector-backed, so AppKit re-rasterizes rather than scaling a bitmap.
    private static func menuBarImage(_ image: NSImage) -> NSImage {
        let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
        image.size = NSSize(
            width: menuBarIconHeight * ratio,
            height: menuBarIconHeight
        )
        // Template rendering is what makes the mark follow the menu bar through
        // light, dark, and a tinted desktop behind a transparent bar.
        image.isTemplate = true
        return image
    }

    private static let markImage: NSImage = menuBarImage(NSImage(resource: .menuBarIcon))

    /// The same height as the mark, so the item does not resize when Scriber starts
    /// or stops needing attention. The symbol is square, so the width still moves by
    /// a few points; matching height is what stops that reading as a jump.
    private static let warningImage: NSImage = menuBarImage(
        NSImage(
            systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: "Scriber needs attention"
        ) ?? NSImage(resource: .menuBarIcon)
    )

    private var needsAttention: Bool {
        guard runtime.preferences.onboardingComplete else { return false }
        return !runtime.coordinator.permissionReadiness.isReady
            || !runtime.coordinator.credentialReadiness.isReady
    }

    private func closeAllNormalWindows() {
        NSApp.windows.filter(AppWindowIdentity.isManagedWindow).forEach { $0.performClose(nil) }
    }

    @MainActor
    private func promoteApplicationForVisibleWindow(isStartupWindow: Bool = false) async {
        guard !AppLaunchConfiguration.launchesWithoutActivating else { return }
        // Promoting on the main window's first appearance is what would put Scriber
        // in front of whatever the user is doing. Every later route in — menu bar
        // item, the pill's Open button, Command-comma — asks for activation itself.
        guard !(isStartupWindow && AppLaunchConfiguration.startsInBackground) else { return }
        NSApp.setActivationPolicy(.regular)
        await Task.yield()
        guard !Task.isCancelled else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MainWindowCommands: Commands {
    let runtime: AppRuntime

    @FocusedValue(\.searchDictationHistoryAction) private var searchDictationHistory

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Dictations") { searchDictationHistory?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(searchDictationHistory == nil)
        }
    }

    /// Settings is its own window. Select the destination first so a window that
    /// has to be created comes up already scrolled to the right section.
    @MainActor
    private func openSettings() {
        runtime.coordinator.openSettingsWindow(destination: .settings)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    private var activationRetryTask: Task<Void, Never>?
    private var accessoryDemotionTask: Task<Void, Never>?
    private var onboardingWindowTask: Task<Void, Never>?
    private var settingsWindowTask: Task<Void, Never>?
    private var showAppInDock = false
    /// Set the moment the user closes a managed window, so the startup show
    /// sequence stops trying to put that window back on screen.
    private var initialWindowDismissed = false
    private var escapeMonitor: Any?
    private var onboardingCentreMonitor: Any?
    /// Windows already placed. `fitOnboardingWindow` runs from `didBecomeKey`,
    /// which fires every time setup is clicked back into — re-centring there
    /// takes the window's position away from whoever moved it.
    private var fittedOnboardingWindows = Set<ObjectIdentifier>()
    private var fittedSettingsWindows = Set<ObjectIdentifier>()

    // Temporary: traces which path orders the startup window back on screen after
    // an early Command-W. Records only window titles, booleans, and policies.
    private static let windowLog = Logger(subsystem: "com.gafiegarcia.scriber", category: "window-lifecycle")

    /// Escape closes Settings when nothing in it has a better use for the key.
    ///
    /// Installed here for the app's lifetime rather than by `SettingsView`: a
    /// SwiftUI `Window` scene does not reliably run `onAppear` when its window is
    /// re-shown, so a monitor tied to that has nothing keeping it alive.
    /// `onExitCommand` fires only for a view that holds focus, which a pane of
    /// toggles and pickers never does.
    ///
    /// Stand aside explicitly rather than positionally: the order two local
    /// monitors run in is undefined, so ask whether a shortcut recorder is
    /// mid-capture rather than assuming this loses the race.
    ///
    /// Known and unfixed: this could not be verified from an injected key event.
    /// The monitor demonstrably runs and reports the right window for ordinary
    /// keys, but a synthesised Escape never reaches it, so something consumes that
    /// key earlier under automation. If Escape does nothing on a real keypress,
    /// this is where to look, and the answer is which responder takes it first —
    /// not this predicate.
    private func installSettingsEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53,
                  let window = event.window,
                  AppWindowIdentity.isSettingsWindow(window) else { return event }
            var consumed = false
            MainActor.assumeIsolated {
                guard !ShortcutConfigurationCapture.isActive else { return }
                // The same route as Command-W and the red control, so the close
                // observers that reconcile the Dock icon still run.
                window.performClose(nil)
                consumed = true
            }
            return consumed ? nil : event
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Sampled here and again below. The Apple event that says who started the
        // app is readable only while AppKit is handling it, and which of these two
        // moments that covers is not something the documentation settles.
#if DEBUG
        if AppLaunchConfiguration.simulatesLoginLaunch { LoginItemLaunch.simulateLoginLaunch() }
#endif
        LoginItemLaunch.capture(phase: "willFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItemLaunch.capture(phase: "didFinishLaunching")
        logLaunchContext(notification)
        showAppInDock = AppLaunchConfiguration.isUITesting
            ? false
            : UserDefaults.standard.bool(forKey: "showAppInDock")
        NSApp.setActivationPolicy(AppLaunchConfiguration.keepsRegularActivationPolicy ? .regular : .accessory)
        installSettingsEscapeMonitor()
        installOnboardingCentreMonitor()
        let center = NotificationCenter.default
        NSApp.windows.filter(AppWindowIdentity.isManagedWindow).forEach { $0.isReleasedWhenClosed = false }
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                guard AppWindowIdentity.isManagedWindow(window) else { return }
                window.isReleasedWhenClosed = false
                NSApp.setActivationPolicy(.regular)
                if window.title == AppWindowIdentity.onboardingTitle { self?.fitOnboardingWindow(window) }
                if AppWindowIdentity.isSettingsWindow(window) { self?.fitSettingsWindow(window) }
            }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            // Record the dismissal synchronously. `willCloseNotification` is posted on
            // the main queue, and the startup poll can wake in the very same millisecond
            // — deferring this to a Task hop loses that race and the window comes back.
            MainActor.assumeIsolated {
                guard AppWindowIdentity.isManagedWindow(window) else { return }
                Self.windowLog.notice("willClose: title=\(window.title, privacy: .public)")
                self?.initialWindowDismissed = true
                self?.activationRetryTask?.cancel()
                self?.activationRetryTask = nil
                self?.fittedOnboardingWindows.remove(ObjectIdentifier(window))
                self?.fittedSettingsWindows.remove(ObjectIdentifier(window))
            }
            Task { @MainActor [weak self] in
                guard AppWindowIdentity.isManagedWindow(window) else { return }
                await Task.yield()
                self?.reconcileActivationPolicy()
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                guard AppWindowIdentity.isManagedWindow(window) else { return }
                await Task.yield()
                self?.reconcileActivationPolicy()
            }
        })
        observers.append(center.addObserver(forName: .openScriberMainWindow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showMainWindow() }
        })
        observers.append(center.addObserver(forName: .openScriberOnboardingWindow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showOnboardingWindow() }
        })
        observers.append(center.addObserver(forName: .openScriberSettingsWindow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showSettingsWindow() }
        })
        observers.append(center.addObserver(forName: .showAppInDockDidChange, object: nil, queue: .main) { [weak self] note in
            guard let showAppInDock = note.object as? Bool else { return }
            Task { @MainActor [weak self] in
                self?.showAppInDock = showAppInDock
                self?.reconcileActivationPolicy()
            }
        })
        let startsInBackground = AppLaunchConfiguration.startsInBackground
        Self.windowLog.notice(
            """
            launch: loginItem=\(LoginItemLaunch.isLoginItemLaunch, privacy: .public) \
            startsInBackground=\(startsInBackground, privacy: .public)
            """
        )
        guard !startsInBackground else {
            // Nothing else will reconcile the policy this launch, and "Show in Dock"
            // is a standing request for a Dock icon whether or not a window is up.
            reconcileActivationPolicy()
            return
        }
        Task { @MainActor [weak self] in
            await self?.showInitialWindowWhenAvailable(
                onboardingComplete: !AppLaunchConfiguration.launchesIntoOnboarding
            )
        }
    }

    /// Everything else macOS says about this launch, beside the Apple event.
    /// Written every launch on purpose: a launch decides behaviour before anyone
    /// can watch it, and the alternative is restarting the Mac once per guess.
    private func logLaunchContext(_ notification: Notification) {
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool
        let userInfoKeys = (notification.userInfo?.keys.map { "\($0)" } ?? []).sorted().joined(separator: ",")
        let xpcServiceName = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] ?? "unset"
        Self.windowLog.notice(
            """
            launchContext: isDefaultLaunch=\(isDefaultLaunch.map(String.init) ?? "absent", privacy: .public) \
            userInfoKeys=[\(userInfoKeys, privacy: .public)] \
            parentPID=\(getppid(), privacy: .public) \
            xpcServiceName=\(xpcServiceName, privacy: .public) \
            active=\(NSApp.isActive, privacy: .public)
            """
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !hasVisibleManagedWindow { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showMainWindow() {
        showWindow(titled: AppWindowIdentity.mainTitle)
    }

    /// Polls like onboarding does: the caller's `openWindow(id:)` may have just
    /// created the scene, and `showWindow` can only order a window AppKit has
    /// actually made.
    private func showSettingsWindow() {
        settingsWindowTask?.cancel()
        settingsWindowTask = Task { @MainActor [weak self] in
            for _ in 0..<20 {
                guard let self, !Task.isCancelled else { return }
                if self.showWindow(titled: AppWindowIdentity.settingsTitle) { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Stops Control-C standing in for Enter on the setup window, handing the key
    /// to the main menu instead.
    ///
    /// AppKit resolves Control-C to `NSEnterCharacter` (0x03), the character the
    /// Enter key sends, so a window's default button answers to it and answers
    /// first. The two keys are only separable before that resolution, where Enter
    /// reports 0x03 with no modifier and Control-C reports "c" with Control held.
    ///
    /// Offer the event to the menu rather than centring the window here, so the
    /// shortcut matches the menu item exactly — `NSWindow.center` rests a window
    /// above centre and moves it in one jump, which is not that command.
    ///
    /// App-lifetime, for the same reason as the Settings escape monitor above.
    private func installOnboardingCentreMonitor() {
        onboardingCentreMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "c",
                  let window = event.window,
                  window.title == AppWindowIdentity.onboardingTitle
            else { return event }
            MainActor.assumeIsolated { NSApp.mainMenu?.performKeyEquivalent(with: event) }
            return nil
        }
    }

    /// Brings onboarding forward for a Redo Setup request. Polls, because the
    /// caller's `openWindow(id:)` is what creates the scene and `showWindow` can
    /// only order a window AppKit has actually made.
    private func showOnboardingWindow() {
        // Setup is presented in front of whatever asked for it, so the windows it
        // replaces go first — through `performClose`, the same route as Command-W
        // and the red control, so the close observers that reconcile the Dock
        // icon still run.
        for window in NSApp.windows
        where AppWindowIdentity.isManagedWindow(window)
            && window.title != AppWindowIdentity.onboardingTitle {
            window.performClose(nil)
        }
        onboardingWindowTask?.cancel()
        onboardingWindowTask = Task { @MainActor [weak self] in
            for _ in 0..<40 {
                guard let self, !Task.isCancelled else { return }
                if self.showWindow(titled: AppWindowIdentity.onboardingTitle) { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
            Self.windowLog.notice("showOnboardingWindow: never appeared")
        }
    }

    /// Holds Settings at its fixed size, and keeps Window ▸ Center working there.
    ///
    /// `.contentSize` resizability sizes a window from its content but never
    /// re-derives a frame AppKit restored from an earlier session, so a Mac that
    /// resized Settings while it still could reopens it at that size. Pinning both
    /// limits corrects it on the way in; the saved position is left alone.
    ///
    /// The resizable mask is claimed for the reason `fitOnboardingWindow` gives.
    private func fitSettingsWindow(_ window: NSWindow) {
        guard fittedSettingsWindows.insert(ObjectIdentifier(window)).inserted else { return }
        let size = NSSize(width: SettingsWindowLayout.width, height: SettingsWindowLayout.height)
        window.styleMask.insert(.resizable)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        window.collectionBehavior.insert(.fullScreenNone)
    }

    private func fitOnboardingWindow(_ window: NSWindow) {
        guard fittedOnboardingWindows.insert(ObjectIdentifier(window)).inserted else { return }
        window.isRestorable = false
        // macOS disables Window ▸ Center and Fill for a window that cannot be
        // resized, and a disabled menu item does not consume its key — so ⌃🌐C
        // falls through to the app, where AppKit reads Control-C as the Enter
        // character (0x03) and fires the default button, advancing a step.
        // Claiming the resizable mask while pinning both size limits enables those
        // commands and still leaves nothing to drag.
        let size = NSSize(
            width: OnboardingLayout.windowWidth,
            height: OnboardingLayout.windowHeight
        )
        window.styleMask.insert(.resizable)
        window.contentMinSize = size
        window.contentMaxSize = size
        // The mask is claimed for Center alone. A resizable window is also a
        // full-screen one, and this content is pinned to the size above, so full
        // screen would strand the page in the middle of an empty display.
        window.collectionBehavior.insert(.fullScreenNone)
        window.center()
        // On a first run the main window is created second and lands in front of
        // the one the user is meant to read. Order here rather than at the open
        // call, because the window does not exist yet when setup asks for it.
        window.makeKeyAndOrderFront(nil)
    }

    /// Known and unfixed: this polls for the startup window by title. Remove it
    /// only after proving which launch paths still depend on it; the Dock
    /// lifecycle is the constraint.
    private func showInitialWindowWhenAvailable(onboardingComplete: Bool) async {
        let title = onboardingComplete ? AppWindowIdentity.mainTitle : AppWindowIdentity.onboardingTitle
        for attempt in 0..<40 {
            guard !Task.isCancelled else { return }
            guard !initialWindowDismissed else {
                Self.windowLog.notice("initialWindowPoll: abandoned, user dismissed the window")
                return
            }
            // Asked for, not waited for. macOS tells an app it started at login not
            // to open windows, and SwiftUI obeys — `.defaultLaunchBehavior(.presented)`
            // does not override it, so at login the window has to be requested.
            // Retried once in case the menu bar icon had not yet handed the action
            // over when the first attempt ran.
            if attempt == 0 || attempt == 10 {
                if title == AppWindowIdentity.mainTitle {
                    SceneOpeners.shared.openMainWindow?()
                } else {
                    SceneOpeners.shared.openOnboardingWindow?()
                }
            }
            if showWindow(titled: title) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Name what was there instead: "exhausted" alone cannot tell a window that
        // arrived late from one that was never built.
        let present = NSApp.windows
            .map { window in
                let name = window.title.isEmpty ? "untitled" : window.title
                let identifier = window.identifier?.rawValue ?? "none"
                return "\(name)/id=\(identifier)/\(type(of: window))/titled=\(window.styleMask.contains(.titled))/\(window.isVisible ? "visible" : "hidden")"
            }
            .joined(separator: " ")
        Self.windowLog.notice(
            """
            initialWindowPoll: exhausted without finding \(title, privacy: .public) \
            opener=\(SceneOpeners.shared.openMainWindow != nil, privacy: .public) \
            windows=[\(present, privacy: .public)]
            """
        )
    }

    @discardableResult
    private func showWindow(titled title: String) -> Bool {
        guard let window = NSApp.windows.first(where: {
            guard AppWindowIdentity.isManagedWindow($0) else { return false }
            switch title {
            case AppWindowIdentity.mainTitle: return AppWindowIdentity.isMainWindow($0)
            case AppWindowIdentity.settingsTitle: return AppWindowIdentity.isSettingsWindow($0)
            default: return $0.title == title
            }
        }) else { return false }
        Self.windowLog.notice(
            "showWindow: ordering front title=\(title, privacy: .public) wasVisible=\(window.isVisible, privacy: .public)"
        )
        let previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
        activationRetryTask?.cancel()
        NSApp.setActivationPolicy(.regular)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        activationRetryTask = Task { @MainActor [weak self, weak window, previouslyActiveApplication] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, let window, !Task.isCancelled, window.isVisible else { return }

            let currentApplication = NSRunningApplication.current
            let activationRequested: Bool
            if let previouslyActiveApplication,
               previouslyActiveApplication.processIdentifier != currentApplication.processIdentifier {
                activationRequested = currentApplication.activate(
                    from: previouslyActiveApplication,
                    options: [.activateAllWindows]
                )
            } else {
                activationRequested = currentApplication.activate(options: [.activateAllWindows])
            }
            if !activationRequested { NSApp.activate() }
            // `activate(from:)` returning true means the request was accepted,
            // not that the app came forward; macOS still declines it when the
            // caller has no activation to trade on. If a route into this method
            // reports success here and stays behind another app, that gap is
            // where to look — the caller needs to ask for activation itself.
            Self.windowLog.notice(
                """
                showWindow: activation title=\(title, privacy: .public) \
                requested=\(activationRequested, privacy: .public) \
                active=\(currentApplication.isActive, privacy: .public)
                """
            )
            window.makeKeyAndOrderFront(nil)
            // Reassert regular mode only after the startup window is visible: AppKit
            // can otherwise process its initial resign-key transition after the
            // earlier promotion, leaving a visible window with no Dock icon.
            self.reconcileActivationPolicy()

            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            // A window closed between the two activation attempts must stay closed.
            // Without this check the retry orders a just-dismissed window back on
            // screen, and the reconcile below then holds regular activation policy.
            if window.isVisible, !currentApplication.isActive {
                Self.windowLog.notice("retry: reactivating a still-visible startup window")
                _ = currentApplication.activate(options: [.activateAllWindows])
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
            }
            self.reconcileActivationPolicy()
            activationRetryTask = nil
        }
        return true
    }

    private var hasVisibleManagedWindow: Bool {
        NSApp.windows.contains { $0.isVisible && AppWindowIdentity.isManagedWindow($0) }
    }

    private func reconcileActivationPolicy() {
        guard !wantsRegularActivationPolicy else {
            accessoryDemotionTask?.cancel()
            accessoryDemotionTask = nil
            applyActivationPolicy(.regular)
            return
        }
        // Demoting waits a beat. A window closing to hand over to another — setup
        // finishing into the main window — leaves a moment with nothing visible,
        // and dropping to accessory only to be promoted straight back leaves a
        // second Dock tile pointing at the same app. A quarter second tells a
        // handover apart from an empty app.
        guard accessoryDemotionTask == nil else { return }
        accessoryDemotionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            accessoryDemotionTask = nil
            guard !wantsRegularActivationPolicy else { return }
            applyActivationPolicy(.accessory)
        }
    }

    private var wantsRegularActivationPolicy: Bool {
        hasVisibleManagedWindow
            || showAppInDock
            || AppLaunchConfiguration.keepsRegularActivationPolicy
    }

    private func applyActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        let applied = NSApp.setActivationPolicy(policy)
        Self.windowLog.notice(
            "reconcile: policy=\(policy == .regular ? "regular" : "accessory", privacy: .public) hasVisibleManaged=\(self.hasVisibleManagedWindow, privacy: .public) applied=\(applied, privacy: .public)"
        )
    }
}
