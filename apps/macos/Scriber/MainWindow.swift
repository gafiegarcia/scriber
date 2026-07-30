import AppKit
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @State private var workspace: Workspace = .dictation
    @State private var searchQuery = ""
    @State private var showingRecovery = false
    @FocusState private var searchFocused: Bool

    private var recoveryConditions: [RecoveryCondition] {
        RecoveryConditions.current(
            onboardingComplete: runtime.preferences.onboardingComplete,
            permission: runtime.coordinator.permissionReadiness,
            credential: runtime.coordinator.credentialReadiness
        )
    }

    /// A record is inserted before its transcription starts, so that an interrupted
    /// job keeps its audio and can be recovered at the next launch. Until the
    /// outcome is known there is nothing truthful to show for it — the row would
    /// read "Transcription failed." purely because no text or error exists yet — so
    /// in-flight dictations stay out of the list. A record the user explicitly
    /// retried is exempt: it was already on screen and keeps its "Retrying" label.
    ///
    /// The window owns this rather than the page because the toolbar count and the
    /// list have to agree, and two copies of the filter is how they stop agreeing.
    private var visibleRecords: [DictationRecord] {
        records.filter {
            $0.transcriptionState != .transcribing
                || runtime.coordinator.retryingRecordID == $0.id
        }
    }

    var body: some View {
        workspaceContent
            .frame(minWidth: 640, minHeight: 480)
            .searchable(
                text: $searchQuery,
                placement: .toolbar,
                prompt: workspace.searchPrompt
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 10) {
                        // A label today, a Picker once Transcription exists. The
                        // slot and its glass stay put across that change.
                        Text(workspace.title)
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                        Text(dictationCountLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("dictation-count")
                    }
                    // The toolbar compresses this group to a truncating width
                    // otherwise, which turns the workspace name into "Dictati…".
                    .fixedSize()
                }
                // Constant: varying it by state asks SwiftUI to reconcile window
                // chrome, which is what this window has already crashed on.
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .primaryAction) {
                    if !recoveryConditions.isEmpty {
                        Button {
                            showingRecovery = true
                        } label: {
                            Label {
                                Text(recoveryConditions[0].title)
                            } icon: {
                                // Tinting the button does not reach the glyph.
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .help("Scriber needs attention")
                        .accessibilityIdentifier("recovery-conditions")
                        .popover(isPresented: $showingRecovery, arrowEdge: .bottom) {
                            RecoveryConditionsPopover(conditions: recoveryConditions) { condition in
                                showingRecovery = false
                                runtime.coordinator.openSettingsWindow(
                                    destination: condition.kind.settingsDestination
                                )
                            }
                        }
                    }
                }

                // SwiftUI pins its search item to the trailing edge behind a
                // flexible space, and nothing declared here can land to the
                // right of it — so the window's controls group after the
                // traffic lights instead of beside the search field.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        runtime.coordinator.openSettingsWindow(destination: .settings)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings")
                    .accessibilityIdentifier("open-settings")
                }
            }
            .searchFocused($searchFocused)
            .focusedSceneValue(\.searchDictationHistoryAction, { searchFocused = true })
            .onAppear {
                runtime.coordinator.registerSettingsWindowOpener { openWindow(id: "settings") }
                openOnboardingIfNeeded()
            }
            .onChange(of: runtime.preferences.onboardingComplete) { _, _ in openOnboardingIfNeeded() }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspace {
        case .dictation:
            DictationHistoryView(records: visibleRecords, searchQuery: searchQuery)
        }
    }

    /// Counts what the workspace holds, not what the current search matches: the
    /// number is a property of the history, not of the query.
    private var dictationCountLabel: String {
        let count = visibleRecords.count
        return "\(count) \(count == 1 ? "dictation" : "dictations")"
    }

    private func openOnboardingIfNeeded() {
        guard !runtime.preferences.onboardingComplete else { return }
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "onboarding")
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension RecoveryConditionKind {
    var settingsDestination: MainWindowDestination {
        switch self {
        case .permissions: .permissions
        case .apiKey: .apiKey
        case .usage: .usage
        }
    }
}

/// Every unresolved condition at once, each with its own way out. The window
/// showing all of them is what lets the floating pill show one at a time.
private struct RecoveryConditionsPopover: View {
    let conditions: [RecoveryCondition]
    let onAction: (RecoveryCondition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(conditions) { condition in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(condition.title)
                            .font(.headline)
                            .accessibilityIdentifier(condition.accessibilityIdentifier)
                        Text(condition.message)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(condition.actionTitle) { onAction(condition) }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                }
                if condition.id != conditions.last?.id { Divider() }
            }
        }
        .padding(16)
        .frame(width: 320)
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

