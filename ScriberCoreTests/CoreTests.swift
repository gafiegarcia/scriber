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

    @Test("Locked recording stops only with the hands-free toggle")
    func lockedStopSemantics() {
        #expect(ShortcutAction.togglePressed.stopsRecording(mode: .locked))
        #expect(!ShortcutAction.holdPressed.stopsRecording(mode: .locked))
        #expect(!ShortcutAction.holdReleased.stopsRecording(mode: .locked))
        #expect(ShortcutAction.holdReleased.stopsRecording(mode: .held))
    }

    @Test("Cancelling is permitted in every recording mode; confirming only while locked")
    func handsFreePillActionPermissions() {
        let held = AppPhase.recording(mode: .held, elapsed: 1, level: -20)
        let locked = AppPhase.recording(mode: .locked, elapsed: 1, level: -20)

        #expect(held.permitsCancelRecording)
        #expect(!held.showsConfirmRecordingControl)
        #expect(HandsFreePillAction.cancel.disposition(for: held) == .cancelRecording)
        #expect(HandsFreePillAction.confirm.disposition(for: held) == nil)
        #expect(locked.permitsCancelRecording)
        #expect(locked.showsConfirmRecordingControl)
        #expect(HandsFreePillAction.cancel.disposition(for: locked) == .cancelRecording)
        #expect(HandsFreePillAction.confirm.disposition(for: locked) == .finishRecording)
        #expect(HandsFreePillAction.cancel.disposition(for: .transcribing(attempt: 1, retryDelay: nil)) == nil)
        #expect(HandsFreePillAction.confirm.disposition(for: .transcribing(attempt: 1, retryDelay: nil)) == nil)
    }

    @Test("Held recording draws Cancel only while hovering; hands-free draws it either way")
    func cancelControlVisibility() {
        let held = AppPhase.recording(mode: .held, elapsed: 1, level: -20)
        let locked = AppPhase.recording(mode: .locked, elapsed: 1, level: -20)

        #expect(!held.showsCancelRecordingControl(isHovering: false))
        #expect(held.showsCancelRecordingControl(isHovering: true))
        #expect(locked.showsCancelRecordingControl(isHovering: false))
        #expect(locked.showsCancelRecordingControl(isHovering: true))
        #expect(!AppPhase.transcribing(attempt: 1, retryDelay: nil).showsCancelRecordingControl(isHovering: true))
    }

    @Test("Busy state is limited to recording and transcription")
    func busyState() {
        #expect(AppPhase.recording(mode: .held, elapsed: 0, level: -80).isBusy)
        #expect(AppPhase.transcribing(attempt: 1, retryDelay: nil).isBusy)
        #expect(!AppPhase.message("Still transcribing").isBusy)
        #expect(!AppPhase.dictationCopied(text: "hi", message: "No target", microphoneDroppedOut: false).isBusy)
    }

    @Test("Every notice phase still accepts the next dictation")
    func noticePhasesAcceptRecordingStart() {
        // A notice describes a dictation that already ended. Speaking again must not
        // wait on its pill: `.noSpeechDetected` used to swallow both shortcuts until
        // the pill was dismissed by hand, which is exactly when the user is likeliest
        // to try again straight away.
        #expect(AppPhase.noSpeechDetected.acceptsRecordingStart)
        // The likeliest phase of all to be followed by an immediate retry: the user
        // just spoke into a microphone that produced nothing, and the obvious next
        // move is to fix it and speak again.
        #expect(AppPhase.noAudioSignal.acceptsRecordingStart)
        #expect(AppPhase.idle.acceptsRecordingStart)
        #expect(AppPhase.message("Copied").acceptsRecordingStart)
        #expect(AppPhase.cancelledTranscript.acceptsRecordingStart)
        #expect(AppPhase.dictationCopied(text: "hi", message: "No target", microphoneDroppedOut: false).acceptsRecordingStart)
        #expect(AppPhase.permissionsRequired([.microphone]).acceptsRecordingStart)
        #expect(AppPhase.credentialsUnusable(.missingAPIKey).acceptsRecordingStart)
        #expect(AppPhase.transcriptCopied.acceptsRecordingStart)
        #expect(AppPhase.transcriptionFailed("Timed out").acceptsRecordingStart)
        #expect(!AppPhase.recording(mode: .held, elapsed: 0, level: -80).acceptsRecordingStart)
        #expect(!AppPhase.transcribing(attempt: 1, retryDelay: nil).acceptsRecordingStart)
    }

    @Test("Names every key a shortcut can realistically bind")
    func namesBoundKeys() {
        #expect(ShortcutChord(modifiers: [.function], keyCode: 49).displayName == "fn+Space")
        #expect(ShortcutChord(modifiers: [.command, .shift], keyCode: 12).displayName == "⇧+⌘+Q")
        #expect(
            ShortcutChord(
                modifiers: [.function, .control, .option, .shift, .command],
                keyCode: 12
            ).displayName == "fn+⌃+⌥+⇧+⌘+Q"
        )
        #expect(KeyCodeNames.name(for: 122) == "F1")
        #expect(KeyCodeNames.name(for: 43) == ",")
        #expect(KeyCodeNames.name(for: 126) == "↑")
        // Anything unmapped still produces a stable, if ugly, label.
        #expect(KeyCodeNames.name(for: 250) == "Key 250")
    }

    @Test("Modifier recorder commits the largest simultaneous snapshot")
    func modifierRecorderCapturesFullChord() {
        var capture = ModifierChordCaptureState()
        capture.observe([.function])
        capture.observe([.function, .control])
        capture.observe([.function, .control, .option])

        #expect(capture.commitOnFirstModifierRelease(currentModifiers: [.function, .option]) == ShortcutChord(
            modifiers: [.function, .control, .option],
            keyCode: nil
        ))
    }

    @Test("Modifier recorder does not union separate snapshots")
    func modifierRecorderDoesNotInventChord() {
        var capture = ModifierChordCaptureState()
        capture.observe([.function, .control])
        capture.observe([.function, .option])

        #expect(capture.commitOnFirstModifierRelease(currentModifiers: []) == ShortcutChord(
            modifiers: [.function, .control],
            keyCode: nil
        ))
    }

    @Test("Modifier recorder commits at the first release, not the last")
    func modifierRecorderCommitsOnFirstRelease() {
        // The recorder used to keep listening until every key was up, which made it
        // look like releasing one key could still edit the chord. It never could.
        var capture = ModifierChordCaptureState()
        capture.observe([.function, .control, .option])

        #expect(capture.commitOnFirstModifierRelease(currentModifiers: [.function, .control]) == ShortcutChord(
            modifiers: [.function, .control, .option],
            keyCode: nil
        ))
        // And it reset, so the keys still held cannot start a second chord.
        #expect(capture.commitOnFirstModifierRelease(currentModifiers: []) == nil)
    }

    @Test("Modifier recorder does not commit while the chord is still building")
    func modifierRecorderIgnoresBuildUp() {
        var capture = ModifierChordCaptureState()
        capture.observe([.function])
        // The plateau between the last press and the first release: equal sets are
        // not a release, or holding a chord steady would commit it immediately.
        #expect(capture.commitOnFirstModifierRelease(currentModifiers: [.function]) == nil)
        capture.observe([.function, .control])
        #expect(capture.commitOnFirstModifierRelease(currentModifiers: [.function, .control]) == nil)
    }

    @Test("Modifier recorder commits the full chord whichever key is released first")
    func modifierRecorderHandlesAllReleaseOrders() {
        let fullChord: KeyModifiers = [.function, .control, .option]

        for firstReleased in [KeyModifiers.function, .control, .option] {
            var capture = ModifierChordCaptureState()
            capture.observe(fullChord)
            var remaining = fullChord
            remaining.remove(firstReleased)

            #expect(capture.commitOnFirstModifierRelease(currentModifiers: remaining) == ShortcutChord(
                modifiers: fullChord,
                keyCode: nil
            ))
        }
    }
}

