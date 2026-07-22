import Foundation
import Testing
@testable import ScriberCore

@Suite("Shortcut matching")
struct ShortcutMatcherTests {
    @Test("Default shortcuts are distinct exact chords")
    func defaultShortcuts() {
        let matcher = ShortcutMatcher(hold: .defaultHold, toggle: .defaultToggle)
        #expect(matcher.matchesExactly(.defaultHold, modifiers: [.function], keyCode: nil))
        #expect(matcher.matchesExactly(.defaultToggle, modifiers: [.function], keyCode: 49))
        #expect(!matcher.matchesExactly(.defaultToggle, modifiers: [.function, .control], keyCode: 49))
    }

    @Test("Hold-only modifiers are ignored when locking")
    func contextualToggle() {
        let hold = ShortcutChord(modifiers: [.function, .control, .option], keyCode: nil)
        let matcher = ShortcutMatcher(hold: hold, toggle: .defaultToggle)
        #expect(matcher.matchesToggleWhileHeld(modifiers: [.function, .control, .option], keyCode: 49))
        #expect(!matcher.matchesToggleWhileHeld(modifiers: [.function, .control, .option, .shift], keyCode: 49))
    }

    @Test("Busy state is limited to recording and transcription")
    func busyState() {
        #expect(AppPhase.recording(mode: .held, elapsed: 0, level: -80).isBusy)
        #expect(AppPhase.transcribing(attempt: 1, retryDelay: nil).isBusy)
        #expect(!AppPhase.message("Still transcribing").isBusy)
        #expect(!AppPhase.pasteFailed("No target").isBusy)
    }
}

@Suite("Pill dismissal")
struct PillDismissalTests {
    @Test("Escape passes through when no pill is presented")
    func hiddenPill() {
        #expect(AppPhase.recording(mode: .held, elapsed: 0, level: -80)
            .pillDismissalAction(isPresented: false) == .passThrough)
        #expect(AppPhase.idle.pillDismissalAction(isPresented: false) == .passThrough)
    }

    @Test("A visible recording is cancelled")
    func recording() {
        #expect(AppPhase.recording(mode: .locked, elapsed: 2, level: -20)
            .pillDismissalAction(isPresented: true) == .cancelRecording)
    }

    @Test("A visible transcription is hidden without cancellation")
    func transcribing() {
        #expect(AppPhase.transcribing(attempt: 2, retryDelay: 3)
            .pillDismissalAction(isPresented: true) == .hideTranscription)
    }

    @Test("Visible terminal pills are dismissed")
    func terminalPills() {
        #expect(AppPhase.dictationCopied(text: "Done", message: "Copied")
            .pillDismissalAction(isPresented: true) == .dismiss)
        #expect(AppPhase.transcriptionFailed("Offline")
            .pillDismissalAction(isPresented: true) == .dismiss)
    }
}

@Suite("Recording cancellation")
struct RecordingCancellationTests {
    @Test("One second begins recoverable cancellation")
    func recoveryBoundary() {
        #expect(!RecordingCancellationPolicy.retainsAudio(elapsed: 0.999, detectedSignal: true))
        #expect(RecordingCancellationPolicy.retainsAudio(elapsed: 1, detectedSignal: true))
        #expect(!RecordingCancellationPolicy.retainsAudio(elapsed: 2, detectedSignal: false))
    }

    @Test("Typing only cancels an early held recording")
    func typingWindow() {
        #expect(RecordingCancellationPolicy.cancelsForNonModifierKey(mode: .held, elapsed: 0.5))
        #expect(!RecordingCancellationPolicy.cancelsForNonModifierKey(mode: .held, elapsed: 1))
        #expect(!RecordingCancellationPolicy.cancelsForNonModifierKey(mode: .locked, elapsed: 0.5))
    }
}

@Suite("Pill shape")
struct PillShapeTests {
    @Test("Expanded result and cancellation recovery use the fixed corner radius")
    func copiedResultShape() {
        let copied = AppPhase.dictationCopied(text: String(repeating: "Long text ", count: 20), message: "Copied")

        #expect(copied.pillShapeStyle == .roundedRectangle)
        #expect(copied.pillCornerRadius(height: 230) == 24)
        #expect(AppPhase.cancelledTranscript.pillShapeStyle == .roundedRectangle)
    }

