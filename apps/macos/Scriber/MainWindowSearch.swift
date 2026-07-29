import AppKit
import Combine
import SwiftUI

enum MainSection: Hashable {
    case dictation
    case settings

    var windowTitle: String {
        switch self {
        case .dictation: "Dictation"
        case .settings: "Settings"
        }
    }

    /// A nil prompt means this workspace has no search capability. The window
    /// still keeps its toolbar and item; only the native inner control hides.
    var searchPrompt: String? {
        switch self {
        case .dictation: "Search Dictations"
        case .settings: nil
        }
    }
}

/// Owns the search UI that belongs to the main window rather than either detail
/// page. SwiftUI owns the toolbar itself; this object only bridges the native
/// search field's value and focus, so AppKit and SwiftUI never compete for the
/// window's `NSToolbar` identity.
@MainActor
final class MainWindowSearchCoordinator: NSObject, ObservableObject {
    @Published private(set) var dictationQuery = ""

    private weak var searchControl: MainWindowSearchControl?
    private weak var searchField: NSSearchField?
    private var section: MainSection = .dictation

    func attach(to control: MainWindowSearchControl) {
        let field = control.searchField
        searchControl = control
        if searchField !== field {
            searchField?.delegate = nil
            searchField = field
            field.delegate = self
            field.identifier = NSUserInterfaceItemIdentifier("dictation-search")
            field.sendsSearchStringImmediately = true
            field.stringValue = dictationQuery
        }
        applySection()
    }

    func update(section: MainSection) {
        guard self.section != section else {
            applySection()
            return
        }
        self.section = section
        applySection()
    }

    func focusSearch() {
        guard section.searchPrompt != nil,
              let searchField else { return }
        searchField.selectText(nil)
    }

    private func applySection() {
        guard let searchControl, let searchField else { return }
        if searchField.window?.title != section.windowTitle {
            searchField.window?.title = section.windowTitle
        }
        let searchIsAvailable = section.searchPrompt != nil
        if !searchIsAvailable, searchField.currentEditor() != nil {
            searchField.window?.makeFirstResponder(nil)
        }
        let prompt = section.searchPrompt ?? ""
        if searchField.placeholderString != prompt {
            searchField.placeholderString = prompt
        }
        searchField.isEnabled = searchIsAvailable
        searchControl.isHidden = !searchIsAvailable
        searchControl.acceptsInteraction = searchIsAvailable
        searchControl.setAccessibilityElement(searchIsAvailable)
        searchControl.setAccessibilityHidden(!searchIsAvailable)
        searchField.setAccessibilityElement(searchIsAvailable)
        searchField.setAccessibilityHidden(!searchIsAvailable)
    }

    func windowDidChange() {
        applySection()
    }
}

extension MainWindowSearchCoordinator: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField,
              field === searchField,
              dictationQuery != field.stringValue else { return }
        dictationQuery = field.stringValue
    }
}

/// A native field inside a SwiftUI-owned, permanently present toolbar item. The
/// representable itself always keeps the same width. Settings hides and disables
/// the inner control rather than removing the item, so toolbar and title-bar
/// geometry remain unchanged while the search is semantically absent.
struct MainWindowSearchField: NSViewRepresentable {
    let searchCoordinator: MainWindowSearchCoordinator

    func makeNSView(context: Context) -> MainWindowSearchControl {
        let control = MainWindowSearchControl()
        control.onWindowChange = { [weak searchCoordinator] in
            searchCoordinator?.windowDidChange()
        }
        searchCoordinator.attach(to: control)
        return control
    }

    func updateNSView(_ control: MainWindowSearchControl, context: Context) {
        searchCoordinator.attach(to: control)
    }

    static func dismantleNSView(_ control: MainWindowSearchControl, coordinator: ()) {
        control.onWindowChange = nil
        control.searchField.delegate = nil
    }
}

@MainActor
final class MainWindowSearchControl: NSGlassEffectView {
    // Liquid Glass lives inside the permanently installed toolbar item, because
    // changing SwiftUI's toolbar background preference by destination makes
    // SwiftUI reconcile window chrome while hiding this inner view does not.
    //
    // The field keeps its bezel. Unbezeled, AppKit mis-aligns its text, drops
    // the magnifier while editing, and draws a rectangular focus ring inside the
    // round capsule; the bezel itself draws nothing visible over the glass.
    let searchField = NSSearchField()
    var acceptsInteraction = true
    var onWindowChange: (@MainActor () -> Void)?

    /// The glass view sizes its content view to fill the capsule, and the field
    /// must not fill it, so a plain container carries the centred field.
    private let fieldContainer = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        style = .regular
        effectIsInteractive = true
        fieldContainer.addSubview(searchField)
        contentView = fieldContainer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 36)
    }

    override func layout() {
        super.layout()
        cornerRadius = bounds.height / 2
        fieldContainer.frame = bounds

        // Centre the field at the height it asks for rather than stretching it
        // to the capsule, which is what pushed the text to the top edge.
        let naturalHeight = searchField.cell?.cellSize.height ?? searchField.fittingSize.height
        let horizontalInset: CGFloat = 8
        searchField.frame = NSRect(
            x: horizontalInset,
            y: ((bounds.height - naturalHeight) / 2).rounded(),
            width: max(0, bounds.width - horizontalInset * 2),
            height: naturalHeight
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        acceptsInteraction ? super.hitTest(point) : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }
}
