import AppKit
import ServiceManagement
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

enum MainSection: Hashable { case dictation, settings }

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

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime
    @State private var section: MainSection? = .dictation
    @FocusState private var sidebarFocused: Bool
    @FocusState private var dictationSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Dictation", systemImage: "clock.arrow.circlepath")
                    .tag(MainSection.dictation)
                    .accessibilityIdentifier("sidebar-dictation")
                Label("Settings", systemImage: "gearshape")
                    .tag(MainSection.settings)
                    .accessibilityIdentifier("sidebar-settings")
            }
            .accessibilityIdentifier("main-sidebar")
            .navigationTitle("Scriber")
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
            .focused($sidebarFocused)
        } detail: {
            Group {
                switch section ?? .dictation {
                case .dictation: DictationHistoryView(searchFocused: $dictationSearchFocused)
                case .settings:
                    SettingsView(
                        onShortcutConfigurationCaptureChanged: runtime.coordinator.setShortcutConfigurationCaptureActive
                    )
                }
            }
            .navigationTitle(section == .settings ? "Settings" : "Dictation")
        }
        .frame(minWidth: 760, minHeight: 520)
        .focusedSceneValue(\.searchDictationHistoryAction, focusDictationSearch)
        .onAppear {
            applyMainWindowRequest(runtime.coordinator.mainWindowRequest)
            openOnboardingIfNeeded()
            focusSidebarIfAppropriate()
        }
        .onChange(of: runtime.preferences.onboardingComplete) { _, _ in openOnboardingIfNeeded() }
        .onChange(of: runtime.coordinator.mainWindowRequest) { _, request in
            applyMainWindowRequest(request)
        }
    }

    private func applyMainWindowRequest(_ request: MainWindowRequest?) {
        guard let request else { return }
        section = request.destination == .dictation ? .dictation : .settings
    }

    private func focusSidebarIfAppropriate() {
        switch runtime.coordinator.mainWindowRequest?.destination {
        case .apiKey, .usage:
            return
        case .dictation, .settings, nil:
            DispatchQueue.main.async { sidebarFocused = true }
        }
    }

    private func focusDictationSearch() {
        section = .dictation
        DispatchQueue.main.async { dictationSearchFocused = true }
    }

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
                    Button { openMain(destination: .settings) } label: {
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
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

}

