import AppKit
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

/// Settings is fixed at this size. The scene derives its frame from it and the
/// window layer pins both limits to it, so the two have to read the same number.
enum SettingsWindowLayout {
    static let width: CGFloat = 660
    static let height: CGFloat = 520
}

/// The main window's own measurements, gathered for the reason
/// `SettingsWindowLayout` is: the scene derives its frame from them and the
/// window layer pins its limits to the same numbers, so the two have to agree.
///
/// `maxWidth` is the window, not the transcript column. The list style's inset
/// and the row's `contentInset` come off it, so the text is about 70pt narrower
/// than this — do not read it as a measure of line length.
enum MainWindowLayout {
    static let maxWidth: CGFloat = 800
    static let minWidth: CGFloat = 640
    static let minHeight: CGFloat = 480
    static let defaultHeight: CGFloat = 640
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
    /// The tab that owns this destination. Nil is not a gap — it means an ordinary
    /// opening, which leaves the user on whatever tab they last chose.
    var settingsTab: SettingsTab? {
        switch self {
        case .dictation, .settings: nil
        case .apiKey, .usage: .elevenLabs
        case .microphone: .sound
        case .permissions: .permissions
        case .updates: .general
        }
    }
}

/// The gaps Settings sets for itself. Row insets, section headers, and the rules
/// between rows belong to the grouped form and stay at its numbers, so everything
/// in a card sits on the same leading edge.
private enum SettingsPaneLayout {
    /// Between a setting and the sentence explaining it, added on top of the gap
    /// AppKit's two-`Text` toggle label draws — which is tight enough that the
    /// caption reads as a wrapped second line of the title.
    static let captionGap: CGFloat = 4

    /// Between a setting and the setting nested under it. Wider than the gap
    /// inside either of them, so the indent is not the only thing saying one
    /// governs the other.
    static let nestedSettingGap: CGFloat = 14

    /// Above an action that belongs to the whole tab. A footer sits close under
    /// its card, which is right for a sentence about that card and too close for
    /// a button that answers to none of them.
    static let pageActionGap: CGFloat = 12

    /// Between the scrolling form and the window's side edges. The grouped form
    /// draws its own row inset inside this, so a card's edge sits further in again.
    static let paneMargin: CGFloat = 26

    /// Between the scrolling form and the window's top and bottom edges. At the
    /// top it is added to the toolbar's height, which the form scrolls under.
    static let paneEdgeGap: CGFloat = 16

    /// A caption inside a card. AppKit draws its own under a toggle's title and
    /// reports the font to no API, so this is measured against it: both ink
    /// 10.5pt, where SwiftUI's `.caption` inks 9.5 and reads a size small beside
    /// one.
    static let cardCaption: Font = .subheadline

    /// A caption outside a card — under a section's title, or in its footer. The
    /// size a grouped form draws its own footers at, and a step above the caption
    /// inside a card, which is the order the system puts them in.
    static let pageCaption: Font = .callout
}

/// Wraps whatever renders the mute-other-audio setting, handing it a binding that
/// asks before it turns on and carrying the dialog that does the asking. One view
/// rather than a binding plus a separate modifier, because a call site that took
/// only the binding gets a toggle that silently never turns on. Settings and
/// onboarding both go through here.
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
/// row is divided from the setting it explains exactly as much as the next setting
/// is, making a group of two settings read as four. The two-`Text` label is
/// AppKit's answer: caption under title, same row, no divider able to fall between.
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
                // Inside AppKit's label rather than a stack of our own: AppKit sets
                // the caption's font and colour and reports neither. All this adds
                // is the gap, which it otherwise draws too tight to read as an
                // explanation rather than a wrapped second line.
                Text(caption).padding(.top, SettingsPaneLayout.captionGap)
            }
        } else {
            Toggle(title, isOn: $isOn)
        }
    }
}

