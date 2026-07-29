import SwiftUI

/// A destination in the main window's sidebar.
///
/// Settings is deliberately not one. Keeping it out of the main window is what
/// makes every destination here searchable, which in turn is what keeps
/// SwiftUI's toolbar — and therefore the title-bar geometry — alive across
/// selection changes without any AppKit toolbar bridging.
enum MainSection: Hashable {
    case dictation

    var title: String {
        switch self {
        case .dictation: "Dictation"
        }
    }

    var searchPrompt: String {
        switch self {
        case .dictation: "Search Dictations"
        }
    }
}
