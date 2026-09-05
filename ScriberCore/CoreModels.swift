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
        if contains(.function) { parts.append("fn") }
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts
    }
}

public enum ModifierSide: String, Codable, Hashable, Sendable {
    case left
    case right
}

/// Which physical key carries a modifier. `NSEvent.modifierFlags` and
/// `CGEventFlags` both report that Option is down and neither reports which
/// Option, so the side is only readable from the key code on the event that
/// changed the flags.
public enum ModifierKeyCodes {
    public static let sides: [UInt16: (modifier: KeyModifiers, side: ModifierSide)] = [
        55: (.command, .left), 54: (.command, .right),
        58: (.option, .left), 61: (.option, .right),
        59: (.control, .left), 62: (.control, .right),
        56: (.shift, .left), 60: (.shift, .right),
    ]

    public static func code(for modifier: KeyModifiers, side: ModifierSide) -> UInt16? {
        sides.first { $0.value.modifier == modifier && $0.value.side == side }?.key
    }

    /// The modifiers whose two keys are worth telling apart. Control often has
    /// no right key at all, and right Shift types capitals all day.
    public static let sidedModifiers: KeyModifiers = [.command, .option]

    public static func name(for keyCode: UInt16) -> String? {
        guard let entry = sides[keyCode] else { return nil }
        let side = entry.side == .right ? "Right" : "Left"
        return "\(side) \(entry.modifier.displayParts.joined())"
    }
}

/// Which physical modifier keys are down right now. Also the only way to know a
/// bound key came back up while its twin keeps the flag set.
public struct HeldModifierKeys: Equatable, Sendable {
    public private(set) var keys: Set<UInt16> = []

    public init() {}

    /// Folds in one `flagsChanged`. A modifier key alternates down and up, so
    /// the key already held is coming up even while its twin keeps the flag.
    public mutating func observe(keyCode: UInt16, modifiers: KeyModifiers) {
        if let entry = ModifierKeyCodes.sides[keyCode] {
            if !modifiers.contains(entry.modifier) || keys.contains(keyCode) {
                keys.remove(keyCode)
            } else {
                keys.insert(keyCode)
            }
        }
        // A key whose modifier is no longer reported at all can only be up. This
        // is what recovers from presses that happened before the tap was armed.
        keys = keys.filter { held in
            ModifierKeyCodes.sides[held].map { modifiers.contains($0.modifier) } ?? false
        }
    }

    public mutating func reset() { keys.removeAll() }
}

public struct ShortcutChord: Codable, Hashable, Sendable {
    public var modifiers: KeyModifiers
    public var keyCode: UInt16?
    /// The exact physical modifier keys this chord requires. Empty means either
    /// side of each modifier will do. Only kept for a chord of modifiers alone;
    /// adding an ordinary key clears it.
    public var modifierKeyCodes: Set<UInt16>

    public init(modifiers: KeyModifiers, keyCode: UInt16?, modifierKeyCodes: Set<UInt16> = []) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        let sideable = keyCode == nil && modifiers.isSubset(of: ModifierKeyCodes.sidedModifiers)
        self.modifierKeyCodes = sideable ? modifierKeyCodes : []
    }

    public init(modifiers: KeyModifiers, keyCode: UInt16?, modifierSide: ModifierSide) {
        let sided = ModifierKeyCodes.code(for: modifiers, side: modifierSide).map { Set([$0]) } ?? []
        self.init(modifiers: modifiers, keyCode: keyCode, modifierKeyCodes: sided)
    }

    public static let defaultDictation = ShortcutChord(modifiers: [.function], keyCode: nil)

    public var isValid: Bool { !modifiers.isEmpty }

    public var usesFunctionKey: Bool { modifiers.contains(.function) }

    public var isSided: Bool { !modifierKeyCodes.isEmpty }

    /// Whether every key this chord names is a right-hand one, which is what
    /// keeps it clear of the shortcuts people actually type.
    public var isEntirelyRightHanded: Bool {
        isSided && modifierKeyCodes.allSatisfy { ModifierKeyCodes.sides[$0]?.side == .right }
    }

    public var displayName: String {
        if isSided, keyCode == nil {
            return modifierKeyCodes
                .compactMap(ModifierKeyCodes.name(for:))
                .sorted()
                .joined(separator: "+")
        }
        let modifierText = modifiers.displayParts.joined(separator: modifiers == [.function] ? "" : "+")
        guard let keyCode else { return modifierText }
        let key = KeyCodeNames.name(for: keyCode)
        return modifierText.isEmpty ? key : "\(modifierText)+\(key)"
    }
}

extension ShortcutChord {
    private enum CodingKeys: String, CodingKey {
        case modifiers, keyCode, modifierKeyCodes, modifierSide
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        // Omitted when empty so an unsided chord stores what it always stored.
        if isSided { try container.encode(modifierKeyCodes, forKey: .modifierKeyCodes) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modifiers = try container.decode(KeyModifiers.self, forKey: .modifiers)
        let keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
        if let codes = try container.decodeIfPresent(Set<UInt16>.self, forKey: .modifierKeyCodes) {
            self.init(modifiers: modifiers, keyCode: keyCode, modifierKeyCodes: codes)
        } else if let side = try container.decodeIfPresent(ModifierSide.self, forKey: .modifierSide) {
            // Stored by the build that carried one side for the whole chord.
            self.init(modifiers: modifiers, keyCode: keyCode, modifierSide: side)
        } else {
            self.init(modifiers: modifiers, keyCode: keyCode)
        }
    }
}

/// What setup suggests to someone whose keyboard has no `fn` key macOS can see.
/// Not a preset in the picker — it is the hint shown once recording your own is
/// the path taken. Two modifiers, because `ReservedShortcuts` refuses a lone one.
public enum SuggestedShortcuts {
    /// What setup offers, in order. Every one is a key held on its own.
    public static let offers = ReservedShortcuts.bindableAlone

