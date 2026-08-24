import Foundation

/// What a recovery condition is resolved through. The window maps these onto its
/// own Settings destinations; this stays free of any window vocabulary so the
/// policy below can be tested without one.
public enum RecoveryConditionKind: Hashable, Sendable {
    case setupUnfinished
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
    /// Every unresolved condition, worst first — all of them, always. The floating
    /// pill shows one recovery at a time, and what makes that acceptable is the
    /// window showing every condition at once, so do not collapse this to one entry.
    ///
    /// Missing permissions outrank an unusable credential, matching the pill: with
    /// no Microphone or Accessibility there is nothing for a working key to do.
    /// Unfinished setup outranks both and replaces them, since setup is where all
    /// of them get resolved. It reports at all because the setup window can be
    /// closed with ⌘W, leaving nothing granted and nothing saying why.
    public static func current(
        onboardingComplete: Bool,
        permission: PermissionReadiness,
        credential: CredentialReadiness
    ) -> [RecoveryCondition] {
        guard onboardingComplete else {
            return [
                RecoveryCondition(
                    kind: .setupUnfinished,
                    title: "Setup is not finished",
                    message: "Scriber cannot dictate until setup is done. It takes a minute.",
                    actionTitle: "Finish Setup",
                    accessibilityIdentifier: "setup-unfinished-banner"
                )
            ]
        }
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
