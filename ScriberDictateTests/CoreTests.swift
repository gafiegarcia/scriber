import Foundation
import Testing
@testable import ScriberDictateCore

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
