import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

/// The dictation shortcut, as presets and one recorded alternative.
///
/// Presets and the recorded chord are one choice, not two, so they share a row
/// group with no divider between them: a divider here would read as two
/// unrelated settings rather than one shortcut with several ways to name it.
struct ShortcutPicker: View {
    @Binding var chord: ShortcutChord
    @Binding var customChord: ShortcutChord?
    @Binding var activeRecorderID: String?
    let isCaptureAllowed: Bool
    let refusalResetToken: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Preset") {
                ForEach(SuggestedShortcuts.offers, id: \.self) { preset in
                    choice(preset)
                }
            }
            row("Custom") {
                if let customChord { choice(customChord) }
                ShortcutRecorderButton(
                    identifier: "dictation",
                    chord: Binding(
                        get: { customChord ?? chord },
                        set: { recorded in
                            customChord = recorded
                            chord = recorded
                        }
                    ),
                    activeRecorderID: $activeRecorderID,
                    isCaptureAllowed: isCaptureAllowed,
                    refusalResetToken: refusalResetToken
                )
            }
        }
    }

    private func row(
        _ label: String,
        @ViewBuilder controls: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            controls()
            Spacer(minLength: 0)
        }
    }

    /// Selecting is the whole interaction: there is no confirm step, because the
    /// shortcut itself is the confirmation.
    private func choice(_ candidate: ShortcutChord) -> some View {
        Button(candidate.displayName) { chord = candidate }
            .buttonStyle(.bordered)
            .tint(candidate == chord ? .accentColor : nil)
            .accessibilityIdentifier("shortcut-choice-\(candidate.displayName)")
            .accessibilityAddTraits(candidate == chord ? [.isSelected] : [])
    }
}

/// Records a new chord. Shows what is being held while it listens, and the
/// reason a chord was refused until the next attempt.
struct ShortcutRecorderButton: View {
    let identifier: String
    @Binding var chord: ShortcutChord
    @Binding var activeRecorderID: String?
    let isCaptureAllowed: Bool
    /// Bumped when the Settings window closes. A refusal explains a key the user
    /// just pressed, so it has no business still being there the next time they
    /// open Settings — the guard that produced it has not gone anywhere.
    let refusalResetToken: Int

    @State private var monitor: Any?
    @State private var modifierCapture = ModifierChordCaptureState()
    @State private var heldKeys = HeldModifierKeys()
    @State private var liveChord: ShortcutChord?
    @State private var error: String?

    private var isRecording: Bool { activeRecorderID == identifier }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(isRecording ? (liveChord?.displayName ?? "Press shortcut…") : "Record…") {
                isRecording ? stopRecording() : startRecording()
            }
            .disabled(!isCaptureAllowed || (activeRecorderID != nil && !isRecording))
            .accessibilityIdentifier("shortcut-record-\(identifier)")
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stopRecording() }
        .onChange(of: activeRecorderID) { _, activeRecorderID in
            if activeRecorderID != identifier { stopMonitoring() }
        }
        .onChange(of: isCaptureAllowed) { _, isCaptureAllowed in
            if !isCaptureAllowed { stopRecording() }
        }
        .onChange(of: refusalResetToken) { _, _ in
            stopRecording()
            error = nil
        }
    }

    private func startRecording() {
        guard isCaptureAllowed else { return }
        guard activeRecorderID == nil || activeRecorderID == identifier else { return }
        error = nil
        modifierCapture.reset()
        heldKeys.reset()
        liveChord = nil
        activeRecorderID = identifier
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown, event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let modifiers = KeyModifiers(event.modifierFlags)
            if event.type == .flagsChanged {
                heldKeys.observe(keyCode: event.keyCode, modifiers: modifiers)
                modifierCapture.observe(modifiers, heldKeys: heldKeys.keys)
                if !modifierCapture.peakModifiers.isEmpty {
                    liveChord = modifierCapture.peakChord
                }
                if let chord = modifierCapture.commitOnFirstModifierRelease(currentModifiers: modifiers) {
                    commit(chord)
                }
                return nil
            }
            guard !modifiers.isEmpty else {
                reject("Include at least one modifier.")
                return nil
            }
            let capturedChord = ShortcutChord(modifiers: modifiers, keyCode: event.keyCode)
            liveChord = capturedChord
            commit(capturedChord)
            return nil
        }
    }

    private func commit(_ value: ShortcutChord) {
        guard value.isValid else { return reject("Include at least one modifier.") }
        if let refusal = ReservedShortcuts.refusal(for: value) { return reject(refusal) }
        chord = value
        stopRecording()
    }

    /// Ends the capture exactly as Escape does, and leaves the reason on screen.
    ///
    /// A refusal used to only set the message and keep listening, which left the
    /// local monitor installed swallowing every key — so nothing in Scriber could
    /// be typed into and global matching stayed suspended — while the button went
    /// on showing the refused chord as though it had been accepted. Order matters
    /// here: `stopRecording` never touches `error`, and `startRecording` is the
    /// only thing that clears it, so the reason survives until the next attempt.
    private func reject(_ message: String) {
        stopRecording()
        error = message
    }

    private func stopRecording() {
        if activeRecorderID == identifier { activeRecorderID = nil }
        stopMonitoring()
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        modifierCapture.reset()
        heldKeys.reset()
        liveChord = nil
    }
}

struct ShortcutTestField: View {
    let target: ShortcutChord
    @Binding var isConfirmed: Bool

    @State private var monitor: Any?
    /// The same tracker the global tap uses, so a shortcut bound to one side of
    /// a modifier is confirmed by that key here too. Comparing the flags alone
    /// let the left twin pass a test for the right key.
    @State private var heldKeys = HeldModifierKeys()

    private var isListening: Bool { monitor != nil }

    var body: some View {
        HStack(spacing: 8) {
            if isConfirmed {
                Label("\(target.displayName) works", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("shortcut-test-confirmed")
            } else {
                Button(isListening ? "Press \(target.displayName) now…" : "Test \(target.displayName)") {
                    isListening ? stop() : start()
                }
                .accessibilityIdentifier("shortcut-test-button")
                Text(isListening
                    ? "Waiting. Escape stops listening."
                    : "Check it reaches Scriber before you finish setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stop)
        .onChange(of: target) { _, _ in
            stop()
            isConfirmed = false
        }
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown, event.keyCode == 53 {
                stop()
                return nil
            }
            let modifiers = KeyModifiers(event.modifierFlags)
            if event.type == .flagsChanged {
                heldKeys.observe(keyCode: event.keyCode, modifiers: modifiers)
            }
            let matcher = ShortcutMatcher(dictation: target)
            let matched = target.keyCode == nil
                ? event.type == .flagsChanged
                    && matcher.matches(modifiers: modifiers, keyCode: nil, heldKeys: heldKeys.keys)
                : event.type == .keyDown
                    && matcher.matches(modifiers: modifiers, keyCode: event.keyCode)
            guard matched else { return nil }
            isConfirmed = true
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        heldKeys.reset()
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.function) { insert(.function) }
    }
}