@Suite("Permission readiness")
struct PermissionReadinessTests {
    @Test("Reports each missing requirement in a stable order")
    func missingRequirements() {
        let readiness = PermissionReadiness(microphoneGranted: false, accessibilityGranted: false)

        #expect(readiness.missingPermissions == [.microphone, .accessibility])
        #expect(!readiness.isReady)
        #expect(readiness.recoveryMessage.contains("Microphone and Accessibility"))
    }

    @Test("Becomes ready only when both permissions are granted")
    func readyState() {
        #expect(PermissionReadiness(microphoneGranted: true, accessibilityGranted: true).isReady)
        #expect(!PermissionReadiness(microphoneGranted: true, accessibilityGranted: false).isReady)
        #expect(!PermissionReadiness(microphoneGranted: false, accessibilityGranted: true).isReady)
    }

    @Test("Presents recovery after revocation without repeating every poll")
    func recoveryPresentation() {
        let ready = PermissionReadiness(microphoneGranted: true, accessibilityGranted: true)
        let missing = PermissionReadiness(microphoneGranted: true, accessibilityGranted: false)

        #expect(PermissionRecoveryPolicy.shouldPresent(
            previous: ready,
            current: missing,
            onboardingComplete: true,
            force: false
        ))
        #expect(!PermissionRecoveryPolicy.shouldPresent(
            previous: missing,
            current: missing,
            onboardingComplete: true,
            force: false
        ))
        #expect(PermissionRecoveryPolicy.shouldPresent(
            previous: missing,
            current: missing,
            onboardingComplete: true,
            force: true
        ))
        #expect(!PermissionRecoveryPolicy.shouldPresent(
            previous: ready,
            current: missing,
            onboardingComplete: false,
            force: true
        ))
    }

    @Test("Forces missing-permission recovery only once per completed-onboarding launch")
    func launchRecoveryPresentation() {
        var gate = PermissionRecoveryLaunchGate()

        let beforeOnboarding = gate.consume(onboardingComplete: false)
        let firstCompletedLaunch = gate.consume(onboardingComplete: true)
        let repeatedActivation = gate.consume(onboardingComplete: true)

        #expect(!beforeOnboarding)
        #expect(firstCompletedLaunch)
        #expect(!repeatedActivation)
    }
}

@Suite("Launch at login state")
struct LaunchAtLoginStateTests {
    @Test("Reads as on only when macOS has the login item enabled")
    func onState() {
        #expect(LaunchAtLoginState.enabled.isOn)
        #expect(!LaunchAtLoginState.disabled.isOn)
        #expect(!LaunchAtLoginState.requiresApproval.isOn)
    }

    @Test("Explains only the state the user has to resolve in System Settings")
    func advice() {
        #expect(LaunchAtLoginState.enabled.recoveryAdvice == nil)
        #expect(LaunchAtLoginState.disabled.recoveryAdvice == nil)
        #expect(LaunchAtLoginState.requiresApproval.recoveryAdvice?.contains("Background App Activity") == true)
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
        #expect(AppPhase.dictationCopied(text: "Done", message: "Copied", microphoneDroppedOut: false)
            .pillDismissalAction(isPresented: true) == .dismiss)
        #expect(AppPhase.transcriptionFailed("Offline")
            .pillDismissalAction(isPresented: true) == .dismiss)
        #expect(AppPhase.permissionsRequired([.accessibility])
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

    /// A slipped finger and `fn` used as somebody else's modifier both land here,
    /// and neither asked Scriber for anything.
    @Test("A press too brief to be a dictation is a misclick")
    func misclickBoundary() {
        #expect(RecordingCancellationPolicy.isMisclick(elapsed: 0.03))
        #expect(RecordingCancellationPolicy.isMisclick(elapsed: 0.249))
        #expect(!RecordingCancellationPolicy.isMisclick(elapsed: 0.25))
        #expect(!RecordingCancellationPolicy.isMisclick(elapsed: 1))
    }

    /// A live microphone in a silent room still sends its own noise floor, tens of
    /// decibels above the silence floor. Only a stream that has stopped sending
    /// anything reads that low, which is what keeps a pause before releasing the
    /// key from being reported as a failure.
    @Test("Only a stream sending nothing counts as silent")
    func silenceIsNotQuiet() {
        #expect(MicrophoneDropoutPolicy.isSilent(decibels: -160))
        #expect(MicrophoneDropoutPolicy.isSilent(decibels: -.infinity))
        #expect(!MicrophoneDropoutPolicy.isSilent(decibels: -63))
        #expect(!MicrophoneDropoutPolicy.isSilent(decibels: -80))
    }

    @Test("A dropout needs a silent tail longer than stopping can explain")
    func dropoutBoundary() {
        #expect(!MicrophoneDropoutPolicy.droppedOut(silentTail: 0))
        #expect(!MicrophoneDropoutPolicy.droppedOut(silentTail: 1.49))
        #expect(MicrophoneDropoutPolicy.droppedOut(silentTail: 1.5))
        // The measured case: audio for 4.71 s, then nothing for 5.89 s.
        #expect(MicrophoneDropoutPolicy.droppedOut(silentTail: 5.89))
    }

    /// The misclick window sits inside the window that discards audio, so nothing
    /// silently dropped here could have been kept for a retry.
    @Test("A misclick is always inside the discarding window")
    func misclickIsNeverRecoverable() {
        #expect(RecordingCancellationPolicy.misclickThreshold < RecordingCancellationPolicy.recoveryThreshold)
        #expect(!RecordingCancellationPolicy.retainsAudio(
            elapsed: RecordingCancellationPolicy.misclickThreshold,
            detectedSignal: true
        ))
    }
}

