import AppKit
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

enum MainPageLayout {
    static let maxContentWidth: CGFloat = 640
}

struct SearchDictationHistoryActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var searchDictationHistoryAction: (() -> Void)? {
        get { self[SearchDictationHistoryActionKey.self] }
        set { self[SearchDictationHistoryActionKey.self] = newValue }
    }
}

enum KeySaveFeedback {
    case saved
    case failed(String)

    var message: String {
        switch self {
        case .saved: "API key verified with ElevenLabs and saved in your Mac login Keychain."
        case .failed(let message): message
        }
    }

    var systemImage: String {
        switch self {
        case .saved: "checkmark.shield.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .saved: .green
        case .failed: .red
        }
    }
}


enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case general
    case dictation
    case sound
    case elevenLabs
    case permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .dictation: "Dictation"
        case .sound: "Sound"
        case .elevenLabs: "ElevenLabs"
        case .permissions: "Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .dictation: "text.bubble"
        case .sound: "speaker.wave.2"
        case .elevenLabs: "key"
        case .permissions: "hand.raised"
        }
    }

    var accessibilityIdentifier: String { "settings-tab-\(rawValue.lowercased())" }
}

extension MainWindowDestination {
    /// The tab that owns this destination, or `nil` for one that names no tab.
    ///
    /// Nil is not a gap: a route that exists to fix something has to land on the
    /// tab that owns it, and an ordinary opening must leave the user on whatever
    /// tab they last chose.
    var settingsTab: SettingsTab? {
        switch self {
        case .dictation, .settings: nil
        case .apiKey, .usage: .elevenLabs
        case .microphone: .sound
        case .permissions: .permissions
        }
    }
}

private enum SettingsPaneLayout {
    /// Hangs a section header 2pt off the leading edge of its card, matching the
    /// main window's day label and a Finder sidebar heading.
    ///
    /// A grouped form draws the header 10pt inside the card, which reads as the
    /// header being indented under the thing it names. What should look indented
    /// is the content.
    ///
    /// Known and unfixed: that 10pt is AppKit's, not ours, and no API reads it,
    /// so this is one measured number short of derivable — as is
    /// `rowHorizontalPadding`, which is added on top of the same 10. A macOS
    /// update that moves it moves both, and these two constants are where to
    /// answer that.
    static let sectionHeaderOutdent: CGFloat = -12

    /// Added to each side of every row in a section card, on top of the 10pt a
    /// grouped form already draws there, putting a row's content 12pt in.
    ///
    /// Horizontal only. A row's height is the form's to decide, and it already
    /// gives a row enough; what was short was the distance to the card's sides.
    ///
    /// The rule between two rows keeps the form's own 10pt and so runs a little
    /// wider than the content it separates. It cannot be made to follow:
    /// `listRowInsets` moves nothing at all on a macOS grouped form, and the
    /// rule is the form's to draw. The day cards read the same way on purpose,
    /// with their rules at the card's full width.
    ///
    /// Applied to a section's whole content, which SwiftUI distributes to each
    /// row — the rows are what this has to land on, not the card.
    static let rowHorizontalPadding: CGFloat = 2

    /// Between a setting and the sentence explaining it, added on top of the gap
    /// AppKit's two-`Text` toggle label draws — which is tight enough that the
    /// caption reads as a wrapped second line of the title.
    static let captionGap: CGFloat = 4

    /// Between a setting and the setting nested under it. Wider than the gap
    /// inside either of them, so the indent is not the only thing saying one
    /// governs the other.
    static let nestedSettingGap: CGFloat = 14
}

/// A `Section` whose header sits outside its card, and which has no header at all
/// when it is not given one — an empty header view still takes vertical space.
///
/// `footer` is for a note about the whole group, which belongs below the card
/// rather than inside it. A note about one control goes in that control's row
/// instead; see `SettingsToggle`.
private struct SettingsSection<Content: View>: View {
    let title: String?
    /// A key rather than a `String` so a footer can carry a Markdown link;
    /// `Text` only parses Markdown from literals.
    let footer: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        if let title, let footer {
            Section {
                paddedContent
            } header: {
                Text(title).padding(.leading, SettingsPaneLayout.sectionHeaderOutdent)
            } footer: {
                Text(footer).padding(.leading, SettingsPaneLayout.sectionHeaderOutdent)
            }
        } else if let title {
            Section {
                paddedContent
            } header: {
                Text(title).padding(.leading, SettingsPaneLayout.sectionHeaderOutdent)
            }
        } else {
            Section { paddedContent }
        }
    }

    /// Every section card's rows go through here, which is the whole reason a
    /// plain `Section` is not used directly anywhere in Settings.
    private var paddedContent: some View {
        content.padding(.horizontal, SettingsPaneLayout.rowHorizontalPadding)
    }
}

