import Foundation

// Shared, UI-independent behavior used by the app and its credit-free tests.

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)

    public static let all: KeyModifiers = [.command, .option, .control, .shift, .function]

    public var displayParts: [String] {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        if contains(.function) { parts.append("fn") }
        return parts
    }
}

public struct ShortcutChord: Codable, Hashable, Sendable {
    public var modifiers: KeyModifiers
    public var keyCode: UInt16?

    public init(modifiers: KeyModifiers, keyCode: UInt16?) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public static let defaultHold = ShortcutChord(modifiers: [.function], keyCode: nil)
    public static let defaultToggle = ShortcutChord(modifiers: [.function], keyCode: 49)

    public var isValid: Bool { !modifiers.isEmpty }

    public var displayName: String {
        let modifierText = modifiers.displayParts.joined(separator: modifiers == [.function] ? "" : "+")
        guard let keyCode else { return modifierText }
        let key = KeyCodeNames.name(for: keyCode)
        return modifierText.isEmpty ? key : "\(modifierText)+\(key)"
    }
}

/// Captures a modifier-only shortcut without replacing a complete chord while
/// its modifiers are released one at a time.
public struct ModifierChordCaptureState: Equatable, Sendable {
    public private(set) var peakModifiers: KeyModifiers = []

    public init() {}

    /// Records a simultaneous modifier snapshot. Equal-sized snapshots retain
    /// the first observed chord rather than combining keys that were never
    /// held together.
    public mutating func observe(_ modifiers: KeyModifiers) {
        guard !modifiers.isEmpty else { return }
        guard modifiers.rawValue.nonzeroBitCount > peakModifiers.rawValue.nonzeroBitCount else { return }
        peakModifiers = modifiers
    }

    /// Returns the complete modifier-only chord once every modifier has been
    /// released, then resets for the next capture.
    public mutating func commitWhenAllModifiersReleased(
        currentModifiers: KeyModifiers
    ) -> ShortcutChord? {
        guard currentModifiers.isEmpty, !peakModifiers.isEmpty else { return nil }
        defer { reset() }
        return ShortcutChord(modifiers: peakModifiers, keyCode: nil)
    }

    public mutating func reset() {
        peakModifiers = []
    }
}

public enum KeyCodeNames {
    /// Virtual key codes for the standard ANSI layout, matching Carbon's
    /// `kVK_` constants. Codes are positional, so this names the key by where it
    /// sits rather than by what a remapped layout produces — good enough for a
    /// shortcut label, and it avoids pulling Carbon into this UI-free module.
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
        50: "`",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Keypad Clear", 75: "Keypad /",
        76: "Keypad Enter", 78: "Keypad -", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}

public enum RecordingMode: Equatable, Sendable {
    case held
    case locked
}

public struct AudioInputDeviceDescriptor: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool

    public init(id: String, name: String, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

public enum AudioInputSelection: Codable, Equatable, Hashable, Sendable {
    case automatic
    case device(id: String, name: String)

    public var deviceID: String? {
        guard case .device(let id, _) = self else { return nil }
        return id
    }

    public static func initialSelection(from devices: [AudioInputDeviceDescriptor]) -> AudioInputSelection {
        guard let builtIn = devices.first(where: \AudioInputDeviceDescriptor.isBuiltIn) else { return .automatic }
        return .device(id: builtIn.id, name: builtIn.name)
    }
}

public enum AudioSignal {
    public static let detectionThreshold: Float = -60
    public static let visibleCeiling: Float = -6

    public static func isDetected(decibels: Float) -> Bool {
        decibels.isFinite && decibels > detectionThreshold
    }

    public static func normalized(decibels: Float) -> Double {
        guard decibels.isFinite, decibels > detectionThreshold else { return 0 }
        let range = visibleCeiling - detectionThreshold
        return Double(min(1, max(0, (decibels - detectionThreshold) / range)))
    }
}

public enum APIKeyValidity: String, Codable, Sendable {
    case unchecked
    case valid
    case invalid
}

public enum ScriberPermission: String, CaseIterable, Hashable, Sendable {
    case microphone
    case accessibility

    public var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }
}

public struct PermissionReadiness: Equatable, Sendable {
    public let missingPermissions: [ScriberPermission]

    public init(microphoneGranted: Bool, accessibilityGranted: Bool) {
        var missing: [ScriberPermission] = []
        if !microphoneGranted { missing.append(.microphone) }
        if !accessibilityGranted { missing.append(.accessibility) }
        missingPermissions = missing
    }

    public init(missingPermissions: [ScriberPermission]) {
        self.missingPermissions = ScriberPermission.allCases.filter(missingPermissions.contains)
    }

    public var isReady: Bool { missingPermissions.isEmpty }