@Suite("Pill shape")
struct PillShapeTests {
    @Test("Expanded result and cancellation recovery use the fixed corner radius")
    func copiedResultShape() {
        let copied = AppPhase.dictationCopied(text: String(repeating: "Long text ", count: 20), message: "Copied", microphoneDroppedOut: false)

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
            (.permissionsRequired([.microphone, .accessibility]), 76),
            (.transcriptCopied, 62),
            (.transcriptionFailed("Offline"), 72)
        ]

        for (phase, height) in destinations {
            #expect(phase.pillShapeStyle == .capsule)
            #expect(phase.pillCornerRadius(height: height) == height / 2)
        }
    }
}

/// Every phase in this file appears in both suites below. Neither switch carries
/// a `default:`, so a new phase is a compile error rather than an untinted pill
/// or an inert click — but only while every case is also asserted here.
private let everyPhase: [AppPhase] = [
    .idle,
    .recording(mode: .held, elapsed: 1, level: -20),
    .transcribing(attempt: 1, retryDelay: nil),
    .cancelledTranscript,
    .dictationCopied(text: "hi", message: "No target", microphoneDroppedOut: false),
    .permissionsRequired([.microphone, .accessibility]),
    .credentialsUnusable(.missingAPIKey),
    .transcriptionFailed("Offline"),
    .noSpeechDetected,
    .noAudioSignal,
    .transcriptCopied,
    .message("Copied")
]

@Suite("Pill tone")
struct PillToneTests {
    @Test("Only the two copied phases report success")
    func success() {
        #expect(AppPhase.dictationCopied(text: "hi", message: "No target", microphoneDroppedOut: false).pillTone == .success)
        #expect(AppPhase.transcriptCopied.pillTone == .success)
    }

    @Test("Recoverable outcomes warn")
    func warning() {
        let warning: [AppPhase] = [
            .permissionsRequired([.accessibility]),
            .credentialsUnusable(.missingAPIKey),
            .transcriptionFailed("Offline"),
            .noSpeechDetected,
            .noAudioSignal,
            .microphoneDroppedOut(deliveredPartialText: true),
            .microphoneDroppedOut(deliveredPartialText: false),
            // A copied transcript is still a success, but not when the microphone
            // is why half of it is missing.
            .dictationCopied(text: "hi", message: "Microphone cut out", microphoneDroppedOut: true)
        ]
        for phase in warning { #expect(phase.pillTone == .warning) }
    }

    /// Both microphone outcomes are resolved in the same place, so both have to
    /// offer the route there rather than leaving the user to find it.
    @Test("Every microphone outcome routes to the input settings")
    func microphoneOutcomesRouteToInput() {
        let inputFailures: [AppPhase] = [
            .noAudioSignal,
            .noSpeechDetected,
            .microphoneDroppedOut(deliveredPartialText: true),
            .microphoneDroppedOut(deliveredPartialText: false),
            // The copy fallback is the one route where the outcome reads as a
            // success, so it is the one most able to hide a broken microphone.
            .dictationCopied(text: "hi", message: "Microphone cut out", microphoneDroppedOut: true)
        ]
        for phase in inputFailures {
            #expect(phase.pillDefaultAction(isPresented: true) == .openInputSettings)
        }
    }

    @Test("A dictation in flight, and a cancellation, carry no tint")
    func neutral() {
        let neutral: [AppPhase] = [
            .idle,
            .recording(mode: .locked, elapsed: 3, level: -20),
            .transcribing(attempt: 2, retryDelay: 3),
            .cancelledTranscript,
            .message("Copied")
        ]
        for phase in neutral { #expect(phase.pillTone == .neutral) }
    }

    /// Red is reserved for the toast stack. Every pill phase that could claim it
    /// keeps the transcript and offers a way out on the pill itself, so escalating
    /// them would misreport what happened.
    @Test("No phase claims the failure tone")
    func neverFailure() {
        for phase in everyPhase { #expect(phase.pillTone != .failure) }
    }

    @Test("The pill agrees with the toast the copy route posts")
    func agreesWithToastStack() {
        #expect(AppPhase.transcriptCopied.pillTone == Toast.transcriptCopied().tone)
    }
}

@Suite("Pill default action")
struct PillDefaultActionTests {
    @Test("A hidden pill has no default action to take")
    func hiddenPill() {
        for phase in everyPhase {
            #expect(phase.pillDefaultAction(isPresented: false) == .none)
        }
    }

    @Test("Phases that own their own controls ignore a body click")
    func inertPhases() {
        let inert: [AppPhase] = [
            .idle,
            // Cancel and Confirm own the hands-free pill; a stray click on the
            // body must not reach either.
            .recording(mode: .locked, elapsed: 3, level: -20),
            .transcribing(attempt: 1, retryDelay: nil),
            // Its transcript is selectable, so a body tap would fight the
            // selection it sits on.
            .dictationCopied(text: "hi", message: "No target", microphoneDroppedOut: false),
            .cancelledTranscript
        ]
        for phase in inert { #expect(phase.pillDefaultAction(isPresented: true) == .none) }
    }

    @Test("Notices route to where they are resolved")
    func routingPhases() {
        #expect(AppPhase.transcriptCopied.pillDefaultAction(isPresented: true) == .openMainWindow)
        #expect(AppPhase.transcriptionFailed("Offline")
            .pillDefaultAction(isPresented: true) == .openMainWindow)
        #expect(AppPhase.permissionsRequired([.microphone])
            .pillDefaultAction(isPresented: true) == .openPermissionSettings)
        #expect(AppPhase.credentialsUnusable(.missingAPIKey)
            .pillDefaultAction(isPresented: true) == .openCredentialSettings)
        #expect(AppPhase.noSpeechDetected.pillDefaultAction(isPresented: true) == .openInputSettings)
        #expect(AppPhase.noAudioSignal.pillDefaultAction(isPresented: true) == .openInputSettings)
        #expect(AppPhase.message("Copied").pillDefaultAction(isPresented: true) == .dismiss)
    }

    /// The whole reason the mapping is written down rather than inferred. Retry
    /// and Undo both transcribe, and a click landed by accident must never reach
    /// either — so the phases that offer them route somewhere harmless instead.
    @Test("The phases whose button spends API credit keep it on the button")
    func neverSpendsCredit() {
        #expect(AppPhase.transcriptionFailed("Offline")
            .pillDefaultAction(isPresented: true) == .openMainWindow)
        #expect(AppPhase.cancelledTranscript.pillDefaultAction(isPresented: true) == .none)
    }

