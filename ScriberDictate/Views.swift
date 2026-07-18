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
    @State private var section: MainSection = .history

    var body: some View {
        TabView(selection: $section) {
            HistoryView().tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(MainSection.history)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(MainSection.settings)
        }
        .frame(minWidth: 760, minHeight: 520)
        .sheet(isPresented: Binding(
            get: { !runtime.preferences.onboardingComplete },
            set: { _ in }
        )) {
            OnboardingView().interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showScriberDictateSettings)) { _ in section = .settings }
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
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
        WindowOpenBridge()
            .frame(width: 0, height: 0)
            .onAppear {
                runtime.coordinator.startServices()
                if !runtime.preferences.onboardingComplete { openMain(section: .history) }
            }
    }

    private func openMain(section: MainSection) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        if section == .settings {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showScriberDictateSettings, object: nil)
            }
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

private struct WindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .openScriberDictateMainWindow)) { _ in
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @State private var selection: UUID?
    @State private var search = ""
    @State private var confirmClear = false

    private var filtered: [DictationRecord] {
        guard !search.isEmpty else { return records }
        return records.filter { ($0.text ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.text?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80) ?? "Failed dictation")
                        .lineLimit(2)
                    HStack {
                        Text(record.createdAt, style: .relative)
                        Text("·")
                        Text(record.durationSeconds.formatted(.number.precision(.fractionLength(1))) + "s")
                        if record.transcriptionState == .failed {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .tag(record.id)
                .contextMenu {
                    if record.text != nil { Button("Copy") { runtime.coordinator.copy(record) } }
                    if record.transcriptionState == .failed, record.pendingAudioRelativePath != nil {
                        Button("Retry") { runtime.coordinator.retry(record) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { runtime.coordinator.delete(record) }
                }
            }
            .searchable(text: $search, prompt: "Search dictations")
            .navigationTitle("History")
            .toolbar {
                Button("Clear", role: .destructive) { confirmClear = true }.disabled(records.isEmpty)
            }
        } detail: {
            if let record = records.first(where: { $0.id == selection }) {
                DictationDetailView(record: record)
            } else {
                ContentUnavailableView("Select a Dictation", systemImage: "waveform")
            }
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { runtime.coordinator.clearHistory(records) }
        } message: {
            Text("This permanently removes transcripts and any retained failed recordings.")
        }
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
                LabeledContent("Microphone", value: runtime.coordinator.microphoneGranted ? "Allowed" : "Required")
                LabeledContent("Accessibility", value: runtime.coordinator.accessibilityGranted ? "Allowed" : "Required")
                HStack {
                    Button("Request Microphone") { Task { await runtime.coordinator.requestMicrophone() } }
                    Button("Open Accessibility Prompt") { runtime.coordinator.refreshPermissions(promptForAccessibility: true) }
                    Button("Check Again") { runtime.coordinator.refreshPermissions(promptForAccessibility: false) }
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
        .padding()
        .onAppear { apiKey = runtime.coordinator.loadAPIKey() }
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
            GroupBox("2. Permissions") {
                HStack {
                    Label(runtime.coordinator.microphoneGranted ? "Microphone allowed" : "Microphone required", systemImage: runtime.coordinator.microphoneGranted ? "checkmark.circle.fill" : "mic")
                    Spacer()
                    Button("Allow") { Task { await runtime.coordinator.requestMicrophone() } }
                }
                HStack {
                    Label(runtime.coordinator.accessibilityGranted ? "Accessibility allowed" : "Accessibility required", systemImage: runtime.coordinator.accessibilityGranted ? "checkmark.circle.fill" : "keyboard")
                    Spacer()
                    Button("Allow") { runtime.coordinator.refreshPermissions(promptForAccessibility: true) }
                    Button("Check Again") { runtime.coordinator.refreshPermissions(promptForAccessibility: false) }
                }
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
        .frame(width: 560)
        .onAppear { apiKey = runtime.coordinator.loadAPIKey() }
        .onChange(of: apiKey) { _, _ in keyFeedback = nil }
    }

    private func finish() {
        if runtime.preferences.launchAtLoginRequested {
            do { try runtime.coordinator.setLaunchAtLogin(true) }
            catch { self.error = "Setup finished, but Launch at Login could not be enabled: \(error.localizedDescription)" }
        }
        runtime.preferences.onboardingComplete = true
        runtime.coordinator.startServices()
    }
}
