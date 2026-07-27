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

    /// The launch smoke check's flag. The app still builds and renders its window —
    /// that is the path the check exists to exercise — but never activates, so it
    /// does not steal the front from whatever Gaf is doing. Only the smoke check
    /// passes this; XCUITest needs the real activation behaviour.
    static var launchesWithoutActivating: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-no-activate")
    }

    static var permissionReadinessOverride: PermissionReadiness? {
        simulatesMissingPermissions
            ? PermissionReadiness(missingPermissions: [.microphone, .accessibility])
            : nil
    }
}

@MainActor
private enum AppWindowIdentity {
    static let mainTitle = "Scriber"
    static let onboardingTitle = "Set Up Scriber"
    private static let mainWindowTitles: Set<String> = [mainTitle, "Dictation", "Settings"]

    static func isManagedWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.styleMask.contains(.titled) else { return false }
        return mainWindowTitles.contains(window.title) || window.title == onboardingTitle
    }
}

/// Keep Scriber's history isolated from other SwiftData apps. The framework's
/// default URL is the generic `~/Library/Application Support/default.store`, so
/// multiple unsandboxed apps can otherwise attempt to open the same database.
@MainActor
private enum DictationHistoryStore {
    private static let retryDelays: [TimeInterval] = [0, 0.2, 0.5, 1]

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
            preferences.onboardingComplete = true
            if AppLaunchConfiguration.presentsInvalidKeyPill {
                Task { @MainActor [coordinator] in
                    try? await Task.sleep(for: .milliseconds(100))
                    coordinator.presentInvalidAPIKeyPillForUITesting()
                }
            }
            if AppLaunchConfiguration.simulatesMissingPermissions {
                Task { @MainActor [coordinator] in
                    try? await Task.sleep(for: .milliseconds(100))
                    coordinator.presentPermissionRecoveryPillForUITesting()
                }
            }
        }
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
                .task { await promoteApplicationForVisibleWindow() }
        }
        .defaultSize(width: 980, height: 640)
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

        Window("Set Up Scriber", id: "onboarding") {
            OnboardingView()
                .environmentObject(runtime)
                .modelContainer(runtime.container)
                .task { await promoteApplicationForVisibleWindow() }
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
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
    @ViewBuilder
    private var menuBarLabel: some View {
        if needsAttention {
            Image(nsImage: Self.warningImage)
                .accessibilityLabel("Scriber needs attention")
        } else {
            Image(nsImage: Self.markImage)
                .accessibilityLabel("Scriber")
        }
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
    /// layout in the path to be honoured or ignored. Rounding the width keeps the
    /// item on whole points.
    private static func menuBarImage(_ image: NSImage) -> NSImage {
        let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
        image.size = NSSize(
            width: (menuBarIconHeight * ratio).rounded(),
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
    private func promoteApplicationForVisibleWindow() async {
        guard !AppLaunchConfiguration.launchesWithoutActivating else { return }
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
        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { toggleSidebar() }
                .keyboardShortcut(".", modifiers: .command)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Dictations") { searchDictationHistory?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(searchDictationHistory == nil)
        }
    }

    /// SwiftUI builds the split view controller behind `NavigationSplitView`, so
    /// there is no reference to hold. Sending the selector down the responder
    /// chain reaches it wherever it ended up.
    @MainActor
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }

    /// Scriber has no SwiftUI `Settings` scene; Settings is a section of the main
    /// window. Select the destination before asking for the window so the window
    /// comes up already showing it, and go through the notification rather than
    /// `openWindow` so this still works with every window closed.
    @MainActor
    private func openSettings() {
        runtime.coordinator.selectMainWindowDestination(.settings)
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .openScriberMainWindow, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    private var activationRetryTask: Task<Void, Never>?
    private var showAppInDock = false
    /// Set the moment the user closes a managed window, so the startup show
    /// sequence stops trying to put that window back on screen.
    private var initialWindowDismissed = false

    // Temporary: traces which path orders the startup window back on screen after
    // an early Command-W. Records only window titles, booleans, and policies.
    private static let windowLog = Logger(subsystem: "com.gafiegarcia.scriber", category: "window-lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        showAppInDock = AppLaunchConfiguration.isUITesting
            ? false
            : UserDefaults.standard.bool(forKey: "showAppInDock")
        NSApp.setActivationPolicy(AppLaunchConfiguration.keepsRegularActivationPolicy ? .regular : .accessory)
        let center = NotificationCenter.default
        NSApp.windows.filter(AppWindowIdentity.isManagedWindow).forEach { $0.isReleasedWhenClosed = false }
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                guard AppWindowIdentity.isManagedWindow(window) else { return }
                window.isReleasedWhenClosed = false
                NSApp.setActivationPolicy(.regular)
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
        observers.append(center.addObserver(forName: .showAppInDockDidChange, object: nil, queue: .main) { [weak self] note in
            guard let showAppInDock = note.object as? Bool else { return }
            Task { @MainActor [weak self] in
                self?.showAppInDock = showAppInDock
                self?.reconcileActivationPolicy()
            }
        })
        Task { @MainActor [weak self] in
            let onboardingComplete = AppLaunchConfiguration.isUITesting
                || UserDefaults.standard.bool(forKey: "onboardingComplete")
            await self?.showInitialWindowWhenAvailable(onboardingComplete: onboardingComplete)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !hasVisibleManagedWindow { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showMainWindow() {
        showWindow(titled: AppWindowIdentity.mainTitle)
    }

    private func showInitialWindowWhenAvailable(onboardingComplete: Bool) async {
        let title = onboardingComplete ? AppWindowIdentity.mainTitle : AppWindowIdentity.onboardingTitle
        for _ in 0..<40 {
            guard !Task.isCancelled else { return }
            guard !initialWindowDismissed else {
                Self.windowLog.notice("initialWindowPoll: abandoned, user dismissed the window")
                return
            }
            if showWindow(titled: title) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        Self.windowLog.notice("initialWindowPoll: exhausted without finding \(title, privacy: .public)")
    }

    @discardableResult
    private func showWindow(titled title: String) -> Bool {
        guard let window = NSApp.windows.first(where: {
            AppWindowIdentity.isManagedWindow($0) && $0.title == title
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