    @Test("Phases after a copied result restore their capsule radius")
    func restoresCapsuleAfterCopiedResult() {
        let destinations: [(AppPhase, Double)] = [
            (.recording(mode: .held, elapsed: 1, level: -20), 62),
            (.transcribing(attempt: 1, retryDelay: nil), 62),
            (.message("Copied"), 62),
            (.pasteFailed("No target"), 72),
            (.transcriptionFailed("Offline"), 72)
        ]

        for (phase, height) in destinations {
            #expect(phase.pillShapeStyle == .capsule)
            #expect(phase.pillCornerRadius(height: height) == height / 2)
        }
    }
}

@Suite("Paste confirmation")
struct PasteConfirmationTests {
    @Test("Confirms an observable Accessibility mutation")
    func accessibilityMutation() {
        #expect(PasteConfirmationPolicy.confirmsInsertion(
            accessibilityMutationObserved: true,
            pasteboardDataRequested: false
        ))
    }

    @Test("Confirms a destination requesting the concealed promised text")
    func pasteboardRequest() {
        #expect(PasteConfirmationPolicy.confirmsInsertion(
            accessibilityMutationObserved: false,
            pasteboardDataRequested: true
        ))
    }

    @Test("Rejects a dispatched paste with no data request or observable mutation")
    func noConsumptionOrMutation() {
        #expect(!PasteConfirmationPolicy.confirmsInsertion(
            accessibilityMutationObserved: false,
            pasteboardDataRequested: false
        ))
    }
}

@Suite("Scribe validation")
struct ScribeValidationTests {
    @Test("Trims and removes empty keyterms")
    func trimsKeyterms() throws {
        let result = try ScribeClient.validateKeyterms(["  Scriber  ", "", "Sobat HAPE"])
        #expect(result == ["Scriber", "Sobat HAPE"])
    }

