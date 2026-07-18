import Combine
import Foundation
#if SWIFT_PACKAGE
import ScriberDictateCore
#endif

@MainActor
final class Preferences: ObservableObject {
    private enum Keys {
        static let apiKeyConfigured = "apiKeyConfigured"
        static let holdShortcut = "holdShortcut"
        static let toggleShortcut = "toggleShortcut"
        static let languageCode = "languageCode"
        static let noVerbatim = "noVerbatim"
        static let keyterms = "keyterms"
        static let onboardingComplete = "onboardingComplete"
        static let launchAtLoginRequested = "launchAtLoginRequested"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published var apiKeyConfigured: Bool { didSet { defaults.set(apiKeyConfigured, forKey: Keys.apiKeyConfigured) } }
    @Published var holdShortcut: ShortcutChord { didSet { save(holdShortcut, key: Keys.holdShortcut) } }
    @Published var toggleShortcut: ShortcutChord { didSet { save(toggleShortcut, key: Keys.toggleShortcut) } }
    @Published var languageCode: String { didSet { defaults.set(languageCode, forKey: Keys.languageCode) } }
    @Published var noVerbatim: Bool { didSet { defaults.set(noVerbatim, forKey: Keys.noVerbatim) } }
    @Published var keyterms: [String] { didSet { save(keyterms, key: Keys.keyterms) } }
    @Published var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Keys.onboardingComplete) } }
    @Published var launchAtLoginRequested: Bool { didSet { defaults.set(launchAtLoginRequested, forKey: Keys.launchAtLoginRequested) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        apiKeyConfigured = defaults.bool(forKey: Keys.apiKeyConfigured)
        holdShortcut = Self.decode(ShortcutChord.self, key: Keys.holdShortcut, defaults: defaults) ?? .defaultHold
        toggleShortcut = Self.decode(ShortcutChord.self, key: Keys.toggleShortcut, defaults: defaults) ?? .defaultToggle
        languageCode = defaults.string(forKey: Keys.languageCode) ?? "auto"
        noVerbatim = defaults.object(forKey: Keys.noVerbatim) == nil ? true : defaults.bool(forKey: Keys.noVerbatim)
        keyterms = Self.decode([String].self, key: Keys.keyterms, defaults: defaults) ?? []
        onboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
        launchAtLoginRequested = defaults.object(forKey: Keys.launchAtLoginRequested) == nil ? true : defaults.bool(forKey: Keys.launchAtLoginRequested)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
