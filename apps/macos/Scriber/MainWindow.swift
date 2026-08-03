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
    @StateObject private var toasts = ToastPresenter()
    @FocusState private var searchFocused: Bool

    /// Whether the next time this window becomes key counts as *opening* it.
    ///
    /// True at launch, and true again from the moment the window closes. Every
    /// route that puts the window back on screen — Open Scriber in the menu bar, a
    /// Dock click, the startup poll in `AppDelegate` — ends in AppKit making this
    /// window key, and that is both the one signal all of them share and the first
    /// moment at which asking for focus can succeed. `onAppear` is neither: it runs
    /// before the window is key, and three of those routes order a retained window
    /// front without SwiftUI presenting anything.
    ///
    /// Becoming key also happens every time the user merely switches back to a
    /// window that stayed open, and moving focus then would drop a transcript
    /// selection they were part-way through making. So this is consumed once per
    /// presentation and only a close re-arms it: an app switch, an unhide, and a
    /// de-miniaturize all leave focus where the user left it.
    @State private var opensWithSearchFocused = true

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
            .environmentObject(toasts)
            .overlay(alignment: .bottomTrailing) { ToastStackView().environmentObject(toasts) }
            .onDisappear { toasts.cancelAll() }
            // No `placement: .toolbar`: the toolbar's own `DefaultToolbarItem`
            // places the field, and asking for it here as well contributes a
            // second one with a second flexible space behind it.
            .searchable(
                text: $searchQuery,
                prompt: workspace.searchPrompt
            )
            .toolbar {
                // One item, because everything in it describes the workspace:
                // which one, how much it holds, and whether it can run. Status
                // belongs together, and the group grows rightward when the
                // warning appears rather than reflowing the toolbar.
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 10) {
                        // Plain text, because it is not a control. A background here
                        // said "click me" about the one thing in this group that
                        // does nothing; it earns one back when Transcription lands
                        // and this becomes a Picker.
                        Text(workspace.title)
                            .font(.headline)

                        Text(dictationCountLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("dictation-count")

                        if !recoveryConditions.isEmpty { recoveryControl }
                    }
                    // The toolbar compresses this group to a truncating width
                    // otherwise, which turns the workspace name into "Dictati…".
                    .fixedSize()
                }
                // Constant: varying it by state asks SwiftUI to reconcile window
                // chrome, which is what this window has already crashed on.
                .sharedBackgroundVisibility(.hidden)

                // Declared rather than left implicit, because `.searchable`
                // otherwise contributes a *second* search item and a second
                // flexible space, and the button ends up balanced between the
                // two springs in the middle of the titlebar.
                //
                // Known and unfixed: this button cannot sit beside the search
                // field. `.searchable` anchors the field to the trailing edge
                // behind a flexible space of its own, and nothing declared here
                // gets past it — `.primaryAction` and `.confirmationAction`
                // measure identically, and declaration order does not move it.
                // Reaching the mockup's position means hand-building the field
                // in AppKit, which is the machinery this window already crashed
                // on. The button groups with the workspace instead.
                DefaultToolbarItem(kind: .search, placement: .primaryAction)

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        runtime.coordinator.openSettingsWindow(destination: .settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Scriber Settings")
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("open-settings")
                }
            }
            .searchFocused($searchFocused)
            .focusedSceneValue(\.searchDictationHistoryAction, { searchFocused = true })
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                guard let window = note.object as? NSWindow,
                      AppWindowIdentity.isMainWindow(window) else { return }
                focusSearchForPresentation()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard let window = note.object as? NSWindow,
                      AppWindowIdentity.isMainWindow(window) else { return }
                opensWithSearchFocused = true
            }
            .onAppear {
                runtime.coordinator.registerSettingsWindowOpener { openWindow(id: "settings") }
                openOnboardingIfNeeded()
                // If SwiftUI rebuilt this content after the window was already key,
                // no further `didBecomeKey` is coming and the presentation would go
                // unserved. Reading the key window tells the two orderings apart
                // without guessing at a delay between them.
                if let window = NSApp.keyWindow, AppWindowIdentity.isMainWindow(window) {
                    focusSearchForPresentation()
                }
            }
            .onChange(of: runtime.preferences.onboardingComplete) { _, _ in openOnboardingIfNeeded() }
    }

    /// Present only while something is wrong, and carrying every condition at
    /// once rather than the worst one.
    private var recoveryControl: some View {
        Button {
            showingRecovery = true
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Scriber needs attention")
        .accessibilityLabel("Scriber needs attention")
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

    /// Consumes a pending presentation by focusing the toolbar's search field.
    ///
    /// Deferred by one main-actor turn rather than written directly.
    /// `didBecomeKeyNotification` is posted from inside AppKit's key-window
    /// transition, and a `@FocusState` write SwiftUI cannot satisfy yet is dropped
    /// silently rather than queued. A turn is enough, and unlike a sleep it is not
    /// a guess at how long the transition takes.
    ///
    /// Known and accepted: a route that orders the window front without winning
    /// activation leaves this armed, so search takes focus on the click that
    /// eventually makes the window key — even a click that landed on a row. Do not
    /// add a mouse-event filter for it.
    @MainActor
    private func focusSearchForPresentation() {
        guard opensWithSearchFocused else { return }
        opensWithSearchFocused = false
        Task { @MainActor in searchFocused = true }
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

