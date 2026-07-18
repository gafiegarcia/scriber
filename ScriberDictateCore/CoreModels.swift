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

public enum AppPhase: Equatable, Sendable {
    case idle
    case recording(mode: RecordingMode, elapsed: TimeInterval, level: Float)
    case transcribing(attempt: Int, retryDelay: TimeInterval?)
    case pasted
    case pasteFailed(String)
    case transcriptionFailed(String)
    case message(String)

    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing: true
        default: false
        }
    }
}

public enum ShortcutAction: Equatable, Sendable {
    case holdPressed
    case holdReleased
    case togglePressed
    case cancel
}

public enum TranscriptContent {
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else { return nil }
        return trimmed
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
