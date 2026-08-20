import Foundation
import Testing
@testable import ScriberCore

@Suite("Recording start gate")
struct RecordingStartGateTests {
    @Test("A press starts a held recording and the open session is metered")
    func startsAndMeters() {
        var gate = RecordingStartGate()
        #expect(gate.apply(.shortcut(.pressed)) == .beginStart(mode: .held))
        #expect(gate.isStarting)
        #expect(gate.apply(.sessionOpened) == .beginMetering(mode: .held))
        #expect(!gate.isStarting)
    }

    @Test("A tap during the start window locks the recording that opens")
    func tapDuringStartWindowLocks() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        #expect(gate.apply(.shortcut(.releasedAsTap)) == .ignore)
        #expect(gate.apply(.sessionOpened) == .beginMetering(mode: .locked))
    }

    @Test("A tap after the session opens promotes the running recording")
    func tapAfterOpenPromotes() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        _ = gate.apply(.sessionOpened)
        #expect(gate.apply(.shortcut(.releasedAsTap)) == .promote(mode: .locked))
    }

    @Test("A hold released before the microphone opens closes the session unseen")
    func holdReleasedBeforeOpen() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        #expect(gate.apply(.shortcut(.releasedAfterHold)) == .ignore)
        #expect(gate.apply(.sessionOpened) == .abandonOpenedSession)
        #expect(gate.isIdle)
    }

    @Test("Escape during the start window closes the session unseen")
    func escapeDuringStartWindow() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        #expect(gate.apply(.cancelRequested) == .cancelPendingStart)
        #expect(gate.apply(.sessionOpened) == .abandonOpenedSession)
    }

    @Test("Typing during the start window closes the session unseen")
    func typingDuringStartWindow() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        _ = gate.apply(.cancelRequested)
        #expect(gate.apply(.sessionOpened) == .abandonOpenedSession)
        #expect(gate.isIdle)
    }

    @Test("Cancel outranks a stop latched in the same window")
    func cancelOutranksStop() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        _ = gate.apply(.stopRequested)
        _ = gate.apply(.cancelRequested)
        #expect(gate.apply(.sessionOpened) == .abandonOpenedSession)
    }

    @Test("A latched stop and cancel resolve the same way in either order")
    func latchOrderDoesNotMatter() {
        var stopFirst = RecordingStartGate()
        _ = stopFirst.apply(.shortcut(.pressed))
        _ = stopFirst.apply(.stopRequested)
        _ = stopFirst.apply(.cancelRequested)

        var cancelFirst = RecordingStartGate()
        _ = cancelFirst.apply(.shortcut(.pressed))
        _ = cancelFirst.apply(.cancelRequested)
        _ = cancelFirst.apply(.stopRequested)

        #expect(stopFirst == cancelFirst)
    }

    @Test("A second press during the start window starts nothing")
    func secondPressStartsNothing() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        #expect(gate.apply(.shortcut(.pressed)) == .ignore)
        #expect(gate.apply(.sessionOpened) == .beginMetering(mode: .held))
    }

    @Test("A press stops a hands-free recording that has not opened yet")
    func pressStopsUnopenedHandsFree() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        _ = gate.apply(.shortcut(.releasedAsTap))
        #expect(gate.apply(.shortcut(.pressed)) == .ignore)
        #expect(gate.apply(.sessionOpened) == .abandonOpenedSession)
    }

    @Test("A press stops a hands-free recording that is running")
    func pressStopsRunningHandsFree() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        _ = gate.apply(.sessionOpened)
        _ = gate.apply(.shortcut(.releasedAsTap))
        #expect(gate.apply(.shortcut(.pressed)) == .stop)
        #expect(gate.isIdle)
    }

    @Test("A release after a hold stops a running held recording")
    func releaseStopsRunningHold() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        _ = gate.apply(.sessionOpened)
        #expect(gate.apply(.shortcut(.releasedAfterHold)) == .stop)
    }

    @Test("A start that never opens returns the gate to idle")
    func failedStartReturnsToIdle() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        #expect(gate.apply(.startFailed) == .startDidNotOpen)
        #expect(gate.isIdle)
        #expect(gate.apply(.shortcut(.pressed)) == .beginStart(mode: .held))
    }

    @Test("A failed start reports itself even after the user changed their mind")
    func failedStartReportsAfterCancel() {
        var gate = RecordingStartGate()
        _ = gate.apply(.shortcut(.pressed))
        _ = gate.apply(.cancelRequested)
        #expect(gate.apply(.startFailed) == .startDidNotOpen)
    }

    @Test("The menu can start hands-free without a shortcut press")
    func menuStartsHandsFree() {
        var gate = RecordingStartGate()
        #expect(gate.apply(.startRequested(mode: .locked)) == .beginStart(mode: .locked))
        #expect(gate.apply(.sessionOpened) == .beginMetering(mode: .locked))
        #expect(gate.apply(.stopRequested) == .stop)
    }

    @Test("Typing cancels a held dictation from the press, not from the microphone")
    func typingCancelsFromThePress() {
        var gate = RecordingStartGate()
        #expect(!gate.cancelsForTyping(elapsed: 0))
        _ = gate.apply(.shortcut(.pressed))
        // The window that used to be deaf: no session, no elapsed time, and the
        // key still has to land.
        #expect(gate.cancelsForTyping(elapsed: 0))
        _ = gate.apply(.sessionOpened)
        #expect(gate.cancelsForTyping(elapsed: 0.5))
        // Past the recovery threshold it is a dictation worth keeping.
        #expect(!gate.cancelsForTyping(elapsed: 1))
    }

    @Test("Typing never cancels a hands-free dictation, opened or not")
    func typingLeavesHandsFreeAlone() {
        var starting = RecordingStartGate()
        _ = starting.apply(.shortcut(.pressed))
        _ = starting.apply(.shortcut(.releasedAsTap))
        #expect(!starting.cancelsForTyping(elapsed: 0))

        var running = RecordingStartGate()
        _ = running.apply(.shortcut(.pressed))
        _ = running.apply(.sessionOpened)
        _ = running.apply(.shortcut(.releasedAsTap))
        #expect(!running.cancelsForTyping(elapsed: 0.1))
    }

    @Test("No sequence of events can leave the gate unable to start")
    func noSequenceOfEventsLeavesTheGateUnableToStart() {
        var generator = SeededGenerator(seed: 0x5372_6962_6572_0001)
        for _ in 0..<2_000 {
            var gate = RecordingStartGate()
            for _ in 0..<12 {
                _ = gate.apply(randomEvent(using: &generator))
            }
            // Ending whatever is in flight, whichever state that is: a cancel
            // resolves a running recording and latches on a starting one, the
            // open answers that latch, and the failure answers a start that
            // never opened. A recording still running is meant to refuse a new
            // start — that is the recorder's business, not a wedge.
            _ = gate.apply(.cancelRequested)
            _ = gate.apply(.sessionOpened)
            _ = gate.apply(.startFailed)
            #expect(gate.isIdle)
            #expect(gate.apply(.startRequested(mode: .held)) == .beginStart(mode: .held))
        }
    }

    /// A start whose session is never answered is an open microphone with no pill
    /// on screen, and nothing in the app would say so.
    @Test("Every start is answered exactly once")
    func everyStartIsAnsweredExactlyOnce() {
        var generator = SeededGenerator(seed: 0x5372_6962_6572_0002)
        for _ in 0..<2_000 {
            var gate = RecordingStartGate()
            var outstanding = 0
            for _ in 0..<12 {
                switch gate.apply(randomEvent(using: &generator)) {
                case .beginStart:
                    #expect(outstanding == 0)
                    outstanding += 1
                case .beginMetering, .abandonOpenedSession, .startDidNotOpen:
                    #expect(outstanding == 1)
                    outstanding -= 1
                case .ignore, .promote, .stop, .cancel, .cancelPendingStart:
                    break
                }
                #expect(gate.isStarting == (outstanding == 1))
            }
        }
    }

    private func randomEvent(using generator: inout SeededGenerator) -> RecordingStartGate.Event {
        let modes: [RecordingMode] = [.held, .locked]
        let actions: [ShortcutAction] = [.pressed, .releasedAfterHold, .releasedAsTap, .cancel]
        switch Int.random(in: 0..<6, using: &generator) {
        case 0: return .startRequested(mode: modes.randomElement(using: &generator)!)
        case 1: return .sessionOpened
        case 2: return .startFailed
        case 3: return .shortcut(actions.randomElement(using: &generator)!)
        case 4: return .stopRequested
        default: return .cancelRequested
        }
    }
}
