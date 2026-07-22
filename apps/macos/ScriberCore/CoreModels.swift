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

public enum KeyCodeNames {
    public static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return "Space"
        case 53: return "Escape"
        case 36: return "Return"
        case 48: return "Tab"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key \(keyCode)"
        }
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
    case dictationCopied(text: String, message: String)
    case apiKeyInvalid
    case apiCreditsExhausted
    case pasteFailed(String)
    case transcriptionFailed(String)
    case message(String)

    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing: true
        default: false
        }
    }

    func resolvingCredentialBlock(
        apiKeyConfigured: Bool,
        apiKeyValidity: APIKeyValidity,
        apiCreditsExhausted: Bool
    ) -> AppPhase {
        switch self {
        case .apiKeyInvalid where apiKeyConfigured && apiKeyValidity == .valid:
            .idle
        case .apiCreditsExhausted
            where apiKeyConfigured && apiKeyValidity == .valid && !apiCreditsExhausted:
            .idle
        default:
            self
        }
    }
}

public enum ShortcutAction: Equatable, Sendable {
    case holdPressed
    case holdReleased
    case togglePressed
    case cancel
}

public enum PillDismissalAction: Equatable, Sendable {
    case passThrough
    case cancelRecording
    case hideTranscription
    case dismiss
}

public enum PillShapeStyle: Equatable, Sendable {
    case capsule
    case roundedRectangle
}

public extension AppPhase {
    var pillShapeStyle: PillShapeStyle {
        if case .dictationCopied = self { return .roundedRectangle }
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
        case .dictationCopied, .apiKeyInvalid, .apiCreditsExhausted,
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

public enum CapturedSelectionRestorePolicy {
    /// Restoring a saved AX selection range is only safe when the text has not
    /// changed, or when the original control remains focused at that same range.
    /// Otherwise the caller should paste at the current insertion point instead.
    public static func canRestore(
        capturedText: String?,
        currentText: String?,
        capturedRange: NSRange?,
        currentRange: NSRange?,
        isOriginalTargetFocused: Bool
    ) -> Bool {
        guard let capturedRange else { return false }
        if let capturedText { return currentText == capturedText }
        return isOriginalTargetFocused && currentRange == capturedRange
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
