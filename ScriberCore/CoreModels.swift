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

public struct ShortcutChord: Codable, Hashable, Sendable {
    public var modifiers: KeyModifiers
    public var keyCode: UInt16?

    public init(modifiers: KeyModifiers, keyCode: UInt16?) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public static let defaultDictation = ShortcutChord(modifiers: [.function], keyCode: nil)

    public var isValid: Bool { !modifiers.isEmpty }

    public var usesFunctionKey: Bool { modifiers.contains(.function) }

    public var displayName: String {
        let modifierText = modifiers.displayParts.joined(separator: modifiers == [.function] ? "" : "+")
        guard let keyCode else { return modifierText }
        let key = KeyCodeNames.name(for: keyCode)
        return modifierText.isEmpty ? key : "\(modifierText)+\(key)"
    }
}

/// What setup suggests to someone whose keyboard has no `fn` key macOS can see.
///
/// Not a preset in the picker: setup offers `fn` or recording your own, and this
/// is the hint shown once recording is the path taken. Two modifiers because
/// `ReservedShortcuts` refuses a lone one.
public enum SuggestedShortcuts {
    public static let withoutFunctionKey = ShortcutChord(modifiers: [.control, .option], keyCode: nil)
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

    /// Returns the peak modifier-only chord as soon as the **first** modifier is
    /// released, then resets for the next capture.
    ///
    /// It used to wait for every modifier to be released, which was worse for a
    /// reason that is not about correctness: while keys were still down after a
    /// release, the recorder looked like it was still listening, which invites the
    /// belief that letting go of one key edits the chord already captured. It never
    /// did — the peak is what gets committed either way — and it could not be made
    /// to. Honouring it would mean deciding which keys counted as "released
    /// together", and there is no signal that answers that: a user correcting a
    /// mistake and a user finishing a chord produce the same events.
    ///
    /// Committing at the first release removes the question. The window in which
    /// the interface implies an ability it does not have closes, and the chord is
    /// still the peak, so every release order yields the same result as before.
    public mutating func commitOnFirstModifierRelease(
        currentModifiers: KeyModifiers
    ) -> ShortcutChord? {
        guard !peakModifiers.isEmpty else { return nil }
        // A strict subset means something that was held is no longer held. Equal
        // sets are the plateau between the last press and the first release, and a
        // superset is still building up.
        guard currentModifiers.isStrictSubset(of: peakModifiers) else { return nil }
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

    /// The reverse, so a table of chords can be written in the names a person
    /// reads instead of in codes they have to trust. The positional layout makes
    /// those codes genuinely misleading — 23 is `5` and 22 is `6`, F3 is 99 and
    /// F5 is 96 — and a mistyped one is a rule that silently never matches.
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

    public var cachedUsageTitle: String {
        usageUnavailable ? "Last known ElevenLabs credits" : "ElevenLabs credits"
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
    /// cannot help. Names the list holding the switch: the Open at Login list
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
    case dictationCopied(text: String, message: String)
    case permissionsRequired([ScriberPermission])
    case credentialsUnusable(CredentialReadiness)
    case transcriptionFailed(String)
    /// The transcription succeeded but contained no words. Sound did reach the
    /// recorder, so the input is working — routes to input settings anyway, because
    /// an input that is too quiet is the next likeliest cause.
    case noSpeechDetected
    /// Nothing ever crossed the signal threshold, so the recording was discarded
    /// before it cost any API credit.
    ///
    /// Distinct from `.noSpeechDetected` on purpose. This one means the microphone
    /// produced no usable sound at all — muted, wrong device, input volume at zero
    /// — and it used to be discarded in complete silence, which made a broken
    /// microphone indistinguishable from not having spoken.
    case noAudioSignal
    /// A transcript reached the clipboard instead of the cursor, from a History
    /// retry rather than from a failed paste.
    ///
    /// Its own phase rather than a `.message`, because it is not an
    /// acknowledgement of something the user just did — it is the outcome telling
    /// them the text is *not* where they wanted it and they have to paste it
    /// themselves. As a 1.5-second `.message` with a generic waveform it was
    /// missable, and it named the same outcome differently from
    /// `.dictationCopied`.
    case transcriptCopied
    case message(String)

    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing: true
        default: false
        }
    }

