import Foundation
import Testing
@testable import ScriberCore

@Suite("Toasts")
struct ToastTests {
    /// The visual-inspection procedure finds this by name and no UI suite would
    /// catch a rename.
    @Test("A copied transcript reports success and says so briefly")
    func copiedTranscript() {
        let toast = Toast.transcriptCopied()
        #expect(toast.title == "Transcript copied")
        #expect(toast.tone == .success)
        #expect(toast.duration == 1.4)
        #expect(toast.accessibilityIdentifier == "dictation-copy-toast")
    }

    @Test("An empty stack shows nothing")
    func emptyStack() {
        #expect(ToastStack.visible([]).isEmpty)
    }

    @Test("Everything shows while the stack is within its cap")
    func showsEverythingWhileSmall() {
        let toasts = [Toast.transcriptCopied(), Toast.transcriptCopied()]
        #expect(ToastStack.visible(toasts).map(\.id) == toasts.map(\.id))
    }

    /// Past the cap the corner stops reading as a stack and starts covering the
    /// content it reports on.
    @Test("A long stack keeps the newest and drops the oldest")
    func capsTheStack() {
        let toasts = (0..<5).map { _ in Toast.transcriptCopied() }
        let visible = ToastStack.visible(toasts)
        #expect(visible.count == ToastStack.maximumVisible)
        #expect(visible.map(\.id) == toasts.suffix(ToastStack.maximumVisible).map(\.id))
    }

    @Test("The newest toast sits last, nearest the corner it grows from")
    func ordersOldestFirst() {
        let first = Toast.transcriptCopied()
        let second = Toast.transcriptCopied()
        #expect(ToastStack.visible([first, second]).last?.id == second.id)
    }

    /// Every toast carries a finite duration by construction. A notice that has
    /// to persist until it is resolved is a condition, and conditions live in
    /// the window chrome — see `RecoveryConditions`.
    @Test("Toasts are transient by construction")
    func toastsAreTransient() {
        #expect(Toast.transcriptCopied().duration > 0)
    }
}