/// The shape every tab's content takes: one grouped form, inset so the cards
/// leave margins rather than stretching from edge to edge.
///
/// Inset with content margins, never with padding around the form. A scroll view
/// padded off the window's edges stops running under the toolbar, and AppKit
/// fills the titlebar with an opaque band the moment it does — which is what a
/// card scrolled up into it then disappears behind.
private struct SettingsPane<Content: View>: View {
    let accessibilityIdentifier: String
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .accessibilityIdentifier(accessibilityIdentifier)
            .contentMargins(.horizontal, SettingsPaneLayout.paneMargin, for: .scrollContent)
            .contentMargins(.vertical, SettingsPaneLayout.paneEdgeGap, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The controls that answer to a whole tab rather than to any group in it,
/// trailing-aligned below the last card. Carried in a `Section` with no rows, so
/// the form draws no card around them and they scroll with the content.
///
/// One recipe, because the gap above them is the whole point of the shape: it is
/// what says these are the tab's and not the card's, and a tab that writes its
/// own gets it wrong quietly. Do not reach for `VStack(spacing:)` around a single
/// row — spacing needs two children to sit between, so it adds nothing and the
/// row lands hard against the card above.
private struct SettingsPageActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Spacer()
            content
        }
        .padding(.top, SettingsPaneLayout.pageActionGap)
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
    /// Changes once per visit, and is the tab picker's identity. SwiftUI keeps a
    /// `Window` scene alive after its window closes — the same `NSScrollView`
    /// comes back on the next opening, still holding the offset it was left at,
    /// so a tab that scrolls would reopen mid-content. A new identity is a new
    /// scroll view, which starts at its top.
    @State private var visitToken = 0

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
        // Once, on the whole picker, rather than on each tab's content: a sixth
        // tab must not be able to arrive without it.
        .id(visitToken)
        .accessibilityIdentifier("settings-view")
        // The size, not a floor: the window is fixed, so a tab is seen at the
        // size it was designed at whatever else is in Settings, and a tab with
        // more in it than fits scrolls. Adding a setting does not move this.
        .frame(width: SettingsWindowLayout.width, height: SettingsWindowLayout.height)
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
            // Leaving General mid-recording strands the recorder's local monitor,
            // which returns nil for every key event — nothing in Scriber can be
            // typed into and global matching stays suspended until the window
            // closes. `ShortcutRecorderView` watches this ID to tear it down.
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
            visitToken += 1
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
    /// Opens a new issue directly, rather than the repository's front page: the
    /// user has already decided what they came to do.
    private static let issuesURL = URL(string: "https://github.com/gafiegarcia/scriber/issues/new")

    @EnvironmentObject private var runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow
    @Binding var activeShortcutRecorderID: String?
    let refusalResetToken: Int
    @State private var confirmRestartSetup = false
    @State private var showingHomebrewUpdate = false
    @State private var launchAtLoginError: String?
    /// Set only by a request that macOS refused. Switching Scriber off under
    /// Background App Activity is a decision the user is allowed to make, so
    /// the state alone must stay silent — the explanation belongs to the moment
    /// they ask for the opposite and nothing happens.
    @State private var launchAtLoginRefused = false

