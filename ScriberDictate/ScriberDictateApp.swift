import AppKit
import Combine
import SwiftData
import SwiftUI

@MainActor
final class AppRuntime: ObservableObject {
    let container: ModelContainer
    var preferences: Preferences
    let coordinator: AppCoordinator
    private var cancellables = Set<AnyCancellable>()

    init() {
        do {
            container = try ModelContainer(for: DictationRecord.self)
        } catch {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: DictationRecord.self, configurations: configuration)
        }
        let inputDevices = AudioRecorder.availableInputDevices()
        preferences = Preferences(defaultAudioInputSelection: .initialSelection(from: inputDevices))
        coordinator = AppCoordinator(preferences: preferences, modelContext: container.mainContext)
        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        coordinator.startServices()
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
            CommandGroup(replacing: .appTermination) {
                Button("Quit Scriber Dictate") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Close All Windows") { closeAllNormalWindows() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
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
        case .pasteFailed, .transcriptionFailed: "exclamationmark.circle"
        default: "waveform.circle"
        }
    }

    private func closeAllNormalWindows() {
        NSApp.windows.filter { !($0 is NSPanel) }.forEach { $0.performClose(nil) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let center = NotificationCenter.default
        NSApp.windows.filter { !($0 is NSPanel) }.forEach { $0.isReleasedWhenClosed = false }
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, !(window is NSPanel) else { return }
            Task { @MainActor in
                window.isReleasedWhenClosed = false
                NSApp.setActivationPolicy(.regular)
            }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, !(window is NSPanel) else { return }
            Task { @MainActor in
                let visibleNormalWindow = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
                if !visibleNormalWindow { NSApp.setActivationPolicy(.accessory) }
            }
        })
        observers.append(center.addObserver(forName: .openScriberDictateMainWindow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showMainWindow() }
        })
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showMainWindow() {
        guard let window = NSApp.windows.first(where: { !($0 is NSPanel) }) else { return }
        NSApp.setActivationPolicy(.regular)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
