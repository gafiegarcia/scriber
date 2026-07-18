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
        #expect(!ScribeError.invalidRequest("bad input").retryable)
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
