import Testing
@testable import ScriberCore

@Suite("Recovery conditions")
struct RecoveryConditionTests {
    private let blockedPermissions = PermissionReadiness(missingPermissions: [.microphone, .accessibility])

    /// The setup window closes with ⌘W, so this state is reachable and has to say
    /// something. Reporting nothing leaves an abandoned setup looking like an app
    /// that simply does not work.
    @Test("Unfinished setup is itself the one thing reported")
    func unfinishedSetupIsReported() throws {
        let conditions = RecoveryConditions.current(
            onboardingDismissed: false,
            servicesEnabled: false,
            permission: blockedPermissions,
            credential: .missingAPIKey
        )
        let only = try #require(conditions.first)
        #expect(conditions.count == 1)
        #expect(only.kind == .setupUnfinished)
    }

    /// Setup resolves permissions and the key on its way through, so listing
    /// them beside it would offer three routes to the same window.
    @Test("Unfinished setup hides the conditions it is going to fix")
    func unfinishedSetupSubsumesTheRest() {
        let conditions = RecoveryConditions.current(
            onboardingDismissed: false,
            servicesEnabled: false,
            permission: blockedPermissions,
            credential: .missingAPIKey
        )
        #expect(!conditions.contains { $0.kind == .permissions })
        #expect(!conditions.contains { $0.kind == .apiKey })
    }

    /// Closing setup on its dictation step leaves everything granted and the
    /// shortcut live, so the banner must not claim dictation is unavailable. It is
    /// the state the services flag exists to make reachable, and the only one
    /// where an unfinished setup is not also a broken app.
    @Test("Setup left at its dictation step does not claim dictation is unavailable")
    func unfinishedSetupWithServicesRunningSaysSo() throws {
        let stuck = RecoveryConditions.current(
            onboardingDismissed: false,
            servicesEnabled: false,
            permission: blockedPermissions,
            credential: .missingAPIKey
        )
        let working = RecoveryConditions.current(
            onboardingDismissed: false,
            servicesEnabled: true,
            permission: PermissionReadiness(missingPermissions: []),
            credential: .ready
        )
        #expect(try #require(working.first).kind == .setupUnfinished)
        #expect(working.count == 1)
        #expect(try #require(working.first).message != #require(stuck.first).message)
        #expect(!(try #require(working.first).message.contains("cannot dictate")))
        #expect(try #require(stuck.first).message.contains("cannot dictate"))
    }

    @Test("A ready app reports no conditions")
    func silentWhenReady() {
        let conditions = RecoveryConditions.current(
            onboardingDismissed: true,
            servicesEnabled: true,
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
            onboardingDismissed: true,
            servicesEnabled: true,
            permission: blockedPermissions,
            credential: .missingAPIKey
        )
        #expect(conditions.count == 2)
        #expect(conditions.map(\.kind) == [.permissions, .apiKey])
    }

    @Test("Resolving one condition leaves the other standing")
    func keepsTheRemainingCondition() {
        let conditions = RecoveryConditions.current(
            onboardingDismissed: true,
            servicesEnabled: true,
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
            onboardingDismissed: true,
            servicesEnabled: true,
            permission: PermissionReadiness(missingPermissions: []),
            credential: .creditsExhausted
        )
        #expect(conditions.map(\.kind) == [.usage])
        #expect(conditions[0].actionTitle == "View Credits")
    }

    @Test("Condition copy comes from readiness, not from a second copy of it")
    func reusesReadinessCopy() {
        let conditions = RecoveryConditions.current(
            onboardingDismissed: true,
            servicesEnabled: true,
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
            onboardingDismissed: true,
            servicesEnabled: true,
            permission: blockedPermissions,
            credential: .missingAPIKey
        )
        #expect(conditions[0].accessibilityIdentifier == "permission-recovery-banner")
        #expect(conditions[1].accessibilityIdentifier == "credential-recovery-banner")
    }
}