    public static let withoutFunctionKey = ShortcutChord(modifiers: [.control, .option], keyCode: nil)
}

/// Captures a modifier-only shortcut without replacing a complete chord while
/// its modifiers are released one at a time.
public struct ModifierChordCaptureState: Equatable, Sendable {
    public private(set) var peakModifiers: KeyModifiers = []
    /// The physical keys that were down at the peak, which is the only place a
    /// modifier's side is readable.
    private var peakKeyCodes: Set<UInt16> = []

    public init() {}

    /// What would be committed if a key were released now.
    public var peakChord: ShortcutChord {
        ShortcutChord(modifiers: peakModifiers, keyCode: nil, modifierKeyCodes: peakKeyCodes)
    }

    /// Records a simultaneous modifier snapshot. Equal-sized snapshots retain
    /// the first observed chord rather than combining keys that were never
    /// held together.
    /// `heldKeys` is what `HeldModifierKeys` reports at this moment. A peak
    /// naming fewer keys than modifiers is stored unsided rather than half-sided:
    /// `fn` has no side at all, so any chord including it can only be unsided.
    public mutating func observe(_ modifiers: KeyModifiers, heldKeys: Set<UInt16> = []) {
        guard !modifiers.isEmpty else { return }
        guard modifiers.rawValue.nonzeroBitCount > peakModifiers.rawValue.nonzeroBitCount else { return }
        peakModifiers = modifiers
        peakKeyCodes = heldKeys.count == modifiers.rawValue.nonzeroBitCount ? heldKeys : []
    }

    /// Returns the peak modifier-only chord as soon as the **first** modifier is
    /// released, then resets for the next capture.
    public mutating func commitOnFirstModifierRelease(
        currentModifiers: KeyModifiers
    ) -> ShortcutChord? {
        guard !peakModifiers.isEmpty else { return nil }
        // A strict subset means something that was held is no longer held. Equal
        // sets are the plateau between the last press and the first release, and a
        // superset is still building up.
        guard currentModifiers.isStrictSubset(of: peakModifiers) else { return nil }
        defer { reset() }
        return peakChord
    }

    public mutating func reset() {
        peakModifiers = []
        peakKeyCodes = []
    }
}

public enum KeyCodeNames {
    /// Virtual key codes for the standard ANSI layout, matching Carbon's `kVK_`
    /// constants. Codes are positional, so this names the key by where it sits
    /// rather than by what a remapped layout produces.
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

    /// The reverse, so a table of chords can be written in names rather than
    /// codes. The positional layout makes the codes misleading — 23 is `5` and
    /// 22 is `6`, F3 is 99 and F5 is 96 — and a mistyped one is a rule that
    /// silently never matches.
    public static func code(for name: String) -> UInt16? { codes[name] }

    private static let codes: [String: UInt16] = Dictionary(
        names.map { ($0.value, $0.key) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Keys macOS reports with the function modifier already set, whatever else is
    /// held. A chord bound to one of them arrives carrying `.function` that the
    /// user never pressed.
    static let intrinsicallyFunctionKeyed: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,  // F1–F12
        105, 106, 107, 113,                                      // F13–F16
        123, 124, 125, 126,                                      // arrows
        114, 115, 116, 121, 117, 119,                            // Help, Home, Page Up/Down, Fwd Delete, End
    ]
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

    public static func initialSelection(from devices: [AudioInputDeviceDescriptor]) -> AudioInputSelection {
        guard let builtIn = devices.first(where: \AudioInputDeviceDescriptor.isBuiltIn) else { return .automatic }
        return .device(id: builtIn.id, name: builtIn.name)
    }
}

/// When other apps get their sound back after a dictation.
public enum OtherAudioMutePolicy {
    /// How long the mute outlasts the recording. Sound returning in the same
    /// instant the input stream closes is heard as a glitch, because a device
    /// changing mode right then has not settled.
    ///
    /// It covers the transition, not a Bluetooth headset's whole trip out of
    /// call mode, which runs about a second and stays audible.
    public static let restoreDelay: TimeInterval = 0.2
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

public struct SubscriptionUsagePresentation: Equatable, Sendable {
    public let hasCachedUsage: Bool
    public let usageUnavailable: Bool

    public init(hasCachedUsage: Bool, usageUnavailable: Bool) {
        self.hasCachedUsage = hasCachedUsage
        self.usageUnavailable = usageUnavailable
    }

    public var cachedUsageIsStale: Bool { hasCachedUsage && usageUnavailable }
    public var showsCachedUsageRefresh: Bool { hasCachedUsage && !usageUnavailable }
    public var showsUnavailableRetry: Bool { usageUnavailable }
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

/// Why Scriber cannot currently reach ElevenLabs, if it cannot. Onboarding can
/// complete and then stop being sufficient: a revoked key, a key replaced at
/// ElevenLabs, an account out of credits.
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

/// What macOS reports about Scriber's login item, reduced to the three answers
/// the Settings toggle has to tell apart. "Not registered" and "not found" both
/// mean Scriber does not launch at login, so they arrive here as `disabled`.
public enum LaunchAtLoginState: String, Sendable {
    case enabled
    case disabled
    /// The entry exists and macOS has it switched off, which it offers under
    /// Background App Activity rather than in the Open at Login list.
    /// Registering again does not flip it back on — only the user can.
    case requiresApproval

    public var isOn: Bool { self == .enabled }

