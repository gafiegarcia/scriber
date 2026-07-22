@preconcurrency import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
#if SWIFT_PACKAGE
import ScriberCore
#endif

enum PasteResult: Sendable {
    static let noEditableTargetMessage = "No editable text box was focused"

    case inserted
    case noEditableTarget(String)
    case failed(String)
}

@MainActor
final class PasteService {
    private var target: AXUIElement?
    private var focusAnchor: AXUIElement?
    private var targetPID: pid_t = 0
    private var capturedTextState: TextElementState?
    private(set) var targetScreen: NSScreen?

    @discardableResult
    func captureTarget() -> NSScreen? {
        target = nil
        focusAnchor = nil
        targetPID = 0
        capturedTextState = nil
        targetScreen = nil
        guard let runningApplication = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = runningApplication.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        guard let focused = focusedElement(in: application, pid: pid) else {
            // Retain the process so delivery can retry focus discovery after
            // transcription; web-backed apps can publish focus inconsistently.
            targetPID = pid
            return nil
        }
        let candidates = candidateElements(startingAt: focused)
        guard !candidates.contains(where: isSecureTextElement) else { return nil }
        target = candidates.first(where: isEditableTextElement)
        focusAnchor = focused
        targetPID = pid
        capturedTextState = target.map { self.textState(of: $0) }
        targetScreen = candidates.lazy.compactMap { self.screen(containing: $0) }.first
        return targetScreen
    }

