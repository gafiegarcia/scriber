import Combine
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

/// Holds the toasts currently on screen and nothing else. Timers live here; what
/// a toast says and how long it lasts is decided in `ScriberCore`.
@MainActor
final class ToastPresenter: ObservableObject {
    @Published private(set) var toasts: [Toast] = []

    private var expiries: [UUID: Task<Void, Never>] = [:]
    private var undoObserver: AnyCancellable?

    init() {
        undoObserver = NotificationCenter.default
            .publisher(for: .NSUndoManagerDidUndoChange)
            .sink { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let undone = (notification.object as? UndoManager)?.redoActionName
                    else { return }
                    self.toasts
                        .filter { $0.undoActionName == undone }
                        .forEach { self.dismiss($0.id) }
                }
            }
    }

    func post(_ toast: Toast) {
        let replaced = Set(toasts.map(\.id))
        toasts = ToastStack.posting(toast, onto: toasts)
        replaced.subtracting(toasts.map(\.id)).forEach { expiries.removeValue(forKey: $0)?.cancel() }
        expiries[toast.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(toast.duration))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID) {
        expiries[id]?.cancel()
        expiries[id] = nil
        toasts.removeAll { $0.id == id }
    }

    /// The window is going away and so is anything it was about to say.
    func cancelAll() {
        expiries.values.forEach { $0.cancel() }
        expiries.removeAll()
        toasts.removeAll()
    }
}

/// Bottom-trailing inside the window, growing upward. A toast materializes and
/// dematerializes where it sits; the rest of the stack moves to make room.
///
/// Attached to the window shell rather than to the Dictation page, so a second
/// workspace inherits it without moving.
struct ToastStackView: View {
    @EnvironmentObject private var presenter: ToastPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(ToastStack.visible(presenter.toasts)) { toast in
                    ToastView(toast: toast)
                        .glassEffectTransition(reduceMotion ? .identity : .materialize)
                        .transition(.opacity)
                }
            }
        }
        .padding(16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: presenter.toasts)
        .allowsHitTesting(false)
    }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(toast.title)
                if let hint = toast.hint {
                    Text(hint).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: toast.systemImage)
        }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(toast.tone.glassTint), in: .capsule)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(toast.accessibilityIdentifier)
    }
}

/// Lives here rather than beside the tone itself because `ScriberCore` is
/// deliberately free of SwiftUI. The floating pill reads the same `accent`, which
/// is what stops it and the toast stack from coloring one outcome twice.
extension ToastTone {
    /// Symbols carry this at full strength.
    var accent: Color? {
        switch self {
        case .success: .green
        case .warning: .orange
        case .failure: .red
        case .neutral: nil
        }
    }

    /// Tint, not fill: the glass still has to read as glass over whatever is
    /// behind it. A neutral toast takes the window's own background, which quiets
    /// the colored row controls under it without adding a hue of its own.
    var glassTint: Color {
        if let accent { return accent.opacity(0.18) }
        // Measured: in dark mode, the color showing through behind the hint fell
        // 17% at 0.18, 42% at 0.4 and 59% at 0.6 — the window's color sits close
        // to the glass's own, so it takes more of it to register. 0.4 was chosen
        // by eye as the most that still reads as glass.
        return Color(nsColor: .windowBackgroundColor).opacity(0.4)
    }
}
