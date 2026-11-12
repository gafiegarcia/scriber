import Foundation
import Testing
@testable import ScriberCore

@Suite("Build numbers")
struct BuildNumberTests {
    @Test("A longer build number is newer, which text ordering gets wrong")
    func numericOrdering() {
        #expect(BuildNumber.isNewer("100", than: "99"))
        #expect(!BuildNumber.isNewer("99", than: "100"))
    }

    @Test("Equal builds are not newer, however they are written")
    func equal() {
        #expect(!BuildNumber.isNewer("400", than: "400"))
        #expect(!BuildNumber.isNewer("400.0", than: "400"))
    }

    @Test("An unreadable build is never newer, and nothing is newer than one")
    func unreadable() {
        #expect(!BuildNumber.isNewer("nightly", than: "400"))
        #expect(!BuildNumber.isNewer("401", than: "nightly"))
        #expect(!BuildNumber.isNewer("", than: "400"))
    }
}

@Suite("Staged update")
struct StagedUpdateTests {
    @Test("A staged build newer than the running one is still pending")
    func pending() {
        #expect(StagedUpdate(version: "0.10.1", build: "412").isPending(runningBuild: "410"))
    }

    @Test("Once the staged build is the running one, nothing is pending")
    func installed() {
        #expect(!StagedUpdate(version: "0.10.1", build: "412").isPending(runningBuild: "412"))
        #expect(!StagedUpdate(version: "0.10.1", build: "412").isPending(runningBuild: "415"))
    }
}

@Suite("Update relaunch")
struct UpdateRelaunchTests {
    @Test("The relaunch into the recorded build restores what was recorded")
    func appliesToItsBuild() {
        #expect(UpdateRelaunch(build: "405", windows: [.main]).applies(toRunningBuild: "405"))
    }

    @Test("A record from an update that never relaunched is ignored by any other build")
    func ignoredElsewhere() {
        let record = UpdateRelaunch(build: "405", windows: [.main])
        #expect(!record.applies(toRunningBuild: "404"))
        #expect(!record.applies(toRunningBuild: "406"))
    }

    @Test("Each window is recorded once, in a fixed order")
    func normalizesWindows() {
        let record = UpdateRelaunch(build: "405", windows: [.settings, .main, .settings])
        #expect(record.windows == [.main, .settings])
    }
}

@Suite("Automatically update migration")
struct AutomaticUpdatePreferenceTests {
    @Test("Someone who switched update checks off starts with Automatically update off")
    func carriesOff() {
        #expect(!AutomaticUpdatePreference.resolve(stored: nil, legacyAutomaticChecks: false))
    }

    @Test("Everyone else starts with it on, new installs included")
    func defaultsOn() {
        #expect(AutomaticUpdatePreference.resolve(stored: nil, legacyAutomaticChecks: true))
        #expect(AutomaticUpdatePreference.resolve(stored: nil, legacyAutomaticChecks: nil))
    }

    @Test("A choice already made under the new switch wins over the old one")
    func storedWins() {
        #expect(AutomaticUpdatePreference.resolve(stored: true, legacyAutomaticChecks: false))
        #expect(!AutomaticUpdatePreference.resolve(stored: false, legacyAutomaticChecks: true))
    }
}

@Suite("Update status line")
struct UpdateStatusLineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func resolve(
        offer: UpdateOffer = .none,
        error: String? = nil,
        recent: RecentUpdate? = nil,
        lastCheck: Date? = nil
    ) -> UpdateStatusLine {
        UpdateStatusLine.resolve(
            offer: offer,
            checkError: error,
            recentUpdate: recent,
            lastCheck: lastCheck,
            now: now,
            calendar: calendar
        )
    }

    @Test("A waiting update outranks a failed check and a recent update")
    func offerWins() {
        let recent = RecentUpdate(version: "0.10.0", date: now)
        #expect(resolve(offer: .ready(version: "0.10.1"), error: "x", recent: recent) == .ready(version: "0.10.1"))
        #expect(resolve(offer: .available(version: "0.10.1"), error: "x") == .available(version: "0.10.1"))
        #expect(resolve(offer: .downloading(version: "0.10.1"), recent: recent) == .downloading(version: "0.10.1"))
    }

    @Test("A failed check is reported before an earlier update")
    func errorBeforeRecent() {
        let recent = RecentUpdate(version: "0.10.0", date: now)
        #expect(resolve(error: "Could not reach GitHub", recent: recent) == .failed("Could not reach GitHub"))
    }

    @Test("An update from today or yesterday is named, and one older is not")
    func recentUpdateWindow() {
        let lastCheck = now.addingTimeInterval(-60)
        #expect(resolve(recent: RecentUpdate(version: "0.10.1", date: now), lastCheck: lastCheck)
            == .updated(version: "0.10.1", day: "today"))
        #expect(resolve(recent: RecentUpdate(version: "0.10.1", date: now.addingTimeInterval(-86_400)), lastCheck: lastCheck)
            == .updated(version: "0.10.1", day: "yesterday"))
        #expect(resolve(recent: RecentUpdate(version: "0.10.1", date: now.addingTimeInterval(-3 * 86_400)), lastCheck: lastCheck)
            == .current(lastChecked: lastCheck))
    }

    @Test("Without a check that got an answer, the line never claims to be current")
    func neverChecked() {
        #expect(resolve() == .neverChecked)
    }

    @Test("What's New is offered for an available update and a recent one, not a ready one")
    func whatsNew() {
        #expect(UpdateStatusLine.available(version: "0.10.1").whatsNewVersion == "0.10.1")
        #expect(UpdateStatusLine.updated(version: "0.10.1", day: "today").whatsNewVersion == "0.10.1")
        #expect(UpdateStatusLine.ready(version: "0.10.1").whatsNewVersion == nil)
    }

    @Test("What's New opens the version's release page")
    func releasePage() {
        #expect(UpdateLinks.releasePage(version: "0.10.1").absoluteString
            == "https://github.com/gafiegarcia/scriber/releases/tag/v0.10.1")
    }
}