    private func candidateElements(startingAt focused: AXUIElement) -> [AXUIElement] {
        var ancestry = [focused]
        var current = focused
        for _ in 0..<24 {
            guard let parent = elementAttribute(current, named: kAXParentAttribute),
                  !ancestry.contains(where: { CFEqual($0, parent) }) else { break }
            ancestry.append(parent)
            current = parent
        }

        var candidates = ancestry
        for attribute in ["AXEditableAncestor", "AXHighestEditableAncestor"] {
            if let editableAncestor = elementAttribute(focused, named: attribute),
               !candidates.contains(where: { CFEqual($0, editableAncestor) }) {
                candidates.insert(editableAncestor, at: 1)
            }
        }
        return candidates
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        stringAttribute(element, named: kAXRoleAttribute) == "AXSecureTextField"
            || stringAttribute(element, named: kAXSubroleAttribute) == "AXSecureTextField"
    }

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, named: kAXRoleAttribute)
        let subrole = stringAttribute(element, named: kAXSubroleAttribute)
        var selectedTextSettable = DarwinBoolean(false)
        let selectedTextStatus = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextSettable
        )
        var characterCountValue: CFTypeRef?
        let characterCountStatus = AXUIElementCopyAttributeValue(
            element,
            kAXNumberOfCharactersAttribute as CFString,
            &characterCountValue
        )
        var enabledValue: CFTypeRef?
        let enabledStatus = AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &enabledValue
        )
        let explicitlyEditable = boolAttribute(element, named: "AXIsEditable") == true
        return TextInputTargetPolicy.accepts(
            role: role,
            subrole: subrole,
            selectedTextSettable: selectedTextStatus == .success && selectedTextSettable.boolValue,
            exposesCharacterCount: characterCountStatus == .success && characterCountValue != nil,
            explicitlyEditable: explicitlyEditable,
            enabled: enabledStatus == .success ? enabledValue as? Bool : nil
        )
    }

    private func elementAttribute(_ element: AXUIElement, named name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func stringAttribute(_ element: AXUIElement, named name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, named name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    func clearTarget() {
        target = nil
        focusAnchor = nil
        targetPID = 0
        capturedTextState = nil
        targetScreen = nil
    }

    func insert(_ text: String) async -> PasteResult {
        guard AXIsProcessTrusted() else { return .failed("Accessibility permission is not enabled.") }

        if await insertAtCapturedSelection(text) { return .inserted }
        guard let currentTarget = currentFocusedPasteTarget() else {
            return .noEditableTarget(PasteResult.noEditableTargetMessage)
        }
        return await pasteAtCurrentSelection(text, into: currentTarget)
    }

    private func insertAtCapturedSelection(_ text: String) async -> Bool {
        guard let target, let capturedTextState else { return false }
        let currentState = textState(of: target)
        let isOriginalTargetFocused = NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
            && focusedElementStillMatches(focusAnchor ?? target)
        guard CapturedSelectionRestorePolicy.canRestore(
            capturedText: capturedTextState.value,
            currentText: currentState.value,
            capturedRange: capturedTextState.selectedRange,
            currentRange: currentState.selectedRange,
            isOriginalTargetFocused: isOriginalTargetFocused
        ), let capturedRange = capturedTextState.selectedRange,
           setSelectedTextRange(capturedRange, on: target),
           textState(of: target).selectedRange == capturedRange,
           isSelectedTextSettable(on: target) else { return false }

        let stateBeforeInsertion = textState(of: target)
        guard AXUIElementSetAttributeValue(
            target,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else { return false }
        try? await Task.sleep(for: .milliseconds(100))
        let stateAfterInsertion = textState(of: target)
        return stateAfterInsertion.hasObservableValue
            && stateAfterInsertion != stateBeforeInsertion
    }

    private func currentFocusedPasteTarget() -> FocusedTextTarget? {
        guard let runningApplication = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = runningApplication.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        let observationElements: [AXUIElement]
        if let focused = focusedElement(in: application, pid: pid) {
            let candidates = candidateElements(startingAt: focused)
            guard !candidates.contains(where: isSecureTextElement) else { return nil }
            observationElements = candidates
        } else {
            // The destination may keep a real editor outside its Accessibility
            // tree. Process-level paste remains safe to try because success is
            // confirmed independently by target mutation or pasteboard access.
            observationElements = []
        }
        return FocusedTextTarget(
            application: application,
            pid: pid,
            observationElements: observationElements
        )
    }

    private func focusedElement(in application: AXUIElement, pid: pid_t) -> AXUIElement? {
        if let focused = elementAttribute(application, named: kAXFocusedUIElementAttribute),
           isPotentialTextFocus(focused) {
            return focused
        }

        let systemWide = AXUIElementCreateSystemWide()
        if let focused = elementAttribute(systemWide, named: kAXFocusedUIElementAttribute) {
            var focusedPID: pid_t = 0
            if AXUIElementGetPid(focused, &focusedPID) == .success,
               focusedPID == pid,
               isPotentialTextFocus(focused) {
                return focused
            }
        }

        // Web-backed apps sometimes omit AXFocusedUIElement while still marking
        // the actual DOM-backed control as focused in their Accessibility tree.
        var queue = [application]
        var index = 0
        while index < queue.count, index < 1_024 {
            let element = queue[index]
            index += 1
            if boolAttribute(element, named: kAXFocusedAttribute) == true,
               isPotentialTextFocus(element) {
                return element
            }
            let remainingCapacity = 1_024 - queue.count
            if remainingCapacity > 0 {
                queue.append(contentsOf: elementArrayAttribute(element, named: kAXChildrenAttribute).prefix(remainingCapacity))
            }
        }
        return nil
    }

    private func isPotentialTextFocus(_ element: AXUIElement) -> Bool {
        candidateElements(startingAt: element).contains {
            isEditableTextElement($0) || isSecureTextElement($0)
        }
    }

    private func pasteAtCurrentSelection(_ text: String, into currentTarget: FocusedTextTarget) async -> PasteResult {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == currentTarget.pid else {
            return .failed("The focused app changed before Scriber could paste.")
        }

        let statesBeforePaste = observableTextStates(of: currentTarget.observationElements)
        let mutationObserver = PasteMutationObserver(
            pid: currentTarget.pid,
            application: currentTarget.application,
            expectedText: text
        )
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        pasteboard.clearContents()
        let pasteboardReadProbe = PasteboardReadProbe(text: text)
        let transcriptItem = NSPasteboardItem()
        guard transcriptItem.setDataProvider(pasteboardReadProbe, forTypes: [.string]),
              pasteboard.writeObjects([transcriptItem]) else {
            return .failed("The transcription could not be placed on the clipboard.")
        }
        let transcriptChangeCount = pasteboard.changeCount
        try? await Task.sleep(for: .milliseconds(75))
        guard await dispatchPaste(to: currentTarget) else {
            snapshot.restoreIfUnchanged(pasteboard, expectedChangeCount: transcriptChangeCount)
            return .failed("The focused app did not provide a usable Paste command.")
        }
        try? await Task.sleep(for: .milliseconds(500))
        let stateAfterPaste = currentFocusedPasteTarget()
        let statesAfterPaste = stateAfterPaste?.pid == currentTarget.pid
            ? observableTextStates(of: stateAfterPaste?.observationElements ?? [])
            : []
        let pasteboardDataRequested = pasteboardReadProbe.wasRequested
        snapshot.restoreIfUnchanged(pasteboard, expectedChangeCount: transcriptChangeCount)
        let accessibilityConfirmed = (!statesBeforePaste.isEmpty || !statesAfterPaste.isEmpty)
            && statesBeforePaste != statesAfterPaste
        guard PasteConfirmationPolicy.confirmsInsertion(
            accessibilityMutationObserved: accessibilityConfirmed,
            pasteboardDataRequested: pasteboardDataRequested,
            insertedTextNotificationObserved: mutationObserver?.insertedTextObserved == true,
            editableSelectionMutationObserved: mutationObserver?.editableSelectionMutationObserved == true
        ) else {
            return .failed("macOS did not confirm that the transcription was inserted.")
        }
        return .inserted
    }

    private func dispatchPaste(to target: FocusedTextTarget) async -> Bool {
        if performApplicationPasteCommand(in: target.application) {
            return true
        }
        return await postPasteShortcut(to: target.pid)
    }

    private func performApplicationPasteCommand(in application: AXUIElement) -> Bool {
        guard let menuBar = elementAttribute(application, named: kAXMenuBarAttribute),
              let pasteItem = pasteMenuItem(in: menuBar) else { return false }
        return AXUIElementPerformAction(pasteItem, kAXPressAction as CFString) == .success
    }

    private func pasteMenuItem(in root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var index = 0
        while index < queue.count, index < 256 {
            let element = queue[index]
            index += 1
            if stringAttribute(element, named: kAXRoleAttribute) == "AXMenuItem",
               boolAttribute(element, named: kAXEnabledAttribute) != false,
               isStandardPasteMenuItem(element) {
                return element
            }
            queue.append(contentsOf: elementArrayAttribute(element, named: kAXChildrenAttribute))
        }
        return nil
    }

    private func isStandardPasteMenuItem(_ element: AXUIElement) -> Bool {
        let title = stringAttribute(element, named: kAXTitleAttribute)?.localizedLowercase
        if title == "paste" { return true }
        let commandCharacter = stringAttribute(element, named: "AXMenuItemCmdChar")?.lowercased()
        let commandModifiers = numberAttribute(element, named: "AXMenuItemCmdModifiers")?.intValue
        return commandCharacter == "v" && commandModifiers == 0
    }

    private func elementArrayAttribute(_ element: AXUIElement, named name: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let values = value as? [Any] else { return [] }
        return values.compactMap { value in
            let reference = value as CFTypeRef
            guard CFGetTypeID(reference) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(reference, to: AXUIElement.self)
        }
    }

    private func numberAttribute(_ element: AXUIElement, named name: String) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? NSNumber
    }

    private func observableTextStates(of elements: [AXUIElement]) -> [TextElementState] {
        elements.map { self.textState(of: $0) }.filter(\.hasObservableValue)
    }

    private func isSelectedTextSettable(on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    private func setSelectedTextRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else { return false }
        var accessibilityRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &accessibilityRange) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success
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

        var characterCountReference: CFTypeRef?
        let characterCount: Int?
        if AXUIElementCopyAttributeValue(
            element,
            kAXNumberOfCharactersAttribute as CFString,
            &characterCountReference
        ) == .success,
           let number = characterCountReference as? NSNumber {
            characterCount = number.intValue
        } else {
            characterCount = nil
        }
        return TextElementState(value: value, selectedRange: selectedRange, characterCount: characterCount)
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

    private func postPasteShortcut(to pid: pid_t) async -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        try? await Task.sleep(for: .milliseconds(12))
        up.postToPid(pid)
        return true
    }
}

