import AppKit
@preconcurrency import AVFoundation
import Combine
import Foundation
import SwiftData
#if SWIFT_PACKAGE
import ScriberDictateCore
#endif

extension Notification.Name {
    static let openScriberDictateMainWindow = Notification.Name("openScriberDictateMainWindow")
    static let showScriberDictateHistory = Notification.Name("showScriberDictateHistory")
    static let showScriberDictateSettings = Notification.Name("showScriberDictateSettings")
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var phase: AppPhase = .idle
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var microphoneGranted = AudioRecorder.microphoneAuthorized
    @Published private(set) var microphonePermissionState = AudioRecorder.microphonePermissionState
    @Published private(set) var audioInputDevices = AudioRecorder.availableInputDevices()
    @Published private(set) var microphoneTestLevel: Float = -160
    @Published private(set) var microphoneTestError: String?
    @Published private(set) var shortcutMonitorAvailable = false

    let preferences: Preferences
    let modelContext: ModelContext

    private let keychain = KeychainStore()
    private let recorder = AudioRecorder()
    private let scribe = ScribeClient()
    private let paste = PasteService()
    private let login = LaunchAtLoginService()
    private let pill = PillController()
    private let shortcuts: GlobalShortcutService
    private var meterTask: Task<Void, Never>?
    private var microphoneTestTask: Task<Void, Never>?
    private var currentRecord: DictationRecord?
    private var currentRecording: CompletedRecording?
    private var cancellables = Set<AnyCancellable>()

    init(preferences: Preferences, modelContext: ModelContext) {
        self.preferences = preferences
        self.modelContext = modelContext
        shortcuts = GlobalShortcutService(hold: preferences.holdShortcut, toggle: preferences.toggleShortcut)

        shortcuts.onAction = { [weak self] action in self?.handle(action) }
        shortcuts.onAvailabilityChanged = { [weak self] value in self?.shortcutMonitorAvailable = value }
        pill.model.onCopy = { [weak self] in self?.copyCurrentResult() }
        pill.model.onOpen = { [weak self] in self?.openMainWindow() }
        pill.model.onRetry = { [weak self] in self?.retryCurrentFailure() }
        pill.model.onDismiss = { [weak self] in self?.returnToIdle() }

        Publishers.CombineLatest(preferences.$holdShortcut, preferences.$toggleShortcut)
            .sink { [weak self] hold, toggle in self?.shortcuts.update(hold: hold, toggle: toggle) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshPermissions(promptForAccessibility: false) }
            }
            .store(in: &cancellables)

