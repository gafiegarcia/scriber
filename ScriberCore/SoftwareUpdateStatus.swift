import Foundation

/// The update Sparkle is holding, as Settings and the menu bar describe it.
public enum UpdateOffer: Equatable, Sendable {
    case none
    /// Found while **Automatically update** is off, waiting for **Install**.
    case available(version: String)
    /// Downloading — after **Install**, or after a check made with the switch on.
    case downloading(version: String)
    /// Downloaded and prepared, installing at the next screen lock or quit.
    case ready(version: String)

    public var version: String? {
        switch self {
        case .none: nil
        case .available(let version), .downloading(let version), .ready(let version): version
        }
    }
}

/// An update that has been downloaded and prepared, remembered across launches so
/// a launch that finds it still uninstalled — Scriber crashed, or was force-quit
/// before the installer ran — can install it straight away.
public struct StagedUpdate: Codable, Equatable, Sendable {
    public let version: String
    /// `CFBundleVersion`, which is what Sparkle compares.
    public let build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// Whether the running build is still older than the one that was staged.
    public func isPending(runningBuild: String) -> Bool {
        BuildNumber.isNewer(build, than: runningBuild)
    }
}

/// What was on screen when an update relaunched Scriber, so the new version puts
/// back exactly that and nothing more.
public struct UpdateRelaunch: Codable, Equatable, Sendable {
    public enum Window: String, Codable, Sendable, CaseIterable {
        case main
        case settings
    }

    /// The build being installed, so a record left by an update that never
    /// relaunched is not taken up by some later, unrelated launch.
    public let build: String
    public let windows: [Window]

    /// Keeps one of each window, in a fixed order, whatever order AppKit listed
    /// them in.
    public init(build: String, windows: [Window]) {
        self.build = build
        self.windows = Window.allCases.filter(windows.contains)
    }

    /// Whether this launch is the relaunch the record was written for.
    public func applies(toRunningBuild runningBuild: String) -> Bool {
        !BuildNumber.isNewer(build, than: runningBuild) && !BuildNumber.isNewer(runningBuild, than: build)
    }
}

/// A launch that found itself newer than the launch before it.
public struct RecentUpdate: Codable, Equatable, Sendable {
    public let version: String
    public let date: Date

    public init(version: String, date: Date) {
        self.version = version
        self.date = date
    }

    /// "today" or "yesterday", and nil once neither is true. An update that
    /// installs at a screen lock overnight is first seen the next morning, so
    /// "today" alone would hide most of them.
    public func dayPhrase(now: Date, calendar: Calendar = .current) -> String? {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
              calendar.isDate(date, inSameDayAs: yesterday) else { return nil }
        return "yesterday"
    }
}

public enum BuildNumber {
    /// Compares dotted numeric components, so `100` is newer than `99` — a text
    /// comparison puts it below. Missing trailing components read as zero, and a
    /// build that cannot be read is never newer than anything.
    public static func isNewer(_ candidate: String, than reference: String) -> Bool {
        guard let left = components(candidate), let right = components(reference) else { return false }
        for index in 0..<max(left.count, right.count) {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func components(_ text: String) -> [Int]? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var values: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            values.append(value)
        }
        return values
    }
}

public enum UpdateLinks {
    /// What's New for a version: its GitHub release page.
    public static func releasePage(version: String) -> URL {
        URL(string: "https://github.com/gafiegarcia/scriber/releases/tag/v\(version)")
            ?? URL(string: "https://github.com/gafiegarcia/scriber/releases")!
    }
}

public enum AutomaticUpdatePreference {
    /// The **Automatically update** switch at launch. Someone who had switched
    /// "Check for updates automatically" off starts with it off; everyone else,
    /// and every new install, starts with it on.
    public static func resolve(stored: Bool?, legacyAutomaticChecks: Bool?) -> Bool {
        stored ?? legacyAutomaticChecks ?? true
    }
}

/// The line under Settings' version row.
public enum UpdateStatusLine: Equatable, Sendable {
    case ready(version: String)
    case available(version: String)
    case downloading(version: String)
    case updated(version: String, day: String)
    case failed(String)
    case current(lastChecked: Date)
    case neverChecked

    /// An update waiting outranks everything, because it is the one line that
    /// asks for something. A failed check comes next: it answers a button the
    /// user just pressed. Neither an update installed yesterday nor the time of
    /// the last check says anything a waiting update does not.
    public static func resolve(
        offer: UpdateOffer,
        checkError: String?,
        recentUpdate: RecentUpdate?,
        lastCheck: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Self {
        switch offer {
        case .ready(let version): return .ready(version: version)
        case .available(let version): return .available(version: version)
        case .downloading(let version): return .downloading(version: version)
        case .none: break
        }
        if let checkError { return .failed(checkError) }
        if let recentUpdate, let day = recentUpdate.dayPhrase(now: now, calendar: calendar) {
            return .updated(version: recentUpdate.version, day: day)
        }
        if let lastCheck { return .current(lastChecked: lastCheck) }
        return .neverChecked
    }

    /// The version this line offers **What's New** for, if any.
    public var whatsNewVersion: String? {
        switch self {
        case .available(let version), .updated(let version, _): version
        default: nil
        }
    }
}
