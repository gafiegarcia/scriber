@preconcurrency import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum PasteResult: Sendable {
    case inserted
    case failed(String)
}

@MainActor
final class PasteService {
    private var target: AXUIElement?
    private var targetPID: pid_t = 0
    private(set) var targetScreen: NSScreen?

    @discardableResult
    func captureTarget() -> NSScreen? {
        target = nil
        targetPID = 0
        targetScreen = nil
        let system = AXUIElementCreateSystemWide()
        var applicationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &applicationValue) == .success,
              let applicationValue,
              CFGetTypeID(applicationValue) == AXUIElementGetTypeID() else { return nil }
        let application = unsafeDowncast(applicationValue, to: AXUIElement.self)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
        var roleValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleValue)
        if let role = roleValue as? String, role == "AXSecureTextField" { return nil }
        guard isEditableTextElement(focused, role: roleValue as? String) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(application, &pid)
        target = focused
        targetPID = pid
        targetScreen = screen(containing: focused)
        return targetScreen
    }

    private func isEditableTextElement(_ element: AXUIElement, role: String?) -> Bool {
        var selectedTextSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextSettable
        ) == .success, selectedTextSettable.boolValue {
            return true
        }

        guard let role, ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) else {
            return false
        }
        var valueSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &valueSettable
        ) == .success && valueSettable.boolValue
    }

    func clearTarget() {
        target = nil
        targetPID = 0
        targetScreen = nil
    }

    func insert(_ text: String) async -> PasteResult {
        guard AXIsProcessTrusted() else { return .failed("Accessibility permission is not enabled.") }
        guard let target else { return .failed("No editable text box was focused when dictation began.") }

        var settable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(target, kAXSelectedTextAttribute as CFString, &settable)
        if settableStatus == .success, settable.boolValue {
            let status = AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString, text as CFString)
            if status == .success { return .inserted }
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID,
              focusedElementStillMatches(target) else {
            return .failed("The original text box is no longer focused.")
        }

        let stateBeforePaste = textState(of: target)
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return .failed("The transcription could not be placed on the clipboard.")
        }
        let transcriptChangeCount = pasteboard.changeCount
        guard postPasteShortcut() else {
            snapshot.restoreIfUnchanged(pasteboard, expectedChangeCount: transcriptChangeCount)
            return .failed("macOS could not dispatch the Paste command.")
        }
        try? await Task.sleep(for: .milliseconds(500))
        let stateAfterPaste = textState(of: target)
        snapshot.restoreIfUnchanged(pasteboard, expectedChangeCount: transcriptChangeCount)
        guard stateBeforePaste != stateAfterPaste,
              stateBeforePaste.hasObservableValue || stateAfterPaste.hasObservableValue else {
            return .failed("macOS did not confirm that the transcription was inserted.")
        }
        return .inserted
    }

    private func focusedElementStillMatches(_ expected: AXUIElement) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let current = value else { return false }
        return CFEqual(current, expected)
    }

    private func textState(of element: AXUIElement) -> TextElementState {
        var valueReference: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueReference
        )
        let value = valueStatus == .success ? valueReference as? String : nil

        var rangeReference: CFTypeRef?
        var selectedRange: NSRange?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeReference
        ) == .success,
           let rangeReference,
           CFGetTypeID(rangeReference) == AXValueGetTypeID() {
            let rangeValue = unsafeDowncast(rangeReference, to: AXValue.self)
            var range = CFRange()
            if AXValueGetValue(rangeValue, .cfRange, &range) {
                selectedRange = NSRange(location: range.location, length: range.length)
            }
        }
        return TextElementState(value: value, selectedRange: selectedRange)
    }

    private func screen(containing element: AXUIElement) -> NSScreen? {
        var positionReference: CFTypeRef?
        var sizeReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionReference) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeReference) == .success,
              let positionReference, let sizeReference,
              CFGetTypeID(positionReference) == AXValueGetTypeID(),
              CFGetTypeID(sizeReference) == AXValueGetTypeID() else { return nil }
        let positionValue = unsafeDowncast(positionReference, to: AXValue.self)
        let sizeValue = unsafeDowncast(sizeReference, to: AXValue.self)
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        let accessibilityCenter = CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitCenter = CGPoint(x: accessibilityCenter.x, y: primaryTop - accessibilityCenter.y)
        return NSScreen.screens.first { $0.frame.contains(appKitCenter) }
    }

    private func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

private struct TextElementState: Equatable {
    let value: String?
    let selectedRange: NSRange?

    var hasObservableValue: Bool { value != nil || selectedRange != nil }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return PasteboardSnapshot(items: items)
    }

    func restoreIfUnchanged(_ pasteboard: NSPasteboard, expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else { return }
        pasteboard.clearContents()
        let restored = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
