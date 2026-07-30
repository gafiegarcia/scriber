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

    func post(_ toast: Toast) {
        toasts.append(toast)
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

/// Bottom-trailing inside the window, growing upward.
///
/// Attached to the window shell rather than to the Dictation page, so a second
/// workspace inherits it without moving.
struct ToastStackView: View {
    @EnvironmentObject private var presenter: ToastPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(ToastStack.visible(presenter.toasts)) { toast in
                ToastView(toast: toast)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .trailing).combined(with: .opacity)
                    )
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
        Label(toast.title, systemImage: toast.systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(tint), in: .capsule)
            .accessibilityIdentifier(toast.accessibilityIdentifier)
    }

    /// Tint, not fill: the glass still has to read as glass over whatever the
    /// window is showing behind it.
    private var tint: Color {
        switch toast.tone {
        case .success: .green.opacity(0.18)
        case .warning: .orange.opacity(0.18)
        case .failure: .red.opacity(0.18)
        case .neutral: .clear
        }
    }
}
