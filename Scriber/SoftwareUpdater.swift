import AppKit
import Combine
import os
import Sparkle

/// Scriber's side of Sparkle. Sparkle finds, downloads, verifies and installs an
/// update; this decides when one may install, and holds what Settings and the
/// menu bar say about it.
///
/// It is Sparkle's user driver as well as its delegate, so Sparkle draws no
/// window of its own: everything it would have shown arrives here and becomes
/// the Settings status line or the menu bar's offer.
@MainActor
final class SoftwareUpdater: NSObject, ObservableObject {
    @Published private(set) var offer: UpdateOffer = .none
    @Published private(set) var isChecking = false
    @Published private(set) var checkError: String?

    private static let log = Logger(subsystem: "com.gafiegarcia.scriber", category: "updates")
    private static let checkInterval: TimeInterval = 60 * 60 * 24
    /// How often a waiting install looks again for the dictation it is waiting on.
    private static let busyRetryInterval: TimeInterval = 2

    private let preferences: Preferences
    private let dictationWorkInFlight: () -> Bool
    private var updater: SPUUpdater?
    private var cancellables = Set<AnyCancellable>()

    /// The update the current Sparkle session is about, which
    /// `showReady(toInstallAndRelaunch:)` is not told again.
    private var sessionUpdate: StagedUpdate?
    /// Whoever asked for the update now — Install, a lock, a launch that found
    /// one left over — is answered Install at the next point Sparkle asks.
    private var installRequested = false
    /// A launch that found an update staged by an earlier one that never ran it.
    private var installsAtLaunch = false
    private var immediateInstall: (() -> Void)?
    private var waitingInstall: (lockBound: Bool, action: () -> Void)?
    private var waitTimer: Timer?
    private var screenLocked = false
    private var informationOnlyURL: URL?

    init(preferences: Preferences, dictationWorkInFlight: @escaping () -> Bool) {
        self.preferences = preferences
        self.dictationWorkInFlight = dictationWorkInFlight
        super.init()
    }

    func start() {
        guard updater == nil else { return }
        noteLaunch()

        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        self.updater = updater
        apply(automaticallyUpdate: preferences.automaticallyUpdate)
        do {
            try updater.start()
        } catch {
            Self.log.error("updater did not start: \(error.localizedDescription, privacy: .public)")
            self.updater = nil
            return
        }

        // `$` publishes before the property changes, so the new value is the
        // one handed in rather than the one read back.
        preferences.$automaticallyUpdate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isOn in self?.automaticallyUpdateChanged(isOn) }
            .store(in: &cancellables)

        // Platform: `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
        // are undocumented, and are the only signal that the lock screen is up.
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .sink { [weak self] _ in Task { @MainActor in self?.screenLockChanged(true) } }
            .store(in: &cancellables)
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .sink { [weak self] _ in Task { @MainActor in self?.screenLockChanged(false) } }
            .store(in: &cancellables)

        if installsAtLaunch {
            Self.log.notice("an update staged by an earlier launch never installed; installing it now")
            updater.checkForUpdatesInBackground()
        }
    }

    /// Check for Updates.
    func checkNow() {
        guard let updater, updater.canCheckForUpdates else { return }
        checkError = nil
        updater.checkForUpdates()
    }

    /// Install and Install Now, and the menu bar's update item: download if need
    /// be, then install and relaunch as soon as no dictation is in flight.
    func install() {
        if let informationOnlyURL, case .available = offer {
            NSWorkspace.shared.open(informationOnlyURL)
            return
        }
        installWhenIdle(lockBound: false) { [weak self] in self?.installNow() }
    }

    private func installNow() {
        installRequested = true
        if let immediateInstall {
            immediateInstall()
            return
        }
        guard let updater else { return }
        // A session already running reaches `showUpdateFound` or
        // `showReady(toInstallAndRelaunch:)`, both of which read the request.
        guard !updater.sessionInProgress else { return }
        if case .available(let version) = offer { offer = .downloading(version: version) }
        updater.checkForUpdates()
    }

    private func noteLaunch() {
        // Do not: move this below the clearing of `stagedUpdate`. The launch
        // decides whether to show a window from that record, and reads it once.
        _ = AppLaunchConfiguration.relaunchesIntoStagedUpdate
        let running = AppCoordinator.runningBuild
        if let previous = preferences.lastLaunchedBuild, BuildNumber.isNewer(running, than: previous) {
            preferences.recentUpdate = RecentUpdate(version: AppCoordinator.runningVersion, date: Date())
        }
        preferences.lastLaunchedBuild = running

        guard let staged = preferences.stagedUpdate else { return }
        if staged.isPending(runningBuild: running), preferences.automaticallyUpdate {
            installsAtLaunch = true
        } else {
            preferences.stagedUpdate = nil
        }
    }

    private func apply(automaticallyUpdate isOn: Bool) {
        guard let updater else { return }
        // Off still checks: an install switched off by accident must go on
        // hearing about a security fix.
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = Self.checkInterval
        updater.automaticallyDownloadsUpdates = isOn
    }

    private func automaticallyUpdateChanged(_ isOn: Bool) {
        apply(automaticallyUpdate: isOn)
        // An offer already on screen is downloaded now rather than at tomorrow's
        // check, which is what switching this on asks for.
        if isOn, case .available = offer, let updater, !updater.sessionInProgress {
            updater.checkForUpdatesInBackground()
        }
    }

    private func screenLockChanged(_ locked: Bool) {
        screenLocked = locked
        if locked {
            scheduleLockInstallIfReady()
        } else if waitingInstall?.lockBound == true {
            // Unlocked before the dictation it waited on finished: the moment
            // it was waiting for has passed, and the user is back.
            waitingInstall = nil
            waitTimer?.invalidate()
            waitTimer = nil
        }
    }

    private func scheduleLockInstallIfReady() {
        guard screenLocked, preferences.automaticallyUpdate, case .ready = offer else { return }
        installWhenIdle(lockBound: true) { [weak self] in self?.installNow() }
    }

    private func markStaged(_ update: StagedUpdate) {
        offer = .ready(version: update.version)
        if preferences.stagedUpdate != update { preferences.stagedUpdate = update }
        Self.log.notice("update \(update.version, privacy: .public) (\(update.build, privacy: .public)) staged")
        scheduleLockInstallIfReady()
    }

    /// Runs `action` once nothing a dictation started is still running. One
    /// waiting install at a time; a newer request replaces an older one.
    /// `lockBound` drops it if the screen unlocks first.
    private func installWhenIdle(lockBound: Bool, _ action: @escaping () -> Void) {
        waitingInstall = (lockBound, action)
        attemptWaitingInstall()
    }

    private func attemptWaitingInstall() {
        waitTimer?.invalidate()
        waitTimer = nil
        guard let waiting = waitingInstall else { return }
        if waiting.lockBound && !screenLocked {
            waitingInstall = nil
            return
        }
        guard !dictationWorkInFlight() else {
            waitTimer = Timer.scheduledTimer(withTimeInterval: Self.busyRetryInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.attemptWaitingInstall() }
            }
            return
        }
        waitingInstall = nil
        waiting.action()
    }

    private static func isNoUpdate(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }
        return error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)
    }
}