struct DictationHistoryView: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    let searchFocused: FocusState<Bool>.Binding
    @State private var search = ""
    @State private var confirmClear = false

    private var filtered: [DictationRecord] {
        guard !search.isEmpty else { return records }
        return records.filter { ($0.text ?? "").localizedCaseInsensitiveContains(search) }
    }

    private var sections: [DictationHistorySection] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { date in
            DictationHistorySection(date: date, records: grouped[date] ?? [])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(records.count) \(records.count == 1 ? "dictation" : "dictations")")
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Clear Dictation History…", role: .destructive) { confirmClear = true }
                        .disabled(records.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Dictation history actions")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            if runtime.preferences.onboardingComplete {
                if !runtime.coordinator.permissionReadiness.isReady {
                    RecoveryBanner(
                        title: "Dictation is unavailable",
                        message: runtime.coordinator.permissionReadiness.recoveryMessage,
                        actionTitle: "Review Permissions",
                        identifier: "permission-recovery-banner"
                    ) {
                        runtime.coordinator.selectMainWindowDestination(.settings)
                    }
                    Divider()
                }
                // Setup can complete and then stop being sufficient. A revoked or
                // replaced key leaves Scriber silently non-functional otherwise.
                let credentials = runtime.coordinator.credentialReadiness
                if !credentials.isReady {
                    RecoveryBanner(
                        title: credentials.title,
                        message: credentials.recoveryMessage,
                        actionTitle: credentials.resolvesInUsageSettings ? "View Usage" : "Update Key",
                        identifier: "credential-recovery-banner"
                    ) {
                        runtime.coordinator.selectMainWindowDestination(
                            credentials.resolvesInUsageSettings ? .usage : .apiKey
                        )
                    }
                    Divider()
                }
            }

            if records.isEmpty {
                ContentUnavailableView(
                    "No Dictations Yet",
                    systemImage: "waveform",
                    description: Text("Your completed dictations and retryable failures will appear here.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.records) { record in
                                DictationHistoryRow(record: record)
                                    .contextMenu {
                                        if let text = record.text, !text.isEmpty {
                                            Button("Copy") { runtime.coordinator.copy(record) }
                                        }
                                        if record.isRetryable, record.pendingAudioRelativePath != nil {
                                            Button("Retry") { runtime.coordinator.retry(record) }
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) { runtime.coordinator.delete(record) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("dictation-history-view")
        .searchable(text: $search, prompt: "Search past transcripts")
        .searchFocused(searchFocused)
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { runtime.coordinator.clearDictationHistory(records) }
        } message: {
            Text("This permanently removes transcripts and any retained failed recordings.")
        }
    }
}

private struct RecoveryBanner: View {
    let title: String
    let message: String
    let actionTitle: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .accessibilityIdentifier(identifier)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        .padding(16)
    }
}

private struct DictationHistorySection: Identifiable {
    let date: Date
    let records: [DictationRecord]

    var id: Date { date }

    var title: String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct DictationHistoryRow: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Bindable var record: DictationRecord

    private var isRetrying: Bool {
        runtime.coordinator.retryingRecordID == record.id
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(rowText)
                    .lineLimit(4)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(record.durationSeconds.formatted(.number.precision(.fractionLength(1))) + "s")
                    if isRetrying {
                        Label("Retrying", systemImage: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                    } else if record.transcriptionState == .cancelled {
                        Label("Cancelled", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.orange)
                    } else if record.transcriptionState == .failed {
                        Label("Failed", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let text = record.text, !text.isEmpty {
                Button { runtime.coordinator.copy(record) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy transcription")
            }
            if isRetrying {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 48)
            } else if record.isRetryable, record.pendingAudioRelativePath != nil {
                Button("Retry") { runtime.coordinator.retry(record) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(runtime.coordinator.phase.isBusy)
            }
            Menu {
                Button("Delete", role: .destructive) { runtime.coordinator.delete(record) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.vertical, 8)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var rowText: String {
        if let text = record.text, !text.isEmpty { return text }
        return record.errorMessage ?? "Transcription failed."
    }
}

private extension DictationRecord {
    var isRetryable: Bool {
        transcriptionState == .failed || transcriptionState == .cancelled
    }
}

private struct DictationDetailView: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Bindable var record: DictationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                    Text(metadata).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let text = record.text {
                    Button("Copy") { runtime.coordinator.copy(record) }
                        .disabled(text.isEmpty)
                }
                if record.isRetryable, record.pendingAudioRelativePath != nil {
                    Button("Retry") { runtime.coordinator.retry(record) }.buttonStyle(.borderedProminent)
                }
                Button("Delete", role: .destructive) { runtime.coordinator.delete(record) }
            }
            Divider()
            if let text = record.text {
                ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                ContentUnavailableView("No Transcript", systemImage: "exclamationmark.waveform", description: Text(record.errorMessage ?? "Transcription did not complete."))
            }
        }
        .padding(24)
    }

    private var metadata: String {
        var parts = [record.durationSeconds.formatted(.number.precision(.fractionLength(1))) + " seconds"]
        if let language = record.detectedLanguageCode { parts.append(language.uppercased()) }
        parts.append(record.deliveryStateRaw.replacingOccurrences(of: "Failed", with: " failed"))
        return parts.joined(separator: " · ")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var runtime: AppRuntime
    let onShortcutConfigurationCaptureChanged: (Bool) -> Void
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

    var body: some View {
        ScrollViewReader { proxy in
            Form {
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
                    }
                }
                subscriptionUsageView
                    .id(MainWindowDestination.usage)
                Picker("Language", selection: $runtime.preferences.languageCode) {
                    Text("Automatic").tag("auto")
                    Text("English").tag("en")
                    Text("Indonesian").tag("id")
                }
                Toggle("Remove filler words and false starts", isOn: $runtime.preferences.noVerbatim)
            }
            Section("Shortcuts") {
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
            Section("Dictation History") {
                Toggle(
                    "Delete unused recordings after 30 days",
                    isOn: $runtime.preferences.deletesExpiredRetainedAudio
                )
                .accessibilityIdentifier("delete-expired-audio-toggle")
                Text("Failed and cancelled dictations keep their audio so you can retry them. Transcripts and history entries are always kept; only the unused recording is removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Personal Dictionary") {
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
            Section("Permissions and Startup") {
                PermissionStatusRow(
                    title: "Microphone",
                    systemImage: "mic",
                    allowed: runtime.coordinator.microphoneGranted
                ) {
                    microphonePermissionButton
                }
                MicrophonePicker()

                PermissionStatusRow(
                    title: "Accessibility",
                    systemImage: "keyboard",
                    allowed: runtime.coordinator.accessibilityGranted
                ) {
                    if !runtime.coordinator.accessibilityGranted {
                        Button("Allow") { runtime.coordinator.refreshPermissions(promptForAccessibility: true) }
                    }
                }
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
            }
            if let message { Text(message).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("settings-view")
            .padding()
            .onAppear {
                apiKey = ""
                runtime.coordinator.refreshPermissions(promptForAccessibility: false)
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
    }

    private var canSubmitAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCheckingAPIKey
    }

    private func submitAPIKey() {
        guard canSubmitAPIKey else { return }
        Task { await saveKey() }
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
            if let usage = runtime.preferences.subscriptionUsage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("ElevenLabs credits", systemImage: "gauge.with.dots.needle.33percent")
                        Spacer()
                        Text("\(usage.remainingCredits.formatted()) of \(usage.totalCredits.formatted()) remaining")
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(usage.remainingCredits), total: Double(max(usage.totalCredits, 1)))
                        .tint(usage.remainingCredits == 0 ? .orange : .accentColor)
                    HStack {
                        Text(usage.tier.capitalized + " plan")
                        if let resetAt = usage.resetAt {
                            Text("· Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))")
                        }
                        Text("· Updated \(usage.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        Spacer()
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if usage.remainingCredits == 0, usage.canExtendCredits {
                        Text("Included credits are depleted, but ElevenLabs reports that extended usage is available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if runtime.coordinator.subscriptionUsageUnavailable {
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

    @ViewBuilder private var microphonePermissionButton: some View {
        if !runtime.coordinator.microphoneGranted {
            switch runtime.coordinator.microphonePermissionState {
            case .notDetermined:
                Button("Allow") { Task { await runtime.coordinator.requestMicrophone() } }
            case .denied:
                Button("Open Settings") { runtime.coordinator.openMicrophoneSettings() }
            case .allowed:
                EmptyView()
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var runtime: AppRuntime
    @State private var apiKey = ""
    @State private var keyFeedback: KeySaveFeedback?
    @State private var isCheckingAPIKey = false
    @State private var error: String?

    var body: some View {
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
                        microphonePermissionButton
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
                        if !runtime.coordinator.accessibilityGranted {
                            Button("Allow") { runtime.coordinator.refreshPermissions(promptForAccessibility: true) }
                        }
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
        .onAppear {
            guard !runtime.preferences.onboardingComplete else {
                dismissWindow(id: "onboarding")
                return
            }
            apiKey = ""
            runtime.coordinator.refreshPermissions(promptForAccessibility: false)
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

    @ViewBuilder private var microphonePermissionButton: some View {
        if !runtime.coordinator.microphoneGranted {
            switch runtime.coordinator.microphonePermissionState {
            case .notDetermined:
                Button("Allow") { Task { await runtime.coordinator.requestMicrophone() } }
            case .denied:
                Button("Open Settings") { runtime.coordinator.openMicrophoneSettings() }
            case .allowed:
                EmptyView()
            }
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