    /// Every phase resolves to something nameable. A phase added without a
    /// deliberate mapping cannot reach this — the switch has no `default:` — but
    /// this catches one silently given a wrong one.
    @Test("Every phase has a mapping and only recording controls are inert")
    func totality() {
        let inertCount = everyPhase
            .filter { $0.pillDefaultAction(isPresented: true) == .none }
            .count
        #expect(inertCount == 5)
    }
}

@Suite("Keyboard focus redirect")
struct KeyboardFocusRedirectPolicyTests {
    private let scriber: Int32 = 100
    private let frontmost: Int32 = 200
    private let panelOwner: Int32 = 300

    @Test("Follows focus into a nonactivating panel that owns a text field")
    func followsFocusIntoPanel() {
        // Observed live: Raycast's command bar is an AXTextField owned by an
        // LSUIElement process, while Finder remained frontmost.
        #expect(KeyboardFocusRedirectPolicy.redirects(
            focusOwnerPID: panelOwner,
            frontmostPID: frontmost,
            scriberPID: scriber,
            focusExposesTextInput: true
        ))
    }

    @Test("Leaves an ordinary app alone")
    func ordinaryAppIsUnaffected() {
        #expect(!KeyboardFocusRedirectPolicy.redirects(
            focusOwnerPID: frontmost,
            frontmostPID: frontmost,
            scriberPID: scriber,
            focusExposesTextInput: true
        ))
    }

    @Test("Never redirects into a focus with no text input")
    func requiresTextInput() {
        #expect(!KeyboardFocusRedirectPolicy.redirects(
            focusOwnerPID: panelOwner,
            frontmostPID: frontmost,
            scriberPID: scriber,
            focusExposesTextInput: false
        ))
    }

    @Test("Never redirects into Scriber itself")
    func neverTargetsScriber() {
        // Scriber's pill is the same species of nonactivating panel. Its own
        // windows need no redirect: they are frontmost when focused, so the
        // Dictation search field stays reachable.
        #expect(!KeyboardFocusRedirectPolicy.redirects(
            focusOwnerPID: scriber,
            frontmostPID: frontmost,
            scriberPID: scriber,
            focusExposesTextInput: true
        ))
        #expect(!KeyboardFocusRedirectPolicy.redirects(
            focusOwnerPID: scriber,
            frontmostPID: scriber,
            scriberPID: scriber,
            focusExposesTextInput: true
        ))
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

    @Test("State drift on a non-text focus is not evidence")
    func rejectsDriftOnNonTextFocus() {
        #expect(!PasteConfirmationPolicy.qualifiesAsAccessibilityEvidence(
            focusContainsTextInput: false,
            mutationObserved: true
        ))
        #expect(PasteConfirmationPolicy.qualifiesAsAccessibilityEvidence(
            focusContainsTextInput: true,
            mutationObserved: true
        ))
        #expect(!PasteConfirmationPolicy.qualifiesAsAccessibilityEvidence(
            focusContainsTextInput: true,
            mutationObserved: false
        ))
    }

    @Test("A live page with no focused text box is still a failed paste")
    func livePageWithoutTextBoxStillFails() {
        // Observed live on claude.ai in Zen: the page reports a focused element
        // that is not text input, and its own accessibility state drifts between
        // the before and after snapshots. Counting that drift reported a paste
        // that never happened and suppressed the copied-result recovery.
        let accessibilityEvidence = PasteConfirmationPolicy.qualifiesAsAccessibilityEvidence(
            focusContainsTextInput: false,
            mutationObserved: true
        )
        #expect(!PasteConfirmationPolicy.confirmsInsertion(
            accessibilityMutationObserved: accessibilityEvidence,
            pasteboardDataRequested: false
        ))
    }
}

