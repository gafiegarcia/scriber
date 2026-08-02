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

private enum KeySaveFeedback {
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


struct SettingsView: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow
    /// Only so Clear Dictation History knows whether there is anything to clear,
    /// and how much. Sorted to match the Dictation page rather than for display.
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    let onShortcutConfigurationCaptureChanged: (Bool) -> Void
    @State private var confirmClearHistory = false
    @State private var confirmRemoveKey = false
    @State private var isRemovingAPIKey = false
    @State private var confirmRestartOnboarding = false
    @State private var apiKey = ""
    @State private var keyFeedback: KeySaveFeedback?
    @State private var isCheckingAPIKey = false
    @State private var newKeyterm = ""
    @State private var message: String?
    @FocusState private var apiKeyFieldFocused: Bool
    @State private var activeShortcutRecorderID: String?

    init(onShortcutConfigurationCaptureChanged: @escaping (Bool) -> Void = { _ in }) {
        self.onShortcutConfigurationCaptureChanged = onShortcutConfigurationCaptureChanged
    }

    /// A dictation still being transcribed is not shown in history and must not
    /// be swept up by a clear — its audio is still in use. Matches the filter the
    /// Dictation page applies to what it displays.
    private var clearableRecords: [DictationRecord] {
        records.filter { $0.transcriptionState != .transcribing }
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
            Section("General") {
                ShortcutRecorderView(
                    title: "Hold to Dictate",
                    identifier: "hold",
                    isEnabled: $runtime.preferences.holdShortcutEnabled,
                    chord: $runtime.preferences.holdShortcut,
                    activeRecorderID: $activeShortcutRecorderID,
                    conflictingChord: runtime.preferences.toggleShortcutEnabled ? runtime.preferences.toggleShortcut : nil,
                    isCaptureAllowed: !runtime.coordinator.phase.isBusy
                )
                ShortcutRecorderView(
                    title: "Hands-free Toggle",
                    identifier: "toggle",
                    isEnabled: $runtime.preferences.toggleShortcutEnabled,
                    chord: $runtime.preferences.toggleShortcut,
                    activeRecorderID: $activeShortcutRecorderID,
                    conflictingChord: runtime.preferences.holdShortcutEnabled ? runtime.preferences.holdShortcut : nil,
                    isCaptureAllowed: !runtime.coordinator.phase.isBusy
                )
                Text("Modifier-only chords are supported. Press Escape while recording a binding to cancel.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at Login", isOn: Binding(
                    get: { runtime.preferences.launchAtLoginRequested },
                    set: { enabled in
                        do { try runtime.coordinator.setLaunchAtLogin(enabled) }
                        catch { message = error.localizedDescription }
                    }
                ))
                Toggle("Show in Menu Bar", isOn: $runtime.preferences.showInMenuBar)
                Toggle("Show app in Dock", isOn: $runtime.preferences.showAppInDock)
                    .accessibilityIdentifier("show-app-in-dock-toggle")
                // Onboarding was previously reachable only by deleting a defaults
                // key. Nothing is destroyed by walking it again — it reads current
                // state, so a step already satisfied is presented as satisfied —
                // but it does replace the window in front of you, so it asks.
                HStack {
                    Button("Redo Onboarding…") { confirmRestartOnboarding = true }
                        .accessibilityIdentifier("restart-onboarding")
                    Spacer()
                }
            }
            .onChange(of: activeShortcutRecorderID) { _, activeRecorderID in
                onShortcutConfigurationCaptureChanged(activeRecorderID != nil)
            }
            .onChange(of: runtime.coordinator.phase.isBusy) { _, isBusy in
                if isBusy { activeShortcutRecorderID = nil }
            }
            Section("Feedback") {
                Toggle(
                    "Play recording feedback sounds",
                    isOn: $runtime.preferences.playRecordingFeedbackSounds
                )
                .accessibilityIdentifier("recording-feedback-sounds-toggle")

                Toggle(
                    "Mute other audio while recording",
                    isOn: $runtime.preferences.muteOtherAudioWhileRecording
                )
                .accessibilityIdentifier("mute-other-audio-toggle")
                Text("Other apps keep playing silently and become audible again when recording stops. Calls and notification sounds are also silenced. Scriber never records or saves system audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let status = runtime.coordinator.otherAudioMuteStatus {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(status.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("other-audio-mute-status")
                        Button("Open Privacy & Security") {
                            runtime.coordinator.openSystemAudioPrivacySettings()
                        }
                        .font(.caption)
                    }
                }
            }
            Section("ElevenLabs") {
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
                        .id(MainWindowDestination.apiKey)
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
                        // There was no way to remove a saved key from inside the
                        // app, so reaching Scriber's own missing-key state meant
                        // deleting the item in Keychain Access. Confirmed, because
                        // the key does not come back and dictation stops until it
                        // is re-entered.
                        if runtime.preferences.apiKeyConfigured {
                            Button("Remove Key…", role: .destructive) {
                                confirmRemoveKey = true
                            }
                            .disabled(isCheckingAPIKey || isRemovingAPIKey)
                            .accessibilityIdentifier("remove-api-key")
                        }
                    }
                }
                subscriptionUsageView
                    .id(MainWindowDestination.usage)
            }
            Section("Dictation") {
                Picker("Language", selection: $runtime.preferences.languageCode) {
                    Text("Automatic").tag("auto")
                    Text("English").tag("en")
                    Text("Indonesian").tag("id")
                }
                Toggle("Remove filler words and false starts", isOn: $runtime.preferences.noVerbatim)
                HStack {
                    TextField("Name or term", text: $newKeyterm)
                    Button("Add") { addKeyterm() }.disabled(newKeyterm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(runtime.preferences.keyterms, id: \.self) { term in
                    HStack { Text(term); Spacer(); Button { removeKeyterm(term) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain) }
                }
                Text("ElevenLabs applies an additional usage charge when keyterms are sent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dictation History") {
                Toggle(
                    "Delete unused recordings after 30 days",
                    isOn: $runtime.preferences.deletesExpiredRetainedAudio
                )
                .accessibilityIdentifier("delete-expired-audio-toggle")
                Text("Failed and cancelled dictations keep their audio so you can retry them. Transcripts and history entries are always kept; only the unused recording is removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Moved here from the Dictation page's header, where it was the
                // only item in an overflow menu that sat in the corner of every
                // session for the sake of something done once in a while.
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
            Section("Permissions and Input") {
                PermissionStatusRow(
                    title: "Accessibility",
                    systemImage: "keyboard",
                    allowed: runtime.coordinator.accessibilityGranted
                ) {
                    AccessibilityPermissionButton()
                }
                // The section's first row rather than the `Section`: a scroll
                // target on the Section lands on its header, which a grouped
                // Form insets away from the content it names.
                .id(MainWindowDestination.permissions)

                PermissionStatusRow(
                    title: "Microphone",
                    systemImage: "mic",
                    allowed: runtime.coordinator.microphoneGranted
                ) {
                    MicrophonePermissionButton()
                }
                MicrophonePicker()
                    .id(MainWindowDestination.microphone)
            }
            if let message { Text(message).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("settings-view")
            .padding()
            .confirmationDialog("Delete all dictation history?", isPresented: $confirmClearHistory) {
                Button("Delete All", role: .destructive) {
                    runtime.coordinator.clearDictationHistory(clearableRecords)
                }
            } message: {
                Text("This permanently removes transcripts and any retained failed recordings.")
            }
            .confirmationDialog("Remove the stored API key?", isPresented: $confirmRemoveKey) {
                Button("Remove Key", role: .destructive) { removeAPIKey() }
            } message: {
                Text("Dictation stops working until you enter a key again. Scriber cannot recover the removed key.")
            }
            .confirmationDialog("Go through onboarding again?", isPresented: $confirmRestartOnboarding) {
                Button("Redo Onboarding") {
                    // Create the scene first, then let the coordinator order it
                    // front — it waits for the window to exist.
                    openWindow(id: "onboarding")
                    runtime.coordinator.restartOnboarding()
                }
            } message: {
                Text("Your key, permissions, and history are kept. Onboarding shows each step's current state.")
            }
            .onAppear {
                apiKey = ""
                runtime.coordinator.refreshPermissions()
                applyMainWindowRequest(runtime.coordinator.mainWindowRequest, proxy: proxy)
            }
            .onChange(of: runtime.coordinator.mainWindowRequest) { _, request in
                applyMainWindowRequest(request, proxy: proxy)
            }
            .onChange(of: apiKey) { _, newValue in
                if !newValue.isEmpty { keyFeedback = nil }
            }
            .onDisappear {
                activeShortcutRecorderID = nil
                onShortcutConfigurationCaptureChanged(false)
            }
        }
        .frame(maxWidth: MainPageLayout.maxContentWidth, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func applyMainWindowRequest(_ request: MainWindowRequest?, proxy: ScrollViewProxy) {
        guard let request else { return }
        switch request.destination {
        case .apiKey:
            proxy.scrollTo(MainWindowDestination.apiKey, anchor: .top)
            DispatchQueue.main.async { apiKeyFieldFocused = true }
        case .usage:
            apiKeyFieldFocused = false
            proxy.scrollTo(MainWindowDestination.usage, anchor: .center)
        case .microphone:
            apiKeyFieldFocused = false
            proxy.scrollTo(MainWindowDestination.microphone, anchor: .center)
        case .permissions:
            apiKeyFieldFocused = false
            // `.top`, not `.center`: this is the last section in the pane, so
            // there is nothing below it to centre against and the scroll view
            // clamps at its end either way.
            proxy.scrollTo(MainWindowDestination.permissions, anchor: .top)
        case .dictation, .settings:
            apiKeyFieldFocused = false
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
        if runtime.preferences.apiKeyValidity == .valid {
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
                    ProgressView(value: Double(usage.remainingCredits), total: Double(max(usage.totalCredits, 1)))
                        .tint(
                            presentation.cachedUsageIsStale
                                ? Color.secondary
                                : usage.remainingCredits == 0 ? .orange : .accentColor
                        )
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

    private func addKeyterm() {
        do {
            let validated = try ScribeClient.validateKeyterms(runtime.preferences.keyterms + [newKeyterm])
            runtime.preferences.keyterms = validated
            newKeyterm = ""
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func removeKeyterm(_ term: String) {
        runtime.preferences.keyterms.removeAll { $0 == term }
    }
}

struct OnboardingView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var runtime: AppRuntime
    @State private var apiKey = ""
    @State private var keyFeedback: KeySaveFeedback?
    @State private var isCheckingAPIKey = false
    @State private var error: String?

    /// The setup steps are tall enough to reach the Dock, so they scroll rather
    /// than push the window off the bottom of the screen. `fitOnboardingWindow`
    /// sizes the window itself, to the full height the display allows, so this
    /// only has to fill it.
    var body: some View {
        ScrollView {
            setupSteps
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Scriber").font(.largeTitle.bold())
                Text("Hold Fn to dictate. Your audio goes only to ElevenLabs, and your history stays on this Mac.")
                    .foregroundStyle(.secondary)
            }
            GroupBox("1. ElevenLabs API key") {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField(
                        runtime.preferences.apiKeyConfigured
                            ? "Enter a new API key to replace the stored key"
                            : "xi-api-key",
                        text: $apiKey
                    )
                        .textFieldStyle(.roundedBorder)
                        .disabled(isCheckingAPIKey)
                        .onSubmit(submitAPIKey)
                    HStack(spacing: 12) {
                        Button(action: submitAPIKey) {
                            if isCheckingAPIKey {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Text("Save Key")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmitAPIKey)

                        if let keyFeedback {
                            Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                                .font(.caption)
                                .foregroundStyle(keyFeedback.color)
                                .lineLimit(2)
                        } else if apiKey.isEmpty, runtime.preferences.apiKeyConfigured {
                            switch runtime.preferences.apiKeyValidity {
                            case .valid:
                                Label("Verified", systemImage: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                            case .invalid:
                                Label("Invalid", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            case .unchecked:
                                Label("Stored in Login Keychain", systemImage: "shield")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            GroupBox("2. Microphone") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        PermissionLabel(
                            title: "Microphone",
                            systemImage: "mic",
                            allowed: runtime.coordinator.microphoneGranted
                        )
                        Spacer()
                        MicrophonePermissionButton()
                    }

                    MicrophonePicker()

                    if runtime.coordinator.microphoneGranted {
                        VStack(alignment: .leading, spacing: 10) {
                            AudioLevelWaveform(level: runtime.coordinator.microphoneTestLevel)
                                .frame(height: 42)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Label(
                                AudioSignal.isDetected(decibels: runtime.coordinator.microphoneTestLevel)
                                    ? "Audio signal detected"
                                    : "Speak to test your microphone",
                                systemImage: AudioSignal.isDetected(decibels: runtime.coordinator.microphoneTestLevel)
                                    ? "waveform.badge.mic"
                                    : "waveform"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                AudioSignal.isDetected(decibels: runtime.coordinator.microphoneTestLevel)
                                    ? Color.green
                                    : Color.secondary
                            )
                        }
                    }

                    if let microphoneTestError = runtime.coordinator.microphoneTestError {
                        Label(microphoneTestError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            GroupBox("3. Accessibility") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        PermissionLabel(
                            title: "Accessibility",
                            systemImage: "keyboard",
                            allowed: runtime.coordinator.accessibilityGranted
                        )
                        Spacer()
                        AccessibilityPermissionButton()
                    }
                    Text("Accessibility lets Scriber watch global shortcuts and insert text into the app you were using.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "Mute other audio while recording",
                    isOn: $runtime.preferences.muteOtherAudioWhileRecording
                )
                Text("Other apps continue playing silently while you dictate. macOS may ask for System Audio Recording access; Scriber never records or saves that audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Launch Scriber when I log in", isOn: $runtime.preferences.launchAtLoginRequested)
                Text("Defaults: Hold \(runtime.preferences.holdShortcut.displayName) · Toggle \(runtime.preferences.toggleShortcut.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
            HStack {
                Spacer()
                Button("Finish Setup") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isCheckingAPIKey
                            || !runtime.preferences.apiKeyConfigured
                            || runtime.preferences.apiKeyValidity != .valid
                            || !runtime.coordinator.microphoneGranted
                            || !runtime.coordinator.accessibilityGranted
                    )
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding(32)
        .frame(width: 640)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            guard !runtime.preferences.onboardingComplete else {
                dismissWindow(id: "onboarding")
                return
            }
            apiKey = ""
            runtime.coordinator.refreshPermissions()
            if runtime.coordinator.microphoneGranted { runtime.coordinator.startMicrophoneTest() }
        }
        .onDisappear { runtime.coordinator.stopMicrophoneTest() }
        .onChange(of: runtime.coordinator.microphoneGranted) { _, allowed in
            if allowed {
                runtime.coordinator.startMicrophoneTest()
            } else {
                runtime.coordinator.stopMicrophoneTest()
            }
        }
        .onChange(of: runtime.preferences.audioInputSelection) { _, _ in
            if runtime.coordinator.microphoneGranted { runtime.coordinator.startMicrophoneTest() }
        }
        .onChange(of: apiKey) { _, newValue in
            if !newValue.isEmpty { keyFeedback = nil }
        }
    }

    private var canSubmitAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCheckingAPIKey
    }

    private func submitAPIKey() {
        guard canSubmitAPIKey else { return }
        Task { await saveKey() }
    }

    private func finish() {
        runtime.coordinator.stopMicrophoneTest()
        if runtime.preferences.launchAtLoginRequested {
            do { try runtime.coordinator.setLaunchAtLogin(true) }
            catch { self.error = "Setup finished, but Launch at Login could not be enabled: \(error.localizedDescription)" }
        }
        runtime.preferences.onboardingComplete = true
        runtime.coordinator.startServices()
        dismissWindow(id: "onboarding")
        Task { @MainActor in
            // Let the onboarding window finish closing before restoring the
            // already-created main window to its default Dictation destination.
            await Task.yield()
            runtime.coordinator.openMainWindow()
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
            error = nil
        } catch {
            keyFeedback = .failed(error.localizedDescription)
        }
    }
}

// Both permission rows offer one button with one word, whatever macOS has recorded
// so far. The steps behind it — a system prompt, a trip to System Settings, or both —
// are Scriber's problem, not something to spell out in a changing button title.
private struct MicrophonePermissionButton: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        if !runtime.coordinator.microphoneGranted {
            Button("Allow") { Task { await runtime.coordinator.allowMicrophone() } }
        }
    }
}

private struct AccessibilityPermissionButton: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        if !runtime.coordinator.accessibilityGranted {
            Button("Allow") { runtime.coordinator.allowAccessibility() }
        }
    }
}

private struct PermissionLabel: View {
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

private struct MicrophonePicker: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        Picker("Input", selection: $runtime.preferences.audioInputSelection) {
            Text("Automatic (System Default)")
                .tag(AudioInputSelection.automatic)
            ForEach(runtime.coordinator.audioInputDevices) { device in
                Text(device.isBuiltIn ? "\(device.name) (Built-in)" : device.name)
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
