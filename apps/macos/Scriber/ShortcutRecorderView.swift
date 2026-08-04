import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

struct ShortcutRecorderView: View {
    let title: String
    let identifier: String
    @Binding var isEnabled: Bool
    @Binding var chord: ShortcutChord
    @Binding var activeRecorderID: String?
    let conflictingChord: ShortcutChord?
    let isCaptureAllowed: Bool

    @State private var monitor: Any?
    @State private var modifierCapture = ModifierChordCaptureState()
    @State private var liveChord: ShortcutChord?
    @State private var error: String?

    private var isRecording: Bool { activeRecorderID == identifier }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Toggle(title, isOn: $isEnabled)
                    .disabled(!isEnabled && conflictingChord == chord)
                Spacer()
                Button(isRecording ? (liveChord?.displayName ?? "Press shortcut…") : chord.displayName) {
                    isRecording ? stopRecording() : startRecording()
                }
                .frame(minWidth: 130)
                .disabled(!isEnabled || !isCaptureAllowed || (activeRecorderID != nil && !isRecording))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onDisappear { stopRecording() }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { stopRecording() }
        }
        .onChange(of: activeRecorderID) { _, activeRecorderID in
            if activeRecorderID != identifier { stopMonitoring() }
        }
        .onChange(of: isCaptureAllowed) { _, isCaptureAllowed in
            if !isCaptureAllowed { stopRecording() }
        }
    }

    private func startRecording() {
        guard isCaptureAllowed else { return }
        guard activeRecorderID == nil || activeRecorderID == identifier else { return }
        error = nil
        modifierCapture.reset()
        liveChord = nil
        activeRecorderID = identifier
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown, event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let modifiers = KeyModifiers(event.modifierFlags)
            if event.type == .flagsChanged {
                modifierCapture.observe(modifiers)
                if !modifierCapture.peakModifiers.isEmpty {
                    liveChord = ShortcutChord(modifiers: modifierCapture.peakModifiers, keyCode: nil)
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
        guard conflictingChord == nil || value != conflictingChord else {
            return reject("Hold and Toggle must be different.")
        }
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
        liveChord = nil
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
