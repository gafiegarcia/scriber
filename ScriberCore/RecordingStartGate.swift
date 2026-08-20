import Foundation

/// What a dictation gesture means while the microphone is still opening.
///
/// Opening a capture session is slow enough to need a background queue, so a
/// press returns before there is anything to record. Every gesture that ends a
/// recording can therefore arrive before the recording exists: a tap that asks
/// for hands-free, a release, Escape, a keystroke. Deciding what those mean by
/// looking at what is on screen fails exactly then — nothing is on screen yet —
/// and a dropped release leaves a recording with no gesture left to stop it.
///
/// So the pending gesture is state here rather than a lookup elsewhere. The mode
/// is installed on the press, before any session exists, and an ending that
/// arrives early is remembered until the session opens and can honour it.
///
/// Paired with `RecorderLifecycle`, which tracks the capture stack's own
/// bookkeeping. This type never learns what a recording is; that one never
/// learns what the user pressed.
public struct RecordingStartGate: Equatable, Sendable {
    /// What to do with a session the moment it opens, when the gesture that ends
    /// it has already arrived.
    public enum Resolution: Equatable, Sendable {
        case stop
        case cancel
    }

    public enum State: Equatable, Sendable {
        case idle
        /// A start is in flight. `mode` is what the gesture means so far and can
        /// still be promoted; `resolution` is what the session owes on arrival.
        case starting(mode: RecordingMode, resolution: Resolution?)
        case running(mode: RecordingMode)
    }

    public enum Event: Equatable, Sendable {
        case startRequested(mode: RecordingMode)
        /// The capture session is running. Until this, no audio exists.
        case sessionOpened
        /// It never opened, or a guard refused the request after it was asked.
        case startFailed
        case shortcut(ShortcutAction)
        /// The menu, the pill's Confirm, the duration cap.
        case stopRequested
        /// Escape, typing during a held recording, the pill's Cancel.
        case cancelRequested
    }

    public enum Decision: Equatable, Sendable {
        case ignore
        case beginStart(mode: RecordingMode)
        /// The session opened owing nothing: meter it and let it run.
        case beginMetering(mode: RecordingMode)
        /// A tap promoted a recording that was already running.
        case promote(mode: RecordingMode)
        case stop
        case cancel
        /// The gesture ending this recording arrived before the microphone
        /// opened, so the file holds nothing. Close it without ever showing it.
        case abandonOpenedSession
        /// Cancelled while the session is still opening. It will be abandoned on
        /// arrival, but the gesture is answered now — a pill still up after the
        /// user typed or pressed Escape reads as having been ignored.
        case cancelPendingStart
        case startDidNotOpen
    }

    private var state: State = .idle

    public init() {}

    public var isIdle: Bool { state == .idle }

    public var isStarting: Bool {
        if case .starting = state { return true }
        return false
    }

    /// Whether typing some other key should abandon what is in flight.
    ///
    /// A held dictation is interrupted by any other key, hands-free is not, and a
    /// start still opening is judged by what the gesture means so far — there is
    /// no recording yet to have an age. `fn`+delete is the case that has to be
    /// quick: it is a shortcut people use for forward-delete, and the dictation
    /// it accidentally starts has to get out of the way at once.
    public func cancelsForTyping(elapsed: TimeInterval) -> Bool {
        switch state {
        case .idle:
            false
        case .starting(let mode, _):
            RecordingCancellationPolicy.cancelsForNonModifierKey(mode: mode, elapsed: 0)
        case .running(let mode):
            RecordingCancellationPolicy.cancelsForNonModifierKey(mode: mode, elapsed: elapsed)
        }
    }

    /// Cancelling outranks stopping, and repeating either changes nothing. That
    /// makes the order two endings arrive in irrelevant, which is the one thing
    /// about this that cannot be checked by reading it. `RecorderLifecycle`
    /// resolves a stop racing a cancel the same way, so the two agree on what a
    /// race means.
    private static func combine(_ existing: Resolution?, _ incoming: Resolution) -> Resolution {
        existing == .cancel || incoming == .cancel ? .cancel : .stop
    }

    public mutating func apply(_ event: Event) -> Decision {
        switch (state, event) {
        case (.idle, .startRequested(let mode)):
            state = .starting(mode: mode, resolution: nil)
            return .beginStart(mode: mode)
        case (.starting, .startRequested), (.running, .startRequested):
            return .ignore

        case (.starting(let mode, nil), .sessionOpened):
            state = .running(mode: mode)
            return .beginMetering(mode: mode)
        // Both resolutions abandon identically — nothing was captured either way
        // — so the decision carries no payload to tell them apart.
        case (.starting(_, .some), .sessionOpened):
            state = .idle
            return .abandonOpenedSession
        case (.idle, .sessionOpened), (.running, .sessionOpened):
            return .ignore

        // The user tried to dictate and could not. That is owed to them whether
        // or not they changed their mind while waiting.
        case (.starting, .startFailed):
            state = .idle
            return .startDidNotOpen
        case (.idle, .startFailed), (.running, .startFailed):
            return .ignore

        case (.idle, .shortcut(.pressed)):
            state = .starting(mode: .held, resolution: nil)
            return .beginStart(mode: .held)
        case (.starting(let mode, let resolution), .shortcut(.pressed)):
            guard ShortcutAction.pressed.stopsRecording(mode: mode) else { return .ignore }
            state = .starting(mode: mode, resolution: Self.combine(resolution, .stop))
            return .ignore
        case (.running(let mode), .shortcut(.pressed)):
            guard ShortcutAction.pressed.stopsRecording(mode: mode) else { return .ignore }
            state = .idle
            return .stop

        // The tap that asks for hands-free. Arriving early it changes what the
        // opening session will be, rather than failing to find one to promote.
        case (.starting(.held, let resolution), .shortcut(.releasedAsTap)):
            state = .starting(mode: .locked, resolution: resolution)
            return .ignore
        case (.running(.held), .shortcut(.releasedAsTap)):
            state = .running(mode: .locked)
            return .promote(mode: .locked)
        case (.idle, .shortcut(.releasedAsTap)),
             (.starting(.locked, _), .shortcut(.releasedAsTap)),
             (.running(.locked), .shortcut(.releasedAsTap)):
            return .ignore

        case (.starting(let mode, let resolution), .shortcut(.releasedAfterHold)):
            guard ShortcutAction.releasedAfterHold.stopsRecording(mode: mode) else { return .ignore }
            state = .starting(mode: mode, resolution: Self.combine(resolution, .stop))
            return .ignore
        case (.running(let mode), .shortcut(.releasedAfterHold)):
            guard ShortcutAction.releasedAfterHold.stopsRecording(mode: mode) else { return .ignore }
            state = .idle
            return .stop
        case (.idle, .shortcut(.releasedAfterHold)):
            return .ignore

        // The pill's dismissal, which the coordinator answers from what is on
        // screen. It reaches the recorder as `.cancelRequested` or not at all.
        case (_, .shortcut(.cancel)):
            return .ignore

        case (.starting(let mode, let resolution), .stopRequested):
            state = .starting(mode: mode, resolution: Self.combine(resolution, .stop))
            return .ignore
        case (.running, .stopRequested):
            state = .idle
            return .stop
        case (.idle, .stopRequested):
            return .ignore

        case (.starting(let mode, let resolution), .cancelRequested):
            state = .starting(mode: mode, resolution: Self.combine(resolution, .cancel))
            return .cancelPendingStart
        case (.running, .cancelRequested):
            state = .idle
            return .cancel
        case (.idle, .cancelRequested):
            return .ignore
        }
    }
}
