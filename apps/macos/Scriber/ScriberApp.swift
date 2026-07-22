import AppKit
import Combine
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
        isUITesting && !ProcessInfo.processInfo.arguments.contains("--ui-testing-accessory-lifecycle")
    }

    static var presentsInvalidKeyPill: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-invalid-key-pill")
    }
}

@MainActor
private enum AppWindowIdentity {
    static let mainTitle = "Scriber"
    static let onboardingTitle = "Set Up Scriber"

    static func isManagedWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.styleMask.contains(.titled) else { return false }
        return window.title == mainTitle || window.title == onboardingTitle
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
        if isUITesting {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: DictationRecord.self, configurations: configuration)
        } else {
            do {
                container = try ModelContainer(for: DictationRecord.self)
            } catch {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try! ModelContainer(for: DictationRecord.self, configurations: configuration)
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
        }
        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        if !isUITesting { coordinator.startServices() }
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
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            MainWindowCommands()
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
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Scriber") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra("Scriber", systemImage: menuBarSymbol) {
            MenuBarContent().environmentObject(runtime)
        }
    }

    private var menuBarSymbol: String {
        switch runtime.coordinator.phase {
        case .recording: "waveform.circle.fill"
        case .transcribing: "ellipsis.circle"
        case .cancelledTranscript: "exclamationmark.circle"
        case .dictationCopied: "checkmark.circle"
        case .apiKeyInvalid, .apiCreditsExhausted, .pasteFailed, .transcriptionFailed: "exclamationmark.circle"
        default: "waveform.circle"
        }
    }

    private func closeAllNormalWindows() {
        NSApp.windows.filter(AppWindowIdentity.isManagedWindow).forEach { $0.performClose(nil) }
    }
}

private struct MainWindowCommands: Commands {
    @FocusedValue(\.searchDictationHistoryAction) private var searchDictationHistory

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Search Dictations") { searchDictationHistory?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(searchDictationHistory == nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    private var activationRetryTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppLaunchConfiguration.isUITesting ? .regular : .accessory)
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
        Task { @MainActor [weak self] in
            await Task.yield()
            let onboardingComplete = AppLaunchConfiguration.isUITesting
                || UserDefaults.standard.bool(forKey: "onboardingComplete")
            self?.showInitialWindow(onboardingComplete: onboardingComplete)
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

    private func showInitialWindow(onboardingComplete: Bool) {
        showWindow(titled: onboardingComplete ? AppWindowIdentity.mainTitle : AppWindowIdentity.onboardingTitle)
    }

    private func showWindow(titled title: String) {
        guard let window = NSApp.windows.first(where: {
            AppWindowIdentity.isManagedWindow($0) && $0.title == title
        }) else { return }
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
            window.makeKeyAndOrderFront(nil)

            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            if !currentApplication.isActive {
                _ = currentApplication.activate(options: [.activateAllWindows])
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
            }
            activationRetryTask = nil
        }
    }

    private var hasVisibleManagedWindow: Bool {
        NSApp.windows.contains { $0.isVisible && AppWindowIdentity.isManagedWindow($0) }
    }

    private func reconcileActivationPolicy() {
        let policy: NSApplication.ActivationPolicy =
            hasVisibleManagedWindow || AppLaunchConfiguration.keepsRegularActivationPolicy
            ? .regular
            : .accessory
        NSApp.setActivationPolicy(policy)
    }
}
