import Foundation

/// What an outcome was, which is what tints it.
///
/// Shared vocabulary on purpose: the floating pill is due the same treatment,
/// and one mapping from outcome to color is what keeps the two surfaces saying
/// the same thing in the same color.
public enum ToastTone: Hashable, Sendable {
    case success
    case warning
    case failure
    case neutral
}

/// A moment worth announcing and then forgetting.
///
/// Everything here is transient by construction — there is no way to express a
/// toast that never leaves. Conditions that persist until resolved are the
/// window chrome's job; see `RecoveryConditions`.
public struct Toast: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    /// Set beside the title: how to act on what the title reports.
    public let hint: String?
    public let systemImage: String
    public let tone: ToastTone
    public let duration: TimeInterval
    public let accessibilityIdentifier: String
    /// The undo action this toast announces. Undoing it dismisses the toast, and
    /// a newer announcement of the same action replaces it.
    public let undoActionName: String?

    public init(
        id: UUID = UUID(),
        title: String,
        hint: String? = nil,
        systemImage: String,
        tone: ToastTone,
        duration: TimeInterval,
        accessibilityIdentifier: String,
        undoActionName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.hint = hint
        self.systemImage = systemImage
        self.tone = tone
        self.duration = duration
        self.accessibilityIdentifier = accessibilityIdentifier
        self.undoActionName = undoActionName
    }

    public static func transcriptCopied(id: UUID = UUID()) -> Toast {
        Toast(
            id: id,
            title: "Transcript copied",
            systemImage: "checkmark",
            tone: .success,
            duration: 1.4,
            accessibilityIdentifier: "dictation-copy-toast"
        )
    }

    public static func dictationDeleted(id: UUID = UUID()) -> Toast {
        Toast(
            id: id,
            title: "Dictation deleted",
            hint: "⌘Z to undo",
            systemImage: "trash",
            tone: .neutral,
            duration: 5,
            accessibilityIdentifier: "dictation-delete-toast",
            undoActionName: UndoActionName.deleteDictation
        )
    }
}

/// Names shared by whoever registers an undo and whoever announces it, so the
/// two cannot drift apart.
public enum UndoActionName {
    public static let deleteDictation = "Delete Dictation"
}

public enum ToastStack {
    /// Beyond this the stack stops reading as a stack and starts covering the
    /// content it is reporting on.
    public static let maximumVisible = 3

    /// The most recent toasts, oldest first, so the newest sits nearest the
    /// corner it grows from.
    public static func visible(_ toasts: [Toast]) -> [Toast] {
        Array(toasts.suffix(maximumVisible))
    }

    /// The stack after `toast` arrives. An undo announcement replaces any earlier
    /// one of the same action, so clearing out a history shows one toast rather
    /// than a column of identical ones.
    public static func posting(_ toast: Toast, onto toasts: [Toast]) -> [Toast] {
        var remaining = toasts
        if let name = toast.undoActionName {
            remaining.removeAll { $0.undoActionName == name }
        }
        return remaining + [toast]
    }
}
