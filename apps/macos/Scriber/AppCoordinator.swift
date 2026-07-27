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
    case microphone
    /// Settings, scrolled to Permissions and Input. Distinct from `.settings`,
    /// which opens the pane at the top: Permissions and Input is the last
    /// section of a long pane, so landing on Settings alone leaves the user
    /// looking at General with no sign of what they were sent to fix.
    case permissions
}

struct MainWindowRequest: Equatable {
    let id = UUID()
    let destination: MainWindowDestination
}

@MainActor
final class AppCoordinator: ObservableObject {
    /// Fallback cadence for permission state that macOS does not announce. This
    /// runs for the whole life of a menu-bar app, so it is deliberately slow; the
    /// Accessibility hint and the activation refresh cover the cases a user can
    /// actually notice.
    private static let permissionPollInterval: TimeInterval = 5

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
    @Published private(set) var otherAudioMuteStatus: OtherAudioMuteStatus?

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
    private let feedbackSounds: RecordingFeedbackSoundPlaying
    private let otherAudioMuting: OtherAudioMuting
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
    private var credentialRecoveryPresentationPending = false
    private var lastObservedCredentialReadiness: CredentialReadiness = .ready
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: Preferences,
        modelContext: ModelContext,
        persistenceAvailable: Bool = true,
        permissionReadinessOverride: PermissionReadiness? = nil,
        servicesAllowed: Bool = true,
        feedbackSounds: RecordingFeedbackSoundPlaying = RecordingFeedbackSoundPlayer(),
        otherAudioMuting: OtherAudioMuting = OtherAudioMuteService()
    ) {
        self.preferences = preferences
        self.modelContext = modelContext
        self.persistenceAvailable = persistenceAvailable
        self.permissionReadinessOverride = permissionReadinessOverride
        self.servicesAllowed = servicesAllowed
        self.feedbackSounds = feedbackSounds
        self.otherAudioMuting = otherAudioMuting
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
        pill.model.onOpenInputSettings = { [weak self] in self?.openMicrophoneInputSettings() }
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

        preferences.$muteOtherAudioWhileRecording
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled, case .recording = self.phase {
                    self.beginOtherAudioMuting()
                } else if !enabled {
                    self.endOtherAudioMuting()
                    if self.otherAudioMuteStatus == .unavailableToStart {
                        self.otherAudioMuteStatus = nil
                    }
                }
            }
            .store(in: &cancellables)

        preferences.$playRecordingFeedbackSounds
            .dropFirst()
            .sink { [weak self] enabled in
                if !enabled { self?.feedbackSounds.stop() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.endOtherAudioMuting() }
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
            // Neither Accessibility trust nor microphone authorization publishes a
            // documented change notification, and revoked Accessibility is exactly the
            // case Scriber cannot detect from a keypress, because it stops seeing the
            // keypress at all. macOS does post the long-standing private
            // `com.apple.accessibility.api` distributed notification when the trust
            // database changes, so that is used as a hint to check promptly. It is
            // undocumented and its new value is not readable at post time, so
            // correctness still rests on the slow fallback poll and the activation
            // refresh below; the hint only removes the delay.
            DistributedNotificationCenter.default()
                .publisher(for: Notification.Name("com.apple.accessibility.api"))
                .sink { [weak self] _ in
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        self?.refreshPermissions(
                            promptForAccessibility: false,
                            presentRecoveryWhenMissing: false,
                            refreshAudioInputs: false
                        )
                    }
                }
                .store(in: &cancellables)

            Timer.publish(every: Self.permissionPollInterval, on: .main, in: .common)
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

        preferences.$deletesExpiredRetainedAudio
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled { self?.expireRetainedAudio() }
            }
            .store(in: &cancellables)

        if persistenceAvailable, servicesAllowed {
            recoverPersistedAndOrphanedRecords()
            expireRetainedAudio()
        }
        lastObservedCredentialReadiness = credentialReadiness
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
        case .credentialsUnusable(let readiness): readiness.title
        case .pasteFailed: "Paste failed"
        case .transcriptionFailed: "Transcription failed"
        case .noSpeechDetected: "No words detected"
        case .message(let value): value
        }
    }

    var permissionReadiness: PermissionReadiness {
        PermissionReadiness(
            microphoneGranted: microphoneGranted,
            accessibilityGranted: accessibilityGranted
        )
    }

    var credentialReadiness: CredentialReadiness {
        CredentialReadiness(
            apiKeyConfigured: preferences.apiKeyConfigured,
            apiKeyValidity: preferences.apiKeyValidity,
            apiCreditsExhausted: preferences.apiCreditsExhausted
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

    func openSystemAudioPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") else { return }
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
            refreshCredentialRecovery(force: false)
            return
        }
#endif
        let result = try await scribe.validateAPIKey(value)
        credentialRevision.advance()
        storedAPIKeyValidationTask?.cancel()
        storedAPIKeyValidationTask = nil
        isCheckingStoredAPIKey = false
        isRefreshingSubscriptionUsage = false
        try await keychain.saveAPIKey(value)
        preferences.apiKeyConfigured = true
        preferences.apiKeyValidity = .valid
        preferences.subscriptionUsage = result.subscriptionUsage
        preferences.apiCreditsExhausted = result.subscriptionUsage?.shouldBlockDictation ?? false
        subscriptionUsageUnavailable = result.subscriptionUsageUnavailable
        subscriptionUsageError = result.subscriptionUsageUnavailable
            ? subscriptionUsageUnavailableMessage(accessDenied: result.subscriptionUsageAccessDenied)
            : nil
        refreshCredentialRecovery(force: false)
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
                    refreshCredentialRecovery(force: true)
                }
            }
            do {
                guard let apiKey = try await keychain.readAPIKey(), !apiKey.isEmpty else {
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
        guard let apiKey = try? await keychain.readAPIKey(), !apiKey.isEmpty else { return }
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
            refreshCredentialRecovery(force: false)
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

    /// Reconciles the credential block after anything that could change it.
    ///
    /// `force` presents the current problem even when it has not changed, which is
    /// what the once-per-launch check needs: onboarding can be complete while the
    /// stored key has since been revoked or replaced, and the user has to learn
    /// that from Scriber rather than from a dictation that quietly does nothing.
    private func refreshCredentialRecovery(force: Bool) {
        let previous = lastObservedCredentialReadiness
        let current = credentialReadiness
        lastObservedCredentialReadiness = current

        let resolvedPhase = phase.resolvingCredentialBlock(
            apiKeyConfigured: preferences.apiKeyConfigured,
            apiKeyValidity: preferences.apiKeyValidity,
            apiCreditsExhausted: preferences.apiCreditsExhausted
        )
        if resolvedPhase != phase {
            if resolvedPhase == .idle { returnToIdle() } else { setPhase(resolvedPhase) }
        }

        guard CredentialRecoveryPolicy.shouldPresent(
            previous: previous,
            current: current,
            onboardingComplete: preferences.onboardingComplete,
            force: force
        ) else { return }
        credentialRecoveryPresentationPending = true
        presentPendingCredentialRecoveryIfPossible()
    }

    /// Missing permissions outrank an unusable credential: without Microphone or
    /// Accessibility there is nothing for a working key to do. The Dictation window
    /// and menu bar surface both conditions at once, so nothing is lost by waiting.
    private func presentPendingCredentialRecoveryIfPossible() {
        let readiness = credentialReadiness
        guard credentialRecoveryPresentationPending,
              preferences.onboardingComplete,
              !readiness.isReady,
              !phase.isBusy,
              permissionReadiness.isReady,
              !permissionRecoveryPresentationPending else { return }
        credentialRecoveryPresentationPending = false
        suppressPillForCurrentTranscription = false
        setPhase(.credentialsUnusable(readiness))
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        try login.setEnabled(enabled)
        preferences.launchAtLoginRequested = enabled
    }

    func handle(_ action: ShortcutAction) {
        guard preferences.onboardingComplete else { return }
        switch action {
        case .holdPressed:
            if phase.acceptsRecordingStart {
                startRecording(mode: .held)
            } else if case .transcribing = phase {
                showTransientMessage("Still transcribing")
            }
        case .holdReleased:
            if case .recording(let mode, _, _) = phase,
               ShortcutAction.holdReleased.stopsRecording(mode: mode) {
                stopAndTranscribe()
            }
        case .togglePressed:
            guard !phase.acceptsRecordingStart else {
                startRecording(mode: .locked)
                return
            }
            switch phase {
            case .recording(let mode, let elapsed, let level) where mode == .held:
                shortcuts.setMode(.locked)
                setPhase(.recording(mode: .locked, elapsed: elapsed, level: level))
            case .recording(let mode, _, _) where ShortcutAction.togglePressed.stopsRecording(mode: mode):
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

    func setShortcutConfigurationCaptureActive(_ active: Bool) {
        shortcuts.setConfigurationCaptureActive(active)
    }

    func startHandsFreeFromMenu() {
        guard preferences.onboardingComplete else { return }
        if phase.acceptsRecordingStart {
            startRecording(mode: .locked)
        } else if case .recording = phase {
            stopAndTranscribe()
        } else {
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
        openMainWindow(destination: .permissions)
    }

    func selectMainWindowDestination(_ destination: MainWindowDestination) {
        mainWindowRequest = MainWindowRequest(destination: destination)
    }

    private func openMainWindow(destination: MainWindowDestination) {
        selectMainWindowDestination(destination)
        returnToIdle()
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .openScriberMainWindow, object: nil)
        // Every pill action arrives here from a nonactivating panel, so the app
        // the user was working in is still frontmost and Scriber has no
        // activation of its own for the cooperative `activate(from:)` inside
        // `showWindow` to build on. That call reports success and macOS then
        // declines to honour it, which is why an already-open window came to the
        // front of Scriber's own layer and no further — the window opened and
        // changed section exactly as asked, behind whatever the user was in.
        //
        // The two routes that do land, the menu bar item and Command-comma, both
        // ask outright. This is the same request, and it is warranted the same
        // way: the user just clicked a button asking to be taken somewhere.
        NSApp.activate(ignoringOtherApps: true)
    }

    func presentInvalidAPIKeyPillForUITesting() {
        guard !servicesAllowed else { return }
        setPhase(.credentialsUnusable(.invalidAPIKey))
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
            if preferences.muteOtherAudioWhileRecording { beginOtherAudioMuting() }
            playFeedback(.recordingStarted)
            shortcuts.setMode(mode == .held ? .held : .locked)
            setPhase(.recording(mode: mode, elapsed: 0, level: -80))
            startMeter(mode: mode)
        } catch AudioRecorderError.inputUnavailable(let name) {
            endOtherAudioMuting()
            playFeedback(.terminalFailure)
            showMessage("Microphone “\(name)” is unavailable")
        } catch {
            endOtherAudioMuting()
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
        endOtherAudioMuting()
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
            guard let apiKey = try await keychain.readAPIKey(), !apiKey.isEmpty else { throw ScribeError.authentication }
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
                    playFeedback(.cancellationOrCopyFallback)
                    setPhase(.dictationCopied(text: transcript, message: message))
                case .failed(let message):
                    copy(record)
                    record.errorMessage = message
                    try modelContext.save()
                    playFeedback(.cancellationOrCopyFallback)
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
            playFeedback(.terminalFailure)
            record.transcriptionState = .failed
            record.errorMessage = error.localizedDescription
            try? modelContext.save()
            if let scribeError = error as? ScribeError, scribeError.invalidatesAPIKey {
                preferences.apiKeyValidity = .invalid
                lastObservedCredentialReadiness = credentialReadiness
                setPhase(.credentialsUnusable(credentialReadiness))
            } else if case ScribeError.insufficientCredits = error {
                preferences.apiCreditsExhausted = true
                lastObservedCredentialReadiness = credentialReadiness
                setPhase(.credentialsUnusable(credentialReadiness))
            } else {
                setPhase(.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    /// ElevenLabs returned a transcript with no words in it. The dictation is
    /// discarded as before — nothing useful was captured and an empty history row
    /// would be noise — but it no longer happens silently. A dead or wrongly
    /// selected input is the likeliest cause, and a user who cannot tell the
    /// difference between "no words" and "nothing happened" has no way to find it.
    private func discardNoContent(record: DictationRecord, recording: CompletedRecording) {
        AudioRecorder.delete(relativePath: recording.relativePath)
        modelContext.delete(record)
        try? modelContext.save()
        currentRecord = nil
        currentRecording = nil
        endOtherAudioMuting()
        paste.clearTarget()
        pill.setPreferredScreen(nil)
        shortcuts.setMode(.idle)
        playFeedback(.terminalFailure)
        suppressPillForCurrentTranscription = false
        setPhase(.noSpeechDetected)
    }

    func openMicrophoneInputSettings() {
        openMainWindow(destination: .microphone)
    }

    private func cancelRecording() {
        guard case .recording(_, let elapsed, _) = phase else { return }
        meterTask?.cancel()
        meterTask = nil
        endOtherAudioMuting()
        if elapsed < RecordingCancellationPolicy.recoveryThreshold {
            recorder.cancel()
            paste.clearTarget()
            shortcuts.setMode(.idle)
            playFeedback(.cancellationOrCopyFallback)
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
            playFeedback(.cancellationOrCopyFallback)
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
            playFeedback(.cancellationOrCopyFallback)
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
        // Marks the record as a deliberate re-transcription rather than a fresh
        // one, so history keeps showing the row it already had instead of hiding
        // it for the duration. Cleared by `transcribeCurrentRecord`.
        retryingRecordID = record.id
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
        guard !isCheckingStoredAPIKey else {
            showMessage("Checking API key…")
            return false
        }
        let readiness = credentialReadiness
        guard readiness.isReady else {
            // An attempted dictation always reports its own blocker, even while a
            // permission problem is outranking the credential pill elsewhere.
            credentialRecoveryPresentationPending = false
            lastObservedCredentialReadiness = readiness
            suppressPillForCurrentTranscription = false
            setPhase(.credentialsUnusable(readiness))
            return false
        }
        return true
    }

    private func canUseHistoryStorage() -> Bool {
        guard persistenceAvailable else {
            showFailure(
                "Dictation history could not be opened. Quit and reopen Scriber.",
                transcription: true,
                playTerminalFeedback: false
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

    private func showFailure(
        _ message: String,
        transcription: Bool,
        playTerminalFeedback: Bool = true
    ) {
        endOtherAudioMuting()
        if transcription, playTerminalFeedback { playFeedback(.terminalFailure) }
        shortcuts.setMode(.idle)
        setPhase(transcription ? .transcriptionFailed(message) : .pasteFailed(message))
    }

    private func playFeedback(_ cue: RecordingFeedbackCue) {
        guard preferences.playRecordingFeedbackSounds else { return }
        feedbackSounds.play(cue)
    }

    private func beginOtherAudioMuting() {
        switch otherAudioMuting.beginMuting() {
        case .muted, .alreadyMuted:
            otherAudioMuteStatus = nil
        case .unavailable:
            otherAudioMuteStatus = .unavailableToStart
        }
    }

    private func endOtherAudioMuting() {
        switch otherAudioMuting.endMuting() {
        case .restored:
            if otherAudioMuteStatus == .unableToRestore {
                otherAudioMuteStatus = nil
            }
        case .alreadyRestored:
            break
        case .unavailable:
            otherAudioMuteStatus = .unableToRestore
        }
    }

    private func showMessage(_ message: String) {
        setPhase(.message(message))
    }

    private func showTransientMessage(_ message: String) {
        suppressPillForCurrentTranscription = false
        let retainedPhase = phase
        pill.update(.message(message), autoDismiss: false)
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
        endOtherAudioMuting()
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

        // Removing a transcribed recording can fail, leaving the file behind after its
        // record reference was cleared. Such a file must not be reimported: it would
        // upsert over a succeeded dictation and destroy the saved transcript.
        let referencedAudio = Set(records.compactMap(\.pendingAudioRelativePath))
        let knownRecordIDs = Set(records.map(\.id))
        if let files = try? AudioRecorder.recoverableAudioFiles() {
            for file in files {
                let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) ?? UUID()
                guard OrphanedAudioImportPolicy.shouldImport(
                    recordingID: id,
                    relativePath: file.lastPathComponent,
                    knownRecordIDs: knownRecordIDs,
                    referencedAudioPaths: referencedAudio
                ) else { continue }
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

    /// Removes retained dictation audio older than the retention period.
    ///
    /// Only the recording goes. The history row, its transcript, and why it failed
    /// are preserved, so the user keeps the record of what happened and loses only
    /// the ability to retry a month-old dictation.
    private func expireRetainedAudio() {
        // Never from a test build. `PendingAudio` is a single real directory that
        // `--ui-testing` does not isolate, while the history store under it *is*
        // in-memory — so the orphan sweep below sees every one of Gaf's genuinely
        // retained recordings as referenced by nothing and deletes the expired
        // ones. The launch call site is already gated; the
        // `$deletesExpiredRetainedAudio` sink is not, so switching that
        // preference on in a test build was enough to reach this. Guarding the
        // function covers both call sites and any later one.
        //
        // `servicesAllowed` is true in Release, so shipped behaviour is unchanged.
        guard servicesAllowed else { return }
        guard preferences.deletesExpiredRetainedAudio,
              let records = try? modelContext.fetch(FetchDescriptor<DictationRecord>()) else { return }

        var didExpireRecord = false
        for record in records {
            guard let relativePath = record.pendingAudioRelativePath,
                  RetainedAudioRetentionPolicy.hasExpired(createdAt: record.createdAt) else { continue }
            AudioRecorder.delete(relativePath: relativePath)
            record.pendingAudioRelativePath = nil
            record.errorMessage = RetainedAudioRetentionPolicy.expiredMessage(
                appendingTo: record.errorMessage
            )
            didExpireRecord = true
        }
        if didExpireRecord { try? modelContext.save() }

        // Anything left that no dictation references is stale by construction,
        // including the files orphan recovery deliberately refuses to reimport.
        let referencedAudio = Set(records.compactMap(\.pendingAudioRelativePath))
        guard let files = try? AudioRecorder.recoverableAudioFiles() else { return }
        for file in files where !referencedAudio.contains(file.lastPathComponent) {
            let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            guard RetainedAudioRetentionPolicy.hasExpired(createdAt: createdAt ?? .distantPast) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
