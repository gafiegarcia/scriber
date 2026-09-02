import Foundation
import Network

/// Whether this Mac has any route to a network at all.
///
/// Answers "is there a way out of this machine", never "does the internet
/// work". A captive portal, a hotel splash page, and a router with nothing
/// behind it all report satisfied — those are what the transcription budget in
/// `ScribeClient` exists for. This covers the other case: Wi-Fi off, no
/// Ethernet, nothing to send to, which is knowable before a request is built
/// and is worth not spending eight seconds of backoff discovering.
///
/// Needs no entitlement and prompts for nothing.
@MainActor
final class NetworkReachability: ObservableObject {
    /// Starts optimistic. `NWPathMonitor` reports its first path a moment after
    /// starting, and refusing to transcribe in that window would fail a dictation
    /// over a question that had not been answered yet.
    @Published private(set) var hasNetworkRoute = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.gafiegarcia.scriber.reachability")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.hasNetworkRoute != satisfied else { return }
                self.hasNetworkRoute = satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