private struct TextElementState: Equatable {
    let value: String?
    let selectedRange: NSRange?
    let characterCount: Int?

    var hasObservableValue: Bool { value != nil || selectedRange != nil || characterCount != nil }
}

private struct FocusedTextTarget {
    let application: AXUIElement
    let pid: pid_t
    let observationElements: [AXUIElement]
}

private final class PasteboardReadProbe: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let textData: Data
    private let lock = NSLock()
    private var requested = false

    init(text: String) {
        textData = Data(text.utf8)
    }

    var wasRequested: Bool {
        lock.withLock { requested }
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        if item.setData(textData, forType: type) {
            lock.withLock { requested = true }
        }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}

private final class PasteMutationObserver: @unchecked Sendable {
    private static let textChangeValuesKey = "AXTextChangeValues"
    private static let textChangeElementKey = "AXTextChangeElement"
    private static let textEditTypeKey = "AXTextEditType"
    private static let textChangeValueKey = "AXTextChangeValue"

    private let expectedText: String
    private let application: AXUIElement
    private let lock = NSLock()
    private var observer: AXObserver?
    private var registeredNotifications = [CFString]()
    private var insertedTextWasObserved = false
    private var editableSelectionWasMutated = false

    init?(pid: pid_t, application: AXUIElement, expectedText: String) {
        self.expectedText = expectedText
        self.application = application

        var observer: AXObserver?
        guard AXObserverCreateWithInfoCallback(pid, pasteMutationObserverCallback, &observer) == .success,
              let observer else { return nil }
        self.observer = observer

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXValueChangedNotification, kAXSelectedTextChangedNotification] {
            let notification = notification as CFString
            if AXObserverAddNotification(observer, application, notification, refcon) == .success {
                registeredNotifications.append(notification)
            }
        }
        guard !registeredNotifications.isEmpty else { return nil }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    deinit {
        guard let observer else { return }
        for notification in registeredNotifications {
            AXObserverRemoveNotification(observer, application, notification)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    var insertedTextObserved: Bool {
        lock.withLock { insertedTextWasObserved }
    }

    var editableSelectionMutationObserved: Bool {
        lock.withLock { editableSelectionWasMutated }
    }

    fileprivate func receive(
        element: AXUIElement,
        notification: CFString,
        info: CFDictionary
    ) {
        let dictionary = info as NSDictionary
        if notification as String == kAXValueChangedNotification,
           let changes = dictionary[Self.textChangeValuesKey] as? [NSDictionary] {
            let textChanges = changes.map { change in
                let editType = (change[Self.textEditTypeKey] as? NSNumber)?.intValue
                let value = change[Self.textChangeValueKey] as? String
                return PasteTextChange(editType: editType, value: value)
            }
            if PasteConfirmationPolicy.containsInsertedText(expectedText, changes: textChanges) {
                lock.withLock { insertedTextWasObserved = true }
            }
        }

        guard notification as String == kAXSelectedTextChangedNotification else { return }
        let changedElement = accessibilityElement(
            from: dictionary[Self.textChangeElementKey]
        ) ?? element
        guard isEditableTextElement(changedElement) else { return }
        lock.withLock { editableSelectionWasMutated = true }
    }

    private func accessibilityElement(from value: Any?) -> AXUIElement? {
        guard let value else { return nil }
        let reference = value as CFTypeRef
        guard CFGetTypeID(reference) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(reference, to: AXUIElement.self)
    }

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        if stringAttribute(element, named: kAXRoleAttribute) == "AXSecureTextField"
            || stringAttribute(element, named: kAXSubroleAttribute) == "AXSecureTextField"
            || boolAttribute(element, named: kAXEnabledAttribute) == false {
            return false
        }
        if boolAttribute(element, named: "AXIsEditable") == true { return true }

        var selectedTextSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextSettable
        ) == .success, selectedTextSettable.boolValue {
            return true
        }

        let recognizedRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        return stringAttribute(element, named: kAXRoleAttribute).map(recognizedRoles.contains) == true
    }

    private func stringAttribute(_ element: AXUIElement, named name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, named name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}

private func pasteMutationObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ info: CFDictionary,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<PasteMutationObserver>
        .fromOpaque(refcon)
        .takeUnretainedValue()
        .receive(element: element, notification: notification, info: info)
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
