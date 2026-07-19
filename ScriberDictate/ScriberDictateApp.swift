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
}

@MainActor
private enum AppWindowIdentity {
    static let mainTitle = "Scriber Dictate"
    static let onboardingTitle = "Set Up Scriber Dictate"

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
            let suiteName = "com.gafiegarcia.scriber-dictate.ui-testing"
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
        if isUITesting { preferences.onboardingComplete = true }
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
struct ScriberDictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime()

    var body: some Scene {
        Window("Scriber Dictate", id: "main") {
            MainWindowView()
                .environmentObject(runtime)
                .modelContainer(runtime.container)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            MainWindowCommands()
            CommandGroup(replacing: .appTermination) {
                Button("Quit Scriber Dictate") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Close All Windows") { closeAllNormalWindows() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }

        Window("Set Up Scriber Dictate", id: "onboarding") {
            OnboardingView()
                .environmentObject(runtime)
                .modelContainer(runtime.container)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Scriber Dictate") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra("Scriber Dictate", systemImage: menuBarSymbol) {
            MenuBarContent().environmentObject(runtime)
        }
    }

    private var menuBarSymbol: String {
        switch runtime.coordinator.phase {
        case .recording: "waveform.circle.fill"
        case .transcribing: "ellipsis.circle"
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
    @FocusedValue(\.searchHistoryAction) private var searchHistory

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Search History") { searchHistory?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(searchHistory == nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

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
        observers.append(center.addObserver(forName: .openScriberDictateMainWindow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showMainWindow() }
        })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !hasVisibleManagedWindow { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showMainWindow() {
        guard let window = NSApp.windows.first(where: {
            AppWindowIdentity.isManagedWindow($0) && $0.title == AppWindowIdentity.mainTitle
        }) else { return }
        NSApp.setActivationPolicy(.regular)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