@Suite("Scribe validation")
struct ScribeValidationTests {
    @Test("Trims and removes empty keyterms")
    func trimsKeyterms() throws {
        let result = try ScribeClient.validateKeyterms(["  Scriber  ", "", "Studio Delapan"])
        #expect(result == ["Scriber", "Studio Delapan"])
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

    @Test("Reserves 0 and 100 percent for empty and full credits")
    func remainingPercentage() {
        func usage(used: Int, total: Int) -> ElevenLabsSubscriptionUsage {
            ElevenLabsSubscriptionUsage(
                tier: "free",
                usedCredits: used,
                totalCredits: total,
                canExtendCredits: false,
                resetAt: nil
            )
        }

        #expect(usage(used: 0, total: 10_000).remainingPercentage == 100)
        #expect(usage(used: 10_000, total: 10_000).remainingPercentage == 0)
        #expect(usage(used: 9_800, total: 10_000).remainingPercentage == 2)
        #expect(usage(used: 3_333, total: 10_000).remainingPercentage == 67)
        #expect(usage(used: 9_999, total: 10_000).remainingPercentage == 1)
        #expect(usage(used: 1, total: 10_000).remainingPercentage == 99)
        #expect(usage(used: 0, total: 0).remainingPercentage == nil)
    }

    @Test("Unavailable usage presents cached credits as stale with one retry")
    func unavailableUsagePresentation() {
        let presentation = SubscriptionUsagePresentation(
            hasCachedUsage: true,
            usageUnavailable: true
        )

        #expect(presentation.cachedUsageTitle == "Last known ElevenLabs credits")
        #expect(presentation.cachedUsageIsStale)
        #expect(!presentation.showsCachedUsageRefresh)
        #expect(presentation.showsUnavailableRetry)
    }

    @Test("Available usage presents current credits with its refresh action")
    func availableUsagePresentation() {
        let presentation = SubscriptionUsagePresentation(
            hasCachedUsage: true,
            usageUnavailable: false
        )

        #expect(presentation.cachedUsageTitle == "ElevenLabs credits")
        #expect(!presentation.cachedUsageIsStale)
        #expect(presentation.showsCachedUsageRefresh)
        #expect(!presentation.showsUnavailableRetry)
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
        #expect(AppPhase.credentialsUnusable(.invalidAPIKey).resolvingCredentialBlock(
            apiKeyConfigured: true,
            apiKeyValidity: .valid,
            apiCreditsExhausted: false
        ) == .idle)
        #expect(AppPhase.credentialsUnusable(.creditsExhausted).resolvingCredentialBlock(
            apiKeyConfigured: true,
            apiKeyValidity: .valid,
            apiCreditsExhausted: false
        ) == .idle)
    }

    @Test("Restates a credential block whose reason changed")
    func restatesChangedCredentialBlock() {
        #expect(AppPhase.credentialsUnusable(.invalidAPIKey).resolvingCredentialBlock(
            apiKeyConfigured: false,
            apiKeyValidity: .valid,
            apiCreditsExhausted: false
        ) == .credentialsUnusable(.missingAPIKey))
    }

    @Test("Leaves unrelated phases untouched")
    func ignoresUnrelatedPhases() {
        #expect(AppPhase.transcriptionFailed("Offline").resolvingCredentialBlock(
            apiKeyConfigured: true,
            apiKeyValidity: .valid,
            apiCreditsExhausted: false
        ) == .transcriptionFailed("Offline"))
    }
}

@Suite("Credential readiness")
struct CredentialReadinessTests {
    @Test("Classifies each way a credential can block dictation")
    func classifiesBlockingStates() {
        #expect(CredentialReadiness(
            apiKeyConfigured: false, apiKeyValidity: .unchecked, apiCreditsExhausted: false
        ) == .missingAPIKey)
        #expect(CredentialReadiness(
            apiKeyConfigured: true, apiKeyValidity: .invalid, apiCreditsExhausted: false
        ) == .invalidAPIKey)
        #expect(CredentialReadiness(
            apiKeyConfigured: true, apiKeyValidity: .valid, apiCreditsExhausted: true
        ) == .creditsExhausted)
        #expect(CredentialReadiness(
            apiKeyConfigured: true, apiKeyValidity: .valid, apiCreditsExhausted: false
        ) == .ready)
    }

    @Test("An unreachable check is not a credential problem")
    func uncheckedKeyStaysReady() {
        // Validation could not reach ElevenLabs. Blocking here would strand the
        // user offline with a key that is probably fine.
        #expect(CredentialReadiness(
            apiKeyConfigured: true, apiKeyValidity: .unchecked, apiCreditsExhausted: false
        ) == .ready)
    }

    @Test("Only exhausted credits route to the usage panel")
    func routesRecoveryToTheRightPlace() {
        #expect(CredentialReadiness.creditsExhausted.resolvesInUsageSettings)
        #expect(!CredentialReadiness.missingAPIKey.resolvesInUsageSettings)
        #expect(!CredentialReadiness.invalidAPIKey.resolvesInUsageSettings)
    }

    @Test("Presents a launch-time problem that never changed state")
    func presentsUnchangedProblemOnLaunch() {
        // The stored key was already invalid when Scriber started, so nothing
        // transitions. Without the forced check the user is never told.
        #expect(CredentialRecoveryPolicy.shouldPresent(
            previous: .invalidAPIKey,
            current: .invalidAPIKey,
            onboardingComplete: true,
            force: true
        ))
        #expect(!CredentialRecoveryPolicy.shouldPresent(
            previous: .invalidAPIKey,
            current: .invalidAPIKey,
            onboardingComplete: true,
            force: false
        ))
        #expect(!CredentialRecoveryPolicy.shouldPresent(
            previous: .ready,
            current: .ready,
            onboardingComplete: true,
            force: true
        ))
        #expect(!CredentialRecoveryPolicy.shouldPresent(
            previous: .ready,
            current: .invalidAPIKey,
            onboardingComplete: false,
            force: true
        ))
    }
}

@Suite("Credential persistence")
struct CredentialPersistenceTests {
    @Test("Saves, trims, and updates the login credential")
    func savesAndUpdatesLoginCredential() throws {
        let backend = FakeCredentialStorageBackend()
        let store = VerifiedCredentialStore(backend: backend, policy: .loginKeychain)

        try store.save("  first-key \n")
        #expect(backend.values[.legacy] == "first-key")
        try store.save("second-key")
        #expect(backend.values[.legacy] == "second-key")
        #expect(backend.readCounts[.dataProtection, default: 0] == 0)
        #expect(backend.deleteCounts[.dataProtection, default: 0] == 0)
    }

    @Test("Rejects a save when login readback is missing")
    func rejectsMissingReadback() {
        let backend = FakeCredentialStorageBackend()
        backend.discardWrites.insert(.legacy)
        let store = VerifiedCredentialStore(backend: backend, policy: .loginKeychain)

        #expect(throws: CredentialStoreError.persistenceVerificationFailed) {
            try store.save("valid-key")
        }
    }

    @Test("Rejects a save when login readback differs")
    func rejectsMismatchedReadback() {
        let backend = FakeCredentialStorageBackend()
        backend.writeReplacements[.legacy] = "different-key"
        let store = VerifiedCredentialStore(backend: backend, policy: .loginKeychain)

        #expect(throws: CredentialStoreError.persistenceVerificationFailed) {
            try store.save("valid-key")
        }
    }

    @Test("Migrates a legacy credential into protected storage")
    func migratesLegacyCredential() throws {
        let backend = FakeCredentialStorageBackend(values: [.legacy: "legacy-key"])
        let store = VerifiedCredentialStore(backend: backend, policy: .dataProtectionKeychain)

        #expect(try store.read() == "legacy-key")
        #expect(backend.values[.dataProtection] == "legacy-key")
        #expect(backend.values[.legacy] == nil)
        #expect(backend.deleteCounts[.legacy] == 1)
    }

    @Test("Restores protected storage if legacy cleanup removes it")
    func restoresAfterDestructiveLegacyCleanup() throws {
        let backend = FakeCredentialStorageBackend(values: [.legacy: "legacy-key"])
        backend.legacyDeletionAlsoDeletesProtectedValue = true
        let store = VerifiedCredentialStore(backend: backend, policy: .dataProtectionKeychain)

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
        let store = VerifiedCredentialStore(backend: backend, policy: .dataProtectionKeychain)

        try store.save("replacement-key")
        #expect(backend.values[.dataProtection] == "replacement-key")
        #expect(backend.values[.legacy] == nil)
        #expect(backend.deleteCounts[.legacy] == 1)
    }

    @Test("Login-mode deletion never touches protected storage")
    func deletesOnlyLoginCredential() throws {
        let backend = FakeCredentialStorageBackend(values: [
            .dataProtection: "protected-key",
            .legacy: "legacy-key",
        ])
        let store = VerifiedCredentialStore(backend: backend, policy: .loginKeychain)

        try store.save("  \n")
        #expect(backend.values[.dataProtection] == "protected-key")
        #expect(backend.values[.legacy] == nil)
        #expect(backend.deleteCounts[.dataProtection, default: 0] == 0)
        #expect(backend.deleteCounts[.legacy] == 1)
    }
}

