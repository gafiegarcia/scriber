import AppKit
import Foundation
import ServiceManagement

/// Whether macOS started Scriber as a login item, rather than the user opening it.
///
/// `SMAppService` reports whether the login item is registered and nothing about
/// the launch in progress, so the only signal is the Apple event AppKit is
/// handling while the app starts. It is readable for that moment only, which is
/// why this is captured in `applicationWillFinishLaunching` rather than asked
/// for when the answer is wanted.
@MainActor
enum LoginItemLaunch {
    private(set) static var isLoginItemLaunch = false

    static func capture() {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        isLoginItemLaunch = event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

struct LaunchAtLoginService: Sendable {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
