import AppKit
import ServiceManagement
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberDictateCore
#endif

enum MainSection: Hashable { case history, settings }

private enum KeySaveFeedback {
    case saved
    case failed(String)

    var message: String {
        switch self {
        case .saved: "Saved securely in Keychain. Your first transcription will verify it with ElevenLabs."
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
    @EnvironmentObject private var runtime: AppRuntime
    @State private var section: MainSection? = .history

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .tag(MainSection.history)
                Label("Settings", systemImage: "gearshape")
                    .tag(MainSection.settings)
            }
            .navigationTitle("Scriber Dictate")
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
        } detail: {
            switch section ?? .history {
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .sheet(isPresented: Binding(
            get: { !runtime.preferences.onboardingComplete },
            set: { _ in }
        )) {
            OnboardingView().interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showScriberDictateHistory)) { _ in section = .history }
        .onReceive(NotificationCenter.default.publisher(for: .showScriberDictateSettings)) { _ in section = .settings }
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        Group {
            Text(runtime.coordinator.statusText).foregroundStyle(.secondary)
            Divider()
            Button(menuDictationTitle) {
                runtime.coordinator.startHandsFreeFromMenu()
            }
            Button("Open History") { openMain(section: .history) }
            Button("Settings…") { openMain(section: .settings) }
            Divider()
            Text("Hold: \(runtime.preferences.holdShortcut.displayName)")
            Text("Toggle: \(runtime.preferences.toggleShortcut.displayName)")
            Divider()
            Button("Quit Scriber Dictate") { NSApp.terminate(nil) }
        }
        .onAppear {
            runtime.coordinator.startServices()
            if !runtime.preferences.onboardingComplete { openMain(section: .history) }
        }
    }

