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

    /// Fills the in-memory history so the Dictation list can be checked at all.
    /// Empty is the honest default for a test store, but it left every history
    /// interface check reachable only through Gaf's real entries. See
    /// `UITestingHistoryFixture`.
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
    /// complete so every other check starts in the app proper. Without it the
    /// onboarding window is reachable only by resetting Gaf's real preferences.
    static var showsOnboarding: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-onboarding")
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
        guard !isUITesting, LoginItemLaunch.isLoginItemLaunch else { return false }
        return Preferences.optInFlag("launchAtLoginRequested")
            && Preferences.optInFlag("startInBackground")
            && UserDefaults.standard.bool(forKey: "onboardingComplete")
    }

    /// Whether SwiftUI should build and show the main window at launch. Onboarding
    /// is not a case for suppressing it: setup is opened from the main window's
    /// appearance, so a suppressed main window would take incomplete setup with it.
    @MainActor
    static var presentsMainWindowAtLaunch: Bool { !startsInBackground }

    static var permissionReadinessOverride: PermissionReadiness? {
        simulatesMissingPermissions
            ? PermissionReadiness(missingPermissions: [.microphone, .accessibility])
            : nil
    }
}

/// Where the rest of the app borrows SwiftUI's window-opening action.
///
/// Only a SwiftUI view holds it, and at a login launch there is no window whose
/// view could offer it — which is the situation that needs it most. The menu bar
/// icon is the one piece of Scriber that macOS does draw at login, so that is
/// where it comes from.
@MainActor
final class SceneOpeners {
    static let shared = SceneOpeners()

    var openMainWindow: (() -> Void)?
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
            .task { SceneOpeners.shared.openMainWindow = { openWindow(id: "main") } }
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
    /// does, and the title alone is what fronting, Command-Shift-W, and the
    /// activation-policy count all used to match Settings on.
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

