@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
#if SWIFT_PACKAGE
import ScriberCore
#endif

@MainActor
final class GlobalShortcutService {
    var onAction: ((ShortcutAction) -> Void)?
    /// Whether a visible pill wants Escape. Cheap and synchronous on purpose:
    /// the tap's return value gates the event, so this decision cannot be
    /// deferred. It reads two properties and allocates nothing. The dismissal
    /// itself arrives as an ordinary `.cancel` action.
    var pillConsumesEscape: (() -> Bool)?
    var onNonModifierKeyDown: (() -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Every decision this tap makes. Kept in `ScriberCore` so it can be tested:
    /// nothing in this file can be, and a mistake here stalls the whole machine.
    private var machine: ShortcutTapMachine

    init(hold: ShortcutChord, toggle: ShortcutChord, holdEnabled: Bool, toggleEnabled: Bool) {
        machine = ShortcutTapMachine(
            hold: hold,
            toggle: toggle,
            holdEnabled: holdEnabled,
            toggleEnabled: toggleEnabled
        )
    }

    func update(hold: ShortcutChord, toggle: ShortcutChord, holdEnabled: Bool, toggleEnabled: Bool) {
        machine.reconfigure(
            hold: hold,
            toggle: toggle,
            holdEnabled: holdEnabled,
            toggleEnabled: toggleEnabled
        )
    }

    func setMode(_ mode: ShortcutMonitorMode) {
        machine.setMode(mode)
    }

    func setConfigurationCaptureActive(_ active: Bool) {
        machine.setConfigurationCaptureActive(active)
    }

    func start() {
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<GlobalShortcutService>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { service.reenableTap() }
                return Unmanaged.passUnretained(event)
            }
            guard let kind = ShortcutTapInput.Kind(type) else {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            var modifiers: KeyModifiers = []
            if flags.contains(.maskCommand) { modifiers.insert(.command) }
            if flags.contains(.maskAlternate) { modifiers.insert(.option) }
            if flags.contains(.maskControl) { modifiers.insert(.control) }
            if flags.contains(.maskShift) { modifiers.insert(.shift) }
            if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
            let input = ShortcutTapInput(
                kind: kind,
                keyCode: keyCode,
                modifiers: modifiers,
                // Set only on keyDown; the other two report 0, which is what the
                // machine wants for them. Without it a held chord reads as a
                // stream of fresh presses.
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
            // This tap is installed on the main run loop, so the callback is
            // main-actor isolated. Deciding synchronously is essential: an
            // asynchronous hop would return the event before it can be consumed.
            let suppress = MainActor.assumeIsolated { service.process(input) }
            return suppress ? nil : Unmanaged.passUnretained(event)
        }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: pointer
        )
        guard let eventTap else {
            onAvailabilityChanged?(false)
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        onAvailabilityChanged?(true)
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        runLoopSource = nil
        eventTap = nil
        machine.reset()
    }

    private func reenableTap() {
        guard let eventTap else { return }
        // A revoked tap must be torn down, never re-armed. This tap is head-inserted at
        // the HID level, so the system advances the whole event stream only once the
        // callback replies — a tap the process is no longer trusted to own gets disabled
        // again immediately, and re-arming it in a loop stalls every click and keypress
        // on the machine while starving the main-loop poll that would call `stop()`.
        guard AXIsProcessTrusted() else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            onAvailabilityChanged?(false)
            // Deferred: `stop()` releases the CFMachPort whose callout is running now.
            Task { @MainActor in self.stop() }
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        // Whatever was held while the tap was disabled released unseen.
        machine.reset()
        onAvailabilityChanged?(CGEvent.tapIsEnabled(tap: eventTap))
    }

    private func process(_ input: ShortcutTapInput) -> Bool {
        let outcome = machine.handle(input, pillConsumesEscape: pillConsumesEscape?() ?? false)
        for effect in outcome.effects {
            switch effect {
            case .action(let action): onAction?(action)
            case .nonModifierKeyDown: onNonModifierKeyDown?()
            }
        }
        return outcome.suppressesEvent
    }
}

extension ShortcutTapInput.Kind {
    init?(_ type: CGEventType) {
        switch type {
        case .keyDown: self = .keyDown
        case .keyUp: self = .keyUp
        case .flagsChanged: self = .flagsChanged
        default: return nil
        }
    }
}

