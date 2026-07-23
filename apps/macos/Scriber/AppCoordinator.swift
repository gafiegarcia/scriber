import AppKit
@preconcurrency import AVFoundation
import Combine
import Foundation
import SwiftData
#if SWIFT_PACKAGE
import ScriberCore
#endif

extension Notification.Name {
    static let openScriberMainWindow = Notification.Name("openScriberMainWindow")
    static let showAppInDockDidChange = Notification.Name("showAppInDockDidChange")
}

enum MainWindowDestination: Hashable {
    case dictation
    case settings
    case apiKey
    case usage
}

struct MainWindowRequest: Equatable {
    let id = UUID()
    let destination: MainWindowDestination
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
    @Published private(set) var retryingRecordID: UUID?
    @Published private(set) var subscriptionUsageUnavailable = false
    @Published private(set) var isRefreshingSubscriptionUsage = false
    @Published private(set) var subscriptionUsageError: String?
    @Published private(set) var mainWindowRequest: MainWindowRequest?

    let preferences: Preferences
    let modelContext: ModelContext

    private let servicesAllowed: Bool
    private let persistenceAvailable: Bool
    private let permissionReadinessOverride: PermissionReadiness?
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
    private var checkedStoredAPIKeyThisLaunch = false
    private var isCheckingStoredAPIKey = false
    private var storedAPIKeyValidationTask: Task<Void, Never>?
    private var credentialRevision = CredentialRevision()
    private var suppressPillForCurrentTranscription = false
    private var permissionRecoveryPresentationPending = false
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: Preferences,
        modelContext: ModelContext,
        persistenceAvailable: Bool = true,
        permissionReadinessOverride: PermissionReadiness? = nil,
        servicesAllowed: Bool = true
    ) {
        self.preferences = preferences
        self.modelContext = modelContext
        self.persistenceAvailable = persistenceAvailable
        self.permissionReadinessOverride = permissionReadinessOverride
        self.servicesAllowed = servicesAllowed
        shortcuts = GlobalShortcutService(
            hold: preferences.holdShortcut,
            toggle: preferences.toggleShortcut,
            holdEnabled: preferences.holdShortcutEnabled,
            toggleEnabled: preferences.toggleShortcutEnabled
        )

        shortcuts.onAction = { [weak self] action in self?.handle(action) }
        shortcuts.onEscape = { [weak self] in self?.dismissVisiblePill() ?? false }
        shortcuts.onNonModifierKeyDown = { [weak self] in self?.cancelHeldRecordingForTypingIfNeeded() }
        shortcuts.onAvailabilityChanged = { [weak self] value in self?.shortcutMonitorAvailable = value }
        pill.model.onCopy = { [weak self] in self?.copyCurrentResult() }
        pill.model.onOpen = { [weak self] in self?.openMainWindow() }
        pill.model.onOpenAPIKeySettings = { [weak self] in self?.openAPIKeySettings() }
        pill.model.onOpenUsageSettings = { [weak self] in self?.openUsageSettings() }
        pill.model.onOpenPermissionSettings = { [weak self] in self?.openPermissionSettings() }
        pill.model.onRetry = { [weak self] in self?.retryCurrentFailure() }
        pill.model.onUndo = { [weak self] in self?.undoCancelledDictation() }
        pill.model.onDismiss = { [weak self] in _ = self?.dismissVisiblePill() }

        Publishers.CombineLatest4(
            preferences.$holdShortcut,
            preferences.$toggleShortcut,
            preferences.$holdShortcutEnabled,
            preferences.$toggleShortcutEnabled
        )
            .sink { [weak self] hold, toggle, holdEnabled, toggleEnabled in
                self?.shortcuts.update(
                    hold: hold,
                    toggle: toggle,
                    holdEnabled: holdEnabled,
                    toggleEnabled: toggleEnabled
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPermissions(
                        promptForAccessibility: false,
                        presentRecoveryWhenMissing: true,
                        refreshAudioInputs: true
                    )
                }
            }
            .store(in: &cancellables)

        if servicesAllowed {
            Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.refreshPermissions(
                            promptForAccessibility: false,
                            presentRecoveryWhenMissing: false,
                            refreshAudioInputs: false
                        )
                    }
                }
                .store(in: &cancellables)
        }

        Publishers.Merge(
            NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification),
            NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)
        )
        .sink { [weak self] _ in
            Task { @MainActor in self?.refreshAudioInputDevices() }
        }
        .store(in: &cancellables)

        if persistenceAvailable, servicesAllowed { recoverPersistedAndOrphanedRecords() }
        refreshPermissions(promptForAccessibility: false)
    }

    var statusText: String {
        if !preferences.onboardingComplete { return "Setup required" }
        if !persistenceAvailable { return "Dictation history unavailable" }
        if !permissionReadiness.isReady { return "Permissions required" }
        return switch phase {
        case .idle: shortcutMonitorAvailable ? "Ready" : "Shortcut access needed"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .cancelledTranscript: "Cancelled"
        case .dictationCopied: "Copied"
        case .permissionsRequired: "Permissions required"
        case .apiKeyInvalid: "API key invalid"
        case .apiCreditsExhausted: "Credits exhausted"
        case .pasteFailed: "Paste failed"
        case .transcriptionFailed: "Transcription failed"
        case .message(let value): value
        }
    }

    var permissionReadiness: PermissionReadiness {
        PermissionReadiness(
            microphoneGranted: microphoneGranted,
            accessibilityGranted: accessibilityGranted
        )
    }

    func startServices() {
        refreshPermissions(
            promptForAccessibility: false,
            presentRecoveryWhenMissing: true,
            refreshAudioInputs: true
        )
        guard shortcutMonitoringAllowed else {
            shortcuts.stop()
            shortcutMonitorAvailable = false
            return
        }
        guard preferences.onboardingComplete, accessibilityGranted else {
            shortcuts.stop()
            shortcutMonitorAvailable = false
            return
        }
        if servicesAllowed { validateStoredAPIKeyOnce() }
        shortcuts.start()
    }

    func refreshPermissions(promptForAccessibility: Bool) {
        refreshPermissions(
            promptForAccessibility: promptForAccessibility,
            presentRecoveryWhenMissing: false,
            refreshAudioInputs: true
        )
    }

    private func refreshPermissions(
        promptForAccessibility: Bool,
        presentRecoveryWhenMissing: Bool,
        refreshAudioInputs: Bool
    ) {
        let previousReadiness = permissionReadiness
        if promptForAccessibility { shortcuts.requestAccessibility() }
        if let permissionReadinessOverride {
            accessibilityGranted = !permissionReadinessOverride.missingPermissions.contains(.accessibility)
            microphoneGranted = !permissionReadinessOverride.missingPermissions.contains(.microphone)
            microphonePermissionState = microphoneGranted ? .allowed : .denied
        } else {
            accessibilityGranted = AXIsProcessTrusted()
            microphoneGranted = AudioRecorder.microphoneAuthorized
            microphonePermissionState = AudioRecorder.microphonePermissionState
        }
        if refreshAudioInputs { refreshAudioInputDevices() }

        if shortcutMonitoringAllowed, accessibilityGranted, preferences.onboardingComplete {
            if !shortcutMonitorAvailable { shortcuts.start() }
        } else {
            shortcuts.stop()
            shortcutMonitorAvailable = false
        }

        let currentReadiness = permissionReadiness
        if currentReadiness.isReady {
            permissionRecoveryPresentationPending = false
            if case .permissionsRequired = phase { returnToIdle() }
        } else if PermissionRecoveryPolicy.shouldPresent(
            previous: previousReadiness,
            current: currentReadiness,
            onboardingComplete: preferences.onboardingComplete,
            force: presentRecoveryWhenMissing
        ) {
            permissionRecoveryPresentationPending = true
        }
        presentPendingPermissionRecoveryIfPossible()
    }

    private var shortcutMonitoringAllowed: Bool {
#if DEBUG
        servicesAllowed || ProcessInfo.processInfo.arguments.contains("--ui-testing-global-shortcuts")
#else
        servicesAllowed
#endif
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

    func validateAndSaveAPIKey(_ value: String) async throws {
#if DEBUG
        if !servicesAllowed {
            preferences.apiKeyConfigured = true
            preferences.apiKeyValidity = .valid
            preferences.subscriptionUsage = nil
            preferences.apiCreditsExhausted = false
            subscriptionUsageUnavailable = false
            subscriptionUsageError = nil
            clearResolvedCredentialBlock()
            return
        }
#endif
        let result = try await scribe.validateAPIKey(value)
        credentialRevision.advance()
        storedAPIKeyValidationTask?.cancel()
        storedAPIKeyValidationTask = nil
        isCheckingStoredAPIKey = false
        isRefreshingSubscriptionUsage = false
        try keychain.saveAPIKey(value)
        preferences.apiKeyConfigured = true
        preferences.apiKeyValidity = .valid
        preferences.subscriptionUsage = result.subscriptionUsage
        preferences.apiCreditsExhausted = result.subscriptionUsage?.shouldBlockDictation ?? false
        subscriptionUsageUnavailable = result.subscriptionUsageUnavailable
        subscriptionUsageError = result.subscriptionUsageUnavailable
            ? subscriptionUsageUnavailableMessage(accessDenied: result.subscriptionUsageAccessDenied)
            : nil
        clearResolvedCredentialBlock()
    }

    private func validateStoredAPIKeyOnce() {
        guard !checkedStoredAPIKeyThisLaunch else { return }
        checkedStoredAPIKeyThisLaunch = true
        let validationRevision = credentialRevision.current
        isCheckingStoredAPIKey = true
        storedAPIKeyValidationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if credentialRevision.matches(validationRevision) {
                    isCheckingStoredAPIKey = false
                    storedAPIKeyValidationTask = nil
                }
            }
            do {
                guard let apiKey = try keychain.readAPIKey(), !apiKey.isEmpty else {
                    guard !Task.isCancelled, credentialRevision.matches(validationRevision) else { return }
                    preferences.apiKeyConfigured = false
                    preferences.apiKeyValidity = .unchecked
                    return
                }
                guard !Task.isCancelled, credentialRevision.matches(validationRevision) else { return }
                preferences.apiKeyConfigured = true
                let result = try await scribe.validateAPIKey(apiKey)
                guard !Task.isCancelled, credentialRevision.matches(validationRevision) else { return }
                preferences.apiKeyValidity = .valid
                if let usage = result.subscriptionUsage {
                    preferences.subscriptionUsage = usage
                    preferences.apiCreditsExhausted = usage.shouldBlockDictation
                }
                subscriptionUsageUnavailable = result.subscriptionUsageUnavailable
                subscriptionUsageError = result.subscriptionUsageUnavailable
                    ? subscriptionUsageUnavailableMessage(accessDenied: result.subscriptionUsageAccessDenied)
                    : nil
                clearResolvedCredentialBlock()
            } catch let error as ScribeError where error.invalidatesAPIKey {
                guard !Task.isCancelled, credentialRevision.matches(validationRevision) else { return }
                preferences.apiKeyValidity = .invalid
            } catch {
                // Keep the last definitive result when validation cannot reach the service.
            }
        }
    }

    func refreshSubscriptionUsage() async {
        guard !isRefreshingSubscriptionUsage else { return }
        guard let apiKey = try? keychain.readAPIKey(), !apiKey.isEmpty else { return }
        let refreshRevision = credentialRevision.current
        isRefreshingSubscriptionUsage = true
        defer {
            if credentialRevision.matches(refreshRevision) {
                isRefreshingSubscriptionUsage = false
            }
        }
        do {
            let usage = try await scribe.fetchSubscriptionUsage(apiKey)
            guard !Task.isCancelled, credentialRevision.matches(refreshRevision) else { return }
            preferences.subscriptionUsage = usage
            preferences.apiCreditsExhausted = usage.shouldBlockDictation
            subscriptionUsageUnavailable = false
            subscriptionUsageError = nil
            clearResolvedCredentialBlock()
        } catch let error as ScribeError where error.invalidatesAPIKey {
            guard !Task.isCancelled, credentialRevision.matches(refreshRevision) else { return }
            // Subscription access has a separate optional scope. A rejection here
            // does not invalidate Speech-to-Text access that was already verified.
            subscriptionUsageUnavailable = true
            subscriptionUsageError = subscriptionUsageUnavailableMessage(accessDenied: true)
        } catch {
            guard !Task.isCancelled, credentialRevision.matches(refreshRevision) else { return }
            subscriptionUsageUnavailable = true
            subscriptionUsageError = "Credit usage is temporarily unavailable. Try refreshing again."
        }
    }

    private func subscriptionUsageUnavailableMessage(accessDenied: Bool) -> String {
        accessDenied
            ? "This key is scoped for Speech-to-Text but not account usage. Enable User → Read in ElevenLabs to show credits."
            : "Credit usage is temporarily unavailable. Try refreshing again."
    }

    private func clearResolvedCredentialBlock() {
        let resolvedPhase = phase.resolvingCredentialBlock(
            apiKeyConfigured: preferences.apiKeyConfigured,
            apiKeyValidity: preferences.apiKeyValidity,
            apiCreditsExhausted: preferences.apiCreditsExhausted
        )
        if resolvedPhase == .idle, phase != .idle {
            returnToIdle()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        try login.setEnabled(enabled)
        preferences.launchAtLoginRequested = enabled
    }

    func handle(_ action: ShortcutAction) {
        guard preferences.onboardingComplete else { return }
        switch action {
        case .holdPressed:
            switch phase {
            case .idle, .message, .cancelledTranscript, .dictationCopied, .permissionsRequired,
                 .apiKeyInvalid, .apiCreditsExhausted, .pasteFailed, .transcriptionFailed:
                startRecording(mode: .held)
            case .transcribing:
                showTransientMessage("Still transcribing")
            default:
                break
            }
        case .holdReleased:
            if case .recording(let mode, _, _) = phase, mode == .held { stopAndTranscribe() }
        case .togglePressed:
            switch phase {
            case .idle, .message, .cancelledTranscript, .dictationCopied, .permissionsRequired,
                 .apiKeyInvalid, .apiCreditsExhausted, .pasteFailed, .transcriptionFailed:
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
            _ = dismissVisiblePill()
        }
    }

    func startHandsFreeFromMenu() {
        guard preferences.onboardingComplete else { return }
        switch phase {
        case .idle, .message, .cancelledTranscript, .dictationCopied, .permissionsRequired,
             .apiKeyInvalid, .apiCreditsExhausted, .pasteFailed, .transcriptionFailed:
            startRecording(mode: .locked)
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            showTransientMessage("Still transcribing")
        }
    }

    func retry(_ record: DictationRecord) {
        guard preferences.onboardingComplete else { return }
        suppressPillForCurrentTranscription = false
        guard canUseHistoryStorage() else { return }
        guard canUseConfiguredAPIKey() else { return }
        guard !phase.isBusy else {
            showTransientMessage("Already transcribing")
            return
        }
        guard (record.transcriptionState == .failed || record.transcriptionState == .cancelled),
              let relativePath = record.pendingAudioRelativePath else {
            showMessage("This dictation is no longer retryable")
            return
        }
        guard let url = try? AudioRecorder.url(for: relativePath),
              FileManager.default.fileExists(atPath: url.path) else {
            record.pendingAudioRelativePath = nil
            record.errorMessage = "The retained recording is no longer available."
            try? modelContext.save()
            showMessage("Recording unavailable")
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
        retryingRecordID = record.id
        shortcuts.setMode(.busy)
        setPhase(.transcribing(attempt: 1, retryDelay: nil))
        Task { await transcribeCurrentRecord(delivery: .copy) }
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

    func clearDictationHistory(_ records: [DictationRecord]) {
        for record in records { delete(record) }
    }

    func openMainWindow() {
        openMainWindow(destination: .dictation)
    }

    func openAPIKeySettings() {
        openMainWindow(destination: .apiKey)
    }

    func openUsageSettings() {
        openMainWindow(destination: .usage)
    }

    func openPermissionSettings() {
        openMainWindow(destination: .settings)
    }

    func selectMainWindowDestination(_ destination: MainWindowDestination) {
        mainWindowRequest = MainWindowRequest(destination: destination)
    }

    private func openMainWindow(destination: MainWindowDestination) {
        selectMainWindowDestination(destination)
        returnToIdle()
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .openScriberMainWindow, object: nil)
    }

    func presentInvalidAPIKeyPillForUITesting() {
        guard !servicesAllowed else { return }
        setPhase(.apiKeyInvalid)
    }

    func presentPermissionRecoveryPillForUITesting() {
        guard !servicesAllowed else { return }
        permissionRecoveryPresentationPending = true
        presentPendingPermissionRecoveryIfPossible()
    }

    private func startRecording(mode: RecordingMode) {
        guard preferences.onboardingComplete else { return }
        suppressPillForCurrentTranscription = false
        guard canUseHistoryStorage() else { return }
        refreshPermissions(
            promptForAccessibility: false,
            presentRecoveryWhenMissing: false,
            refreshAudioInputs: false
        )
        guard permissionReadiness.isReady else {
            permissionRecoveryPresentationPending = true
            presentPendingPermissionRecoveryIfPossible()
            return
        }
        guard canUseConfiguredAPIKey() else { return }
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
            suppressPillForCurrentTranscription = false
            shortcuts.setMode(.busy)
            Task { await transcribeCurrentRecord(delivery: .automaticPaste) }
        } catch {
            shortcuts.setMode(.idle)
            showFailure(error.localizedDescription, transcription: true)
        }
    }

    private enum RetryDelivery {
        case automaticPaste
        case copy
    }

    private func transcribeCurrentRecord(delivery: RetryDelivery) async {
        guard let record = currentRecord, let recording = currentRecording else { returnToIdle(); return }
        defer {
            retryingRecordID = nil
            shortcuts.setMode(.idle)
        }
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

            if delivery == .automaticPaste {
                let delivery = await paste.insert(transcript)
                switch delivery {
                case .inserted:
                    record.deliveryState = .pasted
                    try modelContext.save()
                    returnToIdle()
                case .noEditableTarget(let message):
                    copy(record)
                    record.errorMessage = message
                    try modelContext.save()
                    setPhase(.dictationCopied(text: transcript, message: message))
                case .failed(let message):
                    copy(record)
                    record.errorMessage = message
                    try modelContext.save()
                    setPhase(.dictationCopied(text: transcript, message: message))
                }
            } else {
                copy(record)
                try modelContext.save()
                setPhase(.message("Transcript copied"))
            }
            preferences.apiCreditsExhausted = false
            Task { [weak self] in await self?.refreshSubscriptionUsage() }
        } catch {
            record.transcriptionState = .failed
            record.errorMessage = error.localizedDescription
            try? modelContext.save()
            if let scribeError = error as? ScribeError, scribeError.invalidatesAPIKey {
                preferences.apiKeyValidity = .invalid
                setPhase(.apiKeyInvalid)
            } else if case ScribeError.insufficientCredits = error {
                preferences.apiCreditsExhausted = true
                setPhase(.apiCreditsExhausted)
            } else {
                setPhase(.transcriptionFailed(error.localizedDescription))
            }
        }
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
        guard case .recording(_, let elapsed, _) = phase else { return }
        meterTask?.cancel()
        meterTask = nil
        if elapsed < RecordingCancellationPolicy.recoveryThreshold {
            recorder.cancel()
            paste.clearTarget()
            shortcuts.setMode(.idle)
            showMessage("Cancelled")
            return
        }
        shortcuts.setMode(.busy)
        Task { [weak self] in
            guard let self else { return }
            do {
                let completed = try await recorder.stop()
                retainCancelledRecording(completed)
            } catch {
                shortcuts.setMode(.idle)
                showFailure(error.localizedDescription, transcription: true)
            }
        }
    }

    private func cancelHeldRecordingForTypingIfNeeded() {
        guard case .recording(let mode, let elapsed, _) = phase,
              RecordingCancellationPolicy.cancelsForNonModifierKey(mode: mode, elapsed: elapsed) else { return }
        cancelRecording()
    }

    private func retainCancelledRecording(_ completed: CompletedRecording) {
        guard RecordingCancellationPolicy.retainsAudio(
            elapsed: completed.duration,
            detectedSignal: completed.detectedSignal
        ) else {
            AudioRecorder.delete(relativePath: completed.relativePath)
            paste.clearTarget()
            shortcuts.setMode(.idle)
            showMessage("Cancelled")
            return
        }
        let record = DictationRecord(
            id: completed.id,
            durationSeconds: completed.duration,
            transcriptionState: .cancelled,
            errorMessage: "Cancelled before transcription.",
            pendingAudioRelativePath: completed.relativePath
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
            currentRecord = record
            currentRecording = completed
            shortcuts.setMode(.idle)
            setPhase(.cancelledTranscript)
        } catch {
            shortcuts.setMode(.idle)
            showFailure(error.localizedDescription, transcription: true)
        }
    }

    private func undoCancelledDictation() {
        guard let record = currentRecord,
              record.transcriptionState == .cancelled,
              currentRecording != nil else {
            showMessage("Recording unavailable")
            return
        }
        guard canUseConfiguredAPIKey() else { return }
        record.transcriptionState = .transcribing
        record.errorMessage = nil
        try? modelContext.save()
        shortcuts.setMode(.busy)
        setPhase(.transcribing(attempt: 1, retryDelay: nil))
        Task { await transcribeCurrentRecord(delivery: .automaticPaste) }
    }

    @discardableResult
    private func dismissVisiblePill() -> Bool {
        switch phase.pillDismissalAction(isPresented: pill.isPresented) {
        case .passThrough:
            return false
        case .cancelRecording:
            cancelRecording()
        case .hideTranscription:
            suppressPillForCurrentTranscription = true
            pill.dismiss()
        case .dismiss:
            returnToIdle()
        }
        return true
    }

    private func retryCurrentFailure() {
        guard let currentRecord else { return }
        retry(currentRecord)
    }

    private func canUseConfiguredAPIKey() -> Bool {
        guard preferences.apiKeyConfigured else {
            setPhase(.apiKeyInvalid)
            return false
        }
        guard !isCheckingStoredAPIKey else {
            showMessage("Checking API key…")
            return false
        }
        guard preferences.apiKeyValidity != .invalid else {
            setPhase(.apiKeyInvalid)
            return false
        }
        guard !preferences.apiCreditsExhausted else {
            setPhase(.apiCreditsExhausted)
            return false
        }
        return true
    }

    private func canUseHistoryStorage() -> Bool {
        guard persistenceAvailable else {
            showFailure(
                "Dictation history could not be opened. Quit and reopen Scriber.",
                transcription: true
            )
            return false
        }
        return true
    }

    private func presentPendingPermissionRecoveryIfPossible() {
        guard permissionRecoveryPresentationPending,
              preferences.onboardingComplete,
              !permissionReadiness.isReady,
              !phase.isBusy else { return }
        permissionRecoveryPresentationPending = false
        suppressPillForCurrentTranscription = false
        setPhase(.permissionsRequired(permissionReadiness.missingPermissions))
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
        suppressPillForCurrentTranscription = false
        let retainedPhase = phase
        pill.update(.message(message))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.phase == retainedPhase else { return }
            if self.suppressPillForCurrentTranscription {
                self.pill.dismiss()
            } else {
                self.pill.update(retainedPhase)
            }
        }
    }

    private func returnToIdle() {
        suppressPillForCurrentTranscription = false
        paste.clearTarget()
        pill.setPreferredScreen(nil)
        shortcuts.setMode(.idle)
        setPhase(.idle)
    }

    private func setPhase(_ phase: AppPhase) {
        self.phase = phase
        if suppressPillForCurrentTranscription {
            pill.dismiss()
        } else {
            pill.update(phase)
        }
    }

    private func recoverPersistedAndOrphanedRecords() {
        guard let records = try? modelContext.fetch(FetchDescriptor<DictationRecord>()) else { return }
        for record in records where record.transcriptionState == .transcribing {
            record.transcriptionState = .failed
            record.errorMessage = record.pendingAudioRelativePath == nil
                ? "The app stopped before this dictation completed, and no retryable audio remains."
                : "The app stopped before this dictation completed. Retry when ready."
        }

        let referencedAudio = Set(records.compactMap(\.pendingAudioRelativePath))
        if let files = try? AudioRecorder.recoverableAudioFiles() {
            for file in files where !referencedAudio.contains(file.lastPathComponent) {
                let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) ?? UUID()
                modelContext.insert(DictationRecord(
                    id: id,
                    createdAt: values?.creationDate ?? values?.contentModificationDate ?? .now,
                    durationSeconds: AudioRecorder.duration(of: file),
                    transcriptionState: .failed,
                    errorMessage: "Recovered after Scriber could not save this recording. Retry when ready.",
                    pendingAudioRelativePath: file.lastPathComponent
                ))
            }
        }
        try? modelContext.save()
    }
}
