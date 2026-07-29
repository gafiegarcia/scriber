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
    /// still keeps its toolbar; only the native search item becomes hidden.
    var searchPrompt: String? {
        switch self {
        case .dictation: "Search Dictations"
        case .settings: nil
        }
    }
}

/// Owns the search UI that belongs to the main window rather than either detail
/// page. Keeping this toolbar alive is what makes the traffic lights, title,
/// sidebar, and detail content retain one geometry while workspaces change.
@MainActor
final class MainWindowSearchCoordinator: NSObject, ObservableObject {
    @Published private(set) var dictationQuery = ""

    private static let toolbarIdentifier = NSToolbar.Identifier("ScriberMainWindowToolbar")
    private static let searchItemIdentifier = NSToolbarItem.Identifier("ScriberMainWindowSearch")

    private weak var window: NSWindow?
    private weak var searchItem: NSToolbarItem?
    private weak var searchField: NSSearchField?
    private var section: MainSection = .dictation

    private lazy var toolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }()

    func attach(to window: NSWindow) {
        self.window = window
        if window.toolbarStyle != .unified { window.toolbarStyle = .unified }
        if window.titleVisibility != .visible { window.titleVisibility = .visible }
        if window.title != section.windowTitle { window.title = section.windowTitle }
        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
        if !toolbar.isVisible { toolbar.isVisible = true }
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
              let searchItem,
              !searchItem.isHidden,
              let searchField else { return }
        searchField.selectText(nil)
    }

    private func applySection() {
        if window?.title != section.windowTitle {
            window?.title = section.windowTitle
        }

        guard let searchItem else { return }
        let searchIsAvailable = section.searchPrompt != nil
        if !searchIsAvailable, searchField?.currentEditor() != nil {
            window?.makeFirstResponder(nil)
        }
        let prompt = section.searchPrompt ?? ""
        let label = section.searchPrompt ?? "Search"
        if searchField?.placeholderString != prompt {
            searchField?.placeholderString = prompt
        }
        if searchItem.label != label { searchItem.label = label }
        if searchItem.paletteLabel != label { searchItem.paletteLabel = label }
        if searchItem.toolTip != section.searchPrompt { searchItem.toolTip = section.searchPrompt }
        if searchItem.isHidden == searchIsAvailable {
            searchItem.isHidden = !searchIsAvailable
        }
    }
}

extension MainWindowSearchCoordinator: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .flexibleSpace, Self.searchItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.searchItemIdentifier else { return nil }

        let prompt = section.searchPrompt
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 280, height: 0))
        field.delegate = self
        field.identifier = NSUserInterfaceItemIdentifier("dictation-search")
        field.placeholderString = prompt ?? ""
        field.stringValue = dictationQuery
        field.sendsSearchStringImmediately = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = field
        item.label = prompt ?? "Search"
        item.paletteLabel = item.label
        item.toolTip = prompt
        item.isHidden = prompt == nil
        searchItem = item
        searchField = field
        return item
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

/// Finds the `NSWindow` SwiftUI created without replacing the scene or polling
/// global windows by title. Installation waits until SwiftUI's initial window
/// transaction has yielded; replacing its placeholder toolbar synchronously while
/// `AppKitWindowController` is updating constraints raises an `NSRangeException`.
struct MainWindowAccessor: NSViewRepresentable {
    let onWindowAvailable: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        WindowAccessorView(onWindowAvailable: onWindowAvailable)
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindowAvailable = onWindowAvailable
    }
}

@MainActor
final class WindowAccessorView: NSView {
    var onWindowAvailable: @MainActor (NSWindow) -> Void
    private var installationTask: Task<Void, Never>?

    init(onWindowAvailable: @escaping @MainActor (NSWindow) -> Void) {
        self.onWindowAvailable = onWindowAvailable
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installationTask?.cancel()
        guard let window else { return }
        installationTask = Task { @MainActor [weak self, weak window] in
            await Task.yield()
            guard let self, let window, !Task.isCancelled else { return }
            onWindowAvailable(window)
        }
    }
}
