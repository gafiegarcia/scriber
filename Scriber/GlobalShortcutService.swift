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
    private var pendingEffects: [PendingEffect] = []
    private var isDrainScheduled = false

    /// An effect and the timestamp of the input that produced it, kept together.
    ///
    /// The buffer holds several inputs' effects whenever the drain is late, which
    /// is exactly when a press is worth timing, so the timestamp cannot live in a
    /// property the next input overwrites.
    private struct PendingEffect {
        let effect: ShortcutTapEffect
        let hardwareTime: TimeInterval
    }

    init(dictation: ShortcutChord) {
        machine = ShortcutTapMachine(dictation: dictation)
    }

    func update(dictation: ShortcutChord) {
        machine.reconfigure(dictation: dictation)
    }

    func setMode(_ mode: ShortcutMonitorMode) {
        machine.setMode(mode)
    }

    func setConfigurationCaptureActive(_ active: Bool) {
        machine.setConfigurationCaptureActive(active)
    }

    /// `CGEvent.timestamp` counts in mach units, whose ratio to nanoseconds is
    /// the machine's to state. One is 1:1 on Apple silicon; asking is what makes
    /// that a fact rather than an assumption.
    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func seconds(fromMachTime machTime: UInt64) -> TimeInterval {
        let nanoseconds = Double(machTime) * Double(machTimebase.numer) / Double(machTimebase.denom)
        return nanoseconds / 1_000_000_000
    }

    /// The same clock `ShortcutTapInput.timestamp` is on, so the two subtract.
    static func monotonicNow() -> TimeInterval {
        seconds(fromMachTime: mach_absolute_time())
    }

    /// When the key physically went down, for the press this service most
    /// recently reported as `.pressed`.
    ///
    /// Measurement only, for the "Stop delivery holding the main thread" roadmap
    /// item; delete it with that item. Nothing about a dictation depends on this.
    /// The tap is on the main run loop, so a press arriving while the main thread
    /// is busy waits in the queue and every timestamp taken on the main actor —
    /// including the one the start line calls the press — is taken after that
    /// wait is already over. This is the only stamp in the app that predates it.
    ///
    /// Written as the press is handed to `onAction`, not as the tap sees it. A
    /// stall long enough to be worth measuring buffers several inputs into one
    /// drain, so a slot written at tap time would hold the newest press by the
    /// time the oldest one is read — understating the stall it is here to show.
    private(set) var lastPressHardwareTime: TimeInterval?

    /// Never call this from inside the tap's own callback. Its first act is
    /// `stop()`, which releases the `CFMachPort` whose callout would be on the
    /// stack. Everything the tap triggers is deferred a run-loop turn precisely so
    /// that no handler can reach back here while the callback is still running.
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
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                // When the key moved, not when this callback got to run. The tap is
                // on the main run loop, so anything blocking the main thread — a
                // Bluetooth headset changing mode inside Core Audio is a second of
                // it — holds events in the queue, and a tap stamped late reads as a
                // hold, which stops the recording it just started.
                timestamp: GlobalShortcutService.seconds(fromMachTime: event.timestamp)
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
        // Anything still queued was decided against a tap that no longer exists.
        pendingEffects.removeAll()
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
        schedule(outcome.effects, hardwareTime: input.timestamp)
        return outcome.suppressesEvent
    }

    /// Hands the work back to the run loop, so the callback returns the moment it
    /// has decided. Starting a recording opens an `AVCaptureSession`, builds a
    /// CoreAudio aggregate device, and asks the window server for every window on
    /// screen — run inline, all of that happens while the system is blocked waiting
    /// for this tap to reply, and a stalled callback takes the machine with it.
    ///
    /// One buffer drained by one task, not a task per effect: unstructured tasks
    /// have no order relative to each other, and a press and release inverted
    /// either leaves a recording nothing stops or stops one that never started.
    /// Ordering comes from the array here. `DispatchQueue.main.async` is FIFO too,
    /// but wants an `@escaping @Sendable` closure and this class is neither.
    private func schedule(_ effects: [ShortcutTapEffect], hardwareTime: TimeInterval) {
        guard !effects.isEmpty else { return }
        pendingEffects.append(
            contentsOf: effects.map { PendingEffect(effect: $0, hardwareTime: hardwareTime) }
        )
        guard !isDrainScheduled else { return }
        isDrainScheduled = true
        Task { @MainActor in self.drainPendingEffects() }
    }

    private func drainPendingEffects() {
        isDrainScheduled = false
        let pending = pendingEffects
        pendingEffects.removeAll(keepingCapacity: true)
        for entry in pending {
            switch entry.effect {
            case .action(let action):
                // Measurement only — see `lastPressHardwareTime`.
                if case .pressed = action { lastPressHardwareTime = entry.hardwareTime }
                onAction?(action)
            case .nonModifierKeyDown: onNonModifierKeyDown?()
            }
        }
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

