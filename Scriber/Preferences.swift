import Combine
import Foundation
#if SWIFT_PACKAGE
import ScriberCore
#endif

@MainActor
final class Preferences: ObservableObject {
    private enum Keys {
        static let apiKeyConfigured = "apiKeyConfigured"
        static let apiKeyValidity = "apiKeyValidity"
        static let subscriptionUsage = "subscriptionUsage"
        static let apiCreditsExhausted = "apiCreditsExhausted"
        static let dictationShortcut = "dictationShortcut"
        static let customShortcut = "customShortcut"
        /// Read once, to carry an install stored under an older key onto the
        /// dictation shortcut. Never written.
        static let legacyHoldShortcut = "holdShortcut"
        static let languageCode = "languageCode"
        static let noVerbatim = "noVerbatim"
        static let keyterms = "keyterms"
        static let onboardingComplete = "onboardingComplete"
        static let startInBackground = "startInBackground"
        static let showInMenuBar = "showInMenuBar"
        static let showAppInDock = "showAppInDock"
        static let audioInputSelection = "audioInputSelection"
        static let playRecordingFeedbackSounds = "playRecordingFeedbackSounds"
        static let muteOtherAudioWhileRecording = "muteOtherAudioWhileRecording"
        static let deletesExpiredRetainedAudio = "deletesExpiredRetainedAudio"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let availableUpdate = "availableUpdate"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published var apiKeyConfigured: Bool { didSet { defaults.set(apiKeyConfigured, forKey: Keys.apiKeyConfigured) } }
    @Published var apiKeyValidity: APIKeyValidity { didSet { defaults.set(apiKeyValidity.rawValue, forKey: Keys.apiKeyValidity) } }
    @Published var subscriptionUsage: ElevenLabsSubscriptionUsage? { didSet { save(subscriptionUsage, key: Keys.subscriptionUsage) } }
    @Published var apiCreditsExhausted: Bool { didSet { defaults.set(apiCreditsExhausted, forKey: Keys.apiCreditsExhausted) } }
    @Published var dictationShortcut: ShortcutChord { didSet { save(dictationShortcut, key: Keys.dictationShortcut) } }
    /// The last shortcut the user recorded, kept so switching to a preset and
    /// back does not lose it.
    @Published var customShortcut: ShortcutChord? { didSet { save(customShortcut, key: Keys.customShortcut) } }
    @Published var languageCode: String { didSet { defaults.set(languageCode, forKey: Keys.languageCode) } }
    @Published var noVerbatim: Bool { didSet { defaults.set(noVerbatim, forKey: Keys.noVerbatim) } }
    @Published var keyterms: [String] { didSet { save(keyterms, key: Keys.keyterms) } }
    @Published var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Keys.onboardingComplete) } }
    @Published var startInBackground: Bool { didSet { defaults.set(startInBackground, forKey: Keys.startInBackground) } }
    @Published var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) } }
    @Published var showAppInDock: Bool {
        didSet {
            defaults.set(showAppInDock, forKey: Keys.showAppInDock)
            NotificationCenter.default.post(name: .showAppInDockDidChange, object: showAppInDock)
        }
    }
    @Published var audioInputSelection: AudioInputSelection { didSet { save(audioInputSelection, key: Keys.audioInputSelection) } }
    @Published var playRecordingFeedbackSounds: Bool {
        didSet { defaults.set(playRecordingFeedbackSounds, forKey: Keys.playRecordingFeedbackSounds) }
    }
    @Published var muteOtherAudioWhileRecording: Bool {
        didSet { defaults.set(muteOtherAudioWhileRecording, forKey: Keys.muteOtherAudioWhileRecording) }
    }
    @Published var deletesExpiredRetainedAudio: Bool {
        didSet { defaults.set(deletesExpiredRetainedAudio, forKey: Keys.deletesExpiredRetainedAudio) }
    }
    @Published var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: Keys.automaticUpdateChecks) }
    }
    @Published var lastUpdateCheck: Date? { didSet { defaults.set(lastUpdateCheck, forKey: Keys.lastUpdateCheck) } }
    @Published var availableUpdate: AvailableUpdate? { didSet { save(availableUpdate, key: Keys.availableUpdate) } }

    init(
        defaults: UserDefaults = .standard,
        defaultAudioInputSelection: AudioInputSelection = .automatic
    ) {
        self.defaults = defaults
        apiKeyConfigured = defaults.bool(forKey: Keys.apiKeyConfigured)
        apiKeyValidity = defaults.string(forKey: Keys.apiKeyValidity).flatMap(APIKeyValidity.init(rawValue:)) ?? .unchecked
        subscriptionUsage = Self.decode(ElevenLabsSubscriptionUsage.self, key: Keys.subscriptionUsage, defaults: defaults)
        apiCreditsExhausted = defaults.bool(forKey: Keys.apiCreditsExhausted)
        let storedDictation = Self.decode(ShortcutChord.self, key: Keys.dictationShortcut, defaults: defaults)
            ?? Self.decode(ShortcutChord.self, key: Keys.legacyHoldShortcut, defaults: defaults)
            ?? .defaultDictation
        let resolvedDictation = ShortcutPreferences.resolve(dictation: storedDictation)
        dictationShortcut = resolvedDictation
        // Anything already bound that is not one of the presets was recorded by
        // hand, whether or not this key existed when it was.
        customShortcut = Self.decode(ShortcutChord.self, key: Keys.customShortcut, defaults: defaults)
            ?? (SuggestedShortcuts.offers.contains(resolvedDictation) ? nil : resolvedDictation)
        languageCode = defaults.string(forKey: Keys.languageCode) ?? "auto"
        noVerbatim = defaults.object(forKey: Keys.noVerbatim) == nil ? true : defaults.bool(forKey: Keys.noVerbatim)
        keyterms = Self.decode([String].self, key: Keys.keyterms, defaults: defaults) ?? []
        onboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
        startInBackground = Self.optInFlag(Keys.startInBackground, in: defaults)
        showInMenuBar = defaults.object(forKey: Keys.showInMenuBar) == nil ? true : defaults.bool(forKey: Keys.showInMenuBar)
        showAppInDock = defaults.bool(forKey: Keys.showAppInDock)
        audioInputSelection = Self.decode(AudioInputSelection.self, key: Keys.audioInputSelection, defaults: defaults) ?? defaultAudioInputSelection
        playRecordingFeedbackSounds = defaults.object(forKey: Keys.playRecordingFeedbackSounds) == nil
            ? true
            : defaults.bool(forKey: Keys.playRecordingFeedbackSounds)
        // Off by default, unlike its neighbours above: turning it on is what
        // makes macOS demand System Audio Recording, and an opt-out default
        // would spend that prompt during a first dictation.
        muteOtherAudioWhileRecording = defaults.bool(forKey: Keys.muteOtherAudioWhileRecording)
        deletesExpiredRetainedAudio = defaults.object(forKey: Keys.deletesExpiredRetainedAudio) == nil
            ? true
            : defaults.bool(forKey: Keys.deletesExpiredRetainedAudio)
        automaticUpdateChecks = Self.optInFlag(Keys.automaticUpdateChecks, in: defaults)
        lastUpdateCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        availableUpdate = Self.decode(AvailableUpdate.self, key: Keys.availableUpdate, defaults: defaults)

        // Materialize opt-in defaults so upgrades and subsequent launches share one explicit value.
        if defaults.object(forKey: Keys.playRecordingFeedbackSounds) == nil {
            defaults.set(true, forKey: Keys.playRecordingFeedbackSounds)
        }
        if defaults.object(forKey: Keys.deletesExpiredRetainedAudio) == nil {
            defaults.set(true, forKey: Keys.deletesExpiredRetainedAudio)
        }
        if defaults.object(forKey: Keys.startInBackground) == nil {
            defaults.set(true, forKey: Keys.startInBackground)
        }
        if defaults.object(forKey: Keys.automaticUpdateChecks) == nil {
            defaults.set(true, forKey: Keys.automaticUpdateChecks)
        }
        // The chord above was read before `didSet` was live, so it has to be
        // written back here — otherwise a replaced one is replaced again on every
        // launch, and one carried over from the old key is carried over forever.
        if defaults.object(forKey: Keys.dictationShortcut) == nil || dictationShortcut != storedDictation {
            save(dictationShortcut, key: Keys.dictationShortcut)
        }
    }

    /// Reads a flag that is on until the user turns it off. `bool(forKey:)` alone
    /// returns false for a key nobody has written, which is the wrong answer for
    /// these. `AppLaunchConfiguration` reads the same keys straight from
    /// `UserDefaults` before `Preferences` exists, so the rule lives here rather
    /// than being spelled out at each site.
    static func optInFlag(_ key: String, in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    /// Takes an optional because several of these are one: `JSONEncoder` refuses
    /// a top-level `nil`, so encoding it would leave the previous value in
    /// `UserDefaults` and a cleared preference would come back on relaunch.
    private func save<T: Encodable>(_ value: T?, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