private final class FakeCredentialStorageBackend: CredentialStorageBackend, @unchecked Sendable {
    var values: [CredentialStorageDomain: String]
    var readCounts: [CredentialStorageDomain: Int] = [:]
    var deleteCounts: [CredentialStorageDomain: Int] = [:]
    var discardWrites: Set<CredentialStorageDomain> = []
    var writeReplacements: [CredentialStorageDomain: String] = [:]
    var legacyDeletionAlsoDeletesProtectedValue = false
    private(set) var protectedWriteCount = 0

    init(values: [CredentialStorageDomain: String] = [:]) {
        self.values = values
    }

    func read(from domain: CredentialStorageDomain) throws -> String? {
        readCounts[domain, default: 0] += 1
        return values[domain]
    }

    func write(_ value: String, to domain: CredentialStorageDomain) throws {
        if domain == .dataProtection {
            protectedWriteCount += 1
        }
        guard !discardWrites.contains(domain) else { return }
        values[domain] = writeReplacements[domain] ?? value
    }

    func delete(from domain: CredentialStorageDomain) throws {
        deleteCounts[domain, default: 0] += 1
        values[domain] = nil
        if domain == .legacy, legacyDeletionAlsoDeletesProtectedValue {
            values[.dataProtection] = nil
        }
    }
}

@Suite("Retained audio retention")
struct RetainedAudioRetentionPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Expires only at the full retention period")
    func retentionBoundary() {
        let period = RetainedAudioRetentionPolicy.retentionPeriod
        #expect(!RetainedAudioRetentionPolicy.hasExpired(
            createdAt: now.addingTimeInterval(-period + 1), now: now
        ))
        #expect(RetainedAudioRetentionPolicy.hasExpired(
            createdAt: now.addingTimeInterval(-period), now: now
        ))
        #expect(!RetainedAudioRetentionPolicy.hasExpired(createdAt: now, now: now))
    }

    @Test("Keeps why the dictation failed alongside why its audio is gone")
    func preservesExistingFailureReason() {
        let combined = RetainedAudioRetentionPolicy.expiredMessage(
            appendingTo: "Cancelled before transcription."
        )
        #expect(combined.hasPrefix("Cancelled before transcription."))
        #expect(combined.hasSuffix(RetainedAudioRetentionPolicy.expiryMessage))
    }

    @Test("Stands alone when nothing explained the failure")
    func standsAloneWithoutAReason() {
        #expect(RetainedAudioRetentionPolicy.expiredMessage(appendingTo: nil)
            == RetainedAudioRetentionPolicy.expiryMessage)
        #expect(RetainedAudioRetentionPolicy.expiredMessage(appendingTo: "")
            == RetainedAudioRetentionPolicy.expiryMessage)
    }
}

@Suite("Orphaned audio import")
struct OrphanedAudioImportPolicyTests {
    private let recordingID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private var relativePath: String { "\(recordingID.uuidString).m4a" }

    @Test("Imports a recording no dictation can account for")
    func importsUnknownRecording() {
        #expect(OrphanedAudioImportPolicy.shouldImport(
            recordingID: recordingID,
            relativePath: relativePath,
            knownRecordIDs: [],
            referencedAudioPaths: []
        ))
    }

    @Test("Never reimports audio a dictation already references")
    func skipsReferencedRecording() {
        #expect(!OrphanedAudioImportPolicy.shouldImport(
            recordingID: recordingID,
            relativePath: relativePath,
            knownRecordIDs: [recordingID],
            referencedAudioPaths: [relativePath]
        ))
    }

    @Test("Never reimports audio left behind by a succeeded dictation")
    func protectsSavedTranscriptFromUpsert() {
        // The record dropped its audio reference after saving its transcript, but
        // deleting the file failed. Reimporting would upsert over that record.
        #expect(!OrphanedAudioImportPolicy.shouldImport(
            recordingID: recordingID,
            relativePath: relativePath,
            knownRecordIDs: [recordingID],
            referencedAudioPaths: []
        ))
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

@Suite("Shortcut tap")
struct ShortcutTapMachineTests {
    /// The chord that wedged the machine: Hold bound to a key, not a bare
    /// modifier. Only a keyed chord auto-repeats, which is why the default `Fn`
    /// configuration never showed any of this.
    private let keyedHold = ShortcutChord(modifiers: [.command, .shift], keyCode: 2)

    private func machine(hold: ShortcutChord, toggle: ShortcutChord = .defaultToggle) -> ShortcutTapMachine {
        ShortcutTapMachine(hold: hold, toggle: toggle, holdEnabled: true, toggleEnabled: true)
    }

    private func down(_ keyCode: UInt16, _ modifiers: KeyModifiers, repeating: Bool = false) -> ShortcutTapInput {
        ShortcutTapInput(kind: .keyDown, keyCode: keyCode, modifiers: modifiers, isRepeat: repeating)
    }

    private func up(_ keyCode: UInt16, _ modifiers: KeyModifiers) -> ShortcutTapInput {
        ShortcutTapInput(kind: .keyUp, keyCode: keyCode, modifiers: modifiers)
    }

    private func flags(_ modifiers: KeyModifiers) -> ShortcutTapInput {
        ShortcutTapInput(kind: .flagsChanged, keyCode: 0, modifiers: modifiers)
    }