/// Wraps whatever renders the mute-other-audio setting, handing it a binding
/// that asks before it turns on and carrying the dialog that does the asking.
///
/// One view rather than a binding helper plus a separate modifier: the two have
/// to be applied together, and a call site that used only the binding would get
/// a toggle that silently never turns on. The setting appears in both Settings
/// and onboarding, and both go through here.
struct MuteOtherAudioToggle<Content: View>: View {
    @Binding var isOn: Bool
    /// Raises the macOS prompt the moment the user opts in. Left to the first
    /// dictation it arrives with the shortcut still held down, which is the
    /// worst moment to owe an answer.
    let requestAccess: () -> Void
    @ViewBuilder let content: (Binding<Bool>) -> Content

    var body: some View {
        content(asking)
    }

    /// No dialog stands in front of this. Scriber's explanation travels inside
    /// macOS's own prompt, as `NSAudioCaptureUsageDescription` — which puts it
    /// on the question it answers, and spends one fewer click getting there.
    private var asking: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { turningOn in
                let wasOff = !isOn
                isOn = turningOn
                if turningOn, wasOff { requestAccess() }
            }
        )
    }
}

/// A toggle and the sentence explaining it, in one row.
///
/// A grouped form draws a divider between rows, so a caption written as its own
/// row is separated from the setting it explains exactly as much as the next
/// setting is — which is what made a group of two settings read as four. The
/// two-`Text` label is AppKit's own answer: the caption renders under the title,
/// inside the same row, with no divider available to fall between them.
private struct SettingsToggle: View {
    let title: String
    let caption: String?
    @Binding var isOn: Bool

    init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        self._isOn = isOn
    }

    var body: some View {
        if let caption {
            Toggle(isOn: $isOn) {
                Text(title)
                // Inside AppKit's label rather than replacing it with a stack of
                // our own. AppKit sets the caption's font and colour and would
                // have to be guessed at to reproduce; all this adds is the gap,
                // which it draws far too tight to read as an explanation of the
                // line above rather than a second line of it.
                Text(caption).padding(.top, SettingsPaneLayout.captionGap)
            }
        } else {
            Toggle(title, isOn: $isOn)
        }
    }
}

/// The shape every tab's content takes: one grouped form, capped so a wide
/// window leaves margins rather than stretching every control across it.
private struct SettingsPane<Content: View>: View {
    let accessibilityIdentifier: String
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .accessibilityIdentifier(accessibilityIdentifier)
            .padding()
            .frame(maxWidth: MainPageLayout.maxContentWidth, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var runtime: AppRuntime
    let onShortcutConfigurationCaptureChanged: (Bool) -> Void
    @State private var selectedTab: SettingsTab = .general
    /// Held by the window rather than by the General tab. A recorder still
    /// running when its tab goes away leaves a local key monitor installed that
    /// swallows every event, so only something outliving the tab can revoke it.
    @State private var activeShortcutRecorderID: String?
    /// Cleared whenever the window appears, which is a fact about the window and
    /// not about the tab that happens to draw the field.
    @State private var apiKey = ""
    /// Set by a route into the key field, consumed by the pane once it exists.
    /// The pane is not mounted in the turn that selects its tab, and a
    /// `@FocusState` write SwiftUI cannot satisfy yet is dropped, not queued.
    @State private var pendingKeyFieldFocus = false
    @State private var refusalResetToken = 0

    init(onShortcutConfigurationCaptureChanged: @escaping (Bool) -> Void = { _ in }) {
        self.onShortcutConfigurationCaptureChanged = onShortcutConfigurationCaptureChanged
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: SettingsTab.general) {
                GeneralSettingsPane(
                    activeShortcutRecorderID: $activeShortcutRecorderID,
                    refusalResetToken: refusalResetToken
                )
            } label: {
                tabLabel(.general)
            }
            Tab(value: SettingsTab.dictation) {
                DictationSettingsPane()
            } label: {
                tabLabel(.dictation)
            }
            Tab(value: SettingsTab.sound) {
                SoundSettingsPane()
            } label: {
                tabLabel(.sound)
            }
            Tab(value: SettingsTab.elevenLabs) {
                ElevenLabsSettingsPane(
                    apiKey: $apiKey,
                    pendingKeyFieldFocus: $pendingKeyFieldFocus
                )
            } label: {
                tabLabel(.elevenLabs)
            }
            Tab(value: SettingsTab.permissions) {
                PermissionsSettingsPane()
            } label: {
                tabLabel(.permissions)
            }
        }
        .accessibilityIdentifier("settings-view")
        // The floor, not a preferred size. Every tab has to show all of itself
        // without scrolling, and the tallest of them is what sets this — so it
        // is raised when a tab grows, rather than letting that tab scroll.
        .frame(minWidth: 660, minHeight: 560)
        // Every one of these is on the window and not on a pane: a tab that is
        // not selected may not be mounted, and each of them has to run for state
        // the window owns.
        .onChange(of: activeShortcutRecorderID) { _, activeRecorderID in
            onShortcutConfigurationCaptureChanged(activeRecorderID != nil)
        }
        .onChange(of: runtime.coordinator.phase.isBusy) { _, isBusy in
            if isBusy { activeShortcutRecorderID = nil }
        }
        .onChange(of: selectedTab) { _, tab in
            // Leaving General mid-recording would strand the recorder's local
            // monitor, which returns nil for every key event: nothing in Scriber
            // could be typed into, and global shortcut matching would stay
            // suspended, until the window was closed. Clearing the ID is what
            // `ShortcutRecorderView` watches to tear the monitor down.
            if tab != .general { activeShortcutRecorderID = nil }
            // The level meter opens the microphone, so leaving its tab closes it.
            // Nothing else would: the pane keeps its state while the window lives.
            if tab != .sound { runtime.coordinator.stopMicrophoneTest() }
            // The same call refreshes the audio device list, so a microphone
            // plugged in since the window opened is there on arrival.
            if tab == .sound || tab == .permissions {
                runtime.coordinator.refreshPermissions(source: .settings)
            }
        }
        .onAppear {
            apiKey = ""
            runtime.coordinator.refreshPermissions(source: .settings)
            applyMainWindowRequest(runtime.coordinator.mainWindowRequest)
        }
        .onChange(of: runtime.coordinator.mainWindowRequest) { _, request in
            applyMainWindowRequest(request)
        }
        .onDisappear {
            activeShortcutRecorderID = nil
            runtime.coordinator.stopMicrophoneTest()
            onShortcutConfigurationCaptureChanged(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let window = note.object as? NSWindow,
                  AppWindowIdentity.isSettingsWindow(window) else { return }
            activeShortcutRecorderID = nil
            runtime.coordinator.stopMicrophoneTest()
            onShortcutConfigurationCaptureChanged(false)
            refusalResetToken += 1
        }
    }

