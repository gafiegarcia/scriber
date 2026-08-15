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
    /// Settings, on the Permissions tab. Distinct from `.settings`, which names
    /// no tab and so leaves the one already showing alone: a route that exists
    /// to fix something has to land on the tab that owns it, and an ordinary
    /// opening must not drag the user off the tab they chose.
    case permissions
}

struct MainWindowRequest: Equatable {
    let id = UUID()
    let destination: MainWindowDestination
}

/// Whether a Settings shortcut recorder currently owns the keyboard.
///
/// Shared rather than held on the coordinator because the reader is
/// `AppDelegate`, which SwiftUI creates on its own and which is handed no
/// runtime. It describes one app-wide keyboard mode, and both the app and the
/// delegate are singletons, so there is nothing here for an instance to own.
@MainActor
enum ShortcutConfigurationCapture {
    static var isActive = false
}

@MainActor
final class AppCoordinator: ObservableObject {
    /// Fallback cadence for permission state that macOS does not announce. This
    /// runs for the whole life of a menu-bar app, so it is deliberately slow; the
    /// Accessibility hint and the activation refresh cover the cases a user can
    /// actually notice.
    private static let permissionPollInterval: TimeInterval = 5

    /// Records only permission booleans, state names, and which refresh path
    /// observed them. No user content passes through here.
    private static let permissionLog = Logger(
        subsystem: "com.gafiegarcia.scriber",
        category: "permissions"
    )

    /// Which caller drove a permission refresh. Every reading below is unchanged
    /// on almost every tick, so a logged change names the path that caught it —
    /// a grant the poll never observed and an ordinary grant look identical
    /// otherwise.
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
    @Published private(set) var microphoneTestLevel: Float = -160
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

    let preferences: Preferences
    let modelContext: ModelContext

    private let servicesAllowed: Bool
    private let persistenceAvailable: Bool
    private let permissionReadinessOverride: PermissionReadiness?
    private let keychain = KeychainStore()
    private let recorder = AudioRecorder()
    private let scribe = ScribeClient()
    private let updateChecker = UpdateChecker()
    private let paste = PasteService()
    private let login = LaunchAtLoginService()
    private let pill = PillController()
    private let shortcuts: GlobalShortcutService
    private let feedbackSounds: RecordingFeedbackSoundPlaying
    private let otherAudioMuting: OtherAudioMuting
    private let historyMaintenance: DictationHistoryMaintenance
    private var meterTask: Task<Void, Never>?
    private var microphoneTestTask: Task<Void, Never>?
    private var currentRecord: DictationRecord?
    private var currentRecording: CompletedRecording?
    private var checkedStoredAPIKeyThisLaunch = false
    private var isCheckingStoredAPIKey = false
    private var storedAPIKeyValidationTask: Task<Void, Never>?
    /// Separate from `preferences.lastUpdateCheck`, which records only a check
    /// that got an answer. `startServices` runs again every time the menu bar
    /// opens, so without an in-session stamp a failed check starts a new
    /// twenty-second request each time.
    private var lastUpdateAttempt: Date?
    private var credentialRevision = CredentialRevision()
    private var suppressPillForCurrentTranscription = false
    /// Whether setup is being walked a second time. `onboardingComplete` cannot
    /// answer this — Redo Setup clears it, so a redo and a first run look
    /// identical to it — and the two differ in what a step should offer:
    /// a first run recommends, a redo shows what is already there.
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
        historyMaintenance = DictationHistoryMaintenance(
            modelContext: modelContext,
            servicesAllowed: servicesAllowed
        )
        shortcuts = GlobalShortcutService(
            hold: preferences.holdShortcut,
            toggle: preferences.toggleShortcut,
            holdEnabled: preferences.holdShortcutEnabled,
            toggleEnabled: preferences.toggleShortcutEnabled
        )

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
                        presentRecoveryWhenMissing: false,
                        refreshAudioInputs: true,
                        source: .activation
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
        case .microphoneDroppedOut: "Microphone cut out"
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
            // Assign only on change. `@Published` publishes on every assignment,
            // and the poll above runs on `.common`, so it fires while a menu is
            // tracking. A no-op write there re-evaluates the whole `App` body,
            // SwiftUI reinstalls the main menu, and the open Window menu loses
            // the items AppKit contributes from the key window — Close ⌘W among
            // them. Every reading here is unchanged on almost every tick.
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
    /// toggle can grant this, so the pane is the whole action. Raising the system
    /// prompt as well would add nothing: it cannot grant the permission, macOS shows
    /// it once per app, and what lists Scriber in that pane is the trust check every
    /// launch already makes — a fresh process registers itself, a running one cannot.
    func allowAccessibility() {
        openAccessibilitySettings()
    }