    public var recoveryMessage: String {
        switch missingPermissions {
        case [.microphone]:
            "Enable Microphone so Scriber can record dictation."
        case [.accessibility]:
            "Enable Accessibility so Scriber can detect global shortcuts and insert text."
        case [.microphone, .accessibility]:
            "Enable Microphone and Accessibility before using dictation shortcuts."
        default:
            "Review Scriber's permissions before using dictation."
        }
    }
}

/// Why Scriber cannot currently reach ElevenLabs, if it cannot.
///
/// Onboarding can complete and then stop being sufficient: a key is revoked,
/// replaced at ElevenLabs, or the account runs out of credits. Scriber must say
/// so on its own rather than waiting for a dictation attempt to fail.
public enum CredentialReadiness: Equatable, Sendable {
    case ready
    case missingAPIKey
    case invalidAPIKey
    case creditsExhausted

    public init(apiKeyConfigured: Bool, apiKeyValidity: APIKeyValidity, apiCreditsExhausted: Bool) {
        if !apiKeyConfigured {
            self = .missingAPIKey
        } else if apiKeyValidity == .invalid {
            self = .invalidAPIKey
        } else if apiCreditsExhausted {
            self = .creditsExhausted
        } else {
            // An unchecked key is not a known problem. Validation could not reach
            // ElevenLabs, and the last definitive result must not be invented here.
            self = .ready
        }
    }

    public var isReady: Bool { self == .ready }

    public var title: String {
        switch self {
        case .ready: "Ready"
        case .missingAPIKey: "ElevenLabs API key is missing"
        case .invalidAPIKey: "ElevenLabs API key is invalid"
        case .creditsExhausted: "ElevenLabs credits exhausted"
        }
    }

    public var recoveryMessage: String {
        switch self {
        case .ready: "Scriber is ready to dictate."
        case .missingAPIKey: "Add your key in Settings to start dictating."
        case .invalidAPIKey: "Add or update the key in Settings."
        case .creditsExhausted: "Add credits or wait for your quota to reset."
        }
    }

    /// Exhausted credits are resolved at ElevenLabs, so that state routes to the
    /// usage panel. Every other block is resolved in Scriber's own key field.
    public var resolvesInUsageSettings: Bool { self == .creditsExhausted }
}

public enum CredentialRecoveryPolicy {
    public static func shouldPresent(
        previous: CredentialReadiness,
        current: CredentialReadiness,
        onboardingComplete: Bool,
        force: Bool
    ) -> Bool {
        onboardingComplete && !current.isReady && (force || current != previous)
    }
}

public enum PermissionRecoveryPolicy {
    public static func shouldPresent(
        previous: PermissionReadiness,
        current: PermissionReadiness,
        onboardingComplete: Bool,
        force: Bool
    ) -> Bool {
        onboardingComplete && !current.isReady && (force || current != previous)
    }
}

struct CredentialRevision: Equatable, Sendable {
    private(set) var current: UInt = 0

    @discardableResult
    mutating func advance() -> UInt {
        current &+= 1
        return current
    }

    func matches(_ candidate: UInt) -> Bool {
        candidate == current
    }
}

public enum AppPhase: Equatable, Sendable {
    case idle
    case recording(mode: RecordingMode, elapsed: TimeInterval, level: Float)
    case transcribing(attempt: Int, retryDelay: TimeInterval?)
    case cancelledTranscript
    case dictationCopied(text: String, message: String)
    case permissionsRequired([ScriberPermission])
    case credentialsUnusable(CredentialReadiness)
    case pasteFailed(String)
    case transcriptionFailed(String)
    case message(String)

    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing: true
        default: false
        }
    }

    /// Returns idle once the credential block is resolved, and otherwise restates
    /// the block with its current reason so a stale message cannot survive a
    /// change from, say, a missing key to an invalid replacement.
    func resolvingCredentialBlock(
        apiKeyConfigured: Bool,
        apiKeyValidity: APIKeyValidity,
        apiCreditsExhausted: Bool
    ) -> AppPhase {
        guard case .credentialsUnusable = self else { return self }
        let readiness = CredentialReadiness(
            apiKeyConfigured: apiKeyConfigured,
            apiKeyValidity: apiKeyValidity,
            apiCreditsExhausted: apiCreditsExhausted
        )
        return readiness.isReady ? .idle : .credentialsUnusable(readiness)
    }
}

public enum ShortcutAction: Equatable, Sendable {
    case holdPressed
    case holdReleased
    case togglePressed
    case cancel

    public func stopsRecording(mode: RecordingMode) -> Bool {
        switch (self, mode) {
        case (.holdReleased, .held), (.togglePressed, .locked): true
        default: false
        }
    }
}