    private func openMain(section: MainSection) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: section == .history ? .showScriberDictateHistory : .showScriberDictateSettings,
                object: nil
            )
        }
    }

    private var menuDictationTitle: String {
        switch runtime.coordinator.phase {
        case .recording: "Stop Dictation"
        case .transcribing: "Still Transcribing…"
        default: "Start Hands-Free Dictation"
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @State private var search = ""
    @State private var confirmClear = false

    private var filtered: [DictationRecord] {
        guard !search.isEmpty else { return records }
        return records.filter { ($0.text ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("History").font(.largeTitle.bold())
                    Text("\(records.count) \(records.count == 1 ? "dictation" : "dictations")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .disabled(records.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("History actions")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            if records.isEmpty {
                ContentUnavailableView(
                    "No Dictations Yet",
                    systemImage: "waveform",
                    description: Text("Your completed dictations and retryable failures will appear here.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(filtered) { record in
                    HistoryRow(record: record)
                        .contextMenu {
                            if let text = record.text, !text.isEmpty {
                                Button("Copy") { runtime.coordinator.copy(record) }
                            }
                            if record.transcriptionState == .failed, record.pendingAudioRelativePath != nil {
                                Button("Retry") { runtime.coordinator.retry(record) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { runtime.coordinator.delete(record) }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("History")
        .searchable(text: $search, prompt: "Search dictations")
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { runtime.coordinator.clearHistory(records) }
        } message: {
            Text("This permanently removes transcripts and any retained failed recordings.")
        }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var runtime: AppRuntime
    let record: DictationRecord

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(rowText)
                    .lineLimit(4)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Text("·")
                    Text(record.durationSeconds.formatted(.number.precision(.fractionLength(1))) + "s")
                    if record.transcriptionState == .failed {
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
            if record.transcriptionState == .failed, record.pendingAudioRelativePath != nil {
                Button("Retry") { runtime.coordinator.retry(record) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
    }

    private var rowText: String {
        if let text = record.text, !text.isEmpty { return text }
        return record.errorMessage ?? "Transcription failed."
    }
}

private struct DictationDetailView: View {
    @EnvironmentObject private var runtime: AppRuntime
    let record: DictationRecord

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
                if record.transcriptionState == .failed, record.pendingAudioRelativePath != nil {
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
    @State private var apiKey = ""
    @State private var keyFeedback: KeySaveFeedback?
    @State private var newKeyterm = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section("ElevenLabs") {
                SecureField("API key", text: $apiKey)
                HStack {
                    Button(runtime.preferences.apiKeyConfigured ? "Update API Key" : "Save API Key") { saveKey() }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if runtime.preferences.apiKeyConfigured { Label("Stored in Keychain", systemImage: "checkmark.shield") }
                }
                if let keyFeedback {
                    Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                        .font(.caption)
                        .foregroundStyle(keyFeedback.color)
                }
                Picker("Language", selection: $runtime.preferences.languageCode) {
                    Text("Automatic").tag("auto")
                    Text("English").tag("en")
                    Text("Indonesian").tag("id")
                }
                Toggle("Remove filler words and false starts", isOn: $runtime.preferences.noVerbatim)
            }
            Section("Shortcuts") {
                ShortcutRecorderView(title: "Hold to Dictate", chord: $runtime.preferences.holdShortcut, conflictingChord: runtime.preferences.toggleShortcut)
                ShortcutRecorderView(title: "Hands-free Toggle", chord: $runtime.preferences.toggleShortcut, conflictingChord: runtime.preferences.holdShortcut)
                Text("Modifier-only chords are supported. Press Escape while recording a binding to cancel.")
                    .font(.caption).foregroundStyle(.secondary)
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
            }
            if let message { Text(message).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .padding()
        .onAppear {
            apiKey = runtime.coordinator.loadAPIKey()
            runtime.coordinator.refreshPermissions(promptForAccessibility: false)
        }
        .onChange(of: apiKey) { _, _ in keyFeedback = nil }
    }

    private func saveKey() {
        do {
            try runtime.coordinator.saveAPIKey(apiKey)
            keyFeedback = .saved
        } catch {
            keyFeedback = .failed(error.localizedDescription)
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
    @EnvironmentObject private var runtime: AppRuntime
    @State private var apiKey = ""
    @State private var keyFeedback: KeySaveFeedback?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Scriber Dictate").font(.largeTitle.bold())
                Text("Hold Fn to dictate. Your audio goes only to ElevenLabs, and your history stays on this Mac.")
                    .foregroundStyle(.secondary)
            }
            GroupBox("1. ElevenLabs API key") {
                SecureField("xi-api-key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(runtime.preferences.apiKeyConfigured ? "Update Key" : "Save Key") {
                        do {
                            try runtime.coordinator.saveAPIKey(apiKey)
                            keyFeedback = .saved
                            error = nil
                        } catch {
                            keyFeedback = .failed(error.localizedDescription)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if runtime.preferences.apiKeyConfigured {
                        Label("Stored in Keychain", systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                    }
                }
                if let keyFeedback {
                    Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                        .font(.caption)
                        .foregroundStyle(keyFeedback.color)
                }
            }
            GroupBox("2. Microphone") {
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
                    VStack(alignment: .leading, spacing: 8) {
                        AudioLevelWaveform(level: runtime.coordinator.microphoneTestLevel)
                            .frame(height: 42)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
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
            GroupBox("3. Accessibility") {
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
                Text("Accessibility lets Scriber Dictate watch global shortcuts and insert text into the app you were using.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Launch Scriber Dictate when I log in", isOn: $runtime.preferences.launchAtLoginRequested)
            Text("Defaults: Hold \(runtime.preferences.holdShortcut.displayName) · Toggle \(runtime.preferences.toggleShortcut.displayName)")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Finish Setup") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!runtime.preferences.apiKeyConfigured || !runtime.coordinator.microphoneGranted || !runtime.coordinator.accessibilityGranted)
            }
        }
        .padding(28)
        .frame(width: 600)
        .onAppear {
            apiKey = runtime.coordinator.loadAPIKey()
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
        .onChange(of: apiKey) { _, _ in keyFeedback = nil }
    }

    private func finish() {
        runtime.coordinator.stopMicrophoneTest()
        if runtime.preferences.launchAtLoginRequested {
            do { try runtime.coordinator.setLaunchAtLogin(true) }
            catch { self.error = "Setup finished, but Launch at Login could not be enabled: \(error.localizedDescription)" }
        }
        runtime.preferences.onboardingComplete = true
        runtime.coordinator.startServices()
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
