import Foundation

// Asks GitHub Releases whether a newer Scriber than the running one exists.
// Scriber does not install anything itself; the answer routes the user to the
// release page.

/// A released version, compared component by component.
///
/// Ordering these as strings puts `0.10.0` below `0.9.0`, which is wrong the
/// first time a minor number reaches double digits.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]

    /// Accepts the leading `v` that tags carry and `CFBundleShortVersionString`
    /// does not, and stops at the first non-numeric character so a suffix such
    /// as `-rc.1` orders by its numeric line rather than failing to parse.
    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        let numeric = value.prefix { $0.isNumber || $0 == "." }
        let parts = numeric.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let component = Int(part) else { return nil }
            parsed.append(component)
        }
        components = parsed
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    /// Missing trailing components read as zero, so `0.9` and `0.9.0` are the
    /// same version rather than merely neither-greater-nor-less.
    private static func component(_ version: Self, at index: Int) -> Int {
        index < version.components.count ? version.components[index] : 0
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        return (0..<width).allSatisfy { component(lhs, at: $0) == component(rhs, at: $0) }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = component(lhs, at: index)
            let right = component(rhs, at: index)
            if left != right { return left < right }
        }
        return false
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

/// The offer. Codable because a check runs at most once a day, and a relaunch
/// would otherwise drop the offer until the next one came due.
public struct AvailableUpdate: Codable, Equatable, Sendable {
    public let version: String
    public let url: URL

    public init(version: String, url: URL) {
        self.version = version
        self.url = url
    }
}

public enum UpdateCheckError: Error, Equatable, Sendable {
    case unreadableResponse
    case server(status: Int)
    case unparsableVersion(String)
}

public struct UpdateChecker: Sendable {
    public static let defaultEndpoint = URL(
        string: "https://api.github.com/repos/gafiegarcia/scriber/releases/latest"
    )!

    public static let checkInterval: TimeInterval = 60 * 60 * 24

    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = UpdateChecker.defaultEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }

    /// Whether an offer read back from storage still describes an update.
    ///
    /// Taking an offer is what makes the stored one wrong. It is cleared only by
    /// a check that comes back with nothing, checks run at most once a day, and
    /// the check that produced the offer ran minutes before the user acted on it
    /// — so without this the freshly installed version goes on offering itself
    /// for the rest of the day. A version that cannot be read is not an update.
    public static func stillDescribesAnUpdate(
        _ offer: AvailableUpdate,
        currentVersion: String
    ) -> Bool {
        guard let current = ReleaseVersion(currentVersion),
              let offered = ReleaseVersion(offer.version) else { return false }
        return current < offered
    }

    /// `nil` when the running version is already the newest released one.
    public static func newerRelease(
        currentVersion: String,
        release: GitHubRelease
    ) throws -> AvailableUpdate? {
        guard let current = ReleaseVersion(currentVersion) else {
            throw UpdateCheckError.unparsableVersion(currentVersion)
        }
        guard let latest = ReleaseVersion(release.tagName) else {
            throw UpdateCheckError.unparsableVersion(release.tagName)
        }
        guard current < latest else { return nil }
        return AvailableUpdate(version: latest.description, url: release.htmlURL)
    }

    public func check(currentVersion: String) async throws -> AvailableUpdate? {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub refuses an anonymous request that does not name itself.
        request.setValue("Scriber/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.unreadableResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.server(status: http.statusCode)
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return try Self.newerRelease(currentVersion: currentVersion, release: release)
    }
}
