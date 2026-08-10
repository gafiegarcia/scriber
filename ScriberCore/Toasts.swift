import Foundation

/// What an outcome was, which is what tints it.
///
/// Shared vocabulary on purpose: the floating pill is due the same treatment,
/// and one mapping from outcome to colour is what keeps the two surfaces saying
/// the same thing in the same colour.
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
    public let systemImage: String
    public let tone: ToastTone
    public let duration: TimeInterval
    public let accessibilityIdentifier: String

    public init(
        id: UUID = UUID(),
        title: String,
        systemImage: String,
        tone: ToastTone,
        duration: TimeInterval,
        accessibilityIdentifier: String
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.duration = duration
        self.accessibilityIdentifier = accessibilityIdentifier
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
}
