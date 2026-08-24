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
        VStack(alignment: .leading, spacing: 10) {
            row("Preset") {
                ForEach(SuggestedShortcuts.offers, id: \.self) { preset in
                    choice(preset)
                }
            }
            Divider()
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
    ///
    /// Filled rather than tinted. A tint on a bordered button is a wash of accent
    /// over an almost transparent background, which does not read as chosen next
    /// to the plain buttons beside it.
    @ViewBuilder
    private func choice(_ candidate: ShortcutChord) -> some View {
        let button = Button(candidate.displayName) { chord = candidate }
            .accessibilityIdentifier("shortcut-choice-\(candidate.displayName)")
        if candidate == chord {
            button
                .buttonStyle(.borderedProminent)
                .accessibilityAddTraits(.isSelected)
        } else {
            button.buttonStyle(.bordered)
        }
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
    /// A refusal that only sets the message keeps the local monitor installed
    /// swallowing every key. Order matters: `stopRecording` never touches `error`
    /// and `startRecording` is the only thing that clears it, so the reason
    /// survives until the next attempt.
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

/// The chosen shortcut drawn as a key cap that lights up while the key is
/// actually held, and reports the first time it is pressed.
///
/// Listening starts the moment this appears — there is no button to press
/// first, because the thing being tested is a keypress and asking for a click
/// before it is one step too many.
///
/// The global tap cannot serve this. It refuses to start until setup is
/// complete, and drops every action until then, so a local monitor is the only
/// mechanism available before setup ends.
struct ShortcutKeyCapTester: View {
    let target: ShortcutChord
    /// Listening stops while a recorder is capturing a custom chord, so the two
    /// monitors are never installed at once.
    let isPaused: Bool
    @Binding var isConfirmed: Bool

    @State private var monitor: Any?
    @State private var isHeld = false
    /// The same tracker the global tap uses, so a shortcut bound to one side of
    /// a modifier is confirmed by that key here too. Comparing the flags alone
    /// let the left twin pass a test for the right key.
    @State private var heldKeys = HeldModifierKeys()

    var body: some View {
        VStack(spacing: 14) {
            keyCap
            Label(
                isConfirmed ? "\(target.displayName) works" : "Press \(target.displayName)",
                systemImage: isConfirmed ? "checkmark.circle.fill" : "keyboard"
            )
            .font(.callout)
            .foregroundStyle(isConfirmed ? Color.green : Color.secondary)
            .accessibilityIdentifier(isConfirmed ? "shortcut-test-confirmed" : "shortcut-test-waiting")
        }
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onChange(of: isPaused) { _, paused in
            paused ? stop() : start()
        }
        .onChange(of: target) { _, _ in
            stop()
            isConfirmed = false
            start()
        }
    }

    private var keyCap: some View {
        Text(target.displayName)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(isHeld ? Color.accentColor : .primary)
            .frame(minWidth: 96)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHeld ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.background))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isHeld ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            .animation(.easeOut(duration: 0.08), value: isHeld)
            .accessibilityHidden(true)
    }

    private func start() {
        guard monitor == nil, !isPaused else { return }
        // Every event is returned rather than swallowed. A recorder capturing a
        // new binding consumes keys on purpose; a page that merely watches must
        // not, or Tab and Return stop reaching the buttons beside it.
        // Built once rather than per event: it depends only on `target`, and a
        // change to that restarts the monitor.
        let matcher = ShortcutMatcher(dictation: target)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let modifiers = KeyModifiers(event.modifierFlags)
            if event.type == .flagsChanged {
                heldKeys.observe(keyCode: event.keyCode, modifiers: modifiers)
            }
            let matched = target.keyCode == nil
                ? event.type == .flagsChanged
                    && matcher.matches(modifiers: modifiers, keyCode: nil, heldKeys: heldKeys.keys)
                : event.type == .keyDown
                    && matcher.matches(modifiers: modifiers, keyCode: event.keyCode)
            // Only on a change. A held key auto-repeats, and both of these are
            // bindings into the flow's own state.
            let nowHeld = matched
                ? true
                : (event.type == .flagsChanged
                    ? matcher.stillHeld(modifiers: modifiers, heldKeys: heldKeys.keys)
                    : isHeld)
            if nowHeld != isHeld { isHeld = nowHeld }
            if matched, !isConfirmed { isConfirmed = true }
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isHeld = false
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