    /// Every phase that is not itself a dictation in flight is a resting phase: the
    /// notice on screen describes something that already finished, so a shortcut
    /// press must start the next dictation rather than be swallowed. Enumerating
    /// the resting phases by name is how `.noSpeechDetected` came to deadlock both
    /// shortcuts until its pill was dismissed by hand — the pill's own countdown
    /// clears the pill, never this phase. Derive it from `isBusy` instead so a new
    /// phase can never fall out of the list.
    public var acceptsRecordingStart: Bool { !isBusy }

    /// Cancelling is permitted in every recording mode: held recording still
    /// stops on key release, but a change of mind before that should not require
    /// waiting for it. This governs `HandsFreePillAction.disposition(for:)`, so
    /// it covers clicks on the pill's Cancel control only. It says nothing about
    /// whether that control is currently drawn — see
    /// `showsCancelRecordingControl(isHovering:)` — and nothing about Escape,
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

    /// Confirm only makes sense while locked. A held recording already has an
    /// explicit stop gesture — releasing the key — so offering a second one
    /// would just be two ways to do the same thing. Unlike Cancel, its display
    /// never depends on hover.
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
/// rather than "start listening and let go".
///
/// The decision is taken on release, not on press, so this never delays the
/// start of a recording. Too short and a brief deliberate hold ends up
/// hands-free; too long and a tap feels like it hung.
public enum DictationShortcutTiming {
    public static let tapThreshold: TimeInterval = 0.25
}

public enum PillDismissalAction: Equatable, Sendable {
    case passThrough
    case cancelRecording
    case hideTranscription
    case dismiss
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
    /// key was the modifier half of some other shortcut. Nothing is worth saying
    /// about it — no sound, no message, no history row, just the pill closing —
    /// because every one of those is a correction aimed at someone who did not ask
    /// for anything.
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
             .transcriptionFailed, .noSpeechDetected, .noAudioSignal,
             .transcriptCopied, .message: .dismiss
        }
    }

    /// What the outcome was, in the vocabulary the window's toast stack already
    /// speaks, so the two surfaces cannot tint the same outcome differently.
    ///
    /// Nothing maps to `.failure`: every phase that could claim red is
    /// recoverable in place, from the pill, without losing the transcript.
    ///
    /// Cancelling is the one recoverable outcome that stays neutral. The user
    /// asked for it, so amber would be the app disagreeing with a deliberate
    /// choice; the Undo button carries the recovery on its own.
    var pillTone: ToastTone {
        switch self {
        case .dictationCopied: .success
        case .transcriptCopied: .success
        case .permissionsRequired, .credentialsUnusable,
             .transcriptionFailed, .noSpeechDetected, .noAudioSignal: .warning
        case .idle, .recording, .transcribing, .cancelledTranscript, .message: .neutral
        }
    }

    /// What clicking the pill body does, decided per phase before the gesture
    /// exists rather than after someone lands one by accident.
    ///
    /// No case here transcribes, cancels, or discards. Retry and Undo spend API
    /// credit and stay on their buttons, where reaching them is deliberate.
    func pillDefaultAction(isPresented: Bool) -> PillDefaultAction {
        guard isPresented else { return .none }
        return switch self {
        // The transcript in the copied result is selectable; a body tap would
        // fight the selection it sits on.
        case .idle, .recording, .transcribing, .cancelledTranscript: .none
        // The transcript is selectable, so a body tap fights the selection it sits on.
        case .dictationCopied: .none
        case .transcriptCopied, .transcriptionFailed: .openMainWindow
        case .permissionsRequired: .openPermissionSettings
        case .credentialsUnusable: .openCredentialSettings
        case .noSpeechDetected, .noAudioSignal: .openInputSettings
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
    /// takes keyboard focus without ever becoming frontmost. Raycast's command
    /// bar does this, and so does Scriber's own pill. Typing follows keyboard
    /// focus, so dictation must too — otherwise the transcript lands in the
    /// window the user visibly left behind.
    ///
    /// Redirection is deliberately narrow. It requires a different process that
    /// genuinely exposes a focused text input, so an ordinary app whose focus and
    /// frontmost status agree is never affected.
    ///
    /// Scriber never redirects to itself. That keeps the pill from becoming its
    /// own paste target without blocking Scriber's ordinary windows, which are
    /// frontmost when focused and therefore need no redirect.
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
    public static func confirmsInsertion(
        accessibilityMutationObserved: Bool,
        pasteboardDataRequested: Bool
    ) -> Bool {
        accessibilityMutationObserved || pasteboardDataRequested
    }

    /// Accessibility state only counts as evidence when it was observed on a focus
    /// that genuinely looks like text input.
    ///
    /// A live web page with no focused text box changes its own accessibility
    /// state through carets, timers, and streaming content. Watching an unrelated
    /// focused element therefore manufactures confirmations at random, which is
    /// worse than having no Accessibility evidence at all: a failed paste is
    /// reported as delivered and the transcript is never offered for recovery.
    public static func qualifiesAsAccessibilityEvidence(
        focusContainsTextInput: Bool,
        mutationObserved: Bool
    ) -> Bool {
        focusContainsTextInput && mutationObserved
    }
}

public struct ShortcutMatcher: Sendable {
    public var dictation: ShortcutChord

    public init(dictation: ShortcutChord) {
        self.dictation = dictation
    }

    public func matches(modifiers: KeyModifiers, keyCode: UInt16?) -> Bool {
        dictation.modifiers == modifiers && dictation.keyCode == keyCode
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
///
/// It lives here and not beside the tap because that tap is head-inserted at the
/// HID level: the whole machine's event stream advances only when its callback
/// replies, so a wrong decision there wedges the Mac rather than misbehaving
/// quietly. Separating the decision from the C API is what lets a test reach it.
public struct ShortcutTapMachine: Sendable {
    public private(set) var mode: ShortcutMonitorMode = .idle
    public private(set) var holdLatched = false

    private var matcher: ShortcutMatcher
    private var isConfigurationCaptureActive = false
    /// When the latched press happened, so the release can tell a tap from a hold.
    private var pressedAt: TimeInterval?
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

    public mutating func setMode(_ mode: ShortcutMonitorMode) {
        self.mode = mode
        if mode == .idle || mode == .busy { resetLatches() }
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
            // The dictation chord is Scriber's in every mode, so it returns here
            // rather than falling through. Falling through let the chord's own
            // auto-repeat read as the user typing, which cancelled the recording
            // and cleared the latch, so the next repeat started another one — and
            // leaked the character to the app in front on the way past.
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
        if !holdLatched, matcher.dictation.keyCode == nil,
           matcher.matches(modifiers: input.modifiers, keyCode: nil) {
            holdLatched = true
            pressedAt = input.timestamp
            return ShortcutTapOutcome(suppressesEvent: false, effects: [.action(.pressed)])
        }

        // Latch-driven rather than mode-driven. The press reaches the coordinator
        // a run-loop turn before the mode comes back, and a release landing in
        // that window used to be dropped on the `.idle` branch — leaving a
        // recording running that nothing was going to stop. A keyed chord releases
        // here too, when one of its modifiers goes up before its key does.
        if holdLatched, !matcher.dictation.modifiers.isSubset(of: input.modifiers) {
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
    /// Why this chord cannot be bound, or nil when it can.
    public static func refusal(for chord: ShortcutChord) -> String? {
        // One modifier held alone, before the Command rule below, so a bare ⌘ is
        // refused for the reason that actually applies to it. Shift on its own is
        // how every capital letter is typed, and Control, Option, and Command are
        // each held as the first half of most other shortcuts on the system.
        // `fn` is the exception and Scriber's own default: macOS gives it no role
        // beyond the function keys, so holding it alone means nothing else.
        if chord.keyCode == nil,
           chord.modifiers.rawValue.nonzeroBitCount == 1,
           chord.modifiers != [.function] {
            return "\(chord.displayName) on its own is held as part of other shortcuts. Add a key, or another modifier."
        }
        if chord.modifiers == [.command] {
            return "⌘ with a single key belongs to whatever app you are typing in. Add another modifier."
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

    private static func usable(_ chord: ShortcutChord) -> Bool {
        chord.isValid && !ReservedShortcuts.reserves(chord)
    }
}