    /// Why the toggle refused to stay on, for the one state where asking again
    /// cannot help. Name the list holding the switch: the Open at Login list
    /// above it has no per-item switch, so "in Login Items" alone sends people
    /// looking for a control that is not there.
    public var recoveryAdvice: String? {
        self == .requiresApproval
            ? "macOS has Scriber switched off under Background App Activity. Turn it back on there to launch Scriber at login."
            : nil
    }
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

/// Allows the current missing-permission state to be forced onto the pill once
/// after completed onboarding, without making every later activation another
/// forced presentation of the same state.
struct PermissionRecoveryLaunchGate: Equatable, Sendable {
    private(set) var hasRequestedPresentation = false

    mutating func consume(onboardingComplete: Bool) -> Bool {
        guard onboardingComplete, !hasRequestedPresentation else { return false }
        hasRequestedPresentation = true
        return true
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
    /// Stopped before anything was sent, because this Mac has no route to a
    /// network at all. Distinct from a transcription that failed: nothing left
    /// the machine, no credit moved, and the recording is waiting intact.
    case noInternetConnection
    case dictationCopied(text: String, message: String)
    case permissionsRequired([ScriberPermission])
    case credentialsUnusable(CredentialReadiness)
    case transcriptionFailed(String)
    /// The transcription succeeded but contained no words. Sound did reach the
    /// recorder, so the input is working — routes to input settings anyway, because
    /// an input that is too quiet is the next likeliest cause.
    case noSpeechDetected
    /// The same finding, reported for a recording retried from History. It says
    /// only what happened: the recovery the live pill offers is aimed at an input
    /// that is wrong *now*, and this recording was made at some point in the past.
    case retryFoundNoWords
    /// Nothing ever crossed the signal threshold, so the recording was discarded
    /// before it cost any API credit.
    ///
    /// Distinct from `.noSpeechDetected` on purpose: this one means the microphone
    /// produced no usable sound at all — muted, wrong device, input volume at zero.
    case noAudioSignal
    /// A transcript reached the clipboard instead of the cursor, from a History
    /// retry rather than from a failed paste. Its own phase rather than a
    /// `.message`, which is too brief for an outcome the user has to act on.
    case transcriptCopied
    /// A password box had the cursor, so nothing was pasted. Its own phase rather
    /// than a `.dictationCopied` with different words: the transcript is on the
    /// clipboard either way, but this one is Scriber declining on purpose, and it
    /// is tinted to say so.
    case dictationBlockedBySecureField(text: String, message: String)
    case message(String)

    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing: true
        default: false
        }
    }

    /// Every phase that is not a dictation in flight is a resting phase: the notice
    /// on screen describes something already finished, so a shortcut press must
    /// start the next dictation rather than be swallowed. Derive this from `isBusy`
    /// and never from a list of phase names — a name left out of such a list
    /// deadlocks both shortcuts until the pill is dismissed by hand.
    public var acceptsRecordingStart: Bool { !isBusy }

    /// Cancelling is permitted in every recording mode. Governs
    /// `HandsFreePillAction.disposition(for:)`, so it covers clicks on the pill's
    /// Cancel control only: it says nothing about whether that control is drawn —
    /// see `showsCancelRecordingControl(isHovering:)` — and nothing about Escape,
    /// which cancels through `pillDismissalAction(isPresented:)` regardless.
    var permitsCancelRecording: Bool {
        guard case .recording = self else { return false }
        return true
    }

    /// Whether the pill actually draws the Cancel control. Locked recording
    /// shows it unconditionally; held recording keeps it out of the way until
    /// the pointer arrives, since Escape already covers cancellation without it.
    func showsCancelRecordingControl(isHovering: Bool) -> Bool {
        switch self {
        case .recording(.locked, _, _): true
        case .recording(.held, _, _): isHovering
        default: false
        }
    }

