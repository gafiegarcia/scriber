import Foundation
import Testing
@testable import ScriberCore

@Suite("Release versions")
struct ReleaseVersionTests {
    @Test("A tag's leading v is not part of the version")
    func stripsTagPrefix() {
        #expect(ReleaseVersion("v0.9.0") == ReleaseVersion("0.9.0"))
    }

    /// The case string comparison gets wrong, and the reason this type exists.
    @Test("A double-digit minor sorts above a single-digit one")
    func ordersDoubleDigits() throws {
        let nine = try #require(ReleaseVersion("0.9.0"))
        let ten = try #require(ReleaseVersion("0.10.0"))
        #expect(nine < ten)
        #expect(!(ten < nine))
    }

    @Test("Missing trailing components read as zero")
    func padsMissingComponents() throws {
        #expect(ReleaseVersion("0.9") == ReleaseVersion("0.9.0"))
        let short = try #require(ReleaseVersion("0.9"))
        let patch = try #require(ReleaseVersion("0.9.1"))
        #expect(short < patch)
    }

    @Test("A suffix orders by the numeric line before it")
    func ignoresSuffix() throws {
        let candidate = try #require(ReleaseVersion("0.9.0-rc.1"))
        #expect(candidate == ReleaseVersion("0.9.0"))
    }

    @Test("Text with no numeric version is not a version")
    func rejectsNonVersions() {
        #expect(ReleaseVersion("") == nil)
        #expect(ReleaseVersion("nightly") == nil)
    }

    @Test("Ordering is transitive across a realistic release line")
    func ordersARealisticLine() {
        let line = ["0.7.0", "0.8.8", "0.9.0", "0.10.0", "1.0.0"].compactMap(ReleaseVersion.init)
        #expect(line.count == 5)
        #expect(line == line.sorted())
    }
}

@Suite("Update availability")
struct UpdateAvailabilityTests {
    private let releaseURL = URL(string: "https://github.com/gafiegarcia/scriber/releases/tag/v0.9.1")!

    private func release(_ tag: String) -> GitHubRelease {
        GitHubRelease(tagName: tag, htmlURL: releaseURL)
    }

    @Test("A newer tag is offered")
    func offersNewer() throws {
        let outcome = try UpdateChecker.newerRelease(currentVersion: "0.9.0", release: release("v0.9.1"))
        #expect(outcome == AvailableUpdate(version: "0.9.1", url: releaseURL))
    }

    @Test("The same version is up to date")
    func sameIsUpToDate() throws {
        let outcome = try UpdateChecker.newerRelease(currentVersion: "0.9.0", release: release("v0.9.0"))
        #expect(outcome == nil)
    }

    /// A local build ahead of the last release must not be told to downgrade.
    @Test("A running version ahead of the latest release is up to date")
    func aheadIsUpToDate() throws {
        let outcome = try UpdateChecker.newerRelease(currentVersion: "0.10.0", release: release("v0.9.0"))
        #expect(outcome == nil)
    }

    @Test("A tag this code cannot rank is an error, not silence")
    func unrankableTagThrows() {
        #expect(throws: UpdateCheckError.unparsableVersion("nightly")) {
            try UpdateChecker.newerRelease(currentVersion: "0.9.0", release: release("nightly"))
        }
    }
}

@Suite("Update check schedule")
struct UpdateCheckScheduleTests {
    @Test("A first run is always due")
    func firstRunIsDue() {
        #expect(UpdateChecker.isDue(lastCheck: nil))
    }

    @Test("A check within the interval is not due again")
    func recentIsNotDue() {
        let now = Date()
        let anHourAgo = now.addingTimeInterval(-60 * 60)
        #expect(!UpdateChecker.isDue(lastCheck: anHourAgo, now: now))
    }

    @Test("A check older than the interval is due")
    func staleIsDue() {
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-UpdateChecker.checkInterval * 2)
        #expect(UpdateChecker.isDue(lastCheck: twoDaysAgo, now: now))
    }

    /// A clock that moved backwards leaves a future timestamp behind; that must
    /// not wedge the check off forever.
    @Test("A future timestamp is not due, and recovers once the interval passes")
    func futureTimestamp() {
        let now = Date()
        let tomorrow = now.addingTimeInterval(60 * 60 * 24)
        #expect(!UpdateChecker.isDue(lastCheck: tomorrow, now: now))
        #expect(UpdateChecker.isDue(lastCheck: tomorrow, now: tomorrow.addingTimeInterval(UpdateChecker.checkInterval)))
    }
}
