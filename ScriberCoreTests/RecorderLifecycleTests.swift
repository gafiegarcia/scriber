import Foundation
import Testing
@testable import ScriberCore

@Suite("Recorder lifecycle")
struct RecorderLifecycleTests {
    @Test("A recording starts when nothing is in flight")
    func startsFromIdle() {
        var lifecycle = RecorderLifecycle()
        let id = UUID()
        #expect(lifecycle.start(id) == .start)
        #expect(lifecycle.activeRecording == id)
    }

    /// The case a tremor on the shortcut key produces: cancelling returns the app to
    /// idle without waiting for the capture stack to close the microphone, so the
    /// next press arrives while the last recording is still winding down.
    @Test("A press arriving before the last recording is resolved supersedes it")
    func startSupersedesInFlightRecording() {
        var lifecycle = RecorderLifecycle()
        let first = UUID()
        let second = UUID()
        _ = lifecycle.start(first)
        _ = lifecycle.cancel()
        #expect(lifecycle.start(second) == .supersedeThenStart(abandoning: first))
        #expect(lifecycle.activeRecording == second)
    }

    /// The superseded recording's own report can still arrive afterwards. Acting on
    /// it would resolve the recording that is running now, leaving the recorder
    /// convinced it is idle while the microphone is open.
    @Test("A report for a superseded recording is ignored")
    func staleReportLeavesCurrentRecordingAlone() {
        var lifecycle = RecorderLifecycle()
        let first = UUID()
        let second = UUID()
        _ = lifecycle.start(first)
        _ = lifecycle.start(second)
        #expect(lifecycle.finished(first) == .alreadyResolved)
        #expect(lifecycle.activeRecording == second)
    }

    @Test("A stopped recording is delivered, a cancelled one discarded")
    func resolutionFollowsHowItEnded() {
        var lifecycle = RecorderLifecycle()
        let stopped = UUID()
        _ = lifecycle.start(stopped)
        #expect(lifecycle.stop() == .stop(stopped))
        #expect(lifecycle.finished(stopped) == .deliver(stopped))

        let cancelled = UUID()
        _ = lifecycle.start(cancelled)
        #expect(lifecycle.cancel() == .stop(cancelled))
        #expect(lifecycle.finished(cancelled) == .discard(cancelled))
    }

    @Test("A stop and a cancel racing issue one stop, and the audio is discarded")
    func cancelAfterStopDoesNotStopTwice() {
        var lifecycle = RecorderLifecycle()
        let id = UUID()
        _ = lifecycle.start(id)
        #expect(lifecycle.stop() == .stop(id))
        #expect(lifecycle.cancel() == .nothingToStop)
        #expect(lifecycle.finished(id) == .discard(id))
    }

    /// A file output that never began writing can finish without the capture stack
    /// ever reporting it. Without this the recorder would believe a recording is
    /// still in progress for the rest of the session.
    @Test("A recording that is never reported still frees the recorder")
    func timeoutResolvesAnUnreportedRecording() {
        var lifecycle = RecorderLifecycle()
        let id = UUID()
        _ = lifecycle.start(id)
        _ = lifecycle.stop()
        #expect(lifecycle.timedOut(id) == .discard(id))
        #expect(lifecycle.activeRecording == nil)
        #expect(lifecycle.start(UUID()) == .start)
    }

    @Test("A timeout for a superseded recording leaves the current one alone")
    func staleTimeoutIsIgnored() {
        var lifecycle = RecorderLifecycle()
        let first = UUID()
        let second = UUID()
        _ = lifecycle.start(first)
        _ = lifecycle.start(second)
        #expect(lifecycle.timedOut(first) == .alreadyResolved)
        #expect(lifecycle.activeRecording == second)
    }

    /// The invariant the whole type exists for. Whatever order presses, releases and
    /// reports arrive in — including reports that never arrive — a recording can
    /// always be started. This is deliberately blind to which gesture means what, so
    /// it keeps holding through any change to the shortcut scheme.
    @Test("No sequence of events can leave the recorder unable to start")
    func neverRefusesAStart() {
        enum Event: CaseIterable {
            case start, stop, cancel, report, timeout
        }

        var generator = SeededGenerator(seed: 20_260_812)
        for _ in 0..<2_000 {
            var lifecycle = RecorderLifecycle()
            var issued: [UUID] = []
            for _ in 0..<12 {
                switch Event.allCases.randomElement(using: &generator)! {
                case .start:
                    let id = UUID()
                    issued.append(id)
                    _ = lifecycle.start(id)
                case .stop:
                    _ = lifecycle.stop()
                case .cancel:
                    _ = lifecycle.cancel()
                case .report:
                    if let id = issued.randomElement(using: &generator) {
                        _ = lifecycle.finished(id)
                    }
                case .timeout:
                    if let id = issued.randomElement(using: &generator) {
                        _ = lifecycle.timedOut(id)
                    }
                }
            }
            let next = UUID()
            switch lifecycle.start(next) {
            case .start, .supersedeThenStart:
                #expect(lifecycle.activeRecording == next)
            }
        }
    }
}