    /// Confirm only makes sense while locked; a held recording stops on key
    /// release. Unlike Cancel, its display never depends on hover.
    var showsConfirmRecordingControl: Bool {
        guard case .recording(let mode, _, _) = self else { return false }
        return mode == .locked
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

enum HandsFreePillDisposition: Equatable, Sendable {
    case cancelRecording
    case finishRecording
}

enum HandsFreePillAction: Equatable, Sendable {
    case cancel
    case confirm

    func disposition(for phase: AppPhase) -> HandsFreePillDisposition? {
        switch self {
        case .cancel: phase.permitsCancelRecording ? .cancelRecording : nil
        case .confirm: phase.showsConfirmRecordingControl ? .finishRecording : nil
        }
    }
}

public enum ShortcutAction: Equatable, Sendable {
    /// The dictation shortcut went down. Recording starts here in every case, so
    /// the first word is never lost to a decision that has not been made yet.
    case pressed
    /// It came back up after being down past `DictationShortcutTiming.tapThreshold`,
    /// which reads as talking while holding it.
    case releasedAfterHold
    /// It came back up before that, which asks for hands-free instead. The
    /// recording started by `pressed` carries on rather than restarting.
    case releasedAsTap
    case cancel

    public func stopsRecording(mode: RecordingMode) -> Bool {
        switch (self, mode) {
        case (.releasedAfterHold, .held), (.pressed, .locked): true
        default: false
        }
    }
}

/// How long the dictation shortcut must stay down to mean "I am talking now"
/// rather than "start listening and let go". The decision is taken on release,
/// not on press, so this never delays the start of a recording. Too short and a
/// brief deliberate hold ends up hands-free; too long and a tap feels like it hung.
public enum DictationShortcutTiming {
    public static let tapThreshold: TimeInterval = 0.25
}

public enum PillDismissalAction: Equatable, Sendable {
    case passThrough
    case cancelRecording
    case cancelTranscription
    case dismiss
}

/// What a transcription that was cancelled after its request went out came back
/// with. The request is left to finish because it is already billed, but it must
/// not speak: its result is held here until the user asks for it.
public enum CancelledTranscriptionOutcome: Equatable, Sendable {
    case stillRunning
    case transcript(String)
    case noWords
    case failed(String)
}

/// What Recover does with it.
public enum CancelledTranscriptionRecovery: Equatable, Sendable {
    case waitForTranscript
    case deliver(String)
    case reportNoWords
    case transcribeAgain
}

public extension CancelledTranscriptionOutcome {
    /// Names the outcome without carrying it. `String(describing:)` would put the
    /// transcript itself into a log line.
    var label: String {
        switch self {
        case .stillRunning: "stillRunning"
        case .transcript: "transcript"
        case .noWords: "noWords"
        case .failed: "failed"
        }
    }

    /// `stillRunning` waits rather than starting a second transcription: the
    /// first request is in flight and paid for, and racing it would bill the
    /// user twice for one recording and return two transcripts.
    var recovery: CancelledTranscriptionRecovery {
        switch self {
        case .stillRunning: .waitForTranscript
        case .transcript(let text): .deliver(text)
        case .noWords: .reportNoWords
        case .failed: .transcribeAgain
        }
    }
}

public enum PillDefaultAction: Equatable, Sendable {
    case none
    case openMainWindow
    case openPermissionSettings
    /// Resolves to the key field or the usage pane at dispatch, from the same
    /// `CredentialReadiness` the pill's own button reads.
    case openCredentialSettings
    case openInputSettings
    case dismiss
}

public enum RecordingCancellationPolicy {
    public static let recoveryThreshold: TimeInterval = 1

    /// Below this a press was never a dictation attempt: a finger slipped, or the
    /// key was the modifier half of some other shortcut. Say nothing about it —
    /// no sound, no message, no history row, just the pill closing.
    public static let misclickThreshold: TimeInterval = 0.25

    public static func isMisclick(elapsed: TimeInterval) -> Bool {
        elapsed < misclickThreshold
    }

    public static func retainsAudio(elapsed: TimeInterval, detectedSignal: Bool) -> Bool {
        elapsed >= recoveryThreshold && detectedSignal
    }

    public static func cancelsForNonModifierKey(mode: RecordingMode, elapsed: TimeInterval) -> Bool {
        mode == .held && elapsed < recoveryThreshold
    }

    /// Whether a recording that carried no signal is worth saying so about.
    /// **“No sound from the microphone”** is for a dictation someone really gave —
    /// a muted input, a zero volume, the wrong device. Held for less than a moment
    /// it reports silence to someone who never spoke, so those close silently.
    public static func reportsMissingAudio(elapsed: TimeInterval, detectedSignal: Bool) -> Bool {
        !detectedSignal && elapsed >= recoveryThreshold
    }

    /// Longer than someone takes to think better of a dictation and let go.
    public static let speechReportThreshold: TimeInterval = 3

    /// Whether a recording that carried signal but came back wordless is worth
    /// saying so about. The same rule as `reportsMissingAudio`, held longer.
    ///
    /// A microphone too quiet to be understood and a held key released without
    /// speaking produce the same recording: a low peak, above the detection
    /// threshold, with no words in it. Nothing in one clip tells them apart, so
    /// duration decides. Nobody holds the key this long having decided not to
    /// speak, while somebody whose input is misconfigured talked for their whole
    /// dictation and deserves to be told why nothing arrived.
    public static func reportsMissingSpeech(elapsed: TimeInterval) -> Bool {
        elapsed >= speechReportThreshold
    }
}

/// How long a failed or cancelled dictation is kept, as the user chose it.
public enum RetainedAudioRetention: String, CaseIterable, Codable, Sendable {
    case sevenDays
    case thirtyDays
    case never

    public static let standard: RetainedAudioRetention = .sevenDays

    /// `nil` for `never`, which is the one answer that is not a length of time.
    public var period: TimeInterval? {
        switch self {
        case .sevenDays: 7 * 24 * 60 * 60
        case .thirtyDays: 30 * 24 * 60 * 60
        case .never: nil
        }
    }

    public var label: String {
        switch self {
        case .sevenDays: "After 7 days"
        case .thirtyDays: "After 30 days"
        case .never: "Never"
        }
    }

    /// Carries over the answer someone gave the **Delete unused recordings after
    /// 30 days** toggle this replaced. Nobody chose 30 days — it was the only
    /// behaviour on offer — so an enabled toggle means "yes, clean up" and takes
    /// the new default. Only switching it off was ever a decision of its own.
    public static func migrating(fromDeletesExpiredRetainedAudio wasEnabled: Bool) -> RetainedAudioRetention {
        wasEnabled ? standard : .never
    }
}

/// When Scriber stops keeping a failed or cancelled dictation. Unretried audio
/// left in Application Support is a privacy cost as much as a disk one, so
/// retention is bounded unless the user asks otherwise, and a dictation that
/// never produced a transcript goes with its recording: what is left offers
/// nothing to read, copy, or retry.
public enum RetainedAudioRetentionPolicy {
    public static func hasExpired(
        createdAt: Date,
        retention: RetainedAudioRetention,
        now: Date = .now
    ) -> Bool {
        guard let period = retention.period else { return false }
        return now.timeIntervalSince(createdAt) >= period
    }

    /// What the sweep does with one dictation. Ask only about a failed or
    /// cancelled dictation holding no transcript — anything else is either still
    /// in flight or has a transcript to keep, and neither is this sweep's
    /// business.
    public enum Disposition: Equatable, Sendable {
        case keep
        case discardEntry
        case deleteAudioAndDiscardEntry
    }

    /// - Parameter retainedAudioExistsOnDisk: `nil` when the retained-audio
    ///   directory could not be read. An unreadable directory reports no files,
    ///   which would otherwise read as every recording having vanished at once
    ///   and take the whole history with it.
    public static func disposition(
        createdAt: Date,
        retention: RetainedAudioRetention,
        retainedAudioPath: String?,
        retainedAudioExistsOnDisk: Bool?,
        now: Date = .now
    ) -> Disposition {
        // Never means never: not the recording, not the entry, not one whose
        // recording has gone missing on its own.
        guard retention != .never else { return .keep }
        let expired = hasExpired(createdAt: createdAt, retention: retention, now: now)
        guard retainedAudioPath != nil else {
            // Nothing to retry already. The row still waits out the retention
            // period, so a dictation that failed this morning stays visible
            // whether or not any audio survived it.
            return expired ? .discardEntry : .keep
        }
        if expired { return .deleteAudioAndDiscardEntry }
        // A row offering a Retry whose recording is missing can never keep it.
        return retainedAudioExistsOnDisk == false ? .discardEntry : .keep
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
    /// Names the phase for a log line, without the values a case may carry.
    var logLabel: String {
        switch self {
        case .idle: "idle"
        case .recording: "recording"
        case .transcribing: "transcribing"
        case .cancelledTranscript: "cancelled"
        case .noInternetConnection: "noInternet"
        case .dictationCopied: "dictationCopied"
        case .transcriptCopied: "transcriptCopied"
        case .dictationBlockedBySecureField: "secureField"
        case .permissionsRequired: "permissions"
        case .credentialsUnusable: "credentials"
        case .transcriptionFailed: "failed"
        case .noSpeechDetected: "noWords"
        case .retryFoundNoWords: "retryNoWords"
        case .noAudioSignal: "noSignal"
        case .message: "message"
        }
    }

    var pillShapeStyle: PillShapeStyle {
        if case .dictationCopied = self { return .roundedRectangle }
        if case .dictationBlockedBySecureField = self { return .roundedRectangle }
        if case .cancelledTranscript = self { return .roundedRectangle }
        if case .noInternetConnection = self { return .roundedRectangle }
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
        // Escape means cancel at every stage of a dictation, not just while the
        // microphone is open. The transcribing pill carries no controls of its
        // own, so this is the only gesture that reaches it.
        case .transcribing: .cancelTranscription
        case .cancelledTranscript, .noInternetConnection, .dictationCopied, .permissionsRequired, .credentialsUnusable,
             .transcriptionFailed, .noSpeechDetected, .retryFoundNoWords, .noAudioSignal,
             .transcriptCopied, .dictationBlockedBySecureField, .message: .dismiss
        }
    }

    /// What the outcome was, in the vocabulary the window's toast stack already
    /// speaks, so the two surfaces cannot tint the same outcome differently.
    /// Nothing maps to `.failure` — every phase that could claim red is
    /// recoverable in place, from the pill. Cancelling stays neutral, because the
    /// user asked for it and the Undo button carries the recovery on its own.
    var pillTone: ToastTone {
        switch self {
        case .dictationCopied: .success
        case .transcriptCopied: .success
        case .permissionsRequired, .credentialsUnusable,
             .transcriptionFailed, .noSpeechDetected, .retryFoundNoWords, .noAudioSignal,
             .dictationBlockedBySecureField: .warning
        case .idle, .recording, .transcribing, .cancelledTranscript, .noInternetConnection, .message: .neutral
        }
    }

    /// What clicking the pill body does, decided per phase. No case here
    /// transcribes, cancels, or discards: Retry and Undo spend API credit and
    /// stay on their buttons, where reaching them is deliberate.
    func pillDefaultAction(isPresented: Bool) -> PillDefaultAction {
        guard isPresented else { return .none }
        return switch self {
        case .idle, .recording, .transcribing, .cancelledTranscript, .noInternetConnection: .none
        // The transcript is selectable, so a body tap fights the selection it sits on.
        // Both carry a selectable transcript, so a body tap fights the selection.
        case .dictationCopied, .dictationBlockedBySecureField: .none
        case .transcriptCopied, .transcriptionFailed: .openMainWindow
        case .permissionsRequired: .openPermissionSettings
        case .credentialsUnusable: .openCredentialSettings
        case .noSpeechDetected, .noAudioSignal: .openInputSettings
        case .retryFoundNoWords: .none
        case .message: .dismiss
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

public enum KeyboardFocusRedirectPolicy {
    /// Whether delivery should follow keyboard focus into a process other than
    /// the frontmost one.
    ///
    /// An accessory (`LSUIElement`) app can present a nonactivating panel that
    /// takes keyboard focus without ever becoming frontmost — Raycast's command
    /// bar does, and so does Scriber's own pill. Typing follows keyboard focus,
    /// so dictation must too.
    ///
    /// Keep it narrow: a different process that genuinely exposes a focused text
    /// input, and never Scriber itself, which would make the pill its own paste
    /// target.
    public static func redirects(
        focusOwnerPID: Int32,
        frontmostPID: Int32,
        scriberPID: Int32,
        focusExposesTextInput: Bool
    ) -> Bool {
        focusOwnerPID != frontmostPID
            && focusOwnerPID != scriberPID
            && focusExposesTextInput
    }
}

public enum PasteConfirmationPolicy {
    /// Whether the transcript reached a text cursor.
    ///
    /// One question, and it is not a guess. The transcript is published only as a
    /// lazily promised string, so it does not exist until a destination asks for
    /// it. Nothing can insert what it never requested, and nothing that requested
    /// it was doing anything else with a paste.
    ///
    /// Nothing observed *after* the paste is admitted, whatever it looked like.
    /// Accessibility state is not a record of what a paste did: a focused field
    /// disappearing reads identically to text arriving, a live page rewrites
    /// itself on its own timers, and during a hands-free dictation the user may
    /// type into the box themselves. Each of those was read as a successful
    /// delivery at some point. What was focused *before* the paste is no better —
    /// it says where a paste would land, never that one did, and a real search
    /// field held the cursor through three deliveries that inserted nothing.
    public static func confirmsInsertion(pasteboardDataRequested: Bool) -> Bool {
        pasteboardDataRequested
    }
}

public struct ShortcutMatcher: Sendable {
    public var dictation: ShortcutChord

    public init(dictation: ShortcutChord) {
        self.dictation = dictation
    }

    /// `physicalKeyCode` is the key that changed the flags, which is the only
    /// place a modifier's side appears. Ignored unless the chord asks for a side.
    public func matches(
        modifiers: KeyModifiers,
        keyCode: UInt16?,
        heldKeys: Set<UInt16> = []
    ) -> Bool {
        guard dictation.modifiers == modifiers, dictation.keyCode == keyCode else { return false }
        guard dictation.isSided else { return true }
        return heldKeys == dictation.modifierKeyCodes
    }

    /// Whether a chord that was matched is still held. Extra keys do not end it;
    /// one of its own coming up does.
    public func stillHeld(modifiers: KeyModifiers, heldKeys: Set<UInt16>) -> Bool {
        guard dictation.isSided else { return dictation.modifiers.isSubset(of: modifiers) }
        return dictation.modifierKeyCodes.isSubset(of: heldKeys)
    }
}

public enum ShortcutMonitorMode: Equatable, Sendable {
    case idle
    case held
    case locked
    case busy
}

/// One keyboard event, reduced to what a shortcut decision needs.
public struct ShortcutTapInput: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public let kind: Kind
    public let keyCode: UInt16
    public let modifiers: KeyModifiers
    /// True for the stream macOS sends while a key stays down. A repeat is not a
    /// new press, and every place that treats it as one has to say so explicitly.
    public let isRepeat: Bool
    /// Seconds on a monotonic clock. Supplied by the caller rather than read here
    /// so the tap machine stays a pure function a test can drive.
    public let timestamp: TimeInterval

    public init(
        kind: Kind,
        keyCode: UInt16,
        modifiers: KeyModifiers,
        isRepeat: Bool = false,
        timestamp: TimeInterval = 0
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.timestamp = timestamp
    }
}

public enum ShortcutTapEffect: Equatable, Sendable {
    case action(ShortcutAction)
    case nonModifierKeyDown
}

public struct ShortcutTapOutcome: Equatable, Sendable {
    public let suppressesEvent: Bool
    public let effects: [ShortcutTapEffect]

    public init(suppressesEvent: Bool, effects: [ShortcutTapEffect] = []) {
        self.suppressesEvent = suppressesEvent
        self.effects = effects
    }

    public static let passedThrough = ShortcutTapOutcome(suppressesEvent: false)
    public static let suppressed = ShortcutTapOutcome(suppressesEvent: true)
}

/// Every decision the global shortcut tap makes, with no CoreGraphics in reach.
/// Kept apart from the tap because that tap is head-inserted at the HID level:
/// the whole machine's event stream advances only when its callback replies, so
/// a wrong decision there wedges the Mac rather than misbehaving quietly.
public struct ShortcutTapMachine: Sendable {
    public private(set) var mode: ShortcutMonitorMode = .idle
    public private(set) var holdLatched = false

    private var matcher: ShortcutMatcher
    private var isConfigurationCaptureActive = false
    /// When the latched press happened, so the release can tell a tap from a hold.
    private var pressedAt: TimeInterval?
    private var heldKeys = HeldModifierKeys()
    private var suppressedKeyCodes = Set<UInt16>()
    /// Whether the Escape press that began a run of repeats was consumed, so the
    /// repeats agree with it without asking again or cancelling a second time.
    private var escapeConsumed = false

    public init(dictation: ShortcutChord) {
        matcher = ShortcutMatcher(dictation: dictation)
    }

    public mutating func reconfigure(dictation: ShortcutChord) {
        matcher = ShortcutMatcher(dictation: dictation)
        reset()
    }

    /// Changes the mode and nothing else. A mode carries no sense of which
    /// dictation set it, so an idle belonging to a dictation that has just
    /// finished cannot be told from one belonging to the press happening now —
    /// and clearing the press's latch here left its release matching nothing,
    /// with a held recording nobody could stop. Releases clear the latch; a mode
    /// change must not. `reset()` still exists for the cases where the release
    /// genuinely never arrives.
    public mutating func setMode(_ mode: ShortcutMonitorMode) {
        self.mode = mode
    }

    /// Leaves the tap running while a Settings shortcut recorder owns keyboard
    /// input, but passes every event through without interpreting it.
    public mutating func setConfigurationCaptureActive(_ active: Bool) {
        isConfigurationCaptureActive = active
        reset()
    }

    /// Forgets every key believed to be down, for the cases where the releases
    /// will never arrive: the tap stopped, macOS disabled and it was re-armed, or
    /// keyboard input went to a shortcut recorder.
    public mutating func reset() {
        resetLatches()
        suppressedKeyCodes.removeAll()
        heldKeys.reset()
        escapeConsumed = false
    }

    /// Clears what is held without forgetting what to swallow on the way up. A
    /// chord still physically down when a recording is cancelled still owes a
    /// key-up, and letting that one through types the character into whatever the
    /// user was aiming at.
    private mutating func resetLatches() {
        holdLatched = false
        pressedAt = nil
    }

    /// Which release the press earned, given how long it stayed down.
    private func release(at timestamp: TimeInterval) -> ShortcutAction {
        guard let pressedAt, timestamp - pressedAt >= DictationShortcutTiming.tapThreshold else {
            return .releasedAsTap
        }
        return .releasedAfterHold
    }

    public mutating func handle(
        _ input: ShortcutTapInput,
        pillConsumesEscape: @autoclosure () -> Bool
    ) -> ShortcutTapOutcome {
        guard !isConfigurationCaptureActive else { return .passedThrough }

        if input.kind == .keyDown, input.keyCode == Self.escapeKeyCode {
            // Known and unfixed: this consumes Escape key-down while a pill is
            // visible but lets the matching key-up reach the foreground app. No
            // consequence has been observed.
            if input.isRepeat { return ShortcutTapOutcome(suppressesEvent: escapeConsumed) }
            escapeConsumed = pillConsumesEscape()
            return ShortcutTapOutcome(
                suppressesEvent: escapeConsumed,
                effects: escapeConsumed ? [.action(.cancel)] : []
            )
        }

        switch input.kind {
        case .keyUp: return handleKeyUp(input)
        case .keyDown: return handleKeyDown(input)
        case .flagsChanged: return handleFlagsChanged(input)
        }
    }

    private static let escapeKeyCode: UInt16 = 53

    private mutating func handleKeyUp(_ input: ShortcutTapInput) -> ShortcutTapOutcome {
        let wasSuppressed = suppressedKeyCodes.remove(input.keyCode) != nil
        if matcher.dictation.keyCode == input.keyCode, holdLatched {
            let action = release(at: input.timestamp)
            resetLatches()
            return ShortcutTapOutcome(suppressesEvent: true, effects: [.action(action)])
        }
        return ShortcutTapOutcome(suppressesEvent: wasSuppressed)
    }

    private mutating func handleKeyDown(_ input: ShortcutTapInput) -> ShortcutTapOutcome {
        if matcher.dictation.keyCode != nil,
           matcher.matches(modifiers: input.modifiers, keyCode: input.keyCode) {
            // Return here rather than falling through: the chord is Scriber's in
            // every mode, and falling through lets its own auto-repeat read as the
            // user typing, which cancels the recording and leaks the character.
            suppressedKeyCodes.insert(input.keyCode)
            guard !input.isRepeat, !holdLatched else { return .suppressed }
            holdLatched = true
            pressedAt = input.timestamp
            return ShortcutTapOutcome(suppressesEvent: true, effects: [.action(.pressed)])
        }

        if mode == .held {
            return ShortcutTapOutcome(suppressesEvent: false, effects: [.nonModifierKeyDown])
        }
        return .passedThrough
    }

    private mutating func handleFlagsChanged(_ input: ShortcutTapInput) -> ShortcutTapOutcome {
        heldKeys.observe(keyCode: input.keyCode, modifiers: input.modifiers)

        if !holdLatched, matcher.dictation.keyCode == nil,
           matcher.matches(modifiers: input.modifiers, keyCode: nil, heldKeys: heldKeys.keys) {
            holdLatched = true
            pressedAt = input.timestamp
            return ShortcutTapOutcome(suppressesEvent: false, effects: [.action(.pressed)])
        }

        // Latch-driven rather than mode-driven: the press reaches the coordinator a
        // run-loop turn before the mode comes back, and a release landing in that
        // window is otherwise dropped, leaving a recording nothing will stop. A
        // keyed chord releases here too, when a modifier goes up before its key,
        // and a sided one when one of its own keys does — a twin held down keeps
        // the flag set, so watching the flag alone never sees the release.
        let released = !matcher.stillHeld(modifiers: input.modifiers, heldKeys: heldKeys.keys)
        if holdLatched, released {
            let action = release(at: input.timestamp)
            resetLatches()
            return ShortcutTapOutcome(suppressesEvent: false, effects: [.action(action)])
        }

        // Modifier-only shortcuts (including bare Fn) must not consume the
        // flagsChanged event. Swallowing it can leave the focused app with a
        // stale modifier state, which in turn makes ordinary Space input fail.
        return .passedThrough
    }
}

/// Chords Scriber refuses to bind, because something else already answers to them.
///
/// This matters more than a preference usually would: the event tap *swallows*
/// what it matches, system-wide. A shortcut bound to ⌘C does not merely conflict
/// with copy, it replaces copy in every application on the Mac.
public enum ReservedShortcuts {
    /// Every key that may be bound held on its own, best first. `fn` leads
    /// because macOS gives it no role beyond the function keys. The right-hand
    /// twins follow: nothing on the Mac starts a shortcut with them, while Shift
    /// alone types capitals and the left-hand twins open most shortcuts.
    public static let bindableAlone: [ShortcutChord] = [
        .defaultDictation,
        ShortcutChord(modifiers: [.command], keyCode: nil, modifierSide: .right),
        ShortcutChord(modifiers: [.option], keyCode: nil, modifierSide: .right),
    ]

    /// A chord of several modifiers is a deliberate combination rather than a
    /// key someone leans on, so it needs no place on the list above.
    private static func isBindableAlone(_ chord: ShortcutChord) -> Bool {
        bindableAlone.contains(chord)
    }

    /// Why this chord cannot be bound, or nil when it can.
    public static func refusal(for chord: ShortcutChord) -> String? {
        // One modifier held alone, before the Command rule below, so a bare ⌘ is
        // refused for the reason that actually applies to it.
        if chord.keyCode == nil,
           chord.modifiers.rawValue.nonzeroBitCount == 1,
           !isBindableAlone(chord) {
            let rightTwin = ShortcutChord(modifiers: chord.modifiers, keyCode: nil, modifierSide: .right)
            if isBindableAlone(rightTwin) {
                return "\(chord.displayName) on its own starts most shortcuts on the Mac. Press the one on the right instead, or add a key."
            }
            return "\(chord.displayName) on its own is held as part of other shortcuts. Add a key, or another modifier."
        }
        // Only with a key: ⌘ held on its own is answered above, where the side
        // decides, and this rule is about what ⌘ plus a letter already means.
        if chord.keyCode != nil, chord.modifiers == [.command] {
            return "⌘ with a single key belongs to whatever app you are typing in. Add another modifier."
        }
        // ⌘ with another modifier and no key is how most shortcuts on the Mac
        // begin, so binding it starts a recording on the way into ⌘⌥I or ⌘⇧4.
        // Held on the right it is clear of all of them, which is the same reason
        // a lone Right ⌘ is allowed.
        if chord.keyCode == nil,
           chord.modifiers.contains(.command),
           chord.modifiers.rawValue.nonzeroBitCount > 1,
           !chord.isEntirelyRightHanded {
            if chord.modifiers.isSubset(of: ModifierKeyCodes.sidedModifiers) {
                return "\(chord.displayName) starts most shortcuts on the Mac. Hold both on the right instead."
            }
            return "\(chord.displayName) starts most shortcuts on the Mac. Add a key, or use ⌘ and ⌥ on the right."
        }
        if systemChords.contains(normalized(chord)) {
            return "macOS reserves \(chord.displayName). Choose another shortcut."
        }
        return nil
    }

    public static func reserves(_ chord: ShortcutChord) -> Bool { refusal(for: chord) != nil }

    /// Drops the function modifier macOS attaches to the arrow, function, and
    /// navigation keys on its own, so ⌃↑ matches whether it arrives as `[.control]`
    /// or as `[.control, .function]`. Only for those keys: stripping it everywhere
    /// would make `fn⌘Q` match plain ⌘Q, which is a different chord.
    private static func normalized(_ chord: ShortcutChord) -> ShortcutChord {
        guard let keyCode = chord.keyCode,
              KeyCodeNames.intrinsicallyFunctionKeyed.contains(keyCode) else { return chord }
        return ShortcutChord(modifiers: chord.modifiers.subtracting(.function), keyCode: keyCode)
    }

    private static func chord(_ modifiers: KeyModifiers, _ key: String) -> ShortcutChord {
        guard let keyCode = KeyCodeNames.code(for: key) else {
            preconditionFailure("No key code named \(key)")
        }
        return ShortcutChord(modifiers: modifiers, keyCode: keyCode)
    }

    /// Written in key names rather than codes on purpose — see `KeyCodeNames.code(for:)`.
    ///
    /// Single-Command chords are absent because the rule above already covers all
    /// of them. ⌘⇧D is absent because it is free: no part of macOS claims it, and
    /// it is a good chord to dictate with.
    ///
    /// Known and unfixed: this can only know the shortcuts macOS ships with, never
    /// the ones another application has registered.
    private static let systemChords: Set<ShortcutChord> = [
        // Screenshots and screen recording
        chord([.command, .shift], "3"),
        chord([.command, .shift], "4"),
        chord([.command, .shift], "5"),
        chord([.command, .shift], "6"),
        chord([.control, .command, .shift], "3"),
        chord([.control, .command, .shift], "4"),

        // Spotlight, input sources, character viewer
        chord([.option, .command], "Space"),
        chord([.control, .command], "Space"),
        chord([.control], "Space"),
        chord([.control, .option], "Space"),

        // Mission Control
        chord([.control], "↑"),
        chord([.control], "↓"),
        chord([.control], "←"),
        chord([.control], "→"),

        // Switching spaces
        chord([.control], "1"),
        chord([.control], "2"),
        chord([.control], "3"),
        chord([.control], "4"),
        chord([.control], "5"),
        chord([.control], "6"),
        chord([.control], "7"),
        chord([.control], "8"),
        chord([.control], "9"),

        // The Dock
        chord([.option, .command], "D"),

        // Locking, logging out, force quitting
        chord([.control, .command], "Q"),
        chord([.command, .shift], "Q"),
        chord([.option, .command, .shift], "Q"),
        chord([.option, .command], "Escape"),

        // Windows
        chord([.command, .shift], "W"),
        chord([.control, .command], "F"),

        // Accessibility and zoom
        chord([.command], "F5"),
        chord([.option, .command], "F5"),
        chord([.option, .command], "8"),
        chord([.option, .command], "="),
        chord([.option, .command], "-"),
        chord([.control, .option, .command], "8"),

        // Keyboard navigation, and display mirroring
        chord([.control], "F1"),
        chord([.control], "F2"),
        chord([.control], "F3"),
        chord([.control], "F4"),
        chord([.control], "F5"),
        chord([.control], "F6"),
        chord([.control], "F7"),
        chord([.control], "F8"),
        chord([.command], "F1"),

        // Help
        chord([.command, .shift], "/"),

        // Text editing every macOS text field honours. AppKit implements these in
        // the field editor, so binding one replaces it in every app at once.
        chord([.control], "A"),
        chord([.control], "B"),
        chord([.control], "D"),
        chord([.control], "E"),
        chord([.control], "F"),
        chord([.control], "H"),
        chord([.control], "K"),
        chord([.control], "N"),
        chord([.control], "O"),
        chord([.control], "P"),
        chord([.control], "T"),
        chord([.control], "V"),
        chord([.control], "Y"),
    ]
}

/// Resolves what was loaded from disk into a chord Scriber can actually run.
public enum ShortcutPreferences {
    /// A stored chord predates every rule added since it was stored, and nothing
    /// on the load path has ever checked one. Replaces anything unbindable with
    /// the default.
    public static func resolve(dictation: ShortcutChord) -> ShortcutChord {
        usable(dictation) ? dictation : .defaultDictation
    }

    /// The recorded chord is offered as something to switch back to, so one that
    /// is no longer bindable has to stop being offered — selecting it would bind
    /// what the recorder itself would now refuse.
    public static func resolve(custom: ShortcutChord?) -> ShortcutChord? {
        custom.flatMap { usable($0) ? $0 : nil }
    }

    private static func usable(_ chord: ShortcutChord) -> Bool {
        chord.isValid && !ReservedShortcuts.reserves(chord)
    }
}

public extension ContinuousClock.Instant {
    /// Milliseconds since this instant. Every timing line in the app reports in
    /// these, so they can be compared against each other without conversion.
    var elapsedMilliseconds: Int {
        let elapsed = ContinuousClock().now - self
        return Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
