import Foundation

/// The bookkeeping behind "a recording is in progress", separated from the capture
/// stack so the ordering rules can be exercised without a microphone.
///
/// Shortcut presses arrive faster than AVFoundation reports a recording finishing —
/// a tremor on the key is enough, and so is any scheme where a quick tap means
/// something. Every rule here serves one invariant: a new recording can always
/// start, whatever order the events arrive in.
public struct RecorderLifecycle: Equatable, Sendable {
    /// What starting a recording requires of the capture stack.
    public enum Start: Equatable, Sendable {
        case start
        /// Something was still in flight. It is dropped rather than allowed to
        /// refuse the new recording, having already been stopped or cancelled.
        case supersedeThenStart(abandoning: UUID)
    }

    public enum Stop: Equatable, Sendable {
        case stop(UUID)
        case nothingToStop
    }

    /// What to do with the audio of a recording that has reached its end.
    public enum Finish: Equatable, Sendable {
        case deliver(UUID)
        case discard(UUID)
        /// A report for a recording that was already superseded or resolved. Acting
        /// on one would clear the bookkeeping of whichever recording is running now.
        case alreadyResolved
    }

    private var current: UUID?
    private var discarding = false
    private var stopRequested = false

    public init() {}

    public var activeRecording: UUID? { current }

    public mutating func start(_ id: UUID) -> Start {
        let superseded = current
        current = id
        discarding = false
        stopRequested = false
        if let superseded { return .supersedeThenStart(abandoning: superseded) }
        return .start
    }

    public mutating func stop() -> Stop {
        guard let current, !stopRequested else { return .nothingToStop }
        stopRequested = true
        return .stop(current)
    }

    /// Cancelling after a stop keeps the same single stop and only changes what
    /// happens to the audio, so a stop and a cancel racing cannot issue two.
    public mutating func cancel() -> Stop {
        guard let current else { return .nothingToStop }
        discarding = true
        guard !stopRequested else { return .nothingToStop }
        stopRequested = true
        return .stop(current)
    }

    public mutating func finished(_ id: UUID) -> Finish {
        guard current == id else { return .alreadyResolved }
        let discard = discarding
        resolve()
        return discard ? .discard(id) : .deliver(id)
    }

    /// The capture stack never reported this recording finishing. Audio that was
    /// never handed back cannot be delivered, but the recorder must still be free.
    public mutating func timedOut(_ id: UUID) -> Finish {
        guard current == id else { return .alreadyResolved }
        resolve()
        return .discard(id)
    }

    private mutating func resolve() {
        current = nil
        discarding = false
        stopRequested = false
    }
}