public enum PillDismissalAction: Equatable, Sendable {
    case passThrough
    case cancelRecording
    case hideTranscription
    case dismiss
}

public enum RecordingCancellationPolicy {
    public static let recoveryThreshold: TimeInterval = 1

    public static func retainsAudio(elapsed: TimeInterval, detectedSignal: Bool) -> Bool {
        elapsed >= recoveryThreshold && detectedSignal
    }

    public static func cancelsForNonModifierKey(mode: RecordingMode, elapsed: TimeInterval) -> Bool {
        mode == .held && elapsed < recoveryThreshold
    }
}

/// When Scriber stops keeping the audio behind a failed or cancelled dictation.
///
/// Retained recordings exist so a dictation can be retried, but nothing ever
/// collected them, so unretried audio accumulated in Application Support for the
/// life of the install. That is a privacy cost as much as a disk one.
public enum RetainedAudioRetentionPolicy {
    public static let retentionPeriod: TimeInterval = 30 * 24 * 60 * 60

    public static let expiryMessage = "The retained recording was removed after 30 days and can no longer be retried."

    public static func hasExpired(createdAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(createdAt) >= retentionPeriod
    }

    /// Keeps why the dictation failed alongside why its audio is gone.
    public static func expiredMessage(appendingTo existing: String?) -> String {
        guard let existing, !existing.isEmpty else { return expiryMessage }
        return "\(existing) \(expiryMessage)"
    }
}

public enum OrphanedAudioImportPolicy {
    /// A retained recording is named for its dictation's ID, and that ID is unique
    /// in the store, so importing a file whose ID already exists would upsert over
    /// the original record and replace a saved transcript with an empty failed
    /// entry. Import only recordings that no existing dictation can account for.
    public static func shouldImport(
        recordingID: UUID,
        relativePath: String,
        knownRecordIDs: Set<UUID>,
        referencedAudioPaths: Set<String>
    ) -> Bool {
        !referencedAudioPaths.contains(relativePath) && !knownRecordIDs.contains(recordingID)
    }
}

public enum PillShapeStyle: Equatable, Sendable {
    case capsule
    case roundedRectangle
}

public extension AppPhase {
    var pillShapeStyle: PillShapeStyle {
        if case .dictationCopied = self { return .roundedRectangle }
        if case .cancelledTranscript = self { return .roundedRectangle }
        return .capsule
    }

    func pillCornerRadius(height: Double) -> Double {
        switch pillShapeStyle {
        case .capsule: height / 2
        case .roundedRectangle: 24
        }
    }

    func pillDismissalAction(isPresented: Bool) -> PillDismissalAction {
        guard isPresented else { return .passThrough }
        return switch self {
        case .idle: .passThrough
        case .recording: .cancelRecording
        case .transcribing: .hideTranscription
        case .cancelledTranscript, .dictationCopied, .permissionsRequired, .credentialsUnusable,
             .pasteFailed, .transcriptionFailed, .message: .dismiss
        }
    }
}

public enum TranscriptContent {
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else { return nil }
        return trimmed
    }
}

public enum TextInputTargetPolicy {
    private static let recognizedRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
    ]

    public static func accepts(
        role: String?,
        subrole: String?,
        selectedTextSettable: Bool,
        exposesCharacterCount: Bool,
        explicitlyEditable: Bool = false,
        enabled: Bool?
    ) -> Bool {
        guard role != "AXSecureTextField",
              subrole != "AXSecureTextField",
              enabled != false else { return false }
        return selectedTextSettable
            || exposesCharacterCount
            || explicitlyEditable
            || role.map(recognizedRoles.contains) == true
    }
}

public enum PasteConfirmationPolicy {
    public static func confirmsInsertion(
        accessibilityMutationObserved: Bool,
        pasteboardDataRequested: Bool
    ) -> Bool {
        accessibilityMutationObserved || pasteboardDataRequested
    }
}

public struct ShortcutMatcher: Sendable {
    public var hold: ShortcutChord
    public var toggle: ShortcutChord

    public init(hold: ShortcutChord, toggle: ShortcutChord) {
        self.hold = hold
        self.toggle = toggle
    }

    public func matchesExactly(_ chord: ShortcutChord, modifiers: KeyModifiers, keyCode: UInt16?) -> Bool {
        chord.modifiers == modifiers && chord.keyCode == keyCode
    }

    public func matchesToggleWhileHeld(modifiers: KeyModifiers, keyCode: UInt16?) -> Bool {
        guard keyCode == toggle.keyCode else { return false }
        let permittedExtras = hold.modifiers.subtracting(toggle.modifiers)
        let normalized = modifiers.subtracting(permittedExtras)
        return normalized == toggle.modifiers
    }
}