    @Test("A held chord's auto-repeat starts one recording, not eleven")
    func heldChordStartsOnce() {
        var machine = machine(hold: keyedHold)
        var starts = 0

        if machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false)
            .effects.contains(.action(.holdPressed)) { starts += 1 }
        machine.setMode(.held)
        for _ in 0..<10 {
            if machine.handle(down(2, [.command, .shift], repeating: true), pillConsumesEscape: false)
                .effects.contains(.action(.holdPressed)) { starts += 1 }
        }

        #expect(starts == 1)
    }

    @Test("A typing cancel cannot be restarted by the chord still being held")
    func cancelledHoldDoesNotRestartItself() {
        var machine = machine(hold: keyedHold)
        #expect(machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false).effects == [.action(.holdPressed)])
        machine.setMode(.held)
        #expect(machine.handle(down(2, [.command, .shift], repeating: true), pillConsumesEscape: false).effects.isEmpty)

        // What `cancelRecording` does. It clears the latch, which used to re-open
        // the start guard so the next repeat began a whole new recording — and the
        // one after that cancelled it again, at the key-repeat rate, forever.
        machine.setMode(.idle)
        #expect(machine.handle(down(2, [.command, .shift], repeating: true), pillConsumesEscape: false).effects.isEmpty)

        // Releasing and pressing again is still how you start the next one.
        _ = machine.handle(up(2, [.command, .shift]), pillConsumesEscape: false)
        #expect(machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false).effects == [.action(.holdPressed)])
    }

    @Test("The held chord's repeats never reach the app in front")
    func heldChordRepeatsAreSwallowed() {
        var machine = machine(hold: keyedHold)
        #expect(machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false).suppressesEvent)
        machine.setMode(.held)
        for _ in 0..<3 {
            #expect(machine.handle(down(2, [.command, .shift], repeating: true), pillConsumesEscape: false).suppressesEvent)
        }
        #expect(machine.handle(up(2, [.command, .shift]), pillConsumesEscape: false).suppressesEvent)
    }

    @Test("The hold chord is not typing")
    func heldChordIsNotTyping() {
        var machine = machine(hold: keyedHold)
        _ = machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false)
        machine.setMode(.held)

        let outcome = machine.handle(down(2, [.command, .shift], repeating: true), pillConsumesEscape: false)
        #expect(!outcome.effects.contains(.nonModifierKeyDown))
    }

    @Test("Any other key while held still counts as typing")
    func otherKeysStillCountAsTyping() {
        var machine = machine(hold: keyedHold)
        _ = machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false)
        machine.setMode(.held)

        let outcome = machine.handle(down(0, []), pillConsumesEscape: false)
        #expect(outcome.effects == [.nonModifierKeyDown])
        #expect(!outcome.suppressesEvent)
    }

    @Test("A toggle chord's auto-repeat neither nags nor restarts")
    func heldToggleChordFiresOnce() {
        var machine = machine(hold: .defaultHold)
        #expect(machine.handle(down(49, [.function]), pillConsumesEscape: false).effects == [.action(.togglePressed)])

        // `stopAndTranscribe` goes busy, which clears the latches.
        machine.setMode(.busy)
        #expect(machine.handle(down(49, [.function], repeating: true), pillConsumesEscape: false).effects.isEmpty)

        // And the still-held key must not start a recording when transcription ends.
        machine.setMode(.idle)
        #expect(machine.handle(down(49, [.function], repeating: true), pillConsumesEscape: false).effects.isEmpty)
    }

    @Test("A press and its release survive a mode that has not caught up")
    func releaseArrivesBeforeTheModeDoes() {
        var machine = machine(hold: .defaultHold)
        #expect(machine.handle(flags([.function]), pillConsumesEscape: false).effects == [.action(.holdPressed)])

        // No `setMode`: the press reaches the coordinator a run-loop turn later,
        // and a release landing first used to be dropped, leaving a recording
        // running that nothing was going to stop.
        #expect(machine.handle(flags([]), pillConsumesEscape: false).effects == [.action(.holdReleased)])
    }

    @Test("A second press before the mode catches up starts nothing")
    func secondPressStartsNothing() {
        var machine = machine(hold: keyedHold)
        #expect(machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false).effects == [.action(.holdPressed)])
        #expect(machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false).effects.isEmpty)
    }

    @Test("Escape is consumed only while a pill wants it")
    func escapeFollowsThePill() {
        var machine = machine(hold: .defaultHold)

        let ignored = machine.handle(down(53, []), pillConsumesEscape: false)
        #expect(!ignored.suppressesEvent)
        #expect(ignored.effects.isEmpty)

        let taken = machine.handle(down(53, []), pillConsumesEscape: true)
        #expect(taken.suppressesEvent)
        #expect(taken.effects == [.action(.cancel)])

        // Holding Escape must not queue a cancel per repeat.
        let repeated = machine.handle(down(53, [], repeating: true), pillConsumesEscape: true)
        #expect(repeated.suppressesEvent)
        #expect(repeated.effects.isEmpty)
    }

    @Test("Configuration capture passes every key through")
    func configurationCapturePassesEverythingThrough() {
        var machine = machine(hold: keyedHold)
        machine.setConfigurationCaptureActive(true)

        #expect(machine.handle(down(2, [.command, .shift]), pillConsumesEscape: false) == .passedThrough)
        #expect(machine.handle(down(49, [.function]), pillConsumesEscape: false) == .passedThrough)
        #expect(machine.handle(flags([.function]), pillConsumesEscape: false) == .passedThrough)
        #expect(machine.handle(down(53, []), pillConsumesEscape: true) == .passedThrough)
    }

    @Test("Locked recording ignores the hold release")
    func lockedRecordingIgnoresHoldRelease() {
        var machine = machine(hold: .defaultHold)
        _ = machine.handle(flags([.function]), pillConsumesEscape: false)
        machine.setMode(.locked)

        #expect(machine.handle(flags([]), pillConsumesEscape: false).effects.isEmpty)
    }

    @Test("A modifier-only hold chord still presses and releases exactly once")
    func modifierOnlyHoldStillWorks() {
        var machine = machine(hold: .defaultHold)
        #expect(machine.handle(flags([.function]), pillConsumesEscape: false).effects == [.action(.holdPressed)])
        machine.setMode(.held)
        #expect(machine.handle(flags([.function]), pillConsumesEscape: false).effects.isEmpty)
        #expect(machine.handle(flags([]), pillConsumesEscape: false).effects == [.action(.holdReleased)])
        #expect(machine.handle(flags([]), pillConsumesEscape: false).effects.isEmpty)
    }
}

