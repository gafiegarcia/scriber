import SwiftUI

/// A workspace the main window can show.
///
/// Settings is deliberately not one: it is its own window, which is what makes
/// every workspace here searchable, and an unconditional search item is what
/// keeps SwiftUI's toolbar alive across workspace changes.
enum Workspace: Hashable, CaseIterable, Identifiable {
    case dictation

    var id: Self { self }

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
