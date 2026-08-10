import Testing
@testable import ScriberCore

@Suite("Recovery conditions")
struct RecoveryConditionTests {
    private let blockedPermissions = PermissionReadiness(missingPermissions: [.microphone, .accessibility])

    @Test("Nothing is wrong before onboarding finishes")
    func silentDuringOnboarding() {
        let conditions = RecoveryConditions.current(
            onboardingComplete: false,
            permission: blockedPermissions,
            credential: .missingAPIKey
        )
        #expect(conditions.isEmpty)
    }

    @Test("A ready app reports no conditions")
    func silentWhenReady() {
        let conditions = RecoveryConditions.current(
            onboardingComplete: true,
            permission: PermissionReadiness(missingPermissions: []),
            credential: .ready
        )
        #expect(conditions.isEmpty)
    }

    /// The floating pill presents one recovery at a time, and what licenses that
    /// is the window presenting every condition at once.
    @Test("Both blocked states are reported together, permissions first")
    func reportsEveryCondition() {
        let conditions = RecoveryConditions.current(
            onboardingComplete: true,
            permission: blockedPermissions,
            credential: .missingAPIKey
        )
        #expect(conditions.count == 2)
        #expect(conditions.map(\.kind) == [.permissions, .apiKey])
    }

    @Test("Resolving one condition leaves the other standing")
    func keepsTheRemainingCondition() {
        let conditions = RecoveryConditions.current(
            onboardingComplete: true,
            permission: PermissionReadiness(missingPermissions: []),
            credential: .invalidAPIKey
        )
        #expect(conditions.map(\.kind) == [.apiKey])
        #expect(conditions[0].title == CredentialReadiness.invalidAPIKey.title)
        #expect(conditions[0].actionTitle == "Update Key")
    }

    /// Exhausted credit is resolved at ElevenLabs, not in Scriber's key field.
    @Test("Exhausted credit routes to usage rather than the key")
    func routesExhaustedCreditToUsage() {
        let conditions = RecoveryConditions.current(
            onboardingComplete: true,
            permission: PermissionReadiness(missingPermissions: []),
            credential: .creditsExhausted
        )
        #expect(conditions.map(\.kind) == [.usage])
        #expect(conditions[0].actionTitle == "View Usage")
    }

    @Test("Condition copy comes from readiness, not from a second copy of it")
    func reusesReadinessCopy() {
        let conditions = RecoveryConditions.current(
            onboardingComplete: true,
            permission: blockedPermissions,
            credential: .ready
        )
        #expect(conditions[0].message == blockedPermissions.recoveryMessage)
    }

    /// The visual-inspection procedure finds these by name and no UI suite would
    /// catch a rename.
    @Test("Accessibility identifiers are the ones inspection looks for")
    func keepsAccessibilityIdentifiers() {
        let conditions = RecoveryConditions.current(
            onboardingComplete: true,
            permission: blockedPermissions,
            credential: .missingAPIKey
        )
        #expect(conditions[0].accessibilityIdentifier == "permission-recovery-banner")
        #expect(conditions[1].accessibilityIdentifier == "credential-recovery-banner")
    }
}
