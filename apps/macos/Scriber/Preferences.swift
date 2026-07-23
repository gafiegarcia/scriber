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
        static let holdShortcut = "holdShortcut"
        static let toggleShortcut = "toggleShortcut"
        static let holdShortcutEnabled = "holdShortcutEnabled"
        static let toggleShortcutEnabled = "toggleShortcutEnabled"
        static let languageCode = "languageCode"
        static let noVerbatim = "noVerbatim"
        static let keyterms = "keyterms"
        static let onboardingComplete = "onboardingComplete"
        static let launchAtLoginRequested = "launchAtLoginRequested"
        static let showInMenuBar = "showInMenuBar"
        static let showAppInDock = "showAppInDock"
        static let audioInputSelection = "audioInputSelection"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published var apiKeyConfigured: Bool { didSet { defaults.set(apiKeyConfigured, forKey: Keys.apiKeyConfigured) } }
    @Published var apiKeyValidity: APIKeyValidity { didSet { defaults.set(apiKeyValidity.rawValue, forKey: Keys.apiKeyValidity) } }
    @Published var subscriptionUsage: ElevenLabsSubscriptionUsage? { didSet { save(subscriptionUsage, key: Keys.subscriptionUsage) } }
    @Published var apiCreditsExhausted: Bool { didSet { defaults.set(apiCreditsExhausted, forKey: Keys.apiCreditsExhausted) } }
    @Published var holdShortcut: ShortcutChord { didSet { save(holdShortcut, key: Keys.holdShortcut) } }
    @Published var toggleShortcut: ShortcutChord { didSet { save(toggleShortcut, key: Keys.toggleShortcut) } }
    @Published var holdShortcutEnabled: Bool { didSet { defaults.set(holdShortcutEnabled, forKey: Keys.holdShortcutEnabled) } }
    @Published var toggleShortcutEnabled: Bool { didSet { defaults.set(toggleShortcutEnabled, forKey: Keys.toggleShortcutEnabled) } }
    @Published var languageCode: String { didSet { defaults.set(languageCode, forKey: Keys.languageCode) } }
    @Published var noVerbatim: Bool { didSet { defaults.set(noVerbatim, forKey: Keys.noVerbatim) } }
    @Published var keyterms: [String] { didSet { save(keyterms, key: Keys.keyterms) } }
    @Published var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Keys.onboardingComplete) } }
    @Published var launchAtLoginRequested: Bool { didSet { defaults.set(launchAtLoginRequested, forKey: Keys.launchAtLoginRequested) } }
    @Published var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) } }
    @Published var showAppInDock: Bool {
        didSet {
            defaults.set(showAppInDock, forKey: Keys.showAppInDock)
            NotificationCenter.default.post(name: .showAppInDockDidChange, object: showAppInDock)
        }
    }
    @Published var audioInputSelection: AudioInputSelection { didSet { save(audioInputSelection, key: Keys.audioInputSelection) } }

    init(
        defaults: UserDefaults = .standard,
        defaultAudioInputSelection: AudioInputSelection = .automatic
    ) {
        self.defaults = defaults
        apiKeyConfigured = defaults.bool(forKey: Keys.apiKeyConfigured)
        apiKeyValidity = defaults.string(forKey: Keys.apiKeyValidity).flatMap(APIKeyValidity.init(rawValue:)) ?? .unchecked
        subscriptionUsage = Self.decode(ElevenLabsSubscriptionUsage.self, key: Keys.subscriptionUsage, defaults: defaults)
        apiCreditsExhausted = defaults.bool(forKey: Keys.apiCreditsExhausted)
        holdShortcut = Self.decode(ShortcutChord.self, key: Keys.holdShortcut, defaults: defaults) ?? .defaultHold
        toggleShortcut = Self.decode(ShortcutChord.self, key: Keys.toggleShortcut, defaults: defaults) ?? .defaultToggle
        holdShortcutEnabled = defaults.object(forKey: Keys.holdShortcutEnabled) == nil ? true : defaults.bool(forKey: Keys.holdShortcutEnabled)
        toggleShortcutEnabled = defaults.object(forKey: Keys.toggleShortcutEnabled) == nil ? true : defaults.bool(forKey: Keys.toggleShortcutEnabled)
        languageCode = defaults.string(forKey: Keys.languageCode) ?? "auto"
        noVerbatim = defaults.object(forKey: Keys.noVerbatim) == nil ? true : defaults.bool(forKey: Keys.noVerbatim)
        keyterms = Self.decode([String].self, key: Keys.keyterms, defaults: defaults) ?? []
        onboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
        launchAtLoginRequested = defaults.object(forKey: Keys.launchAtLoginRequested) == nil ? true : defaults.bool(forKey: Keys.launchAtLoginRequested)
        showInMenuBar = defaults.object(forKey: Keys.showInMenuBar) == nil ? true : defaults.bool(forKey: Keys.showInMenuBar)
        showAppInDock = defaults.bool(forKey: Keys.showAppInDock)
        audioInputSelection = Self.decode(AudioInputSelection.self, key: Keys.audioInputSelection, defaults: defaults) ?? defaultAudioInputSelection
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
