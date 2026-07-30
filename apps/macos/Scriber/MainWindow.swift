import AppKit
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime
    @State private var section: MainSection? = .dictation
    @State private var searchQuery = ""
    @FocusState private var sidebarFocused: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $section) {
                Label("Dictation", systemImage: "clock.arrow.circlepath")
                    .tag(MainSection.dictation)
                    .accessibilityIdentifier("sidebar-dictation")
            }
            .accessibilityIdentifier("main-sidebar")
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
            .focused($sidebarFocused)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selectedSection {
                case .dictation:
                    DictationHistoryView(searchQuery: searchQuery)
                }
            }
            .navigationTitle(selectedSection.title)
        }
        .frame(minWidth: 760, minHeight: 520)
        .toolbar(removing: .sidebarToggle)
        // Every destination in this window is searchable, so the search field
        // belongs to the window shell. That is what keeps one toolbar, one title
        // presentation, and one set of toolbar observers across selection.
        .searchable(
            text: $searchQuery,
            placement: .toolbar,
            prompt: selectedSection.searchPrompt
        )
        .searchFocused($searchFocused)
        .focusedSceneValue(\.searchDictationHistoryAction, { searchFocused = true })
        .onAppear {
            runtime.coordinator.registerSettingsWindowOpener { openWindow(id: "settings") }
            openOnboardingIfNeeded()
            focusSidebarIfAppropriate()
        }
        .onChange(of: runtime.preferences.onboardingComplete) { _, _ in openOnboardingIfNeeded() }
    }

    private func focusSidebarIfAppropriate() {
        switch runtime.coordinator.mainWindowRequest?.destination {
        case .apiKey, .usage, .microphone, .permissions, .settings:
            return
        case .dictation, nil:
            DispatchQueue.main.async { sidebarFocused = true }
        }
    }

    private var selectedSection: MainSection { section ?? .dictation }

    private func openOnboardingIfNeeded() {
        guard !runtime.preferences.onboardingComplete else { return }
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "onboarding")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        Group {
            Button("Open Scriber") { openMain(destination: .dictation) }
            Button("Settings") { openMain(destination: .settings) }
            if runtime.preferences.onboardingComplete {
                if !runtime.coordinator.permissionReadiness.isReady {
                    Divider()
                    Button { openMain(destination: .permissions) } label: {
                        Label("Permissions Required…", systemImage: "exclamationmark.triangle.fill")
                    }
                }
                let credentials = runtime.coordinator.credentialReadiness
                if !credentials.isReady {
                    Divider()
                    Button {
                        openMain(destination: credentials.resolvesInUsageSettings ? .usage : .apiKey)
                    } label: {
                        Label("\(credentials.title)…", systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }
            Divider()
            shortcutHint(
                "Hold to Dictate: \(runtime.preferences.holdShortcut.displayName)",
                isEnabled: runtime.preferences.holdShortcutEnabled
            )
            shortcutHint(
                "Hands-free Toggle: \(runtime.preferences.toggleShortcut.displayName)",
                isEnabled: runtime.preferences.toggleShortcutEnabled
            )
            Divider()
            Button("Quit Scriber") { NSApp.terminate(nil) }
        }
        .onAppear {
            runtime.coordinator.startServices()
            if !runtime.preferences.onboardingComplete { openOnboarding() }
        }
    }

    private func shortcutHint(_ title: String, isEnabled: Bool) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .strikethrough(!isEnabled)
    }

    private func openOnboarding() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "onboarding")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openMain(destination: MainWindowDestination) {
        runtime.coordinator.selectMainWindowDestination(destination)
        NSApp.setActivationPolicy(.regular)
        switch destination {
        case .dictation:
            openWindow(id: "main")
        case .settings, .apiKey, .usage, .microphone, .permissions:
            openWindow(id: "settings")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

}

