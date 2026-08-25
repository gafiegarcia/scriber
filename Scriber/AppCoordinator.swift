import AppKit
@preconcurrency import AVFoundation
import Combine
import Foundation
import SwiftData
import os
#if SWIFT_PACKAGE
import ScriberCore
#endif

extension Notification.Name {
    static let openScriberMainWindow = Notification.Name("openScriberMainWindow")
    static let openScriberOnboardingWindow = Notification.Name("openScriberOnboardingWindow")
    static let openScriberSettingsWindow = Notification.Name("openScriberSettingsWindow")
    static let showAppInDockDidChange = Notification.Name("showAppInDockDidChange")
}

enum MainWindowDestination: Hashable {
    case dictation
    case settings
    case apiKey
    case usage
    case microphone
    /// Settings, on the Permissions tab. Distinct from `.settings`, which names no
    /// tab and leaves the one already showing alone: a route that exists to fix
    /// something lands on the tab that owns it, an ordinary opening does not.
    case permissions
}

struct MainWindowRequest: Equatable {
    let id = UUID()
    let destination: MainWindowDestination
}

/// Whether a Settings shortcut recorder currently owns the keyboard. Shared
/// rather than held on the coordinator because the reader is `AppDelegate`, which
/// SwiftUI creates on its own and hands no runtime.
@MainActor
enum ShortcutConfigurationCapture {
    static var isActive = false
}

@MainActor
final class AppCoordinator: ObservableObject {
    /// Fallback cadence for permission state macOS does not announce. Runs for the
    /// whole life of a menu-bar app, so keep it slow: the Accessibility hint and
    /// the activation refresh cover the cases a user can actually notice.
    private static let permissionPollInterval: TimeInterval = 5

    /// Records only permission booleans, state names, and which refresh path
    /// observed them. No user content passes through here.
    private static let permissionLog = Logger(
        subsystem: "com.gafiegarcia.scriber",
        category: "permissions"
    )

    /// Which caller drove a permission refresh, so a logged change names the path
    /// that caught it — a grant the poll never observed and an ordinary grant look
    /// identical otherwise.
    enum PermissionRefreshSource: String {
        case launch
        case startServices
        case activation
        case trustNotification
        case poll
        case startRecording
        case settings
        case onboarding
    }

    @Published private(set) var phase: AppPhase = .idle
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var microphoneGranted = AudioRecorder.microphoneAuthorized
    @Published private(set) var microphonePermissionState = AudioRecorder.microphonePermissionState
    @Published private(set) var launchAtLoginState = LaunchAtLoginService.state
    @Published private(set) var audioInputDevices = AudioRecorder.availableInputDevices()
    /// Not `@Published` on this object: it changes ten times a second, and
    /// publishing it here re-renders everything that observes the coordinator.
    let microphoneLevel = AudioLevelSource()
    /// Flips once when the input is first heard, so a step can gate on it without
    /// watching the level itself.
    @Published private(set) var microphoneSignalDetected = false
    @Published private(set) var microphoneTestError: String?
    @Published private(set) var isMicrophoneTestRunning = false
    @Published private(set) var shortcutMonitorAvailable = false
    @Published private(set) var retryingRecordID: UUID?
    @Published private(set) var subscriptionUsageUnavailable = false
    @Published private(set) var isRefreshingSubscriptionUsage = false
    @Published private(set) var subscriptionUsageError: String?
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var updateCheckError: String?
    @Published private(set) var mainWindowRequest: MainWindowRequest?
    private var settingsWindowOpener: (@MainActor () -> Void)?
    @Published private(set) var otherAudioMuteStatus: OtherAudioMuteStatus?
    private var pendingUnmute: Task<Void, Never>?

    let preferences: Preferences
    let modelContext: ModelContext