    private func tabLabel(_ tab: SettingsTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
            .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    private func applyMainWindowRequest(_ request: MainWindowRequest?) {
        guard let request else { return }
        if let tab = request.destination.settingsTab { selectedTab = tab }
        if request.destination == .apiKey { pendingKeyFieldFocus = true }
        // Deferred one turn. Clearing the request writes an `@Published` this
        // view is observing, from inside that view's own update, which is the
        // shape AttributeGraph aborts the process for.
        Task { @MainActor in runtime.coordinator.consumeMainWindowRequest() }
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow
    @Binding var activeShortcutRecorderID: String?
    let refusalResetToken: Int
    @State private var confirmRestartSetup = false
    @State private var launchAtLoginError: String?
    /// Set only by a request that macOS refused. Switching Scriber off under
    /// Background App Activity is a decision the user is allowed to make, so
    /// the state alone must stay silent — the explanation belongs to the moment
    /// they ask for the opposite and nothing happens.
    @State private var launchAtLoginRefused = false

    var body: some View {
        SettingsPane(accessibilityIdentifier: "settings-general-pane") {
            SettingsSection(
                "Shortcut",
                footer: "Tap to dictate and tap again to stop. Hold and release for quick dictation. Cancel recording with Escape."
            ) {
                ShortcutPicker(
                    chord: $runtime.preferences.dictationShortcut,
                    customChord: $runtime.preferences.customShortcut,
                    activeRecorderID: $activeShortcutRecorderID,
                    isCaptureAllowed: !runtime.coordinator.phase.isBusy,
                    refusalResetToken: refusalResetToken
                )
            }
            SettingsSection("Startup and Presence") {
                // Both toggles share one row, because a divider between a setting
                // and the setting that depends on it reads as two unrelated
                // settings — the same divider the group boundary uses. The indent
                // is what names the owner; the greying only confirms it.
                VStack(alignment: .leading, spacing: SettingsPaneLayout.nestedSettingGap) {
                    // Reads what macOS has registered, not what Scriber last
                    // asked for, so removing Scriber from Login Items in System
                    // Settings turns this off within a poll.
                    Toggle("Launch at login", isOn: Binding(
                        get: { runtime.coordinator.launchAtLoginState.isOn },
                        set: { enabled in
                            do {
                                try runtime.coordinator.setLaunchAtLogin(enabled)
                                launchAtLoginError = nil
                            } catch {
                                launchAtLoginError = error.localizedDescription
                            }
                            launchAtLoginRefused = enabled && !runtime.coordinator.launchAtLoginState.isOn
                        }
                    ))
                    .accessibilityIdentifier("launch-at-login-toggle")
                    if let launchAtLoginError {
                        Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                    }
                    // The toggle snapping back is the only other signal here, and
                    // on its own it reads as a bug rather than as something the
                    // user has to go and switch on.
                    if launchAtLoginRefused, let advice = runtime.coordinator.launchAtLoginState.recoveryAdvice {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(advice).font(.caption).foregroundStyle(.secondary)
                            Button("Open Login Items…") { runtime.coordinator.openLoginItemsSettings() }
                                .controlSize(.small)
                        }
                        .accessibilityIdentifier("launch-at-login-advice")
                    }
                    SettingsToggle(
                        "Start in the background",
                        caption: "Only applies when macOS starts Scriber at login. Opening Scriber yourself always shows the window.",
                        isOn: $runtime.preferences.startInBackground
                    )
                    .accessibilityIdentifier("start-in-background-toggle")
                    // Disabled together, so the caption dims with the control it
                    // explains rather than staying live beside a dead toggle.
                    // `.disabled` alone only lowers the alpha a little and keeps
                    // the accent colour, so a switch left on still reads as
                    // live; draining the tint is what makes it read as governed
                    // by the setting above.
                    .tint(
                        runtime.coordinator.launchAtLoginState.isOn
                            ? Color.accentColor
                            : Color(nsColor: .tertiaryLabelColor)
                    )
                    .disabled(!runtime.coordinator.launchAtLoginState.isOn)
                    .padding(.leading, 18)
                }
                // The refusal is answered the moment macOS reports the switch
                // back on, which the refresh notices without the window being
                // touched — so the message goes on its own rather than waiting
                // to be dismissed by another attempt.
                .onChange(of: runtime.coordinator.launchAtLoginState) { _, state in
                    if state.isOn { launchAtLoginRefused = false }
                }
                Toggle("Show in menu bar", isOn: $runtime.preferences.showInMenuBar)
                Toggle("Show in Dock", isOn: $runtime.preferences.showAppInDock)
                    .accessibilityIdentifier("show-app-in-dock-toggle")
            }
            SettingsSection("Updates") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button(action: { runtime.coordinator.checkForUpdates(force: true) }) {
                            if runtime.coordinator.isCheckingForUpdates {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Text("Check Now")
                            }
                        }
                        .disabled(runtime.coordinator.isCheckingForUpdates)
                        .accessibilityIdentifier("check-for-updates")
                        if let update = runtime.preferences.availableUpdate {
                            Link("Get \(update.version)…", destination: update.url)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("download-update")
                        }
                        Spacer(minLength: 0)
                    }
                    updateStatus
                }
                SettingsToggle(
                    "Check for updates automatically",
                    caption: "Asks GitHub once a day whether a newer version has been released. Scriber never installs anything on its own.",
                    isOn: $runtime.preferences.automaticUpdateChecks
                )
                .accessibilityIdentifier("automatic-update-checks-toggle")
            }
            SettingsSection {
                // Nothing is destroyed by walking setup again — it reads current
                // state, so a step already satisfied is presented as satisfied —
                // but it does replace the window in front of you, so it asks.
                HStack {
                    Button("Redo Setup…") { confirmRestartSetup = true }
                        .accessibilityIdentifier("restart-onboarding")
                    Spacer()
                }
            }
        }
        .confirmationDialog("Go through setup again?", isPresented: $confirmRestartSetup) {
            Button("Redo Setup") {
                // Create the scene first, then let the coordinator order it
                // front — it waits for the window to exist.
                openWindow(id: "onboarding")
                runtime.coordinator.restartOnboarding()
            }
        } message: {
            Text("Your key, permissions, and history are kept. Setup shows each step's current state.")
        }
    }

    private var updateStatus: some View {
        Text(updateStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("update-status")
    }

    /// Never claims to be current on the strength of a check that has not
    /// happened: an install that has never reached GitHub says so.
    private var updateStatusText: String {
        let running = AppCoordinator.runningVersion
        if let error = runtime.coordinator.updateCheckError {
            return error
        }
        if let update = runtime.preferences.availableUpdate {
            return "Scriber \(update.version) is available. You have \(running)."
        }
        if runtime.preferences.lastUpdateCheck == nil {
            return "You have Scriber \(running). No check has run yet."
        }
        return "Scriber \(running) is the latest version."
    }
}

