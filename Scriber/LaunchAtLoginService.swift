import AppKit
import Foundation
import os
import ServiceManagement
#if SWIFT_PACKAGE
import ScriberCore
#endif

/// Whether macOS started Scriber as a login item, rather than the user opening it.
///
/// `SMAppService` reports whether the login item is registered and nothing about
/// the launch in progress, so the only signal is the Apple event AppKit is handling
/// while it starts — readable only during that handling. Sample at both startup
/// moments and keep the first answer that is not "nothing was there": sample once
/// and a launch carrying the marker late looks like one that never carries it.
@MainActor
enum LoginItemLaunch {
    enum Reading: String {
        /// No Apple event was being handled at that moment. Says nothing about
        /// the launch, which is exactly why it must be told apart from `no`.
        case noEvent
        /// An event was there and named a launch macOS made at login.
        case yes
        /// An event was there and did not.
        case no
    }

    private(set) static var isLoginItemLaunch = false
    private(set) static var reading: Reading = .noEvent

    private static let log = Logger(subsystem: "com.gafiegarcia.scriber", category: "window-lifecycle")

    /// Reads the launch event and records what it found. Safe to call more than
    /// once: a later reading only replaces an earlier one that saw no event.
    static func capture(phase: String) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let found: Reading
        if let event {
            let launchedAtLogin = event.eventID == kAEOpenApplication
                && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
            found = launchedAtLogin ? .yes : .no
        } else {
            found = .noEvent
        }
        log.notice(
            """
            launchEvent: phase=\(phase, privacy: .public) reading=\(found.rawValue, privacy: .public) \
            \(describe(event), privacy: .public)
            """
        )
        guard found != .noEvent, reading == .noEvent else { return }
        reading = found
        isLoginItemLaunch = found == .yes
    }

#if DEBUG
    /// Forces the answer, so the background-start path can be exercised without
    /// restarting the Mac. Without it the only way to reach that path is a real
    /// login, which is why a broken one went unnoticed for as long as it did.
    static func simulateLoginLaunch() {
        reading = .yes
        isLoginItemLaunch = true
    }
#endif

    /// Everything the event carries, so a single restart can settle which signal
    /// is worth trusting instead of one guess per restart.
    private static func describe(_ event: NSAppleEventDescriptor?) -> String {
        guard let event else { return "event=none" }
        var parts = [
            "eventClass=\(fourCharacterCode(event.eventClass))",
            "eventID=\(fourCharacterCode(event.eventID))"
        ]
        if let property = event.paramDescriptor(forKeyword: keyAEPropData) {
            parts.append("propData=\(fourCharacterCode(property.enumCodeValue))")
        } else {
            parts.append("propData=absent")
        }
        parts.append("items=\(event.numberOfItems)")
        return parts.joined(separator: " ")
    }

    private static func fourCharacterCode(_ code: OSType) -> String {
        let scalars = [24, 16, 8, 0].compactMap { shift -> Character? in
            let byte = UInt8((code >> UInt32(shift)) & 0xFF)
            guard let scalar = Unicode.Scalar(UInt32(byte)), byte >= 32, byte < 127 else { return nil }
            return Character(scalar)
        }
        return scalars.count == 4 ? String(scalars) : String(format: "0x%08X", code)
    }
}

struct LaunchAtLoginService: Sendable {
    /// What macOS currently has registered. A plain synchronous read with no
    /// change notification behind it, which is why the permission refresh polls
    /// it rather than waiting to be told.
    static var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