        // Synchronously, here, before anything can render. Deferring this to a
        // `Task { @MainActor … }` the way the pill flags do would insert into a
        // context `@Query` has already read from — a value changing inside an
        // update, which is the failure the comment further down this file records
        // AttributeGraph aborting the process for. Running inside `init` means the
        // store is already populated the first time any view fetches.
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
                    // Exercise a post-render toolbar update. This is deliberately
                    // later than initial window construction so the fixture runs
                    // after SwiftUI has installed its toolbar observers.
                    try? await Task.sleep(for: .seconds(1))
                    coordinator.presentPermissionRecoveryPillForUITesting()
                }
            }
        }
        // Nested `ObservableObject`s do not propagate, so views reading
        // `runtime.coordinator.x` need this fan-out to update at all.
        //
        // Known and unfixed: it also means any coordinator change invalidates
        // this whole `App` body, so SwiftUI reinstalls the main menu. Starting a
        // dictation while the Window menu is open therefore prunes it of the
        // items AppKit contributes from the key window. Undoing the fan-out
        // means every view observing the coordinator directly — a wide change
        // whose failure mode is a view that silently stops updating, which is
        // worse than the menu blink it would buy.
        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // Deferred by one main-actor turn rather than called directly.
        //
        // `@StateObject` builds this object lazily, in the middle of SwiftUI's
        // scene-graph update. `startServices` refreshes permissions, and when a
        // permission is missing it presents the recovery pill immediately — which
        // resizes an AppKit panel and provokes a nested SwiftUI render. That is a
        // value being set while the graph is mid-update, and AttributeGraph aborts
        // the process for it.
        //
        // It only reproduces when a permission is genuinely missing at launch, so
        // the installed app never showed it while a freshly built binary — which
        // macOS has not granted Accessibility — crashed on every run.
        //
        // `startServices` is already re-entrant; `MenuBarContent.onAppear` calls it
        // too. Waiting for the current update to finish costs nothing.
        if !isUITesting {
            Task { @MainActor [coordinator] in coordinator.startServices() }
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
        // Said outright rather than waited for. Left to itself SwiftUI creates this
        // window at launch only when there is a saved one to restore, so a login
        // that followed a session ending with the window closed produced nothing
        // for the startup poll to find, and Scriber came up with no window at all
        // however the settings were set.
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
        // Sized for the tallest tab rather than for all of Settings at once.
        // Only a Mac that has never opened this window sees it: SwiftUI persists
        // the frame per scene id, and a persisted frame wins.
        .defaultSize(width: 660, height: 560)
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
        // No `.windowResizability(.contentSize)`: it pins the window to the
        // content's ideal height, which for a scroll view is greedy, and it
        // refuses the explicit frame `fitOnboardingWindow` sets.
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Scriber") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra(
            isInserted: Binding(
                // `--ui-testing` launches (the smoke check included) never show a menu
                // bar icon: the throwaway defaults suite always starts `showInMenuBar`
                // true, and nothing under automated launch reads the icon, so it would
                // only sit as a second, unexplained mark next to the real app's.
                get: { runtime.preferences.showInMenuBar && !AppLaunchConfiguration.isUITesting },
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

    /// The icon reports configuration problems and nothing else.
    ///
    /// It used to track the dictation phase, but the pill and the sounds already
    /// narrate a dictation, and a menu bar icon that animates through every
    /// recording is a distraction rather than information. What the menu bar is
    /// good at is the state the user cannot otherwise see: Scriber is installed,
    /// running, and unable to work until something is fixed.
    private var menuBarLabel: some View {
        MenuBarLabel(
            image: needsAttention ? Self.warningImage : Self.markImage,
            accessibilityLabel: needsAttention ? "Scriber needs attention" : "Scriber"
        )
    }

    /// Height of the mark in the menu bar. The single knob worth turning.
    ///
    /// 15 rather than 17 after looking at it next to real neighbours: the mark is
    /// tall and narrow, so matching a square symbol's height makes it read as the
    /// biggest thing in the bar. Two points down sits it in the row rather than
    /// above it.
    private static let menuBarIconHeight: CGFloat = 15

    /// **A menu bar item measures `NSImage.size`, not the SwiftUI frame around
    /// it.** Two builds were spent on the frame before that was established, and
    /// both failed in the same direction the artwork pointed:
    ///
    /// - Build 16 handed it the app-icon artwork on its 1024 square. The mark is
    ///   414 x 602 of that canvas, so whatever size the item took, 59% of it was
    ///   the mark and the rest was transparency. It looked far too small.
    /// - Build 17 cropped the asset to its ink and set a 17pt frame. The frame
    ///   was ignored, the item took the image's own size, and at 414 points wide
    ///   it ate the menu bar — every other status item was pushed into the
    ///   overflow. Loading the compiled asset confirms the intrinsic size is
    ///   exactly 414 x 602, and the other items returned the moment this sizing
    ///   landed.
    ///
    /// So the size is set on the image, once, here. `Image(nsImage:)` then hands
    /// AppKit an image that already knows how big it is, and there is no SwiftUI
    /// layout in the path to be honoured or ignored. The width is left fractional
    /// so the ratio matches the source exactly — the asset is vector-backed, so
    /// AppKit re-rasterizes at whatever size it's given rather than scaling a
    /// fixed bitmap.
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

    /// Deliberately the same height as the mark, so the item does not resize
    /// when Scriber starts or stops needing attention. The symbol is square, so
    /// the width still changes by a few points; matching height is what stops it
    /// reading as a jump.
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
        // The main window's first appearance is the one SwiftUI makes at launch,
        // and promoting there is what would put Scriber in front of whatever the
        // user is doing. Every later route into this window — the menu bar item,
        // the pill's Open button, Command-comma — asks for activation itself, so
        // nothing else loses its Dock icon by this.
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
    private var onboardingWindowTask: Task<Void, Never>?
    private var settingsWindowTask: Task<Void, Never>?
    private var showAppInDock = false
    /// Set the moment the user closes a managed window, so the startup show
    /// sequence stops trying to put that window back on screen.
    private var initialWindowDismissed = false
    private var escapeMonitor: Any?

    // Temporary: traces which path orders the startup window back on screen after
    // an early Command-W. Records only window titles, booleans, and policies.
    private static let windowLog = Logger(subsystem: "com.gafiegarcia.scriber", category: "window-lifecycle")

    /// Escape closes Settings when nothing in it has a better use for the key.
    ///
    /// Installed here and for the app's lifetime rather than by `SettingsView`,
    /// because a SwiftUI `Window` scene does not reliably run `onAppear` when its
    /// window is re-shown, so a monitor tied to that had nothing keeping it alive.
    /// `onExitCommand` is no use either: it fires only for a view that holds
    /// focus, and a pane of toggles and pickers never does.
    ///
    /// Standing aside is explicit rather than positional. A shortcut recorder
    /// mid-capture has already promised the user that Escape cancels it, and the
    /// order two local monitors run in is not defined, so this asks rather than
    /// assuming it loses the race. A confirmation gets the key in its own window,
    /// which is not the one this matches.
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
        let center = NotificationCenter.default
        NSApp.windows.filter(AppWindowIdentity.isManagedWindow).forEach { $0.isReleasedWhenClosed = false }
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                guard AppWindowIdentity.isManagedWindow(window) else { return }
                window.isReleasedWhenClosed = false
                NSApp.setActivationPolicy(.regular)
                if window.title == AppWindowIdentity.onboardingTitle { self?.fitOnboardingWindow(window) }
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
            let onboardingComplete = !AppLaunchConfiguration.showsOnboarding
                && (AppLaunchConfiguration.isUITesting
                    || UserDefaults.standard.bool(forKey: "onboardingComplete"))
            await self?.showInitialWindowWhenAvailable(onboardingComplete: onboardingComplete)
        }
    }

    /// Everything else macOS says about this launch, beside the Apple event.
    ///
    /// Written on every launch on purpose: a launch decides behaviour before
    /// anyone can watch it, and the alternative to recording it is restarting the
    /// Mac once per guess.
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

    /// Brings onboarding forward for a Redo Setup request.
    ///
    /// Polls, because the scene may not exist yet: unlike the main window,
    /// onboarding is usually never instantiated in a session that started with
    /// setup already complete, and `showWindow` can only order a window that
    /// AppKit has actually created. The caller's `openWindow(id:)` is what creates
    /// it; this waits for it to appear and then does the ordering and activation.
    private func showOnboardingWindow() {
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

    /// Fits onboarding to the screen itself rather than trusting AppKit's frame.
    ///
    /// Setup is taller than a laptop display, and AppKit's own frame for it was
    /// wrong in both directions: opened while the main window is up it gets
    /// cascaded down until it runs under the Dock, and reopened in a later
    /// session it gets a restored frame that the scene's `.contentSize`
    /// resizability never re-derives — which is how it came back stuck small.
    /// So neither is trusted. The window is given the whole height the screen
    /// offers and centred, every time it appears. A first-time user should see
    /// the setup steps, not have to find them by scrolling.
    private func fitOnboardingWindow(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        window.isRestorable = false
        let chrome = window.frame.height - window.contentLayoutRect.height
        window.setContentSize(
            NSSize(width: 640, height: max(420, visible.height - chrome - 24))
        )
        window.center()
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
            if title == AppWindowIdentity.mainTitle, attempt == 0 || attempt == 10 {
                SceneOpeners.shared.openMainWindow?()
            }
            if showWindow(titled: title) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Names what was there instead. "Exhausted" alone could not tell a window
        // that arrived late from one that was never built, which is the difference
        // between waiting longer and asking for it.
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
            // The app begins as an accessory so a launch with no visible window stays
            // out of the Dock. Reassert regular mode only after the startup window is
            // visible: AppKit can otherwise process its initial resign-key transition
            // after the earlier promotion and leave a visible window without a Dock icon.
            self.reconcileActivationPolicy()

            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            // A window closed between the two activation attempts must stay closed.
            // Without this visibility check the retry orders a just-dismissed window
            // back on screen, and the reconcile below then sees it and holds the
            // process in regular activation policy.
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
        let policy: NSApplication.ActivationPolicy =
            hasVisibleManagedWindow
                || showAppInDock
                || AppLaunchConfiguration.keepsRegularActivationPolicy
            ? .regular
            : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let applied = NSApp.setActivationPolicy(policy)
        Self.windowLog.notice(
            "reconcile: policy=\(policy == .regular ? "regular" : "accessory", privacy: .public) hasVisibleManaged=\(self.hasVisibleManagedWindow, privacy: .public) applied=\(applied, privacy: .public)"
        )
    }
}