    private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The Login Items list, the only place a switched-off entry can be turned
    /// back on.
    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The macOS Sound settings, where the input volume lives. Scriber's own
    /// input picker cannot show or change that volume, so a level meter reading
    /// flat has to point somewhere the user can act.
    func openSystemSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The `Privacy_ScreenCapture` anchor is what lands on Screen & System Audio
    /// Recording; without it the pane opens at the top of Privacy & Security,
    /// several screens of scrolling from the row this is sent from.
    func openSystemAudioPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func startMicrophoneTest() {
        guard microphoneGranted, !phase.isBusy else { return }
        stopMicrophoneTest()
        do {
            try recorder.startMonitoring(selection: preferences.audioInputSelection)
            microphoneTestError = nil
            microphoneTestLevel = -160
            isMicrophoneTestRunning = true
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
    /// inside the app.
    ///
    /// It could not before: Settings offered no way to remove a saved key, so
    /// checking that Scriber reports a missing key on its own meant deleting the
    /// item in Keychain Access. That is a bad way to find out whether your own app
    /// handles its own failure state.
    ///
    /// Cancels any in-flight validation first and advances the revision, so a
    /// validation that was already running cannot land afterwards and mark the key
    /// valid again.
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

    /// Sends the user back through onboarding.
    ///
    /// Only the flag is cleared. The key, grants, and history stay where they are —
    /// onboarding reads current state, so it presents each step as already
    /// satisfied rather than asking for it again, and nothing is destroyed by
    /// looking at it a second time.
    func restartOnboarding() {
        isRedoingSetup = true
        preferences.onboardingComplete = false
        // `openWindow(id:)` creates the scene but does not reliably bring it in
        // front of the window the action was invoked from — the first attempt left
        // onboarding rendered behind Settings, with Settings no longer the key
        // window. Ordering and activation already have one careful implementation
        // in `AppDelegate.showWindow(titled:)`; route through it rather than
        // building a second.
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .openScriberOnboardingWindow, object: nil)
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    /// `force` is the Check Now button: it ignores the once-a-day interval but
    /// not the `servicesAllowed` gate, so a `--ui-testing` launch reaches no
    /// network from either path.
    func checkForUpdates(force: Bool = false) {
        guard servicesAllowed else { return }
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
        ShortcutConfigurationCapture.isActive = active
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

    private func handleHandsFreePillAction(_ action: HandsFreePillAction) {
        guard let disposition = action.disposition(for: phase) else { return }
        switch disposition {
        case .cancelRecording:
            cancelRecording()
        case .finishRecording:
            stopAndTranscribe()
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
        openMainWindow(destination: .dictation)
    }

    func openAPIKeySettings() {
        openSettingsWindow(destination: .apiKey)
    }

    func openUsageSettings() {
        openSettingsWindow(destination: .usage)
    }

    func openPermissionSettings() {
        openSettingsWindow(destination: .permissions)
    }

    func selectMainWindowDestination(_ destination: MainWindowDestination) {
        mainWindowRequest = MainWindowRequest(destination: destination)
    }

    /// Discards a request once the window has acted on it.
    ///
    /// A request that outlives its own delivery gets re-applied every time the
    /// window appears again, so a single trip to the key field would go on
    /// selecting the ElevenLabs tab and taking focus on every later opening.
    /// Settings is the only reader, so nothing else loses anything by this.
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
        returnToIdle()
        NSApp.setActivationPolicy(.regular)
        // The opener creates the scene if it does not exist yet; the
        // notification is what orders an existing window front and carries the
        // activation retries every other managed window already relies on.
        settingsWindowOpener?()
        NotificationCenter.default.post(name: .openScriberSettingsWindow, object: nil)
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
            showFailure(error.localizedDescription)
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
        var elapsed: TimeInterval = 0
        if case .recording(_, let value, _) = phase { elapsed = value }
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
            // correction: the signal and duration guards below both speak up, and
            // to someone whose finger slipped they are noise about something they
            // never asked for. The start cue fades rather than stopping dead,
            // which is what made a slipped finger crack the speaker.
            guard !RecordingCancellationPolicy.isMisclick(elapsed: completed.duration) else {
                AudioRecorder.delete(relativePath: completed.relativePath)
                feedbackSounds.fadeOut()
                returnToIdle()
                return
            }
            // Discarded, as before — nothing crossed the signal threshold, so there
            // is nothing to transcribe and no reason to spend credit on it. What
            // changed is that it no longer happens in silence.
            //
            // This was the one terminal outcome with no feedback of any kind: no
            // transcript, no history row, no sound, no pill, just the recording
            // pill vanishing. A microphone that is muted, set to zero input volume,
            // or simply the wrong device therefore looked exactly like not having
            // spoken, and there was nothing on screen to suggest otherwise.
            guard completed.detectedSignal else {
                AudioRecorder.delete(relativePath: completed.relativePath)
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
                    // The words that arrived are real and belong at the cursor, but
                    // the ones after the microphone went quiet are simply gone. The
                    // pill closing without a word is what made that invisible.
                    if recording.microphoneDroppedOut {
                        setPhase(.microphoneDroppedOut(deliveredPartialText: true))
                    } else {
                        returnToIdle()
                    }
                case .noEditableTarget(let message), .failed(let message):
                    copy(record)
                    record.errorMessage = message
                    try modelContext.save()
                    playFeedback(.cancellationOrCopyFallback)
                    // A microphone that died outranks why the paste missed: the
                    // clipboard already answers where the text went, and nothing
                    // else explains the half of it that never arrived.
                    let droppedOut = recording.microphoneDroppedOut
                    setPhase(.dictationCopied(
                        text: transcript,
                        message: droppedOut ? "Microphone cut out — part of this dictation is missing" : message,
                        microphoneDroppedOut: droppedOut
                    ))
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
        // "No words detected" blames the speaker. When the microphone stopped
        // sending partway through, the words may well have been said into a stream
        // that was no longer listening, and only the dropout explains it.
        if recording.microphoneDroppedOut {
            setPhase(.microphoneDroppedOut(deliveredPartialText: false))
        } else {
            setPhase(.noSpeechDetected)
        }
    }

    func openMicrophoneInputSettings() {
        openSettingsWindow(destination: .microphone)
    }

    private func cancelRecording() {
        guard case .recording(_, let elapsed, _) = phase else { return }
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
            cancelRecording()
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

}