    @Test("Rejects unsupported characters")
    func rejectsUnsupportedCharacters() {
        #expect(throws: ScribeError.self) {
            try ScribeClient.validateKeyterms(["bad[keyterm]"])
        }
    }

    @Test("Classifies retryable failures")
    func retryability() {
        #expect(ScribeError.rateLimited.retryable)
        #expect(ScribeError.serviceUnavailable.retryable)
        #expect(ScribeError.network("offline").retryable)
        #expect(!ScribeError.authentication.retryable)
        #expect(ScribeError.authentication.invalidatesAPIKey)
        #expect(ScribeError.authorization("restricted").invalidatesAPIKey)
        #expect(!ScribeError.network("offline").invalidatesAPIKey)
        #expect(!ScribeError.insufficientCredits.invalidatesAPIKey)
        #expect(!ScribeError.insufficientCredits.retryable)
        #expect(!ScribeError.invalidRequest("bad input").retryable)
    }

    @Test("Accepts a successful response with empty text")
    func acceptsEmptySuccessfulResponse() throws {
        let response = try ScribeClient.decodeResponse(Data(#"{"text":"","language_code":"en"}"#.utf8))
        #expect(response.text.isEmpty)
        #expect(TranscriptContent.normalized(response.text) == nil)
    }

    @Test("Classifies credit-free API key checks")
    func apiKeyValidationResponses() {
        let success = ScribeClient.apiKeyValidationError(statusCode: 200, data: Data())
        #expect(success == nil)

        let missingSentinel = ScribeClient.apiKeyValidationError(statusCode: 404, data: Data())
        #expect(missingSentinel == nil)

        let invalidSentinelID = ScribeClient.apiKeyValidationError(statusCode: 422, data: Data())
        #expect(invalidSentinelID == nil)

        let unauthorized = ScribeClient.apiKeyValidationError(statusCode: 401, data: Data())
        #expect(unauthorized?.errorDescription == "ElevenLabs rejected this API key. Check that it is correct and enabled.")

        let forbidden = ScribeClient.apiKeyValidationError(statusCode: 403, data: Data())
        #expect(forbidden?.errorDescription?.contains("scope") == true)
        #expect(forbidden?.invalidatesAPIKey == true)

        let unavailable = ScribeClient.apiKeyValidationError(statusCode: 503, data: Data())
        #expect(unavailable?.retryable == true)
    }

    @Test("Decodes subscription credit usage and extension policy")
    func subscriptionUsage() throws {
        let limited = try ScribeClient.decodeSubscriptionUsage(Data(#"""
        {
            "tier":"free",
            "character_count":9800,
            "character_limit":10000,
            "max_credit_limit_extension":0,
            "can_extend_character_limit":false,
            "next_character_count_reset_unix":1780000000
        }
        """#.utf8))
        #expect(limited.remainingCredits == 200)
        #expect(!limited.shouldBlockDictation)
        let restored = try JSONDecoder().decode(
            ElevenLabsSubscriptionUsage.self,
            from: JSONEncoder().encode(limited)
        )
        #expect(restored == limited)

        let exhausted = ElevenLabsSubscriptionUsage(
            tier: "free",
            usedCredits: 10_000,
            totalCredits: 10_000,
            canExtendCredits: false,
            resetAt: nil
        )
        #expect(exhausted.shouldBlockDictation)

        let unlimited = try ScribeClient.decodeSubscriptionUsage(Data(#"""
        {
            "tier":"creator",
            "character_count":10000,
            "character_limit":10000,
            "max_credit_limit_extension":"unlimited",
            "can_extend_character_limit":false
        }
        """#.utf8))
        #expect(unlimited.canExtendCredits)
        #expect(!unlimited.shouldBlockDictation)
    }
}

@Suite("Credential state")
struct CredentialStateTests {
    @Test("Rejects validation results from an older credential revision")
    func rejectsStaleValidationResults() {
        var revision = CredentialRevision()
        let launchValidationRevision = revision.current

        #expect(revision.matches(launchValidationRevision))
        revision.advance()
        #expect(!revision.matches(launchValidationRevision))
        #expect(revision.matches(revision.current))
    }

    @Test("Clears credential pills only after the replacement is configured and valid")
    func resolvesCredentialPills() {
        #expect(AppPhase.apiKeyInvalid.resolvingCredentialBlock(
            apiKeyConfigured: true,
            apiKeyValidity: .valid,
            apiCreditsExhausted: false
        ) == .idle)
        #expect(AppPhase.apiKeyInvalid.resolvingCredentialBlock(
            apiKeyConfigured: false,
            apiKeyValidity: .valid,
            apiCreditsExhausted: false
        ) == .apiKeyInvalid)
        #expect(AppPhase.apiCreditsExhausted.resolvingCredentialBlock(
            apiKeyConfigured: true,
            apiKeyValidity: .valid,
            apiCreditsExhausted: false
        ) == .idle)
    }
}

@Suite("Credential persistence")
struct CredentialPersistenceTests {
    @Test("Saves, trims, and updates the protected credential")
    func savesAndUpdatesProtectedCredential() throws {
        let backend = FakeCredentialStorageBackend()
        let store = VerifiedCredentialStore(backend: backend)

        try store.save("  first-key \n")
        #expect(backend.values[.dataProtection] == "first-key")
        try store.save("second-key")
        #expect(backend.values[.dataProtection] == "second-key")
        #expect(backend.deleteCounts[.legacy, default: 0] == 0)
    }

    @Test("Rejects a save when protected readback is missing")
    func rejectsMissingReadback() {
        let backend = FakeCredentialStorageBackend()
        backend.discardProtectedWrites = true
        let store = VerifiedCredentialStore(backend: backend)

        #expect(throws: CredentialStoreError.persistenceVerificationFailed) {
            try store.save("valid-key")
        }
    }

    @Test("Rejects a save when protected readback differs")
    func rejectsMismatchedReadback() {
        let backend = FakeCredentialStorageBackend()
        backend.protectedWriteReplacement = "different-key"
        let store = VerifiedCredentialStore(backend: backend)

        #expect(throws: CredentialStoreError.persistenceVerificationFailed) {
            try store.save("valid-key")
        }
    }

    @Test("Migrates a legacy credential into protected storage")
    func migratesLegacyCredential() throws {
        let backend = FakeCredentialStorageBackend(values: [.legacy: "legacy-key"])
        let store = VerifiedCredentialStore(backend: backend)

        #expect(try store.read() == "legacy-key")
        #expect(backend.values[.dataProtection] == "legacy-key")
        #expect(backend.values[.legacy] == nil)
        #expect(backend.deleteCounts[.legacy] == 1)
    }

    @Test("Restores protected storage if legacy cleanup removes it")
    func restoresAfterDestructiveLegacyCleanup() throws {
        let backend = FakeCredentialStorageBackend(values: [.legacy: "legacy-key"])
        backend.legacyDeletionAlsoDeletesProtectedValue = true
        let store = VerifiedCredentialStore(backend: backend)

        #expect(try store.read() == "legacy-key")
        #expect(backend.values[.dataProtection] == "legacy-key")
        #expect(backend.values[.legacy] == nil)
        #expect(backend.protectedWriteCount == 2)
    }

    @Test("A replacement supersedes and removes a stale legacy credential")
    func replacementSupersedesLegacyCredential() throws {
        let backend = FakeCredentialStorageBackend(values: [
            .dataProtection: "old-protected-key",
            .legacy: "stale-legacy-key",
        ])
        let store = VerifiedCredentialStore(backend: backend)

        try store.save("replacement-key")
        #expect(backend.values[.dataProtection] == "replacement-key")
        #expect(backend.values[.legacy] == nil)
        #expect(backend.deleteCounts[.legacy] == 1)
    }

    @Test("Deletes both storage domains for blank input")
    func deletesBlankCredential() throws {
        let backend = FakeCredentialStorageBackend(values: [
            .dataProtection: "protected-key",
            .legacy: "legacy-key",
        ])
        let store = VerifiedCredentialStore(backend: backend)

        try store.save("  \n")
        #expect(backend.values.isEmpty)
        #expect(backend.deleteCounts[.dataProtection] == 1)
        #expect(backend.deleteCounts[.legacy] == 1)
    }
}

private final class FakeCredentialStorageBackend: CredentialStorageBackend, @unchecked Sendable {
    var values: [CredentialStorageDomain: String]
    var deleteCounts: [CredentialStorageDomain: Int] = [:]
    var discardProtectedWrites = false
    var protectedWriteReplacement: String?
    var legacyDeletionAlsoDeletesProtectedValue = false
    private(set) var protectedWriteCount = 0

    init(values: [CredentialStorageDomain: String] = [:]) {
        self.values = values
    }

    func read(from domain: CredentialStorageDomain) throws -> String? {
        values[domain]
    }

    func write(_ value: String, to domain: CredentialStorageDomain) throws {
        if domain == .dataProtection {
            protectedWriteCount += 1
            guard !discardProtectedWrites else { return }
            values[domain] = protectedWriteReplacement ?? value
        } else {
            values[domain] = value
        }
    }

    func delete(from domain: CredentialStorageDomain) throws {
        deleteCounts[domain, default: 0] += 1
        values[domain] = nil
        if domain == .legacy, legacyDeletionAlsoDeletesProtectedValue {
            values[.dataProtection] = nil
        }
    }
}

@Suite("Transcript content")
struct TranscriptContentTests {
    @Test("Rejects empty and punctuation-only results")
    func rejectsNoWords() {
        #expect(TranscriptContent.normalized("   \n") == nil)
        #expect(TranscriptContent.normalized("... — !") == nil)
    }

    @Test("Trims a transcript containing words")
    func normalizesWords() {
        #expect(TranscriptContent.normalized("  Hello, world. \n") == "Hello, world.")
    }
}

@Suite("Audio input policy")
struct AudioInputPolicyTests {
    @Test("Prefers a built-in microphone on first launch")
    func prefersBuiltInInput() {
        let devices = [
            AudioInputDeviceDescriptor(id: "usb", name: "USB Microphone", isBuiltIn: false),
            AudioInputDeviceDescriptor(id: "built-in", name: "MacBook Microphone", isBuiltIn: true),
        ]
        #expect(AudioInputSelection.initialSelection(from: devices) == .device(id: "built-in", name: "MacBook Microphone"))
        #expect(AudioInputSelection.initialSelection(from: []) == .automatic)
    }

    @Test("Uses a low, monotonic signal threshold")
    func signalThreshold() {
        #expect(!AudioSignal.isDetected(decibels: -80))
        #expect(!AudioSignal.isDetected(decibels: AudioSignal.detectionThreshold))
        #expect(AudioSignal.isDetected(decibels: -59.9))
        #expect(AudioSignal.normalized(decibels: -80) == 0)
        #expect(AudioSignal.normalized(decibels: -30) < AudioSignal.normalized(decibels: -10))
        #expect(AudioSignal.normalized(decibels: 0) == 1)
    }
}

@Suite("Text input target policy")
struct TextInputTargetPolicyTests {
    @Test("Accepts standard text roles without writable Accessibility values")
    func acceptsStandardTextRoles() {
        #expect(TextInputTargetPolicy.accepts(
            role: "AXTextArea",
            subrole: nil,
            selectedTextSettable: false,
            exposesCharacterCount: false,
            enabled: true
        ))
        #expect(TextInputTargetPolicy.accepts(
            role: "AXTextField",
            subrole: "AXSearchField",
            selectedTextSettable: false,
            exposesCharacterCount: false,
            enabled: nil
        ))
    }

    @Test("Accepts custom controls that expose editable character counts")
    func acceptsCustomEditableControls() {
        #expect(TextInputTargetPolicy.accepts(
            role: "AXGroup",
            subrole: nil,
            selectedTextSettable: false,
            exposesCharacterCount: true,
            enabled: true
        ))
    }

    @Test("Accepts web controls that explicitly report editability")
    func acceptsExplicitlyEditableWebControls() {
        #expect(TextInputTargetPolicy.accepts(
            role: "AXGroup",
            subrole: nil,
            selectedTextSettable: false,
            exposesCharacterCount: false,
            explicitlyEditable: true,
            enabled: true
        ))
    }

    @Test("Rejects secure, disabled, and non-text controls")
    func rejectsUnsafeTargets() {
        #expect(!TextInputTargetPolicy.accepts(
            role: "AXTextField",
            subrole: "AXSecureTextField",
            selectedTextSettable: true,
            exposesCharacterCount: true,
            enabled: true
        ))
        #expect(!TextInputTargetPolicy.accepts(
            role: "AXTextArea",
            subrole: nil,
            selectedTextSettable: true,
            exposesCharacterCount: true,
            enabled: false
        ))
        #expect(!TextInputTargetPolicy.accepts(
            role: "AXButton",
            subrole: nil,
            selectedTextSettable: false,
            exposesCharacterCount: false,
            enabled: true
        ))
    }
}

@Suite("Captured text selection")
struct CapturedSelectionRestorePolicyTests {
    @Test("Restores a captured range when the original text is unchanged")
    func restoresUnchangedText() {
        #expect(CapturedSelectionRestorePolicy.canRestore(
            capturedText: "A note",
            currentText: "A note",
            capturedRange: NSRange(location: 2, length: 0),
            currentRange: NSRange(location: 0, length: 0),
            isOriginalTargetFocused: false
        ))
    }

    @Test("Falls back to the current insertion point when text changed")
    func rejectsChangedText() {
        #expect(!CapturedSelectionRestorePolicy.canRestore(
            capturedText: "A note",
            currentText: "An edited note",
            capturedRange: NSRange(location: 2, length: 0),
            currentRange: NSRange(location: 2, length: 0),
            isOriginalTargetFocused: true
        ))
    }

    @Test("Needs the original focused range without observable text")
    func requiresFocusedMatchingRangeWithoutText() {
        #expect(CapturedSelectionRestorePolicy.canRestore(
            capturedText: nil,
            currentText: nil,
            capturedRange: NSRange(location: 2, length: 1),
            currentRange: NSRange(location: 2, length: 1),
            isOriginalTargetFocused: true
        ))
        #expect(!CapturedSelectionRestorePolicy.canRestore(
            capturedText: nil,
            currentText: nil,
            capturedRange: NSRange(location: 2, length: 1),
            currentRange: NSRange(location: 2, length: 1),
            isOriginalTargetFocused: false
        ))
    }
}
