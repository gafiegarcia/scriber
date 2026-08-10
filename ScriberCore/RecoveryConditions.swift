import Foundation

/// What a recovery condition is resolved through. The window maps these onto its
/// own Settings destinations; this stays free of any window vocabulary so the
/// policy below can be tested without one.
public enum RecoveryConditionKind: Hashable, Sendable {
    case permissions
    case apiKey
    case usage
}

/// One thing that is wrong and stays wrong until it is fixed.
///
/// Deliberately not a toast. A toast is transient by contract — it appears, says
/// its piece and leaves — and a condition that outlives its own announcement
/// breaks that contract. These belong to the window's chrome; transient outcomes
/// belong to the toast stack.
public struct RecoveryCondition: Identifiable, Equatable, Sendable {
    public let kind: RecoveryConditionKind
    public let title: String
    public let message: String
    public let actionTitle: String
    public let accessibilityIdentifier: String

    public var id: RecoveryConditionKind { kind }

    public init(
        kind: RecoveryConditionKind,
        title: String,
        message: String,
        actionTitle: String,
        accessibilityIdentifier: String
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

public enum RecoveryConditions {
    /// Every unresolved condition, worst first.
    ///
    /// All of them, always: the floating pill shows one recovery at a time, and
    /// what makes that acceptable is the window showing every condition at once.
    /// Collapsing this to a single entry would leave the second one with nowhere
    /// to appear.
    ///
    /// Missing permissions outrank an unusable credential, matching the pill:
    /// without Microphone or Accessibility there is nothing for a working key to
    /// do. Before onboarding finishes there are no conditions at all — setup is
    /// where those states are being resolved.
    public static func current(
        onboardingComplete: Bool,
        permission: PermissionReadiness,
        credential: CredentialReadiness
    ) -> [RecoveryCondition] {
        guard onboardingComplete else { return [] }
        var conditions: [RecoveryCondition] = []

        if !permission.isReady {
            conditions.append(
                RecoveryCondition(
                    kind: .permissions,
                    title: "Dictation is unavailable",
                    message: permission.recoveryMessage,
                    actionTitle: "Review Permissions",
                    accessibilityIdentifier: "permission-recovery-banner"
                )
            )
        }

        if !credential.isReady {
            conditions.append(
                RecoveryCondition(
                    kind: credential.resolvesInUsageSettings ? .usage : .apiKey,
                    title: credential.title,
                    message: credential.recoveryMessage,
                    actionTitle: credential.resolvesInUsageSettings ? "View Credits" : "Update Key",
                    accessibilityIdentifier: "credential-recovery-banner"
                )
            )
        }

        return conditions
    }
}
