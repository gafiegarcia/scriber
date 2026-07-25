@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
#if SWIFT_PACKAGE
import ScriberCore
#endif

enum ShortcutMonitorMode: Equatable, Sendable {
    case idle
    case held
    case locked
    case busy
}

@MainActor
final class GlobalShortcutService {
    var onAction: ((ShortcutAction) -> Void)?
    var onEscape: (() -> Bool)?
    var onNonModifierKeyDown: (() -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var matcher: ShortcutMatcher
    private var holdEnabled: Bool
    private var toggleEnabled: Bool
    private var mode: ShortcutMonitorMode = .idle
    private var isConfigurationCaptureActive = false
    private var holdLatched = false
    private var toggleLatched = false
    private var suppressedKeyCodes = Set<UInt16>()

    init(hold: ShortcutChord, toggle: ShortcutChord, holdEnabled: Bool, toggleEnabled: Bool) {
        matcher = ShortcutMatcher(hold: hold, toggle: toggle)
        self.holdEnabled = holdEnabled
        self.toggleEnabled = toggleEnabled
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func update(hold: ShortcutChord, toggle: ShortcutChord, holdEnabled: Bool, toggleEnabled: Bool) {
        matcher = ShortcutMatcher(hold: hold, toggle: toggle)
        self.holdEnabled = holdEnabled
        self.toggleEnabled = toggleEnabled
        resetLatches()
    }

    func setMode(_ mode: ShortcutMonitorMode) {
        self.mode = mode
        if mode == .idle || mode == .busy { resetLatches() }
    }

    /// Leaves the event tap running while a Settings shortcut recorder owns
    /// keyboard input, but passes all events through without interpretation.
    func setConfigurationCaptureActive(_ active: Bool) {
        isConfigurationCaptureActive = active
        resetLatches()
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
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            var modifiers: KeyModifiers = []
            if flags.contains(.maskCommand) { modifiers.insert(.command) }
            if flags.contains(.maskAlternate) { modifiers.insert(.option) }
            if flags.contains(.maskControl) { modifiers.insert(.control) }
            if flags.contains(.maskShift) { modifiers.insert(.shift) }
            if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
            let snapshot = EventSnapshot(type: type, keyCode: keyCode, modifiers: modifiers)
            // This tap is installed on the main run loop, so the callback is
            // main-actor isolated. Processing synchronously is essential: an
            // asynchronous hop would return the event before it can be consumed.
            let suppress = MainActor.assumeIsolated { service.process(snapshot) }
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
        resetLatches()
    }

    private func reenableTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        onAvailabilityChanged?(CGEvent.tapIsEnabled(tap: eventTap))
    }

    private func process(_ event: EventSnapshot) -> Bool {
        guard !isConfigurationCaptureActive else { return false }

        if event.type == .keyDown, event.keyCode == 53 {
            return onEscape?() ?? false
        }

        if event.type == .keyUp {
            let wasSuppressed = suppressedKeyCodes.remove(event.keyCode) != nil
            if matcher.toggle.keyCode == event.keyCode { toggleLatched = false }
            if matcher.hold.keyCode == event.keyCode, holdLatched {
                holdLatched = false
                if mode == .held { onAction?(.holdReleased) }
                return true
            }
            return wasSuppressed
        }

        if event.type == .keyDown {
            let exactHold = matcher.matchesExactly(matcher.hold, modifiers: event.modifiers, keyCode: event.keyCode)
            if holdEnabled, matcher.hold.keyCode != nil, exactHold, !holdLatched, mode == .idle {
                holdLatched = true
                suppressedKeyCodes.insert(event.keyCode)
                onAction?(.holdPressed)
                return true
            }
            let toggleMatches: Bool
            if mode == .held {
                toggleMatches = matcher.matchesToggleWhileHeld(modifiers: event.modifiers, keyCode: event.keyCode)
            } else {
                toggleMatches = matcher.matchesExactly(matcher.toggle, modifiers: event.modifiers, keyCode: event.keyCode)
            }
            if toggleEnabled, toggleMatches, !toggleLatched {
                toggleLatched = true
                suppressedKeyCodes.insert(event.keyCode)
                onAction?(.togglePressed)
                return true
            }
            if mode == .held { onNonModifierKeyDown?() }
            return false
        }

        guard event.type == .flagsChanged else { return false }
        let holdSatisfied = holdEnabled && matcher.hold.modifiers.isSubset(of: event.modifiers)
        let exactHold = holdEnabled && matcher.matchesExactly(matcher.hold, modifiers: event.modifiers, keyCode: nil)

        switch mode {
        case .idle:
            if matcher.hold.keyCode == nil, exactHold, !holdLatched {
                holdLatched = true
                onAction?(.holdPressed)
            }
        case .held:
            if holdLatched, !holdSatisfied {
                holdLatched = false
                onAction?(.holdReleased)
            }
        case .locked:
            if !holdSatisfied { holdLatched = false }
        case .busy:
            break
        }
        // Modifier-only shortcuts (including bare Fn) must not consume the
        // flagsChanged event. Swallowing it can leave the focused app with a
        // stale modifier state, which in turn makes ordinary Space input fail.
        return false
    }

    private func resetLatches() {
        holdLatched = false
        toggleLatched = false
        suppressedKeyCodes.removeAll()
    }
}

private struct EventSnapshot: Sendable {
    let type: CGEventType
    let keyCode: UInt16
    let modifiers: KeyModifiers
}