extension SoftwareUpdater: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Legacy: `SUEnableAutomaticChecks` in Info.plist means Sparkle never
        // asks. Answered anyway, since an unanswered request stalls the updater.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        isChecking = true
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        isChecking = false
        checkError = nil
        let update = StagedUpdate(version: appcastItem.displayVersionString, build: appcastItem.versionString)
        sessionUpdate = update

        if appcastItem.isInformationOnlyUpdate {
            informationOnlyURL = appcastItem.infoURL ?? UpdateLinks.releasePage(version: update.version)
            installRequested = false
            offer = .available(version: update.version)
            reply(.dismiss)
            return
        }
        informationOnlyURL = nil

        if installRequested || installsAtLaunch {
            if state.stage == .notDownloaded { offer = .downloading(version: update.version) }
            reply(.install)
            return
        }

        switch state.stage {
        case .notDownloaded:
            if preferences.automaticallyUpdate {
                // A check the user made with the switch on: download now, and
                // `showReady(toInstallAndRelaunch:)` stages it.
                offer = .downloading(version: update.version)
                reply(.install)
            } else {
                offer = .available(version: update.version)
                // Dismissed rather than held: a held reply keeps the session
                // open, and an open session stops the next day's check from
                // finding anything newer. Install asks Sparkle again.
                reply(.dismiss)
            }
        case .downloaded, .installing:
            markStaged(update)
            // The installer is kept, and installs when Scriber quits.
            reply(.dismiss)
        @unknown default:
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        isChecking = false
        checkError = nil
        installRequested = false
        if case .available = offer { offer = .none }
        if case .downloading = offer { offer = .none }
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        isChecking = false
        installRequested = false
        Self.log.error("update failed: \(error.localizedDescription, privacy: .public)")
        if case .downloading(let version) = offer {
            offer = .available(version: version)
            checkError = "Could not download \(AppCoordinator.displayVersion(version))."
        } else {
            checkError = "Could not reach GitHub to check for updates."
        }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {}

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installRequested || installsAtLaunch {
            installWhenIdle(lockBound: false) { reply(.install) }
            return
        }
        if let sessionUpdate { markStaged(sessionUpdate) }
        // The installer is kept, and installs when Scriber quits; a lock, or
        // Install Now, resumes it through `installNow`.
        reply(.dismiss)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        Self.log.notice("installing update, applicationTerminated=\(applicationTerminated, privacy: .public)")
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        isChecking = false
    }
}

extension SoftwareUpdater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        AppLaunchConfiguration.debugAppcastURL
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        immediateInstall = immediateInstallHandler
        markStaged(StagedUpdate(version: item.displayVersionString, build: item.versionString))
        if installRequested || installsAtLaunch {
            installWhenIdle(lockBound: false) { [weak self] in self?.installNow() }
        }
        // Scriber decides when: at the next lock, or now if asked. Sparkle
        // installs it on quit either way.
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        isChecking = false
        // Only a check that got an answer counts, so an install that has never
        // reached the appcast does not claim to be current.
        if error == nil || Self.isNoUpdate(error) { preferences.lastUpdateCheck = Date() }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // A background check, which reaches no user driver method: an offer
        // whose release was pulled goes with it.
        if case .available = offer { offer = .none }
    }

    // Do not: implement `updaterShouldRelaunchApplication` to keep a test build
    // from relaunching. Answering no does not skip the relaunch, it cancels the
    // install. `launchArguments` (`ScriberApp.swift`) is what keeps a relaunched
    // test build a test build.
}