@Suite("Reserved shortcuts")
struct ReservedShortcutsTests {
    private func chord(_ modifiers: KeyModifiers, _ key: String) -> ShortcutChord {
        ShortcutChord(modifiers: modifiers, keyCode: KeyCodeNames.code(for: key))
    }

    @Test("Command with a single key is never bindable")
    func singleCommandIsRefused() {
        for key in ["Q", "W", "H", "M", "C", "V", "X", "Z", "A", "Space", "Tab", "`"] {
            #expect(ReservedShortcuts.reserves(chord([.command], key)), "⌘\(key) should be refused")
        }
        // Bare Command as a modifier-only chord would swallow every Command
        // shortcut on the system.
        #expect(ReservedShortcuts.reserves(ShortcutChord(modifiers: [.command], keyCode: nil)))
    }

    @Test("A single modifier held alone is refused, except fn")
    func loneModifiersAreRefused() {
        for modifier in [KeyModifiers.command, .shift, .control, .option] {
            let chord = ShortcutChord(modifiers: modifier, keyCode: nil)
            #expect(ReservedShortcuts.reserves(chord), "\(chord.displayName) alone should be refused")
        }
        // fn alone is the default Hold binding and must stay bindable.
        #expect(ReservedShortcuts.refusal(for: .defaultHold) == nil)
        // Two modifiers together are a deliberate chord, not a key someone leans on.
        #expect(ReservedShortcuts.refusal(for: ShortcutChord(modifiers: [.control, .option], keyCode: nil)) == nil)
    }

    @Test("⌘⇧D stays bindable")
    func commandShiftDIsAllowed() {
        // Gaf uses this one. Nothing in macOS claims it, and the single-Command
        // rule must never be widened to "any chord containing Command".
        #expect(ReservedShortcuts.refusal(for: chord([.command, .shift], "D")) == nil)
    }

    @Test("Named system combinations are refused")
    func systemCombinationsAreRefused() {
        let reserved: [(KeyModifiers, String)] = [
            ([.command, .shift], "3"), ([.command, .shift], "4"), ([.command, .shift], "5"),
            ([.command, .shift], "6"), ([.control, .command, .shift], "4"),
            ([.option, .command], "Space"), ([.control, .command], "Space"),
            ([.control], "Space"), ([.control, .option], "Space"),
            ([.control], "↑"), ([.control], "↓"), ([.control], "←"), ([.control], "→"),
            ([.control], "1"), ([.control], "5"), ([.control], "9"),
            ([.option, .command], "D"),
            ([.control, .command], "Q"), ([.command, .shift], "Q"),
            ([.option, .command, .shift], "Q"), ([.option, .command], "Escape"),
            ([.command, .shift], "W"), ([.control, .command], "F"),
            ([.command], "F5"), ([.option, .command], "F5"), ([.option, .command], "8"),
            ([.option, .command], "="), ([.option, .command], "-"),
            ([.control, .option, .command], "8"),
            ([.control], "F1"), ([.control], "F8"), ([.command], "F1"),
            ([.command, .shift], "/"),
            ([.control], "A"), ([.control], "D"), ([.control], "K"), ([.control], "Y"),
        ]
        for (modifiers, key) in reserved {
            let value = chord(modifiers, key)
            let refusal = ReservedShortcuts.refusal(for: value)
            #expect(refusal != nil, "\(value.displayName) should be refused")
        }
    }

    @Test("A refusal names the chord it is refusing")
    func refusalNamesTheChord() {
        let refusal = ReservedShortcuts.refusal(for: chord([.command, .shift], "4"))
        #expect(refusal?.contains("⇧+⌘+4") == true)
    }

    @Test("Arrow and function chords are refused whichever way macOS spells them")
    func functionFlagIsNormalized() {
        // macOS sets the function modifier on these keys itself, so the chord
        // arrives carrying a modifier the user never pressed.
        #expect(ReservedShortcuts.reserves(chord([.control], "↑")))
        #expect(ReservedShortcuts.reserves(chord([.control, .function], "↑")))
        #expect(ReservedShortcuts.reserves(chord([.control], "F3")))
        #expect(ReservedShortcuts.reserves(chord([.control, .function], "F3")))

        // But the flag is only dropped for those keys. fn⌘Q is not ⌘Q.
        #expect(!ReservedShortcuts.reserves(chord([.function, .command], "Q")))
    }

    @Test("An ordinary chord is allowed")
    func ordinaryChordsAreAllowed() {
        #expect(ReservedShortcuts.refusal(for: .defaultHold) == nil)
        #expect(ReservedShortcuts.refusal(for: .defaultToggle) == nil)
        #expect(ReservedShortcuts.refusal(for: chord([.control, .shift], "D")) == nil)
        #expect(ReservedShortcuts.refusal(for: chord([.option], "R")) == nil)
        #expect(ReservedShortcuts.refusal(for: ShortcutChord(modifiers: [.function, .control, .option], keyCode: nil)) == nil)
    }

    @Test("A stored reserved chord is replaced on load")
    func storedReservedChordIsReplaced() {
        let resolved = ShortcutPreferences.resolve(
            hold: ShortcutChord(modifiers: [.command], keyCode: KeyCodeNames.code(for: "Q")),
            toggle: .defaultToggle
        )
        #expect(resolved.hold == .defaultHold)
        #expect(resolved.toggle == .defaultToggle)
    }

    @Test("Sanitizing never leaves Hold and Toggle the same chord")
    func resolvedPairIsAlwaysDistinct() {
        let resolved = ShortcutPreferences.resolve(
            hold: ShortcutChord(modifiers: [.command], keyCode: KeyCodeNames.code(for: "Q")),
            toggle: .defaultHold
        )
        #expect(resolved.hold != resolved.toggle)
    }

    @Test("An already-valid pair is returned untouched")
    func validPairSurvives() {
        let hold = ShortcutChord(modifiers: [.command, .shift], keyCode: 2)
        let resolved = ShortcutPreferences.resolve(hold: hold, toggle: .defaultToggle)
        #expect(resolved.hold == hold)
        #expect(resolved.toggle == .defaultToggle)
    }
}