        Publishers.Merge(
            NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification),
            NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)
        )
        .sink { [weak self] _ in
            Task { @MainActor in self?.refreshAudioInputDevices() }
        }
        .store(in: &cancellables)

        recoverInterruptedRecords()
        refreshPermissions(promptForAccessibility: false)
    }

    var statusText: String {
        switch phase {
        case .idle: shortcutMonitorAvailable ? "Ready" : "Shortcut access needed"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .pasted: "Pasted"
        case .dictationCopied: "Copied"
        case .pasteFailed: "Paste failed"
        case .transcriptionFailed: "Transcription failed"
        case .message(let value): value
        }
    }

    func startServices() {
        refreshPermissions(promptForAccessibility: false)
        shortcuts.start()
    }

    func refreshPermissions(promptForAccessibility: Bool) {
        if promptForAccessibility { shortcuts.requestAccessibility() }
        accessibilityGranted = AXIsProcessTrusted()
        microphoneGranted = AudioRecorder.microphoneAuthorized
        microphonePermissionState = AudioRecorder.microphonePermissionState
        refreshAudioInputDevices()
        if accessibilityGranted { shortcuts.start() }
    }

    func requestMicrophone() async {
        microphoneGranted = await AudioRecorder.requestMicrophoneAccess()
        microphonePermissionState = AudioRecorder.microphonePermissionState
        refreshAudioInputDevices()
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    func startMicrophoneTest() {
        guard microphoneGranted, !phase.isBusy else { return }
        stopMicrophoneTest()
        do {
            try recorder.startMonitoring(selection: preferences.audioInputSelection)
            microphoneTestError = nil
            microphoneTestLevel = -160
            microphoneTestTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    microphoneTestLevel = recorder.updateMeter()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        } catch {
            microphoneTestError = error.localizedDescription
            microphoneTestLevel = -160
        }
    }

    func stopMicrophoneTest() {
        microphoneTestTask?.cancel()
        microphoneTestTask = nil
        recorder.stopMonitoring()
        microphoneTestLevel = -160
    }

    func refreshAudioInputDevices() {
        let shouldRestartTest = microphoneTestTask != nil
        audioInputDevices = AudioRecorder.availableInputDevices()
        if shouldRestartTest { startMicrophoneTest() }
    }

    func saveAPIKey(_ value: String) throws {
        try keychain.saveAPIKey(value)
        preferences.apiKeyConfigured = !(try keychain.readAPIKey() ?? "").isEmpty
    }

    func loadAPIKey() -> String {
        (try? keychain.readAPIKey()) ?? ""
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        try login.setEnabled(enabled)
        preferences.launchAtLoginRequested = enabled
    }

    func handle(_ action: ShortcutAction) {
        switch action {
        case .holdPressed:
            switch phase {
            case .idle, .message, .pasted, .dictationCopied, .pasteFailed, .transcriptionFailed:
                startRecording(mode: .held)
            case .recording(let mode, _, _) where mode == .locked:
                stopAndTranscribe()
            case .transcribing:
                showTransientMessage("Still transcribing")
            default:
                break
            }
        case .holdReleased:
            if case .recording(let mode, _, _) = phase, mode == .held { stopAndTranscribe() }
        case .togglePressed:
            switch phase {
            case .idle, .message, .pasted, .dictationCopied, .pasteFailed, .transcriptionFailed:
                startRecording(mode: .locked)
            case .recording(let mode, let elapsed, let level) where mode == .held:
                shortcuts.setMode(.locked)
                setPhase(.recording(mode: .locked, elapsed: elapsed, level: level))
            case .recording(let mode, _, _) where mode == .locked:
                stopAndTranscribe()
            case .transcribing:
                showTransientMessage("Still transcribing")
            default:
                break
            }
        case .cancel:
            if case .recording = phase { cancelRecording() }
        }
    }

    func startHandsFreeFromMenu() {
        switch phase {
        case .idle, .message, .pasted, .dictationCopied, .pasteFailed, .transcriptionFailed:
            startRecording(mode: .locked)
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            showTransientMessage("Still transcribing")
        }
    }

    func retry(_ record: DictationRecord) {
        guard !phase.isBusy,
              record.transcriptionState == .failed,
              let relativePath = record.pendingAudioRelativePath,
              let url = try? AudioRecorder.url(for: relativePath),
              FileManager.default.fileExists(atPath: url.path) else {
            showMessage("No retryable recording")
            return
        }
        currentRecord = record
        currentRecording = CompletedRecording(
            id: record.id,
            url: url,
            relativePath: relativePath,
            duration: record.durationSeconds,
            maximumPeakLevel: 0
        )
        record.transcriptionState = .transcribing
        record.errorMessage = nil
        try? modelContext.save()
        shortcuts.setMode(.busy)
        Task { await transcribeCurrentRecord(attemptDelivery: false) }
    }

    func copy(_ record: DictationRecord) {
        guard let text = record.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        record.deliveryState = .copied
        try? modelContext.save()
    }

    func delete(_ record: DictationRecord) {
        if let path = record.pendingAudioRelativePath { AudioRecorder.delete(relativePath: path) }
        if currentRecord?.id == record.id { currentRecord = nil; currentRecording = nil }
        modelContext.delete(record)
        try? modelContext.save()
    }

    func clearHistory(_ records: [DictationRecord]) {
        for record in records { delete(record) }
    }

    func openMainWindow() {
        NotificationCenter.default.post(name: .openScriberDictateMainWindow, object: nil)
        NotificationCenter.default.post(name: .showScriberDictateHistory, object: nil)
    }

    private func startRecording(mode: RecordingMode) {
        guard accessibilityGranted else {
            showFailure("Accessibility permission is required.", transcription: false)
            return
        }
        guard microphoneGranted else {
            showFailure("Microphone permission is required.", transcription: true)
            return
        }
        guard preferences.apiKeyConfigured else {
            showFailure("Add an ElevenLabs API key in Settings.", transcription: true)
            return
        }
        do {
            stopMicrophoneTest()
            pill.setPreferredScreen(paste.captureTarget())
            try recorder.start(selection: preferences.audioInputSelection)
            shortcuts.setMode(mode == .held ? .held : .locked)
            setPhase(.recording(mode: mode, elapsed: 0, level: -80))
            startMeter(mode: mode)
        } catch AudioRecorderError.inputUnavailable(let name) {
            showMessage("Microphone “\(name)” is unavailable")
        } catch {
            showFailure(error.localizedDescription, transcription: true)
        }
    }

    private func startMeter(mode: RecordingMode) {
        meterTask?.cancel()
        let startedAt = Date.now
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = Date.now.timeIntervalSince(startedAt)
                let level = recorder.updateMeter()
                let currentMode: RecordingMode
                if case .recording(let value, _, _) = phase { currentMode = value } else { return }
                setPhase(.recording(mode: currentMode, elapsed: elapsed, level: level))
                if elapsed >= 600 { stopAndTranscribe(); return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopAndTranscribe() {
        meterTask?.cancel()
        meterTask = nil
        shortcuts.setMode(.busy)
        Task { [weak self] in
            guard let self else { return }
            do {
                let completed = try await recorder.stop()
                finishRecording(completed)
            } catch {
                shortcuts.setMode(.idle)
                showFailure(error.localizedDescription, transcription: true)
            }
        }
    }

    private func finishRecording(_ completed: CompletedRecording) {
        do {
            guard completed.detectedSignal else {
                AudioRecorder.delete(relativePath: completed.relativePath)
                returnToIdle()
                return
            }
            guard completed.duration >= 0.1 else {
                AudioRecorder.delete(relativePath: completed.relativePath)
                paste.clearTarget()
                shortcuts.setMode(.idle)
                showMessage("Hold a little longer")
                return
            }
            let record = DictationRecord(
                id: completed.id,
                durationSeconds: completed.duration,
                pendingAudioRelativePath: completed.relativePath
            )
            modelContext.insert(record)
            try modelContext.save()
            currentRecord = record
            currentRecording = completed
            shortcuts.setMode(.busy)
            Task { await transcribeCurrentRecord(attemptDelivery: true) }
        } catch {
            shortcuts.setMode(.idle)
            showFailure(error.localizedDescription, transcription: true)
        }
    }

    private func transcribeCurrentRecord(attemptDelivery: Bool) async {
        guard let record = currentRecord, let recording = currentRecording else { returnToIdle(); return }
        do {
            guard let apiKey = try keychain.readAPIKey(), !apiKey.isEmpty else { throw ScribeError.authentication }
            let request = ScribeRequest(
                audioURL: recording.url,
                apiKey: apiKey,
                languageCode: preferences.languageCode,
                noVerbatim: preferences.noVerbatim,
                keyterms: preferences.keyterms
            )
            let result = try await scribe.transcribe(request) { [weak self] attempt, delay in
                await MainActor.run { self?.setPhase(.transcribing(attempt: attempt, retryDelay: delay)) }
            }
            guard let transcript = TranscriptContent.normalized(result.text) else {
                discardNoContent(record: record, recording: recording)
                return
            }

            record.text = transcript
            record.detectedLanguageCode = result.languageCode
            record.transcriptionState = .succeeded
            record.errorMessage = nil
            try modelContext.save()

            AudioRecorder.delete(relativePath: recording.relativePath)
            record.pendingAudioRelativePath = nil
            try modelContext.save()

            if attemptDelivery {
                let delivery = await paste.insert(transcript)
                switch delivery {
                case .inserted:
                    record.deliveryState = .pasted
                    try modelContext.save()
                    setPhase(.pasted)
                case .noEditableTarget(let message):
                    copy(record)
                    record.errorMessage = message
                    try modelContext.save()
                    setPhase(.dictationCopied(text: transcript, message: message))
                case .failed(let message):
                    record.deliveryState = .pasteFailed
                    record.errorMessage = message
                    try modelContext.save()
                    setPhase(.pasteFailed(message))
                }
            } else {
                record.deliveryState = .notAttempted
                try modelContext.save()
                setPhase(.message("Transcription ready in History"))
            }
        } catch {
            record.transcriptionState = .failed
            record.errorMessage = error.localizedDescription
            try? modelContext.save()
            setPhase(.transcriptionFailed(error.localizedDescription))
        }
        shortcuts.setMode(.idle)
    }

    private func discardNoContent(record: DictationRecord, recording: CompletedRecording) {
        AudioRecorder.delete(relativePath: recording.relativePath)
        modelContext.delete(record)
        try? modelContext.save()
        currentRecord = nil
        currentRecording = nil
        returnToIdle()
    }

    private func cancelRecording() {
        meterTask?.cancel()
        meterTask = nil
        recorder.cancel()
        paste.clearTarget()
        shortcuts.setMode(.idle)
        showMessage("Cancelled")
    }

    private func retryCurrentFailure() {
        guard let currentRecord else { return }
        retry(currentRecord)
    }

    private func copyCurrentResult() {
        guard let currentRecord else { return }
        copy(currentRecord)
        setPhase(.message("Copied"))
    }

    private func showFailure(_ message: String, transcription: Bool) {
        shortcuts.setMode(.idle)
        setPhase(transcription ? .transcriptionFailed(message) : .pasteFailed(message))
    }

    private func showMessage(_ message: String) {
        setPhase(.message(message))
    }

    private func showTransientMessage(_ message: String) {
        let retainedPhase = phase
        pill.update(.message(message))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.phase == retainedPhase else { return }
            self.pill.update(retainedPhase)
        }
    }

    private func returnToIdle() {
        paste.clearTarget()
        pill.setPreferredScreen(nil)
        shortcuts.setMode(.idle)
        setPhase(.idle)
    }

    private func setPhase(_ phase: AppPhase) {
        self.phase = phase
        pill.update(phase)
    }

    private func recoverInterruptedRecords() {
        guard let records = try? modelContext.fetch(FetchDescriptor<DictationRecord>()) else { return }
        for record in records where record.transcriptionState == .transcribing {
            record.transcriptionState = .failed
            record.errorMessage = record.pendingAudioRelativePath == nil
                ? "The app stopped before this dictation completed, and no retryable audio remains."
                : "The app stopped before this dictation completed. Retry when ready."
        }
        try? modelContext.save()
    }
}
