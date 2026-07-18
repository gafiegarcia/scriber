import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import ScriberDictateCore
#endif

struct ShortcutRecorderView: View {
    let title: String
    @Binding var chord: ShortcutChord
    let conflictingChord: ShortcutChord

    @State private var recording = false
    @State private var monitor: Any?
    @State private var pendingModifiers: KeyModifiers = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Button(recording ? "Press shortcut…" : chord.displayName) {
                    recording ? stopRecording() : startRecording()
                }
                .frame(minWidth: 130)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        error = nil
        pendingModifiers = []
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown, event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let modifiers = KeyModifiers(event.modifierFlags)
            if event.type == .flagsChanged {
                if modifiers.isEmpty, !pendingModifiers.isEmpty {
                    commit(ShortcutChord(modifiers: pendingModifiers, keyCode: nil))
                } else {
                    pendingModifiers = modifiers
                }
                return nil
            }
            guard !modifiers.isEmpty else {
                error = "Include at least one modifier."
                return nil
            }
            commit(ShortcutChord(modifiers: modifiers, keyCode: event.keyCode))
            return nil
        }
    }

    private func commit(_ value: ShortcutChord) {
        guard value.isValid else { error = "Include at least one modifier."; return }
        guard value != conflictingChord else { error = "Hold and Toggle must be different."; return }
        chord = value
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        pendingModifiers = []
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
