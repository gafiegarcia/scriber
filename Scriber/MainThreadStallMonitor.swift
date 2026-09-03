import Foundation
import os

/// Reports how long the main thread spends busy in one pass of its run loop.
///
/// Measurement only, for the **Find what delivery does to the main thread**
/// roadmap item; delete it with that item.
///
/// Every other attempt at this question has polled — a task that sleeps, wakes,
/// and checks whether it woke late. That works, but a poll is itself main-actor
/// work, so it competes with what it is measuring and cannot say what the thread
/// was doing, only that it was busy. This adds no wakeups at all: the run loop
/// already calls its observers on every pass, so timing the gap between waking
/// and going back to sleep costs two closure calls that were happening anyway.
///
/// A logged line is one uninterrupted stretch of main-thread work. The line's own
/// timestamp is the *end* of that stretch, so subtract `ms` to place its start
/// against the `dictation` and `paste-target` lines around it — that pairing is
/// what says which step owns a stall.
@MainActor
final class MainThreadStallMonitor {
    private static let log = Logger(
        subsystem: "com.gafiegarcia.scriber",
        category: "dictation"
    )

    /// One 60 Hz frame. Below this nothing has visibly dropped, and logging every
    /// pass would bury the stalls worth reading in thousands of idle ones.
    private let threshold: TimeInterval
    private var observer: CFRunLoopObserver?
    private var passBeganAt: CFAbsoluteTime?
    private var passBeganCPU: UInt64 = 0

    /// CPU actually burned by this thread, as opposed to time passing on it.
    ///
    /// The two come apart exactly where it matters. A pass that takes 350 ms of
    /// wall clock and 350 ms of CPU is work worth hunting. One that takes 350 ms
    /// and 20 ms of CPU is a run loop being woken repeatedly and going back to
    /// waiting — busy on paper, idle in fact, and nothing a fix could remove.
    /// Wall time alone cannot tell those apart, and they call for opposite work.
    private static func threadCPUNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }

    init(threshold: TimeInterval = 0.016) {
        self.threshold = threshold
    }

    func start() {
        guard observer == nil else { return }
        let activities = CFRunLoopActivity.afterWaiting.rawValue
            | CFRunLoopActivity.beforeWaiting.rawValue
        // The observer fires on the main thread, which is where this type lives.
        // `assumeIsolated` rather than a hop: a hop would land in a later pass and
        // measure the wrong one.
        observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, activities, true, 0
        ) { _, activity in
            MainActor.assumeIsolated {
                switch activity {
                case .afterWaiting:
                    self.passBeganAt = CFAbsoluteTimeGetCurrent()
                    self.passBeganCPU = Self.threadCPUNanoseconds()
                case .beforeWaiting:
                    guard let began = self.passBeganAt else { return }
                    self.passBeganAt = nil
                    let elapsed = CFAbsoluteTimeGetCurrent() - began
                    guard elapsed >= self.threshold else { return }
                    let cpu = Self.threadCPUNanoseconds() - self.passBeganCPU
                    Self.log.notice(
                        "main thread stalled ms=\(Int(elapsed * 1_000), privacy: .public) cpuMs=\(Int(cpu / 1_000_000), privacy: .public)"
                    )
                default:
                    return
                }
            }
        }
        if let observer {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    func stop() {
        guard let observer else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = nil
        passBeganAt = nil
    }
}