private struct DictationSettingsPane: View {
    @EnvironmentObject private var runtime: AppRuntime
    /// Only so Clear Dictation History knows whether there is anything to clear,
    /// and how much. Sorted to match the Dictation page rather than for display.
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @State private var newKeyterm = ""
    @State private var keytermError: String?
    @State private var confirmClearHistory = false
    @State private var showsKeytermHelp = false

    /// A dictation still being transcribed is not shown in history and must not
    /// be swept up by a clear — its audio is still in use. Matches the filter the
    /// Dictation page applies to what it displays.
    private var clearableRecords: [DictationRecord] {
        records.filter { $0.transcriptionState != .transcribing }
    }

    var body: some View {
        SettingsPane(accessibilityIdentifier: "settings-dictation-pane") {
            SettingsSection("Transcription") {
                Picker("Language", selection: $runtime.preferences.languageCode) {
                    Text("Automatic").tag("auto")
                    Text("English").tag("en")
                    Text("Indonesian").tag("id")
                }
                Toggle("Remove filler words and false starts", isOn: $runtime.preferences.noVerbatim)
                // Field, captions, and the added-terms list share one Form row
                // so the grouped form draws no divider between them. A divider
                // per keyterm would read as more settings rows rather than as
                // the contents of this one setting; the card below is what marks
                // the list as belonging to Keyterms.
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent {
                        HStack {
                            // Prompt rather than a title: inside `LabeledContent`
                            // a titled field draws its own label too, so the row
                            // read "Keyterms  Name or term  <field>".
                            TextField(text: $newKeyterm, prompt: Text("Name or term")) {
                                Text("Keyterm")
                            }
                            .labelsHidden()
                            // Bordered, unlike the rows above it: those show a
                            // value you pick, this one is empty until typed
                            // into and has nothing else to announce itself as
                            // a field.
                            .textFieldStyle(.roundedBorder)
                            // Left, not the field's default: with no alignment
                            // set, an empty focused field with a prompt longer
                            // than the box scrolled to keep the caret — which
                            // sits after the prompt's last character — in
                            // view, showing the prompt's tail pinned to the
                            // right edge instead of its start.
                            .multilineTextAlignment(.leading)
                            // Fixed, and sized for the word or short phrase a
                            // keyterm actually is: a fixed width keeps the field
                            // from reflowing as the window widens or changing
                            // size as you type. Not `.fixedSize` paired with a
                            // `.frame(minWidth:maxWidth:)` — that lets the true
                            // rendered width ignore both bounds, shrinking below
                            // the minimum on the first keystroke and overflowing
                            // the maximum on a long entry. Wider than the prompt
                            // text alone, so the caret-scrolling quirk noted
                            // above does not pin the prompt's tail right again.
                            .frame(width: 200)
                            .onSubmit(submitKeyterm)
                            .accessibilityIdentifier("keyterm-field")
                            Button("Add", action: submitKeyterm)
                                .disabled(!canAddKeyterm)
                        }
                    } label: {
                        // A popover behind a click, not a permanent caption
                        // line: the explanation is one click away when wanted
                        // instead of spending a row on every launch. Click
                        // rather than `.help()` — a hover tooltip waits out
                        // AppKit's fixed delay before it appears, which reads as
                        // unresponsive for something this small.
                        HStack(spacing: 4) {
                            Text("Keyterms")
                            Button {
                                showsKeytermHelp = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            // A glyph alone announces as its symbol name.
                            .accessibilityLabel("About keyterms")
                            .popover(isPresented: $showsKeytermHelp) {
                                // Without `.fixedSize`, the popover sizes
                                // itself to `Text`'s single-line ideal height
                                // even though `maxWidth` wraps it, so the
                                // second line rendered outside the bubble
                                // instead of growing it.
                                Text("Names, brands, and jargon you want spelled correctly.")
                                    .font(.callout)
                                    .padding()
                                    .frame(maxWidth: 220)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let keytermError {
                        Text(keytermError).font(.caption).foregroundStyle(.red)
                    }
                    if !runtime.preferences.keyterms.isEmpty {
                        KeytermsCard(terms: runtime.preferences.keyterms, onRemove: removeKeyterm)
                    }
                    Text("ElevenLabs applies an additional usage charge when keyterms are sent.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            SettingsSection("History") {
                SettingsToggle(
                    "Delete unused recordings after 30 days",
                    caption: "Failed and cancelled dictations keep their audio so you can retry them. Transcripts and history entries are always kept; only the unused recording is removed.",
                    isOn: $runtime.preferences.deletesExpiredRetainedAudio
                )
                .accessibilityIdentifier("delete-expired-audio-toggle")

                HStack {
                    Button("Clear Dictation History…", role: .destructive) {
                        confirmClearHistory = true
                    }
                    .disabled(clearableRecords.isEmpty)
                    .accessibilityIdentifier("clear-dictation-history")
                    Spacer()
                    Text("\(clearableRecords.count) \(clearableRecords.count == 1 ? "entry" : "entries")")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClearHistory) {
            Button("Delete All", role: .destructive) {
                runtime.coordinator.clearDictationHistory(clearableRecords)
            }
        } message: {
            Text("This permanently removes transcripts and any retained failed recordings.")
        }
    }

    private var canAddKeyterm: Bool {
        !newKeyterm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitKeyterm() {
        guard canAddKeyterm else { return }
        addKeyterm()
    }

    private func addKeyterm() {
        do {
            let validated = try ScribeClient.validateKeyterms(runtime.preferences.keyterms + [newKeyterm])
            runtime.preferences.keyterms = validated
            newKeyterm = ""
            keytermError = nil
        } catch { keytermError = error.localizedDescription }
    }

    private func removeKeyterm(_ term: String) {
        runtime.preferences.keyterms.removeAll { $0 == term }
    }
}

/// The added keyterms as their own card, matching `DictationDayCard`'s recipe:
/// one shape, one outline, one rule between neighbouring rows. Not drawn when
/// there are no keyterms — an empty card would just be an empty box.
///
/// Not indented. The card's own border and per-row padding is what marks this
/// as the contents of Keyterms rather than another setting; indenting on top
/// of that read as two hierarchy cues for the same thing.
private struct KeytermsCard: View {
    let terms: [String]
    let onRemove: (String) -> Void

    // One number for the outline's weight and each rule's horizontal inset, kept
    // equal for the reasons `DictationDayCard.borderWidth` spells out: the rules
    // read as the same line as the border, and their ends butt the border's
    // inner edge instead of stacking on it into a darker dot.
    private let borderWidth: CGFloat = 1

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(terms, id: \.self) { term in
                HStack {
                    Text(term)
                    Spacer()
                    Button {
                        onRemove(term)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    // Named for its own row. Unlabelled, every term's button
                    // announces identically, so nothing says which one this
                    // deletes — the sighted cue is the row it sits in.
                    .accessibilityLabel("Remove \(term)")
                }
                // Roomy on purpose. A cramped row makes the delete button hard
                // to tie to its entry — the eye needs vertical room to anchor
                // "this row" before scanning across it. Under the day card's
                // numbers, because this card is nested inside a settings row
                // rather than standing on the page.
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                if term != terms.last {
                    Divider()
                        .padding(.horizontal, borderWidth)
                }
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: borderWidth) }
    }
}

private struct SoundSettingsPane: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        SettingsPane(accessibilityIdentifier: "settings-sound-pane") {
            // Not "Input": the picker inside already carries that label, and a
            // section repeating its only row's name reads as a stutter.
            SettingsSection("Microphone") {
                MicrophonePicker()
                    .accessibilityIdentifier("microphone-input-picker")

                // One row for the whole input test — meter, advice, controls, and
                // whatever went wrong. Split across rows, the grouped form divided
                // them from each other as if each were its own setting.
                //
                // Behind a button rather than always live: arriving on this tab
                // should not open the microphone and light the recording indicator
                // for someone who only came to change a device.
                VStack(alignment: .leading, spacing: 10) {
                    if runtime.coordinator.isMicrophoneTestRunning {
                        AudioLevelMeter(
                            source: runtime.coordinator.microphoneLevel,
                            presentation: .inputTest
                        )
                        .accessibilityIdentifier("microphone-level-meter")

                        // Tied to the meter rather than to how the user arrived. The
                        // meter running is the only moment this advice is useful, and
                        // it means there is no separate state deciding when to drop it.
                        Text("Speak and watch the level. If it stays flat, check your input volume in macOS Sound Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Stop") { runtime.coordinator.stopMicrophoneTest() }
                            Button("Open Sound Settings") { runtime.coordinator.openSystemSoundSettings() }
                        }
                        .font(.caption)
                    } else {
                        Button("Check Input Level") { runtime.coordinator.startMicrophoneTest() }
                            .accessibilityIdentifier("microphone-level-test-button")
                            .disabled(!runtime.coordinator.microphoneGranted)
                    }

                    if let microphoneTestError = runtime.coordinator.microphoneTestError {
                        Label(microphoneTestError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            SettingsSection("While Dictating") {
                SettingsToggle(
                    "Play sounds while dictating",
                    caption: "You hear one sound when recording starts, and another when a dictation fails or is cancelled.",
                    isOn: $runtime.preferences.playRecordingFeedbackSounds
                )
                .accessibilityIdentifier("recording-feedback-sounds-toggle")

                // The warning and the settings link share the row with the
                // toggle they are about, rather than sitting a divider away
                // from the setting that asked for them.
                MuteOtherAudioToggle(
                    isOn: $runtime.preferences.muteOtherAudioWhileRecording,
                    requestAccess: { runtime.coordinator.requestOtherAudioAccess() }
                ) { isOn in
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsToggle(
                            "Mute other audio while recording",
                            caption: "Silences other apps, calls, and notification sounds while you’re dictating. macOS asks for System Audio Recording access — muting works whether you click “Allow” or “Don’t Allow”, because Scriber never reads what other apps play.",
                            isOn: isOn
                        )
                        .accessibilityIdentifier("mute-other-audio-toggle")
                        if let status = runtime.coordinator.otherAudioMuteStatus {
                            Label(status.message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("other-audio-mute-status")
                        }
                        // Reachable whenever muting is on, not only once it has
                        // failed: withdrawing the grant is something people do
                        // to a feature that works, and they arrive with no
                        // failure to route them anywhere.
                        if runtime.preferences.muteOtherAudioWhileRecording
                            || runtime.coordinator.otherAudioMuteStatus != nil {
                            Button("Open Screen & System Audio Recording settings") {
                                runtime.coordinator.openSystemAudioPrivacySettings()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            .accessibilityIdentifier("open-system-audio-privacy")
                        }
                    }
                }
            }
        }
    }
}

private struct ElevenLabsSettingsPane: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var apiKey: String
    @Binding var pendingKeyFieldFocus: Bool
    @State private var keyFeedback: KeySaveFeedback?
    @State private var isCheckingAPIKey = false
    @State private var isRemovingAPIKey = false
    @State private var confirmRemoveKey = false
    @FocusState private var apiKeyFieldFocused: Bool

    var body: some View {
        SettingsPane(accessibilityIdentifier: "settings-elevenlabs-pane") {
            SettingsSection(
                "API Key",
                footer: "Scriber needs a key with Speech to Text access. [Create a free ElevenLabs account](https://elevenlabs.io/app/sign-up), then [add an API key](https://elevenlabs.io/app/developers/api-keys). Enable User → Read on that key as well to show your credits here."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField(
                        text: $apiKey,
                        prompt: Text(
                            runtime.preferences.apiKeyConfigured
                                ? "Enter a new API key to replace the stored key"
                                : "Paste your ElevenLabs API key"
                        )
                    ) {
                        Text("ElevenLabs API key")
                    }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .disabled(isCheckingAPIKey)
                        .focused($apiKeyFieldFocused)
                        .onSubmit(submitAPIKey)
                    HStack {
                        Button(action: submitAPIKey) {
                            if isCheckingAPIKey {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Text("Save API Key")
                            }
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSubmitAPIKey)
                        if let keyFeedback {
                            Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                                .font(.caption)
                                .foregroundStyle(keyFeedback.color)
                                .lineLimit(2)
                                .accessibilityIdentifier("api-key-save-feedback")
                        } else if apiKey.isEmpty {
                            apiKeyStatusLabel
                        }
                        Spacer(minLength: 0)
                        // Confirmed, because the key does not come back and
                        // dictation stops until it is entered again.
                        if runtime.preferences.apiKeyConfigured {
                            Button("Remove API Key…", role: .destructive) {
                                confirmRemoveKey = true
                            }
                            .disabled(isCheckingAPIKey || isRemovingAPIKey)
                            .accessibilityIdentifier("remove-api-key")
                        }
                    }
                }
            }
            // Guarded here rather than inside the block: `subscriptionUsageView`
            // renders nothing while a valid key's usage has yet to arrive, and an
            // empty section still draws its header.
            if showsUsageSection {
                SettingsSection("Credits") {
                    subscriptionUsageView
                }
            }
        }
        .confirmationDialog("Remove the stored API key?", isPresented: $confirmRemoveKey) {
            Button("Remove API Key", role: .destructive) { removeAPIKey() }
        } message: {
            Text("Dictation stops working until you enter a key again. Scriber cannot recover the removed key.")
        }
        .onChange(of: apiKey) { _, newValue in
            if !newValue.isEmpty { keyFeedback = nil }
        }
        // `initial: true` covers the ordinary case, where the flag was already
        // set by the route that selected this tab before the pane existed.
        .onChange(of: pendingKeyFieldFocus, initial: true) { _, pending in
            guard pending else { return }
            apiKeyFieldFocused = true
            pendingKeyFieldFocus = false
        }
    }

    private var showsUsageSection: Bool {
        guard runtime.preferences.apiKeyValidity == .valid else { return false }
        return runtime.preferences.subscriptionUsage != nil
            || runtime.coordinator.subscriptionUsageUnavailable
    }

    private var canSubmitAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCheckingAPIKey
    }

    private func submitAPIKey() {
        guard canSubmitAPIKey else { return }
        Task { await saveKey() }
    }

    private func removeAPIKey() {
        guard !isRemovingAPIKey else { return }
        isRemovingAPIKey = true
        Task {
            defer { isRemovingAPIKey = false }
            do {
                try await runtime.coordinator.removeAPIKey()
                apiKey = ""
                keyFeedback = nil
            } catch {
                keyFeedback = .failed(error.localizedDescription)
            }
        }
    }

    private func saveKey() async {
        guard !isCheckingAPIKey else { return }
        isCheckingAPIKey = true
        defer { isCheckingAPIKey = false }
        do {
            try await runtime.coordinator.validateAndSaveAPIKey(apiKey)
            keyFeedback = .saved
            apiKey = ""
        } catch {
            keyFeedback = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder private var apiKeyStatusLabel: some View {
        if runtime.preferences.apiKeyConfigured {
            switch runtime.preferences.apiKeyValidity {
            case .valid:
                Label("Verified", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            case .invalid:
                Label("Invalid", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .unchecked:
                Label("Stored in Login Keychain", systemImage: "shield")
            }
        }
    }

    @ViewBuilder private var subscriptionUsageView: some View {
        let presentation = SubscriptionUsagePresentation(
            hasCachedUsage: runtime.preferences.subscriptionUsage != nil,
            usageUnavailable: runtime.coordinator.subscriptionUsageUnavailable
        )
        if let usage = runtime.preferences.subscriptionUsage {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(presentation.cachedUsageTitle, systemImage: "gauge.with.dots.needle.33percent")
                    Spacer()
                    Text("\(usage.remainingCredits.formatted()) of \(usage.totalCredits.formatted()) remaining")
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    ProgressView(value: Double(usage.remainingCredits), total: Double(max(usage.totalCredits, 1)))
                        .tint(
                            presentation.cachedUsageIsStale
                                ? Color.secondary
                                : usage.remainingCredits == 0 ? .orange : .accentColor
                        )
                    if let percentage = usage.remainingPercentage {
                        Text(percentage, format: .percent)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            // Reserves room for three digits so the bar keeps its
                            // width as the number shrinks.
                            .frame(minWidth: 34, alignment: .trailing)
                            // The HStack centers the text's *box*, but the system
                            // font's ascent exceeds its descent, so the glyphs sit
                            // below the bar. Text snaps to the backing-store grid,
                            // so only multiples of 0.5 move anything at 2x.
                            // Optical correction only; `offset` deliberately
                            // leaves the layout alone.
                            .offset(y: -1)
                            .accessibilityLabel("\(percentage) percent of credits remaining")
                    }
                }
                HStack {
                    Text(usage.tier.capitalized + " plan")
                    if let resetAt = usage.resetAt {
                        Text("· Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Text("· Updated \(usage.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    Spacer()
                    if presentation.showsCachedUsageRefresh {
                        Button {
                            Task { await runtime.coordinator.refreshSubscriptionUsage() }
                        } label: {
                            if runtime.coordinator.isRefreshingSubscriptionUsage {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(runtime.coordinator.isRefreshingSubscriptionUsage)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if usage.remainingCredits == 0, usage.canExtendCredits {
                    Text("Included credits are depleted, but ElevenLabs reports that extended usage is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(presentation.cachedUsageIsStale ? 0.58 : 1)
            .padding(.vertical, 4)
        }

        if presentation.showsUnavailableRetry {
            VStack(alignment: .leading, spacing: 4) {
                Label("Speech-to-Text access verified", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(runtime.coordinator.subscriptionUsageError ?? "Credit usage is unavailable for this API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await runtime.coordinator.refreshSubscriptionUsage() }
                } label: {
                    if runtime.coordinator.isRefreshingSubscriptionUsage {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    } else {
                        Text("Retry Credit Usage")
                    }
                }
                .disabled(runtime.coordinator.isRefreshingSubscriptionUsage)
            }
        }
    }
}

private struct PermissionsSettingsPane: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        SettingsPane(accessibilityIdentifier: "settings-permissions-pane") {
            SettingsSection {
                PermissionStatusRow(
                    title: "Accessibility",
                    systemImage: "keyboard",
                    allowed: runtime.coordinator.accessibilityGranted
                ) {
                    AccessibilityPermissionButton()
                }
                PermissionStatusRow(
                    title: "Microphone",
                    systemImage: "mic",
                    allowed: runtime.coordinator.microphoneGranted
                ) {
                    MicrophonePermissionButton()
                }
                systemAudioSignpost
            }
        }
    }

    /// A signpost, not a status row. Core Audio ships no preflight for process
    /// taps, so the only way to read this grant is to attempt one — which is
    /// what raises the prompt. The row says what macOS will not report and
    /// points at where to look, and claims nothing about the answer.
    private var systemAudioSignpost: some View {
        VStack(alignment: .leading, spacing: SettingsPaneLayout.captionGap) {
            HStack {
                Label("Screen & System Audio Recording", systemImage: "speaker.wave.2")
                Spacer()
                Button("Open Privacy & Security") {
                    runtime.coordinator.openSystemAudioPrivacySettings()
                }
                .accessibilityIdentifier("open-system-audio-privacy-signpost")
            }
            Text("Used only to mute other apps while you dictate. macOS does not report whether this one is granted, so Scriber cannot show it here — muting works either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Both permission rows offer one button with one word, whatever macOS has recorded
// so far. The steps behind it — a system prompt, a trip to System Settings, or both —
// are Scriber's problem, not something to spell out in a changing button title.
struct MicrophonePermissionButton: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        if !runtime.coordinator.microphoneGranted {
            Button("Allow") { Task { await runtime.coordinator.allowMicrophone() } }
        }
    }
}

struct AccessibilityPermissionButton: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        if !runtime.coordinator.accessibilityGranted {
            Button("Allow") { runtime.coordinator.allowAccessibility() }
        }
    }
}

struct PermissionLabel: View {
    let title: String
    let systemImage: String
    let allowed: Bool

    var body: some View {
        Label(
            allowed ? "\(title) allowed" : "\(title) required",
            systemImage: allowed ? "checkmark.circle.fill" : systemImage
        )
        .foregroundStyle(allowed ? Color.green : Color.primary)
    }
}

private struct PermissionStatusRow<Actions: View>: View {
    let title: String
    let systemImage: String
    let allowed: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack {
            PermissionLabel(title: title, systemImage: systemImage, allowed: allowed)
            Spacer()
            actions
        }
    }
}

struct MicrophonePicker: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        Picker("Input", selection: $runtime.preferences.audioInputSelection) {
            Text("Automatic (System Default)")
                .tag(AudioInputSelection.automatic)
            ForEach(runtime.coordinator.audioInputDevices) { device in
                Text(device.isBuiltIn ? "\(device.name) (Recommended)" : device.name)
                    .tag(AudioInputSelection.device(id: device.id, name: device.name))
            }
            if let unavailableSelection {
                Text("\(unavailableSelection.name) (Unavailable)")
                    .tag(AudioInputSelection.device(id: unavailableSelection.id, name: unavailableSelection.name))
            }
        }
    }

    private var unavailableSelection: (id: String, name: String)? {
        guard case .device(let id, let name) = runtime.preferences.audioInputSelection,
              !runtime.coordinator.audioInputDevices.contains(where: { $0.id == id }) else { return nil }
        return (id, name)
    }
}