    private let servicesAllowed: Bool
    private let persistenceAvailable: Bool
    private let permissionReadinessOverride: PermissionReadiness?
    private let keychain = KeychainStore()
    private let recorder = AudioRecorder()
    /// What the user has asked for, which a session still opening cannot answer
    /// yet. Every gesture that starts, stops or cancels a dictation goes through
    /// it, so none of them has to read a `phase` that has not caught up.
    private var gate = RecordingStartGate()
    private let scribe = ScribeClient()
    private let updateChecker = UpdateChecker()
    private let paste = PasteService()
    private let login = LaunchAtLoginService()
    private let pill = PillController()
    private let shortcuts: GlobalShortcutService
    private let feedbackSounds: DictationFeedbackSoundPlaying
    private let otherAudioMuting: OtherAudioMuting
    private let historyMaintenance: DictationHistoryMaintenance
    private var meterTask: Task<Void, Never>?
    private var microphoneTestTask: Task<Void, Never>?
    private var currentRecord: DictationRecord?
    private var currentRecording: CompletedRecording?
    private var checkedStoredAPIKeyThisLaunch = false
    @Published private(set) var isCheckingStoredAPIKey = false
    private var storedAPIKeyValidationTask: Task<Void, Never>?
    /// Separate from `preferences.lastUpdateCheck`, which records only a check
    /// that got an answer. `startServices` runs again every time the menu bar
    /// opens, so without an in-session stamp a failed check starts a new
    /// twenty-second request each time.
    private var lastUpdateAttempt: Date?
    private var credentialRevision = CredentialRevision()
    private var suppressPillForCurrentTranscription = false
    /// Whether setup is being walked a second time. `onboardingComplete` cannot
    /// answer it — Redo Setup clears that — and the two differ in what a step
    /// offers: a first run recommends, a redo shows what is already there.
    private(set) var isRedoingSetup = false
    private var permissionRecoveryPresentationPending = false
    private var permissionRecoveryLaunchGate = PermissionRecoveryLaunchGate()
    private var credentialRecoveryPresentationPending = false
    private var lastObservedCredentialReadiness: CredentialReadiness = .ready
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: Preferences,
        modelContext: ModelContext,
        persistenceAvailable: Bool = true,
        permissionReadinessOverride: PermissionReadiness? = nil,
        servicesAllowed: Bool = true,
        feedbackSounds: DictationFeedbackSoundPlaying = DictationFeedbackSoundPlayer(),
        otherAudioMuting: OtherAudioMuting = OtherAudioMuteService()
    ) {
        self.preferences = preferences
        self.modelContext = modelContext
        self.persistenceAvailable = persistenceAvailable
        self.permissionReadinessOverride = permissionReadinessOverride
        self.servicesAllowed = servicesAllowed
        self.feedbackSounds = feedbackSounds
        self.otherAudioMuting = otherAudioMuting
        historyMaintenance = DictationHistoryMaintenance(
            modelContext: modelContext,
            servicesAllowed: servicesAllowed
        )
        shortcuts = GlobalShortcutService(dictation: preferences.dictationShortcut)

        shortcuts.onAction = { [weak self] action in self?.handle(action) }
        // A query, not the dismissal: the tap asks this while the key is passing,
        // and the dismissal itself arrives as an ordinary `.cancel` action.
        shortcuts.pillConsumesEscape = { [weak self] in
            guard let self else { return false }
            return phase.pillDismissalAction(isPresented: pill.isPresented) != .passThrough
        }
        shortcuts.onNonModifierKeyDown = { [weak self] in self?.cancelHeldRecordingForTypingIfNeeded() }
        shortcuts.onAvailabilityChanged = { [weak self] value in
            guard let self else { return }
            // What the monitor actually reports, as opposed to the start and stop
            // requests logged in `refreshPermissions`. The service reports on every
            // tap re-arm, not only when the answer changes, so compare before logging.
            if shortcutMonitorAvailable != value {
                Self.permissionLog.notice("shortcutMonitor: available=\(value, privacy: .public)")
            }
            shortcutMonitorAvailable = value
        }
        pill.model.onOpen = { [weak self] in self?.openMainWindow() }
        pill.model.onOpenAPIKeySettings = { [weak self] in self?.openAPIKeySettings() }
        pill.model.onOpenUsageSettings = { [weak self] in self?.openUsageSettings() }
        pill.model.onOpenPermissionSettings = { [weak self] in self?.openPermissionSettings() }
        pill.model.onOpenInputSettings = { [weak self] in self?.openMicrophoneInputSettings() }
        pill.model.onRetry = { [weak self] in self?.retryCurrentFailure() }
        pill.model.onUndo = { [weak self] in self?.undoCancelledDictation() }
        pill.model.onCancelRecording = { [weak self] in self?.handleHandsFreePillAction(.cancel) }
        pill.model.onConfirmRecording = { [weak self] in self?.handleHandsFreePillAction(.confirm) }
        pill.model.onDismiss = { [weak self] in _ = self?.dismissVisiblePill() }
        pill.model.onDefaultAction = { [weak self] in self?.performPillDefaultAction() }

        preferences.$dictationShortcut
            .sink { [weak self] chord in self?.shortcuts.update(dictation: chord) }
            .store(in: &cancellables)

        preferences.$muteOtherAudioWhileDictating
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled, case .recording = self.phase {
                    self.beginOtherAudioMuting()
                } else if !enabled {
                    // Turning it off is an instruction about right now, not the
                    // end of a dictation, so it does not wait out the delay.
                    self.restoreOtherAudio()
                }
            }
            .store(in: &cancellables)

        preferences.$playDictationFeedbackSounds
            .dropFirst()
            .sink { [weak self] enabled in
                if !enabled { self?.feedbackSounds.stop() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            // Never the delayed path: nothing schedules on an app that is going
            // away, and the tap outliving it leaves the Mac silent.
            .sink { [weak self] _ in self?.restoreOtherAudioBeforeTerminating() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPermissions(
                        presentRecoveryWhenMissing: false,
                        refreshAudioInputs: true,
                        source: .activation
                    )
                }
            }
            .store(in: &cancellables)

        if servicesAllowed {
            // Neither Accessibility trust nor microphone authorization publishes a
            // documented change notification, and revoked Accessibility cannot be
            // detected from a keypress because Scriber stops seeing the keypress.
            // The private `com.apple.accessibility.api` distributed notification is
            // used as a hint only: it is undocumented and its new value is not
            // readable at post time, so correctness rests on the fallback poll and
            // the activation refresh below.
            DistributedNotificationCenter.default()
                .publisher(for: Notification.Name("com.apple.accessibility.api"))
                .sink { [weak self] _ in
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        self?.refreshPermissions(
                            presentRecoveryWhenMissing: false,
                            refreshAudioInputs: false,
                            source: .trustNotification
                        )
                    }
                }
                .store(in: &cancellables)

            Timer.publish(every: Self.permissionPollInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.refreshPermissions(
                            presentRecoveryWhenMissing: false,
                            refreshAudioInputs: false,
                            source: .poll
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
                self?.historyMaintenance.expireRetainedAudio(ifEnabled: enabled)
            }
            .store(in: &cancellables)

        if persistenceAvailable, servicesAllowed {
            historyMaintenance.recoverPersistedAndOrphanedRecords()
            historyMaintenance.expireRetainedAudio(
                ifEnabled: preferences.deletesExpiredRetainedAudio
            )
        }
        lastObservedCredentialReadiness = credentialReadiness
        refreshPermissions(source: .launch)
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
        case .dictationCopied, .transcriptCopied: "Copied"
        case .permissionsRequired: "Permissions required"
        case .credentialsUnusable(let readiness): readiness.title
        case .transcriptionFailed: "Transcription failed"
        case .noSpeechDetected: "No words detected"
        case .noAudioSignal: "No microphone signal"
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
        // Setup is behind us either way by the time services start, so the redo
        // marker has nothing left to distinguish.
        isRedoingSetup = false
        let presentInitialRecovery = permissionRecoveryLaunchGate.consume(
            onboardingComplete: preferences.onboardingComplete
        )
        refreshPermissions(
            presentRecoveryWhenMissing: presentInitialRecovery,
            refreshAudioInputs: true,
            source: .startServices
        )
        // Above the guards below, because a user whose Accessibility grant is
        // missing is exactly the one an update might be fixing.
        checkForUpdates()
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

    func refreshPermissions(source: PermissionRefreshSource) {
        refreshPermissions(
            presentRecoveryWhenMissing: false,
            refreshAudioInputs: true,
            source: source
        )
    }

    private func refreshPermissions(
        presentRecoveryWhenMissing: Bool,
        refreshAudioInputs: Bool,
        source: PermissionRefreshSource
    ) {
        let previousReadiness = permissionReadiness
        if let permissionReadinessOverride {
            accessibilityGranted = !permissionReadinessOverride.missingPermissions.contains(.accessibility)
            microphoneGranted = !permissionReadinessOverride.missingPermissions.contains(.microphone)
            microphonePermissionState = microphoneGranted ? .allowed : .denied
        } else {
            // Assign only on change. `@Published` publishes on every assignment and
            // the poll above runs on `.common`, so it fires while a menu is
            // tracking; a no-op write re-evaluates the whole `App` body, SwiftUI
            // reinstalls the main menu, and the open Window menu loses the items
            // AppKit contributes from the key window — Close ⌘W among them.
            let trusted = AXIsProcessTrusted()
            if accessibilityGranted != trusted {
                accessibilityGranted = trusted
                Self.permissionLog.notice(
                    "accessibility: granted=\(trusted, privacy: .public) source=\(source.rawValue, privacy: .public)"
                )
            }
            let authorized = AudioRecorder.microphoneAuthorized
            if microphoneGranted != authorized {
                microphoneGranted = authorized
                Self.permissionLog.notice(
                    "microphone: granted=\(authorized, privacy: .public) source=\(source.rawValue, privacy: .public)"
                )
            }
            let state = AudioRecorder.microphonePermissionState
            if microphonePermissionState != state {
                microphonePermissionState = state
                Self.permissionLog.notice(
                    "microphoneState: value=\(state.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public)"
                )
            }
        }
        // Outside the override branch: this is not a permission, so a test run
        // that synthesizes missing permissions still reads the real login item.
        // Same assign-only-on-change rule as above.
        let launchState = LaunchAtLoginService.state
        if launchAtLoginState != launchState {
            launchAtLoginState = launchState
            Self.permissionLog.notice(
                "launchAtLogin: state=\(launchState.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public)"
            )
        }
        if refreshAudioInputs { refreshAudioInputDevices() }

        if shortcutMonitoringAllowed, accessibilityGranted, preferences.onboardingComplete {
            if !shortcutMonitorAvailable {
                shortcuts.start()
                Self.permissionLog.notice(
                    "shortcutMonitor: action=start source=\(source.rawValue, privacy: .public)"
                )
            }
        } else {
            shortcuts.stop()
            if shortcutMonitorAvailable {
                shortcutMonitorAvailable = false
                Self.permissionLog.notice(
                    "shortcutMonitor: action=stop source=\(source.rawValue, privacy: .public)"
                )
            }
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

    /// Backs the Microphone row's single Allow button. macOS raises its own prompt only
    /// while the choice is undetermined, and that prompt is the one place the permission
    /// can be granted without a trip to System Settings. A refusal there is a decision:
    /// it does not chain into System Settings, it just leaves the button for next time.
    func allowMicrophone() async {
        guard microphonePermissionState == .notDetermined else {
            openMicrophoneSettings()
            return
        }
        microphoneGranted = await AudioRecorder.requestMicrophoneAccess()
        microphonePermissionState = AudioRecorder.microphonePermissionState
        refreshAudioInputDevices()
    }

    /// Backs the Accessibility row's single Allow button. Only the System Settings
    /// toggle can grant this, so the pane is the whole action — the system prompt
    /// cannot grant it and macOS shows it once per app. What lists Scriber in that
    /// pane is the trust check made at launch; a running process cannot re-register.
    func allowAccessibility() {
        openAccessibilitySettings()
    }

    /// Opens System Settings and brings it to the front. `NSWorkspace.open(_:)`
    /// alone leaves it behind the Scriber window that sent the user there, so the
    /// Allow button reads as broken. `activates` is what orders it front; hiding
    /// Scriber is not enough, because an already-open pane never redraws forward.
    private static func openInSystemSettings(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        Self.openInSystemSettings(url)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        Self.openInSystemSettings(url)
    }

    /// The Login Items list, the only place a switched-off entry can be turned
    /// back on.
    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        Self.openInSystemSettings(url)
    }

    /// The macOS Sound settings, where the input volume lives. Scriber's own
    /// input picker cannot show or change that volume, so a level meter reading
    /// flat has to point somewhere the user can act.
    func openSystemSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        Self.openInSystemSettings(url)
    }

    /// The `Privacy_ScreenCapture` anchor is what lands on Screen & System Audio
    /// Recording; without it the pane opens at the top of Privacy & Security,
    /// several screens of scrolling from the row this is sent from.
    func openSystemAudioPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ) else { return }
        Self.openInSystemSettings(url)
    }

    func startMicrophoneTest() {
        guard microphoneGranted, !phase.isBusy else { return }
        stopMicrophoneTest()
        microphoneTestError = nil
        microphoneLevel.reset()
        microphoneSignalDetected = false
        isMicrophoneTestRunning = true
        microphoneTestTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await recorder.startMonitoring(selection: preferences.audioInputSelection)
            } catch {
                microphoneTestError = error.localizedDescription
                microphoneLevel.reset()
                isMicrophoneTestRunning = false
                return
            }
            while !Task.isCancelled {
                let level = recorder.updateMeter()
                microphoneLevel.update(level)
                if !microphoneSignalDetected, AudioSignal.isDetected(decibels: level) {
                    microphoneSignalDetected = true
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopMicrophoneTest() {
        microphoneTestTask?.cancel()
        microphoneTestTask = nil
        recorder.stopMonitoring()
        microphoneLevel.reset()
        isMicrophoneTestRunning = false
    }

    func refreshAudioInputDevices() {
        let shouldRestartTest = microphoneTestTask != nil
        let devices = AudioRecorder.availableInputDevices()
        if audioInputDevices != devices { audioInputDevices = devices }
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

    /// Removes the stored key, so the missing-credential path can be reached from
    /// inside the app. Cancels any in-flight validation and advances the revision,
    /// so one already running cannot land afterwards and mark the key valid again.
    func removeAPIKey() async throws {
        credentialRevision.advance()
        storedAPIKeyValidationTask?.cancel()
        storedAPIKeyValidationTask = nil
        isCheckingStoredAPIKey = false
        isRefreshingSubscriptionUsage = false
#if DEBUG
        if !servicesAllowed {
            preferences.apiKeyConfigured = false
            preferences.apiKeyValidity = .unchecked
            preferences.subscriptionUsage = nil
            preferences.apiCreditsExhausted = false
            subscriptionUsageUnavailable = false
            subscriptionUsageError = nil
            refreshCredentialRecovery(force: true)
            return
        }
#endif
        try await keychain.deleteAPIKey()
        preferences.apiKeyConfigured = false
        preferences.apiKeyValidity = .unchecked
        preferences.subscriptionUsage = nil
        preferences.apiCreditsExhausted = false
        subscriptionUsageUnavailable = false
        subscriptionUsageError = nil
        refreshCredentialRecovery(force: true)
    }

    /// Sends the user back through onboarding. Only the flag is cleared — the key,
    /// grants, and history stay, and onboarding reads current state, so each step
    /// presents as already satisfied rather than asking again.
    /// Whether setup can be walked again right now.
    ///
    /// Restarting clears `onboardingComplete`, which stops the shortcut tap, and
    /// that tap carries `Escape` as well as the dictation chord — so a hands-free
    /// recording running at this moment loses every keyboard way out and sits
    /// until the duration cap. Every control that offers a restart reads this, so
    /// the disabled state and the refusal below cannot drift apart.
    var canRestartOnboarding: Bool { !phase.isBusy }

    func restartOnboarding() {
        guard canRestartOnboarding else { return }
        isRedoingSetup = true
        preferences.onboardingComplete = false
        // A redo is a fresh run, not a resumption of the one that finished.
        preferences.onboardingStep = 0
        // `openWindow(id:)` creates the scene but does not reliably bring it in
        // front of the window the action came from, which leaves onboarding behind
        // Settings. Route through `AppDelegate.showWindow(titled:)`, which already
        // implements ordering and activation, rather than building a second.
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .openScriberOnboardingWindow, object: nil)
    }

    private func validateStoredAPIKeyOnce() {
        guard !checkedStoredAPIKeyThisLaunch else { return }
        validateStoredAPIKey()
    }

    /// Re-reads the Keychain and re-checks the key it finds, so a surface reporting
    /// on the credential can be sure of it rather than repeating what it was told.
    ///
    /// `apiKeyConfigured` and `apiKeyValidity` are preferences, and neither deleting
    /// the Keychain item nor revoking the key at ElevenLabs touches them, so left
    /// alone the app reports a key it may no longer hold. `validateStoredAPIKeyOnce`
    /// reconciles that at launch but sits behind `startServices`' `onboardingComplete`
    /// guard, so setup has to ask again each time it returns to the step.
    ///
    /// Spends no transcription credit — validation reads the account, not audio.
    func validateStoredAPIKey() {
        guard servicesAllowed else { return }
        checkedStoredAPIKeyThisLaunch = true
        storedAPIKeyValidationTask?.cancel()
        let validationRevision = credentialRevision.current
        isCheckingStoredAPIKey = true
        storedAPIKeyValidationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                // Cancellation here means another call replaced this task without
                // advancing the revision, because nothing about the credential
                // changed. Without both checks this clears the flag and drops the
                // handle belonging to the validation now in flight.
                if !Task.isCancelled, credentialRevision.matches(validationRevision) {
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
                } else if result.subscriptionUsageAccessDenied {
                    // Without account access, cached exhaustion is no longer a
                    // trustworthy reason to block a verified Speech-to-Text key.
                    // A real transcription will report exhaustion authoritatively.
                    preferences.apiCreditsExhausted = false
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

    static let runningVersion =
        AppLaunchConfiguration.pretendedVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"

    /// Carries the `v` that tags and releases carry, so what Scriber says matches
    /// what GitHub shows to anyone who follows an offer. Display only — the bare
    /// string is what the update check compares and what the User-Agent sends.
    static func displayVersion(_ version: String) -> String { "v\(version)" }

    /// Shown beside the version because two installs can share a version and
    /// differ, which is exactly the pair a bug report has to tell apart.
    static let runningBuild =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

    /// Lifted for the update check alone, and only for a launch carrying a
    /// pretend version: reaching the update-available state needs a real answer
    /// from GitHub, which `servicesAllowed` otherwise withholds. Nil in Release,
    /// so the gate is unchanged there. This spends no API credit — the releases
    /// endpoint is GitHub's, not ElevenLabs'.
    private var updateChecksAllowed: Bool {
        servicesAllowed || AppLaunchConfiguration.pretendedVersion != nil
    }

    /// `force` is the Check for Updates button: it ignores the once-a-day interval
    /// but not the gate above, so an ordinary `--ui-testing` launch still reaches
    /// no network from either path.
    func checkForUpdates(force: Bool = false) {
        guard updateChecksAllowed else { return }
        guard force || preferences.automaticUpdateChecks else { return }
        guard force || (UpdateChecker.isDue(lastCheck: preferences.lastUpdateCheck)
            && UpdateChecker.isDue(lastCheck: lastUpdateAttempt)) else { return }
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        lastUpdateAttempt = Date()
        Task { [weak self] in
            guard let self else { return }
            defer { isCheckingForUpdates = false }
            do {
                let update = try await updateChecker.check(currentVersion: Self.runningVersion)
                // Only a check that got an answer is persisted, so a run that
                // has never reached GitHub can still say so rather than
                // claiming to be current.
                preferences.lastUpdateCheck = Date()
                if preferences.availableUpdate != update { preferences.availableUpdate = update }
                if updateCheckError != nil { updateCheckError = nil }
            } catch {
                updateCheckError = "Could not reach GitHub to check for updates."
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
            preferences.apiCreditsExhausted = false
            subscriptionUsageUnavailable = true
            subscriptionUsageError = subscriptionUsageUnavailableMessage(accessDenied: true)
            refreshCredentialRecovery(force: false)
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

    /// Reconciles the credential block after anything that could change it. `force`
    /// presents the current problem even when unchanged, which the once-per-launch
    /// check needs: onboarding can be complete while the stored key has since been
    /// revoked, and the user has to learn that from Scriber rather than from a
    /// dictation that quietly does nothing.
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

    /// Reads the result back rather than assuming the request took: macOS keeps
    /// a switched-off entry that registering again does not revive. The `defer`
    /// covers the throwing path too, so a failure leaves the published state
    /// matching what macOS actually has.
    func setLaunchAtLogin(_ enabled: Bool) throws {
        defer { launchAtLoginState = LaunchAtLoginService.state }
        try login.setEnabled(enabled)
    }

    func handle(_ action: ShortcutAction) {
        guard preferences.onboardingComplete else { return }
        // The pill's own dismissal, answered from what is on screen rather than
        // from what the recorder is doing.
        if case .cancel = action {
            _ = dismissVisiblePill()
            return
        }
        // Only a press with no dictation of its own to end can reach these. Once
        // the gate holds one, the gesture belongs to it, and asking `phase` would
        // be asking state that a start still in flight has not published yet.
        if gate.isIdle, case .pressed = action {
            if case .transcribing = phase {
                showTransientMessage("Still transcribing")
                return
            }
            guard phase.acceptsRecordingStart else { return }
        }
        apply(gate.apply(.shortcut(action)))
    }

    private func apply(_ decision: RecordingStartGate.Decision) {
        switch decision {
        case .ignore, .startDidNotOpen:
            break
        case .beginStart(let mode):
            beginRecording(mode: mode)
        case .beginMetering(let mode):
            beginMetering(mode: mode)
        // The recording the press started carries on, hands-free. Starting a
        // fresh one would throw away whatever was said during the tap itself.
        case .promote(let mode):
            shortcuts.setMode(.locked)
            if case .recording(_, let elapsed, let level) = phase {
                setPhase(.recording(mode: mode, elapsed: elapsed, level: level))
            }
        case .stop:
            stopAndTranscribe()
        case .cancel:
            cancelRecording()
        case .abandonOpenedSession:
            abandonOpenedSession()
        // The recorder teardown waits for the session it has to tear down. The
        // pill does not: leaving it up until the microphone opens reads as the
        // keystroke having been ignored, which is what it used to look like.
        case .cancelPendingStart:
            meterTask?.cancel()
            meterTask = nil
            feedbackSounds.fadeOut()
            returnToIdle()
        }
    }

    func setShortcutConfigurationCaptureActive(_ active: Bool) {
        ShortcutConfigurationCapture.isActive = active
        shortcuts.setConfigurationCaptureActive(active)
    }

    func startHandsFreeFromMenu() {
        guard preferences.onboardingComplete else { return }
        if gate.isIdle {
            guard phase.acceptsRecordingStart else {
                showTransientMessage("Still transcribing")
                return
            }
            apply(gate.apply(.startRequested(mode: .locked)))
        } else {
            apply(gate.apply(.stopRequested))
        }
    }

    /// Cancels a running dictation the way the pill's own Cancel does, for a
    /// caller that is taking the surface it belongs to off screen. Transcription
    /// already in flight is left alone: `HandsFreePillAction` permits cancelling
    /// only while recording, and the audio is spent by then.
    func cancelDictationInProgress() {
        handleHandsFreePillAction(.cancel)
    }

    private func handleHandsFreePillAction(_ action: HandsFreePillAction) {
        guard let disposition = action.disposition(for: phase) else { return }
        switch disposition {
        case .cancelRecording:
            apply(gate.apply(.cancelRequested))
        case .finishRecording:
            apply(gate.apply(.stopRequested))
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

    /// Known and unfixed: this saves once per record. Only worth batching if a
    /// large history makes it measurable.
    func clearDictationHistory(_ records: [DictationRecord]) {
        for record in records { delete(record) }
    }

    func openMainWindow() {
        retireRestingNotice()
        openMainWindow(destination: .dictation)
    }

    func openAPIKeySettings() {
        retireRestingNotice()
        openSettingsWindow(destination: .apiKey)
    }

    func openUsageSettings() {
        retireRestingNotice()
        openSettingsWindow(destination: .usage)
    }

    func openPermissionSettings() {
        retireRestingNotice()
        openSettingsWindow(destination: .permissions)
    }

    func selectMainWindowDestination(_ destination: MainWindowDestination) {
        mainWindowRequest = MainWindowRequest(destination: destination)
    }

    /// Discards a request once the window has acted on it. One that outlives its
    /// delivery is re-applied every time the window appears, so a single trip to
    /// the key field would keep selecting that tab and taking focus.
    func consumeMainWindowRequest() {
        mainWindowRequest = nil
    }

    /// Only a SwiftUI scene can create the Settings window, so the main window
    /// hands its `openWindow` action over once it exists.
    ///
    /// Prototype limitation: with every window closed and the app launched
    /// straight to the menu bar, nothing has registered an opener yet.
    func registerSettingsWindowOpener(_ opener: @escaping @MainActor () -> Void) {
        settingsWindowOpener = opener
    }

    func openSettingsWindow(destination: MainWindowDestination) {
        selectMainWindowDestination(destination)
        NSApp.setActivationPolicy(.regular)
        // The opener creates the scene if it does not exist yet; the
        // notification is what orders an existing window front and carries the
        // activation retries every other managed window already relies on.
        settingsWindowOpener?()
        NotificationCenter.default.post(name: .openScriberSettingsWindow, object: nil)
    }

    private func openMainWindow(destination: MainWindowDestination) {
        selectMainWindowDestination(destination)
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .openScriberMainWindow, object: nil)
        // Every pill action arrives from a nonactivating panel, so Scriber has no
        // activation for the cooperative `activate(from:)` inside `showWindow` to
        // build on: that call reports success and macOS declines to honour it,
        // leaving the window at the front of Scriber's own layer and no further.
        // Ask outright, as the menu bar item and Command-comma both do.
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

    private func beginRecording(mode: RecordingMode) {
        // The gate is already holding this start. Every path that refuses below
        // has to hand it back: left holding one that never happened, it ignores
        // every later dictation silently, with no pill and no log, until relaunch.
        var handedOff = false
        defer { if !handedOff { _ = gate.apply(.startFailed) } }

        guard preferences.onboardingComplete else { return }
        suppressPillForCurrentTranscription = false
        guard canUseHistoryStorage() else { return }
        refreshPermissions(
            presentRecoveryWhenMissing: false,
            refreshAudioInputs: false,
            source: .startRecording
        )
        guard permissionReadiness.isReady else {
            permissionRecoveryPresentationPending = true
            presentPendingPermissionRecoveryIfPossible()
            return
        }
        guard canUseConfiguredAPIKey() else { return }
        stopMicrophoneTest()
        pill.setPreferredScreen(paste.captureTarget())
        // Acknowledged on the press, never on the microphone, so the answer does
        // not depend on what is plugged in. `-160` is the no-signal floor: the
        // waveform draws flat until there is really something to draw, rather
        // than claiming a level it cannot have yet.
        playFeedback(.dictationStarted)
        recordingStartedAt = Date.now
        setPhase(.recording(mode: mode, elapsed: 0, level: -160))
        // Told at the press, not at the open. The tap machine reports another key
        // being typed only while it is in held mode, so a mode arriving with the
        // microphone left the whole start window deaf to `fn`+delete — the key
        // this cancel exists for.
        shortcuts.setMode(mode == .held ? .held : .locked)
        handedOff = true
        // Never cancelled, and never more than one: the gate only begins a start
        // from idle, and it leaves idle here until this task answers. Cancelling
        // would not interrupt the session opening anyway — it would only risk
        // skipping the answer, which is the one thing that wedges the gate.
        Task { [weak self] in
            guard let self else { return }
            do {
                try await recorder.start(selection: preferences.audioInputSelection)
                apply(gate.apply(.sessionOpened))
            // Not this dictation's mute, which was never begun — a previous
            // one's pending unmute, which the failure would otherwise strand.
            } catch AudioRecorderError.inputUnavailable(let name) {
                _ = gate.apply(.startFailed)
                endOtherAudioMuting()
                shortcuts.setMode(.idle)
                playFeedback(.terminalFailure)
                showMessage("Microphone “\(name)” is unavailable")
            } catch {
                _ = gate.apply(.startFailed)
                showFailure(error.localizedDescription)
            }
        }
    }

    /// The microphone is open, so the recording can start describing itself: the
    /// timer counts from here rather than from the press, and the meter has
    /// something real to report.
    private func beginMetering(mode: RecordingMode) {
        if preferences.muteOtherAudioWhileDictating { beginOtherAudioMuting() }
        shortcuts.setMode(mode == .held ? .held : .locked)
        setPhase(.recording(mode: mode, elapsed: 0, level: -80))
        startMeter()
    }

    /// The gesture ending this dictation arrived before the microphone opened, so
    /// the file holds nothing. Closed without ever being shown, which is what a
    /// recording too short to have captured anything already gets.
    private func abandonOpenedSession() {
        recorder.cancel()
        feedbackSounds.fadeOut()
        returnToIdle()
    }

    /// Whether two phases are the same recording differing only in the numbers
    /// the meter refreshes. Anything else — starting, locking, stopping — is a
    /// change this object's observers can see, and publishes.
    private static func differsOnlyByMeter(_ lhs: AppPhase, _ rhs: AppPhase) -> Bool {
        guard case .recording(let lhsMode, _, _) = lhs,
              case .recording(let rhsMode, _, _) = rhs
        else { return false }
        return lhsMode == rhsMode
    }

    private func startMeter() {
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
                if elapsed >= 600 { apply(gate.apply(.stopRequested)); return }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopAndTranscribe() {
        meterTask?.cancel()
        meterTask = nil
        endOtherAudioMuting()
        shortcuts.setMode(.busy)
        let elapsed = elapsedSincePress
        Task { [weak self] in
            guard let self else { return }
            do {
                let completed = try await recorder.stop()
                finishRecording(completed)
            } catch {
                shortcuts.setMode(.idle)
                // A recording too short to have captured anything can fail inside
                // AVFoundation rather than coming back empty, and it reaches here.
                // The press was still a misclick, so it still says nothing.
                guard !RecordingCancellationPolicy.isMisclick(elapsed: elapsed) else {
                    feedbackSounds.fadeOut()
                    returnToIdle()
                    return
                }
                showFailure(error.localizedDescription)
            }
        }
    }

    private func finishRecording(_ completed: CompletedRecording) {
        do {
            // A press this brief was never a dictation attempt, so it gets no
            // correction. The start cue fades rather than stopping dead — cutting
            // it makes a slipped finger crack the speaker.
            guard !RecordingCancellationPolicy.isMisclick(elapsed: completed.duration) else {
                AudioRecorder.delete(relativePath: completed.relativePath)
                feedbackSounds.fadeOut()
                returnToIdle()
                return
            }
            // Nothing crossed the signal threshold, so there is nothing to
            // transcribe and no credit to spend — but say so rather than
            // discarding in silence, which makes a muted or wrong input look
            // exactly like not having spoken.
            guard completed.detectedSignal else {
                AudioRecorder.delete(relativePath: completed.relativePath)
                guard RecordingCancellationPolicy.reportsMissingAudio(
                    elapsed: completed.duration,
                    detectedSignal: completed.detectedSignal
                ) else {
                    feedbackSounds.fadeOut()
                    returnToIdle()
                    return
                }
                paste.clearTarget()
                pill.setPreferredScreen(nil)
                shortcuts.setMode(.idle)
                playFeedback(.terminalFailure)
                setPhase(.noAudioSignal)
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
            showFailure(error.localizedDescription)
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
                case .noEditableTarget(let message), .failed(let message):
                    copy(record)
                    record.errorMessage = message
                    try modelContext.save()
                    playFeedback(.cancellationOrCopyFallback)
                    setPhase(.dictationCopied(text: transcript, message: message))
                }
            } else {
                copy(record)
                try modelContext.save()
                setPhase(.transcriptCopied)
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
    /// discarded, since an empty history row would be noise, but not silently: a
    /// dead or wrongly selected input is the likeliest cause and the user needs to
    /// be able to tell "no words" from "nothing happened".
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
        retireRestingNotice()
        openSettingsWindow(destination: .microphone)
    }

    private func cancelRecording() {
        guard case .recording = phase else { return }
        let elapsed = elapsedSincePress
        meterTask?.cancel()
        meterTask = nil
        endOtherAudioMuting()
        if elapsed < RecordingCancellationPolicy.recoveryThreshold {
            recorder.cancel()
            // `fn` doubles as the modifier half of other shortcuts, so this fires on
            // presses aimed at something else entirely. Those close in silence.
            guard !RecordingCancellationPolicy.isMisclick(elapsed: elapsed) else {
                feedbackSounds.fadeOut()
                returnToIdle()
                return
            }
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
                showFailure(error.localizedDescription)
            }
        }
    }

    private func cancelHeldRecordingForTypingIfNeeded() {
        guard gate.cancelsForTyping(elapsed: elapsedSincePress) else { return }
        apply(gate.apply(.cancelRequested))
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
            showFailure(error.localizedDescription)
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
            apply(gate.apply(.cancelRequested))
        case .hideTranscription:
            suppressPillForCurrentTranscription = true
            pill.dismiss()
        case .dismiss:
            returnToIdle()
        }
        return true
    }

    /// Clicking the pill body. Every destination here is one the pill already
    /// offers on a button; nothing transcribes, cancels, or discards, so landing
    /// a click by accident costs a window at worst.
    private func performPillDefaultAction() {
        switch phase.pillDefaultAction(isPresented: pill.isPresented) {
        case .none:
            break
        case .openMainWindow:
            openMainWindow()
        case .openPermissionSettings:
            openPermissionSettings()
        case .openCredentialSettings:
            credentialReadiness.resolvesInUsageSettings ? openUsageSettings() : openAPIKeySettings()
        case .openInputSettings:
            openMicrophoneInputSettings()
        case .dismiss:
            returnToIdle()
        }
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

    private func showFailure(_ message: String, playTerminalFeedback: Bool = true) {
        endOtherAudioMuting()
        if playTerminalFeedback { playFeedback(.terminalFailure) }
        shortcuts.setMode(.idle)
        setPhase(.transcriptionFailed(message))
    }

    private func playFeedback(_ cue: DictationFeedbackCue) {
        guard preferences.playDictationFeedbackSounds else { return }
        feedbackSounds.play(cue)
    }

    /// Asks for System Audio Recording at the moment the user opts in, rather
    /// than during their next dictation — where the prompt arrives with the
    /// shortcut still held down and the answer is owed before anything moves.
    func requestOtherAudioAccess() {
        Task.detached {
            let status = OtherAudioMuteService.requestAccess()
            await MainActor.run { [weak self] in
                Self.permissionLog.notice("mute: access request status=\(status, privacy: .public)")
                _ = self
            }
        }
    }

    private func beginOtherAudioMuting() {
        // A dictation starting inside the settle delay keeps the tap it already
        // has, rather than tearing one down and building another.
        pendingUnmute?.cancel()
        pendingUnmute = nil
        // Behind the recording rather than in front of it: building the tap is a
        // chain of blocking Core Audio calls, and a mute that is slow or fails
        // has no claim on how soon the pill appears.
        Task { [weak self] in
            guard let self else { return }
            let outcome = await otherAudioMuting.beginMuting()
            // The Core Audio status, so a mute that quietly does nothing can be told
            // from one that works. Nothing here reads or reports any audio.
            switch outcome {
            case .muted, .alreadyMuted:
                Self.permissionLog.notice(
                    "mute: started outcome=\(String(describing: outcome), privacy: .public)"
                )
                otherAudioMuteStatus = nil
            case .unavailable(let status):
                // Nothing on screen: the audio that failed to stop is audible, and a
                // warning about it tells the user what they are already hearing.
                Self.permissionLog.error("mute: refused status=\(status, privacy: .public)")
            }
        }
    }

    /// The mute outlasts the recording by a moment, so other apps do not come
    /// back in the same instant the input stream closes.
    private func endOtherAudioMuting() {
        pendingUnmute?.cancel()
        pendingUnmute = Task { [weak self] in
            try? await Task.sleep(for: .seconds(OtherAudioMutePolicy.restoreDelay))
            guard !Task.isCancelled else { return }
            self?.restoreOtherAudio()
        }
    }

    private func restoreOtherAudio() {
        pendingUnmute?.cancel()
        pendingUnmute = nil
        Task { [weak self] in
            guard let self else { return }
            report(unmuting: await otherAudioMuting.endMuting())
        }
    }

    /// Termination has no later turn to finish in, so this one blocks. A tap that
    /// outlives the process leaves the Mac silent with nothing left to fix it.
    private func restoreOtherAudioBeforeTerminating() {
        pendingUnmute?.cancel()
        pendingUnmute = nil
        report(unmuting: otherAudioMuting.endMutingImmediately())
    }

    private func report(unmuting outcome: OtherAudioUnmutingOutcome) {
        switch outcome {
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

    /// Takes down a notice about a dictation that already ended, because the
    /// action it offered has just been taken and the window answers it from here.
    ///
    /// Only the pill's own actions reach this. Command-comma, the menu bar item,
    /// and the toolbar's warning open the same windows and leave the pill alone:
    /// opening a window says nothing about the dictation a notice reports, and a
    /// cancelled-dictation pill would otherwise have its Undo thrown away by a
    /// trip to Settings.
    ///
    /// A dictation still in flight is never ended here, so do not drop the guard.
    /// `returnToIdle` takes the pill down and leaves the recorder running, and the
    /// next press then stops and transcribes the orphan.
    private func retireRestingNotice() {
        guard gate.isIdle else { return }
        returnToIdle()
    }

    /// When the press that began this dictation arrived.
    ///
    /// The cancellation thresholds count from the press, not from the microphone
    /// opening, and they cannot read `phase` — the meter no longer publishes into
    /// it, so its elapsed time is frozen at the last material change. The pill
    /// keeps its own clock, which is what the user sees.
    private var recordingStartedAt: Date?

    private var elapsedSincePress: TimeInterval {
        guard let recordingStartedAt else { return 0 }
        return Date.now.timeIntervalSince(recordingStartedAt)
    }

    private func returnToIdle() {
        recordingStartedAt = nil
        endOtherAudioMuting()
        suppressPillForCurrentTranscription = false
        paste.clearTarget()
        pill.setPreferredScreen(nil)
        shortcuts.setMode(.idle)
        setPhase(.idle)
    }

    private func setPhase(_ phase: AppPhase) {
        // The meter re-enters here ten times a second with a fresh level and
        // elapsed time. `ObservableObject` publishes per object, and `AppRuntime`
        // forwards this one's `objectWillChange` to every view holding it, so a
        // tick that changes only the pill's numbers re-lays out the menu bar and
        // every open window — about 42% of a core on an M4 through a dictation,
        // against 2% for the capture itself.
        //
        // So this property's level and elapsed time are stale for the length of a
        // recording, and the pill draws them from its own model instead. Anything
        // needing either live takes it as a parameter — do not read them here.
        if !Self.differsOnlyByMeter(phase, self.phase) { self.phase = phase }
        if suppressPillForCurrentTranscription {
            pill.dismiss()
        } else {
            pill.update(phase)
        }
    }

}
