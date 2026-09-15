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
        /// Legacy: the stored name still says "complete" because every install
        /// already carries it under that key and the flag's meaning did not
        /// change when the property was renamed — only its honesty did. Renaming
        /// the key would cost a migration and buy nothing a reader can see.
        static let onboardingDismissed = "onboardingComplete"
        static let onboardingStep = "onboardingStep"
        static let startInBackground = "startInBackground"
        static let showInMenuBar = "showInMenuBar"
        static let showAppInDock = "showAppInDock"
        static let audioInputSelection = "audioInputSelection"
        static let playDictationFeedbackSounds = "playDictationFeedbackSounds"
        static let muteOtherAudioWhileDictating = "muteOtherAudioWhileDictating"
        static let retainedAudioRetention = "retainedAudioRetention"
        /// The boolean this replaced. Read once, to carry over an answer already
        /// given; never written again.
        static let legacyDeletesExpiredRetainedAudio = "deletesExpiredRetainedAudio"
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
    /// Whether Scriber may stop presenting setup on its own. **Done** and **Skip
    /// Setup** both set it and nothing else does, because both mean the same
    /// thing to the person pressing them; **Redo Setup** is how they ask for it
    /// back. It says nothing about how much of setup was actually answered —
    /// a skip sets it having answered none of it.
    @Published var onboardingDismissed: Bool { didSet { defaults.set(onboardingDismissed, forKey: Keys.onboardingDismissed) } }
    /// How far setup had got, so granting a permission macOS then wants the app
    /// relaunched for returns to the step that asked rather than to the start.
    @Published var onboardingStep: Int { didSet { defaults.set(onboardingStep, forKey: Keys.onboardingStep) } }

    /// Whether the dictation services — the shortcut tap above all — may run.
    ///
    /// Derived rather than stored, so it cannot drift from the two answers it is
    /// made of. Setup switches services on by *arriving* at its dictation step,
    /// which is the first step with anything for a dictation to do; walking back
    /// off that step switches them off again, and a restart returns the step to
    /// zero and does the same. Nothing else has to remember to.
    ///
    /// Do not: fold this back into `onboardingDismissed`. One flag answered both
    /// questions once, which meant setup had to claim it was finished two steps
    /// early so the shortcut could be demonstrated — and a quit at that point
    /// then skipped setup forever.
    var servicesEnabled: Bool {
        onboardingDismissed || onboardingStep >= OnboardingStep.tryIt.rawValue
    }
    @Published var startInBackground: Bool { didSet { defaults.set(startInBackground, forKey: Keys.startInBackground) } }
    @Published var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) } }
    @Published var showAppInDock: Bool {
        didSet {
            defaults.set(showAppInDock, forKey: Keys.showAppInDock)
            NotificationCenter.default.post(name: .showAppInDockDidChange, object: showAppInDock)
        }
    }
    @Published var audioInputSelection: AudioInputSelection { didSet { save(audioInputSelection, key: Keys.audioInputSelection) } }
    @Published var playDictationFeedbackSounds: Bool {
        didSet { defaults.set(playDictationFeedbackSounds, forKey: Keys.playDictationFeedbackSounds) }
    }
    @Published var muteOtherAudioWhileDictating: Bool {
        didSet { defaults.set(muteOtherAudioWhileDictating, forKey: Keys.muteOtherAudioWhileDictating) }
    }
    @Published var retainedAudioRetention: RetainedAudioRetention {
        didSet { defaults.set(retainedAudioRetention.rawValue, forKey: Keys.retainedAudioRetention) }
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
        customShortcut = ShortcutPreferences.resolve(
            custom: Self.decode(ShortcutChord.self, key: Keys.customShortcut, defaults: defaults)
                ?? (SuggestedShortcuts.offers.contains(resolvedDictation) ? nil : resolvedDictation)
        )
        languageCode = defaults.string(forKey: Keys.languageCode) ?? "auto"
        noVerbatim = defaults.object(forKey: Keys.noVerbatim) == nil ? true : defaults.bool(forKey: Keys.noVerbatim)
        keyterms = Self.decode([String].self, key: Keys.keyterms, defaults: defaults) ?? []
        onboardingDismissed = defaults.bool(forKey: Keys.onboardingDismissed)
        onboardingStep = defaults.integer(forKey: Keys.onboardingStep)
        startInBackground = Self.optInFlag(Keys.startInBackground, in: defaults)
        showInMenuBar = defaults.object(forKey: Keys.showInMenuBar) == nil ? true : defaults.bool(forKey: Keys.showInMenuBar)
        showAppInDock = defaults.bool(forKey: Keys.showAppInDock)
        audioInputSelection = Self.decode(AudioInputSelection.self, key: Keys.audioInputSelection, defaults: defaults) ?? defaultAudioInputSelection
        playDictationFeedbackSounds = defaults.object(forKey: Keys.playDictationFeedbackSounds) == nil
            ? true
            : defaults.bool(forKey: Keys.playDictationFeedbackSounds)
        // Off by default, unlike its neighbors above: turning it on is what
        // makes macOS demand System Audio Recording, and an opt-out default
        // would spend that prompt during a first dictation.
        muteOtherAudioWhileDictating = defaults.bool(forKey: Keys.muteOtherAudioWhileDictating)
        retainedAudioRetention = defaults.string(forKey: Keys.retainedAudioRetention)
            .flatMap(RetainedAudioRetention.init(rawValue:))
            ?? RetainedAudioRetention.migrating(
                fromDeletesExpiredRetainedAudio: defaults.object(forKey: Keys.legacyDeletesExpiredRetainedAudio) == nil
                    ? true
                    : defaults.bool(forKey: Keys.legacyDeletesExpiredRetainedAudio)
            )
        automaticUpdateChecks = Self.optInFlag(Keys.automaticUpdateChecks, in: defaults)
        lastUpdateCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        availableUpdate = Self.decode(AvailableUpdate.self, key: Keys.availableUpdate, defaults: defaults)

        // Materialize opt-in defaults so upgrades and subsequent launches share one explicit value.
        if defaults.object(forKey: Keys.playDictationFeedbackSounds) == nil {
            defaults.set(true, forKey: Keys.playDictationFeedbackSounds)
        }
        if defaults.string(forKey: Keys.retainedAudioRetention) == nil {
            defaults.set(retainedAudioRetention.rawValue, forKey: Keys.retainedAudioRetention)
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