    var body: some View {
        SettingsPane(accessibilityIdentifier: "settings-general-pane") {
            Section {
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
                        Text(launchAtLoginError).font(SettingsPaneLayout.cardCaption).foregroundStyle(.red)
                    }
                    // The toggle snapping back is the only other signal here, and
                    // on its own it reads as a bug rather than as something the
                    // user has to go and switch on.
                    if launchAtLoginRefused, let advice = runtime.coordinator.launchAtLoginState.recoveryAdvice {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(advice).font(SettingsPaneLayout.cardCaption).foregroundStyle(.secondary)
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
                    // `.disabled` alone only lowers the alpha a little and keeps the
                    // accent colour, so a switch left on still reads as live.
                    // Draining the tint is what makes it read as governed by the
                    // setting above.
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
            Section {
                ShortcutPicker(
                    chord: $runtime.preferences.dictationShortcut,
                    customChord: $runtime.preferences.customShortcut,
                    activeRecorderID: $activeShortcutRecorderID,
                    isEditable: !runtime.coordinator.phase.isBusy,
                    refusalResetToken: refusalResetToken
                )
            } header: {
                // Above the card rather than below it: these are instructions for
                // the control, and the form's header is the only slot that reads
                // before it. The caption's font and weight are set here because a
                // header hands its own down to everything inside it.
                VStack(alignment: .leading, spacing: SettingsPaneLayout.captionGap) {
                    Text("Shortcut")
                    Text("Tap to dictate and tap again to stop. Hold and release for quick dictation. Cancel recording with Escape.")
                        .font(SettingsPaneLayout.pageCaption)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: SettingsPaneLayout.captionGap) {
                    HStack(spacing: 10) {
                        // Anchored to the leading edge, which is what lets the
                        // button opposite change width without moving it.
                        Text("Scriber \(AppCoordinator.displayVersion(AppCoordinator.runningVersion)) (\(AppCoordinator.runningBuild))")
                            .monospacedDigit()
                            .accessibilityLabel(
                                "Scriber version \(AppCoordinator.runningVersion), build \(AppCoordinator.runningBuild)"
                            )
                        Spacer(minLength: 0)
                        Button(action: { runtime.coordinator.checkForUpdates(force: true) }) {
                            HStack(spacing: 6) {
                                // Before the title, not replacing it, and the
                                // button is against the trailing edge: the spinner
                                // grows the button leftwards into the spacer while
                                // the title, being last, does not move at all.
                                if runtime.coordinator.isCheckingForUpdates {
                                    ProgressView().controlSize(.small)
                                }
                                Text("Check for Updates")
                            }
                        }
                        .disabled(runtime.coordinator.isCheckingForUpdates)
                        .accessibilityIdentifier("check-for-updates")
                    }
                    HStack(spacing: 10) {
                        updateStatus
                        Spacer(minLength: 0)
                        // On the line that announces the offer rather than in the
                        // row above, which carried two buttons of different weight
                        // side by side. No ellipsis: it opens the release page,
                        // which is the action finishing, not asking for anything.
                        if let update = runtime.preferences.availableUpdate {
                            // A Homebrew install takes its update from Homebrew,
                            // so the button opens the command rather than the
                            // release page — and earns its ellipsis by doing it,
                            // where "Get" only ever opened a page.
                            if AppCoordinator.isHomebrewManaged {
                                Button("Update…") { showingHomebrewUpdate = true }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("download-update")
                            } else {
                                Link(
                                    "Get \(AppCoordinator.displayVersion(update.version))",
                                    destination: update.url
                                )
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("download-update")
                            }
                        }
                    }
                }
                SettingsToggle(
                    "Check for updates automatically",
                    caption: "Asks GitHub once a day whether a newer version has been released. Scriber never installs anything on its own.",
                    isOn: $runtime.preferences.automaticUpdateChecks
                )
                .accessibilityIdentifier("automatic-update-checks-toggle")
            } header: {
                Text("Updates")
            }
            Section {
                EmptyView()
            } footer: {
                SettingsPageActions {
                    if let issuesURL = Self.issuesURL {
                        Link("Report a Bug…", destination: issuesURL)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("report-a-bug")
                    }
                    // Nothing is destroyed by walking setup again — it reads
                    // current state, so a step already satisfied is presented as
                    // satisfied — but it does replace the window in front of you,
                    // so it asks.
                    //
                    // Disabled during a dictation, for the reason
                    // `canRestartOnboarding` gives.
                    Button("Redo Setup…") { confirmRestartSetup = true }
                        .accessibilityIdentifier("restart-onboarding")
                        .disabled(!runtime.coordinator.canRestartOnboarding)
                }
            }
        }
        // An alert rather than a confirmation: it answers a question rather than
        // asking one, and nothing here is destructive enough to confirm.
        .alert("Scriber was installed with Homebrew", isPresented: $showingHomebrewUpdate) {
            Button("Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(HomebrewInstall.upgradeCommand, forType: .string)
            }
            Button("Close", role: .cancel) {}
        } message: {
            // The command and nothing else. Someone who installed with Homebrew
            // does not need telling that Homebrew is how they update.
            Text("Update it from the terminal:\n\n" + HomebrewInstall.upgradeCommand)
        }
        .confirmationDialog("Go through setup again?", isPresented: $confirmRestartSetup) {
            Button("Redo Setup") {
                // Both halves have to refuse together: creating the scene while
                // `restartOnboarding` declines opens setup over a dictation it
                // did not restart for, and setup is where the shortcut carrying
                // `Escape` is switched off. Reached only if a dictation starts in
                // the same frame as the press; otherwise the box has already
                // closed.
                guard runtime.coordinator.canRestartOnboarding else { return }
                // Create the scene first, then let the coordinator order it
                // front — it waits for the window to exist.
                openWindow(id: AppWindowIdentity.onboardingSceneID)
                runtime.coordinator.restartOnboarding()
            }
        } message: {
            Text("Your key, permissions, and history are kept. Setup shows each step's current state.")
        }
        // The question stops being answerable the moment a dictation starts, so
        // the box goes rather than standing there with a prominent button that
        // dismisses and does nothing. Disabling that button cannot serve: macOS
        // does not redraw an alert's button that became unavailable underneath
        // it, and the box can only have been opened while no dictation ran.
        .onChange(of: runtime.coordinator.canRestartOnboarding) { _, canRestart in
            if !canRestart { confirmRestartSetup = false }
        }
    }

    private var updateStatus: some View {
        Text(updateStatusText)
            .font(SettingsPaneLayout.cardCaption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("update-status")
    }

    /// Never claims to be current on the strength of a check that has not
    /// happened: an install that has never reached GitHub says so.
    ///
    /// The current state carries when the check last ran, because otherwise
    /// pressing Check for Updates on an install that is already current changes
    /// nothing on screen and cannot be told from a button that does nothing.
    private var updateStatusText: String {
        if let error = runtime.coordinator.updateCheckError {
            return error
        }
        if let update = runtime.preferences.availableUpdate {
            return "Scriber \(AppCoordinator.displayVersion(update.version)) is available."
        }
        guard let lastCheck = runtime.preferences.lastUpdateCheck else {
            return "No check has run yet."
        }
        return "You're on the latest version. Last checked: \(Self.lastCheckedDescription(lastCheck))."
    }

    /// Relative, and "just now" under a minute — `.relative` renders that span as
    /// "in 0 seconds", which reads as a check that has not happened yet.
    ///
    /// Not live: nothing redraws this while Settings sits open, so a window left
    /// up goes on saying "just now". Each visit rebuilds the pane and recomputes
    /// it, which is the moment anyone reads it.
    private static func lastCheckedDescription(_ date: Date) -> String {
        Date().timeIntervalSince(date) < 60
            ? "just now"
            : date.formatted(.relative(presentation: .named))
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
            Section {
                Picker("Language", selection: $runtime.preferences.languageCode) {
                    Text("Automatic").tag("auto")
                    Text("English").tag("en")
                    Text("Indonesian").tag("id")
                }
                Toggle("Remove filler words and false starts", isOn: $runtime.preferences.noVerbatim)
                // Field, captions, and the added-terms list share one Form row so
                // the grouped form draws no divider between them. A divider per
                // keyterm reads as more settings rows rather than as the contents
                // of this one setting.
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
                            // Bordered, unlike the rows above: this one is empty
                            // until typed into and has nothing else announcing it
                            // as a field.
                            .textFieldStyle(.roundedBorder)
                            // Left, not the default: unset, an empty focused field
                            // with a prompt longer than the box scrolls to keep the
                            // caret in view, pinning the prompt's tail to the right.
                            .multilineTextAlignment(.leading)
                            // Fixed, so the field neither reflows as the window
                            // widens nor resizes as you type, and wider than the
                            // prompt so the caret quirk above cannot bite. Not
                            // `.fixedSize` with `.frame(minWidth:maxWidth:)` — that
                            // lets the rendered width ignore both bounds.
                            .frame(width: 200)
                            .onSubmit(submitKeyterm)
                            .accessibilityIdentifier("keyterm-field")
                            Button("Add", action: submitKeyterm)
                                .disabled(!canAddKeyterm)
                        }
                    } label: {
                        // Click rather than `.help()`: a hover tooltip waits out
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
                        Text(keytermError).font(SettingsPaneLayout.cardCaption).foregroundStyle(.red)
                    }
                    if !runtime.preferences.keyterms.isEmpty {
                        KeytermsCard(terms: runtime.preferences.keyterms, onRemove: removeKeyterm)
                    }
                    Text("ElevenLabs applies an additional usage charge when keyterms are sent.")
                        .font(SettingsPaneLayout.cardCaption).foregroundStyle(.secondary)
                }
            }
            Section {
                Picker(selection: $runtime.preferences.retainedAudioRetention) {
                    ForEach(RetainedAudioRetention.allCases, id: \.self) { retention in
                        Text(retention.label).tag(retention)
                    }
                } label: {
                    // Two `Text`s inside AppKit's own label, for the reason
                    // `SettingsToggle` gives: a caption written as its own row is
                    // divided from the setting it explains.
                    Text("Delete failed and cancelled dictations")
                    Text("A failed or cancelled dictation keeps its recording so you can retry it. This sets how long it is kept before both the recording and the entry are deleted.")
                        .padding(.top, SettingsPaneLayout.captionGap)
                }
                .accessibilityIdentifier("retained-audio-retention")

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

/// The added keyterms as their own card: one shape, one outline, one rule
/// between neighbouring rows. Not drawn when there are no keyterms, and not
/// indented — the border and per-row padding already mark this as the contents
/// of Keyterms.
///
/// Hand-drawn because this is a handful of terms inside a form, not a list. Do
/// not take it as the pattern for anything that scrolls — a `List` draws its own
/// separators, and a second set on top is what this recipe would give it.
private struct KeytermsCard: View {
    let terms: [String]
    let onRemove: (String) -> Void

    // One number for the outline's weight and each rule's horizontal inset, kept
    // equal. `strokeBorder` draws inward, so the border owns this outer band and
    // insetting each rule by the same width lands its ends on the border's inner
    // edge. Full width instead and both lay a semi-transparent `.separator` over
    // that band, stacking into a darker dot at each end; inset any more and a gap
    // opens.
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
            Section {
                MicrophonePicker()
                    .accessibilityIdentifier("microphone-input-picker")

                // One row for the whole input test — meter, advice, controls, and
                // whatever went wrong. Split across rows, the grouped form divides
                // them as if each were its own setting. Behind a button rather than
                // always live, so arriving on this tab does not open the microphone
                // and light the recording indicator.
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
                            .font(SettingsPaneLayout.cardCaption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Stop") { runtime.coordinator.stopMicrophoneTest() }
                            Button("Open Sound Settings") { runtime.coordinator.openSystemSoundSettings() }
                        }
                        .font(SettingsPaneLayout.cardCaption)
                    } else {
                        Button("Check Input Level") { runtime.coordinator.startMicrophoneTest() }
                            .accessibilityIdentifier("microphone-level-test-button")
                            .disabled(!runtime.coordinator.microphoneGranted
                                || runtime.coordinator.phase.isBusy)
                    }

                    if let microphoneTestError = runtime.coordinator.microphoneTestError {
                        Label(microphoneTestError, systemImage: "exclamationmark.triangle.fill")
                            .font(SettingsPaneLayout.cardCaption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section {
                SettingsToggle(
                    "Play sounds while dictating",
                    caption: "You hear one sound when a dictation starts, and another when one fails or is cancelled.",
                    isOn: $runtime.preferences.playDictationFeedbackSounds
                )
                .accessibilityIdentifier("recording-feedback-sounds-toggle")

                // The warning and the settings link share the row with the
                // toggle they are about, rather than sitting a divider away
                // from the setting that asked for them.
                MuteOtherAudioToggle(
                    isOn: $runtime.preferences.muteOtherAudioWhileDictating,
                    requestAccess: { runtime.coordinator.requestOtherAudioAccess() }
                ) { isOn in
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsToggle(
                            "Mute other audio while dictating",
                            caption: "Silences other apps, calls, and notification sounds while you’re dictating. macOS asks for System Audio Recording access — muting works whether you click “Allow” or “Don’t Allow”, because Scriber never reads what other apps play.",
                            isOn: isOn
                        )
                        .accessibilityIdentifier("mute-other-audio-toggle")
                        if let status = runtime.coordinator.otherAudioMuteStatus {
                            Label(status.message, systemImage: "exclamationmark.triangle.fill")
                                .font(SettingsPaneLayout.cardCaption)
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("other-audio-mute-status")
                        }
                        // Reachable whenever muting is on, not only once it has
                        // failed: withdrawing the grant is something people do
                        // to a feature that works, and they arrive with no
                        // failure to route them anywhere.
                        if runtime.preferences.muteOtherAudioWhileDictating
                            || runtime.coordinator.otherAudioMuteStatus != nil {
                            Button("Open Screen & System Audio Recording settings") {
                                runtime.coordinator.openSystemAudioPrivacySettings()
                            }
                            .buttonStyle(.link)
                            .font(SettingsPaneLayout.cardCaption)
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
    @Environment(\.openWindow) private var openWindow
    @Binding var apiKey: String
    @Binding var pendingKeyFieldFocus: Bool
    @State private var keyFeedback: KeySaveFeedback?
    @State private var isCheckingAPIKey = false
    @State private var isRemovingAPIKey = false
    @State private var confirmRemoveKey = false
    @State private var showsDataUseHelp = false
    @FocusState private var apiKeyFieldFocused: Bool

    var body: some View {
        SettingsPane(accessibilityIdentifier: "settings-elevenlabs-pane") {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
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
                        // Trailing the field, as it is in setup: the same task in
                        // two places, laid out the same way.
                        Button(action: submitAPIKey) {
                            HStack(spacing: 6) {
                                // Beside the title, not instead of it. Replacing
                                // it resizes the button, and the field beside it
                                // takes the change.
                                if isCheckingAPIKey { ProgressView().controlSize(.small) }
                                Text("Save API Key")
                            }
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSubmitAPIKey)
                    }
                    HStack {
                        if let keyFeedback {
                            Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                                .font(SettingsPaneLayout.cardCaption)
                                .foregroundStyle(keyFeedback.color)
                                .lineLimit(2)
                                .accessibilityIdentifier("api-key-save-feedback")
                        } else if apiKey.isEmpty {
                            apiKeyStatusLabel
                        }
                        Spacer(minLength: 0)
                    }
                }
                // Its own row, so destroying a key is not offered from the same line
                // as saving one, and leading, where it does not compete with Save.
                // Confirmed, because the key does not come back.
                if runtime.preferences.apiKeyConfigured {
                    HStack {
                        Button("Remove API Key…", role: .destructive) {
                            confirmRemoveKey = true
                        }
                        .disabled(isCheckingAPIKey || isRemovingAPIKey)
                        .accessibilityIdentifier("remove-api-key")
                        Spacer(minLength: 0)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: SettingsPaneLayout.captionGap) {
                    Text("API Key")
                    Text("Scriber needs a key with Speech to Text access. [Create a free ElevenLabs account](https://elevenlabs.io/app/sign-up), then [add an API key](https://elevenlabs.io/app/developers/api-keys). Enable User → Read on that key as well to show your credits here.")
                        .font(SettingsPaneLayout.pageCaption)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Guarded here rather than inside the block: `subscriptionUsageView`
            // renders nothing while a valid key's usage has yet to arrive, and an
            // empty section still draws its header.
            if showsUsageSection {
                Section {
                    subscriptionUsageView
                } header: {
                    Text("Remaining credits")
                }
            }
            Section {
                EmptyView()
            } footer: {
                pageActions
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

    /// The tab's own controls, not the credits card's — they answer to the whole
    /// ElevenLabs tab, and only happen to be about what it sends.
    ///
    /// **Configure Data Use…** carries its subject on its own. A sentence above it
    /// saying the same thing was tried and read as nagging rather than as
    /// informing — the button names the subject, which is what someone who has
    /// never heard of the setting needs in order to press it.
    private var pageActions: some View {
        SettingsPageActions {
            Link("Privacy Policy", destination: DataUseGuidance.privacyPolicyURL)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("elevenlabs-privacy-policy")
            // `openWindow` from this pane's own environment, not a closure parked
            // by the menu bar icon: that icon is absent whenever **Show in menu
            // bar** is off, and a button wired through it would silently do
            // nothing.
            Button("Configure Data Use…") { openWindow(id: AppWindowIdentity.dataUseSceneID) }
                .accessibilityIdentifier("configure-data-use")
            Button {
                showsDataUseHelp = true
            } label: {
                // `.primary` rather than a literal white: the glyph has to carry
                // against a translucent background that is dark in one appearance
                // and light in the other, and white only works in the first.
                Image(systemName: "questionmark")
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.bordered)
            .clipShape(.circle)
            // A glyph alone announces as its symbol name, and identifies as one
            // too — this button reported as "questionmark" until it was named here.
            .accessibilityLabel("About what Scriber sends and keeps")
            .accessibilityIdentifier("about-data-use")
            .popover(isPresented: $showsDataUseHelp) {
                // Scriber does keep something: every transcript goes into
                // Dictation history on disk. Saying it keeps nothing would be the
                // one claim here a sceptical reader could check and disprove.
                Text("Your recordings go to ElevenLabs to be transcribed, and nowhere else. The transcripts are saved locally on your Mac, in Dictation history.")
                    .font(.callout)
                    // A Form footer styles everything inside it as secondary, and
                    // a popover presented from one inherits that — which is why
                    // this reads grey where the Keyterms popover, which hangs off
                    // a section label, reads white.
                    .foregroundStyle(.primary)
                    .padding()
                    .frame(maxWidth: 260)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(usage.tier.capitalized + " plan")
                        if let resetAt = usage.resetAt {
                            Text("Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(SettingsPaneLayout.cardCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    // The section names them as remaining, so the number does not
                    // have to say it twice.
                    Text("\(usage.remainingCredits.formatted()) of \(usage.totalCredits.formatted()) credits")
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
                    // Relative, because how long ago it was read is the useful part.
                    // Styled here rather than on the row: a button sharing the row
                    // is not a caption, and inheriting the caption's size makes it
                    // read as a smaller control than every other button in Settings.
                    Text("Last checked \(usage.fetchedAt.formatted(.relative(presentation: .named)))")
                        .font(SettingsPaneLayout.cardCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if presentation.showsCachedUsageRefresh {
                        Button {
                            Task { await runtime.coordinator.refreshSubscriptionUsage() }
                        } label: {
                            // An `HStack` and not a `Label`, which reserves an
                            // alignment column for its icon and leaves a gap the
                            // width of one beside a glyph this small.
                            HStack(spacing: 4) {
                                // The spinner takes the icon's place rather than
                                // the whole label's, so the button holds its width.
                                if runtime.coordinator.isRefreshingSubscriptionUsage {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .imageScale(.small)
                                }
                                Text("Refresh")
                            }
                        }
                        .disabled(runtime.coordinator.isRefreshingSubscriptionUsage)
                    }
                }
                if usage.remainingCredits == 0, usage.canExtendCredits {
                    Text("Included credits are depleted, but ElevenLabs reports that extended usage is available.")
                        .font(SettingsPaneLayout.cardCaption)
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
                    .font(SettingsPaneLayout.cardCaption)
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
            Section {
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
                Button("Open Recording Settings") {
                    runtime.coordinator.openSystemAudioPrivacySettings()
                }
                .accessibilityIdentifier("open-system-audio-privacy-signpost")
            }
            Text("Used only to mute other apps while you dictate. macOS does not report whether this one is granted, so Scriber cannot show it here — muting works either way.")
                .font(SettingsPaneLayout.cardCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// While a grant is missing, both rows offer one button with one word; the steps
// behind it are Scriber's problem, not a changing button title. Once granted, the
// button leads back to the pane holding the grant and is named for that pane —
// three buttons reading "Open Settings" would announce identically to VoiceOver,
// and would name Scriber's own Settings besides.
struct MicrophonePermissionButton: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        if runtime.coordinator.microphoneGranted {
            Button("Open Microphone Settings") { runtime.coordinator.openMicrophoneSettings() }
                .accessibilityIdentifier("open-microphone-settings")
        } else {
            Button("Allow") { Task { await runtime.coordinator.allowMicrophone() } }
        }
    }
}

struct AccessibilityPermissionButton: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        if runtime.coordinator.accessibilityGranted {
            Button("Open Accessibility Settings") { runtime.coordinator.openAccessibilitySettings() }
                .accessibilityIdentifier("open-accessibility-settings")
        } else {
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
