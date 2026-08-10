import AppKit
import SwiftUI

/// The day label's text, published from the history list's scroll position, and
/// the leading inset it is drawn at.
///
/// The label does not live in the list any more, so the two need something to
/// talk through. `nil` means there is no day to name — an empty history, or a
/// search that matched nothing — and collapses the titlebar strip.
@MainActor
final class DictationDayTitle: ObservableObject {
    @Published var title: String?

}

/// Puts the day label inside the window's titlebar, below the toolbar items.
///
/// **This is why the label has no backdrop of its own.** A second surface under
/// the toolbar can never be made to agree with it: the toolbar's material is
/// sampled from what passes beneath the window, and `Material.bar` only
/// approximates it. A titlebar accessory is not a matched surface, it is the same
/// surface, so there is nothing left to match.
///
/// Installed once, when the view reaches a window. Adding or removing an
/// accessory later asks SwiftUI to reconcile window chrome while it is drawing,
/// which is what this window has crashed on before; visibility changes go through
/// `isHidden`, which AppKit collapses without restructuring the titlebar.
struct DictationDayTitlebarInstaller: NSViewRepresentable {
    @ObservedObject var model: DictationDayTitle

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = InstallerView()
        view.install = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window, model: model)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.accessory?.isHidden = model.title == nil
    }

    @MainActor
    final class Coordinator {
        var accessory: NSTitlebarAccessoryViewController?

        func install(in window: NSWindow, model: DictationDayTitle) {
            guard accessory == nil else { return }
            // `.automatic` is the whole point: AppKit hides the separator until
            // content actually scrolls under the titlebar, so the strip reads as
            // one surface with the toolbar while the list is at rest.
            window.titlebarSeparatorStyle = .automatic

            let controller = NSTitlebarAccessoryViewController()
            controller.layoutAttribute = .bottom
            let host = NSHostingController(rootView: DictationDayTitlebarLabel(model: model))
            host.view.frame.size = host.view.fittingSize
            host.view.autoresizingMask = [.width]
            controller.view = host.view
            // The hosting controller owns the SwiftUI content; the accessory only
            // holds its view, so it has to be retained alongside it.
            controller.addChild(host)
            controller.isHidden = model.title == nil

            window.addTitlebarAccessoryViewController(controller)
            accessory = controller
        }
    }

    /// `viewDidMoveToWindow` is the only point at which a SwiftUI-hosted view can
    /// name the `NSWindow` it ended up in.
    private final class InstallerView: NSView {
        var install: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            install?(window)
        }
    }
}

/// The label as it sits in the titlebar.
///
/// It hangs off the leading edge of the cards, lined up with the close button,
/// the way Calendar sets its month title against the window rather than against
/// the grid. The label is chrome, so it takes the titlebar's geometry — it does
/// not follow the list's column, and above the width at which the cards stop
/// growing and start centring, the two separate on purpose.
private struct DictationDayTitlebarLabel: View {
    @ObservedObject var model: DictationDayTitle

    var body: some View {
        Text(model.title ?? "")
            .font(.title3.weight(.semibold))
            .padding(.leading, DictationHistoryLayout.dayLabelLeadingInset)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
