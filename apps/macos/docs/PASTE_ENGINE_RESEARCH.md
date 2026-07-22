# Paste Engine Research

This is the durable working note for Scriber's automatic-insertion investigation. Update it with evidence, rejected assumptions, live-test results, and decisions so the reasoning survives context compaction and handoff.

Last updated: 2026-07-23

## Non-negotiable premise

Standard macOS Accessibility text attributes and notifications have never been reliable enough to serve as Scriber's general paste-success receipt. They may provide useful positive evidence in a particular app, but the delivery path and default UX must not depend on receiving them.

Do not regress to another policy that interprets missing Accessibility evidence as failed insertion.

## User-observed behavior

- Scriber successfully inserts into VS Code, Zed, Notion, and the ChatGPT macOS app, but the current confirmation policy reports those insertions as failures.
- A browser with no focused text box must still be recognized as a failed insertion; merely sending Paste or observing a clipboard read is insufficient.
- Wispr Flow inserts into the text cursor that is focused when cloud transcription finishes. The user can move focus or the cursor while transcription is running, and delivery follows that final cursor rather than the element focused when recording began.
- The Wispr behavior is evidence about its delivery model, not a requirement that Scriber must copy its target semantics unchanged.

## Current Scriber behavior and failure

`PasteService` first tries direct Accessibility insertion at the captured selection. It otherwise discovers the frontmost process at delivery time, prepares pasteboard text, dispatches a Paste menu action or PID-targeted Command-V, waits 500 ms, and classifies the attempt.

The current policy accepts success only when:

1. observable Accessibility state changes; or
2. the destination requests the promised pasteboard text and Scriber also receives exact inserted-text metadata or a selection mutation on an element it recognizes as editable.

This creates false failures when a custom editor accepts the paste but exposes neither stable readable text state nor the expected Accessibility notifications.

Important implementation weakness: the Accessibility observer is registered on the application object. Apple's API registers a notification for the specified Accessibility object; it does not document application-root registration as a recursive guarantee for every descendant editor. App-specific behavior observed once must not be promoted into a platform guarantee.

The current focus lookup also filters out elements that do not already look like text input. That can collapse two materially different situations:

- macOS positively exposes a focused noneditable element; and
- the destination hides its real focused editor or exposes insufficient information.

That distinction should be retained as evidence even if Accessibility is removed from the delivery gate.

### Relevant Scriber commits

- `221c10e Fix paste confirmation UX`
- `a98246e Confirm pasteboard consumption`
- `cd49af4 Observe browser paste mutations`
- `25295d6 Confirm contenteditable paste mutations`

These commits oscillated between lenient delivery and strict confirmation because the underlying model remained binary: an unobserved insertion was reported as a failed insertion.

## Freeflow findings

Repository: <https://github.com/zachlatta/freeflow>

Inspected `main` around Freeflow 1.2.0 on 2026-07-23.

### Plain dictation delivery

Freeflow does not attempt to confirm plain-dictation insertion.

1. It writes the final transcript as ordinary `.string` pasteboard data.
2. After the dictation shortcut's keys are released, it posts Command-V at `.cgSessionEventTap`.
3. The event goes to whichever application/cursor is focused at delivery time.
4. It immediately sets its status to `Pasted at cursor!` when clipboard preservation is enabled.
5. It restores the previous clipboard after a one-second delay, unless the user appears to have copied something else.

There is no Accessibility mutation observer, pasteboard-consumption probe, focused-textbox preflight, or post-paste readback in this path.

Relevant source:

- [`AppState.swift`](https://github.com/zachlatta/freeflow/blob/main/Sources/AppState.swift)
- Commit [`1c16e91`](https://github.com/zachlatta/freeflow/commit/1c16e91a0bedfcc74bf273963cb464f952333cd8) waits for shortcut release before pasting.
- Commit [`9e27819`](https://github.com/zachlatta/freeflow/commit/9e27819bc15183c2b3c1d63ab2a0a51479163825) increased clipboard restoration to one second because some apps consume Command-V asynchronously.

### What Freeflow's history demonstrates

- [Issue 237](https://github.com/zachlatta/freeflow/issues/237) reports that Accessibility-based Edit Mode fails in Electron/Chromium while plain dictation works in VS Code and Chromium. This supports decoupling general delivery from Accessibility.
- [Issue 16](https://github.com/zachlatta/freeflow/issues/16) reports that plain paste can silently fail when a CJK IME is active. Freeflow's optimistic path has no way to detect that failure.
- [Issue 150](https://github.com/zachlatta/freeflow/issues/150) asks for clipboard/history recovery when the user was not inside a text input. The proposed recovery was Paste Again/history, not insertion confirmation.
- Freeflow's automated tests currently cover app-context behavior, not end-to-end paste outcomes.

Conclusion: Freeflow is useful evidence for a highly compatible delivery mechanism and timing, but not a solution for reliable failure detection.

## Wispr Flow findings

Official support documentation inspected on 2026-07-23:

- [Fix text not pasting after dictation](https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation)
- [Use Flow with remote desktops](https://docs.wisprflow.ai/articles/7336156466-use-flow-with-remote-desktops-citrix-rdp-vdi)

Documented behavior:

- Flow simulates the standard Command-V paste shortcut on macOS.
- It targets whichever app/text field is focused when transcription finishes.
- It temporarily uses the clipboard.
- After what Flow classifies as a successful paste, it restores the previous clipboard.
- After what Flow classifies as a failed paste, it leaves the dictation on the clipboard and offers a paste-last-text recovery shortcut/notification.

Wispr does not publicly document how its macOS client distinguishes successful insertion from a failed paste. Do not claim that its detector is known or that it guarantees perfect classification.

### Local installed-app inspection

The installed `/Applications/Wispr Flow.app` was inspected read-only on 2026-07-23. This is binary metadata and embedded diagnostic text, not Wispr source code.

- The outer app is Electron 1.6.182.
- It bundles a native Swift background helper, version 1.6.180, with bundle identifier `com.electron.wispr-flow.accessibility-mac-app`.
- The helper links AppKit, ApplicationServices, Carbon, and CoreGraphics and contains Accessibility traversal, event-tap, clipboard, focus-restoration, and paste-outcome machinery.
- Its `DelayedClipboardProvider` starts a failed-paste timer. Embedded diagnostics state that no data request before the timeout means a paste likely failed, while a data request cancels the failure timer and is called a succeeded paste.
- The helper sends `PasteOutcome` with `success`, elapsed time, and transcript identifier. The Electron bundle consumes that outcome for success/failure behavior and its failed-paste notification.
- Wispr separately reports `DictatedTextVerification` with verdicts `verified`, `verified_before_after`, `not_found`, or `skipped`. Reasons include `no_focused_element`, `element_not_editable`, `contents_empty`, `position_not_found`, and `textbox_too_long`.
- Embedded analytics distinguish delayed-clipboard success from optional insertion verification. This suggests, but does not prove without source/runtime tracing, that Accessibility verification is quality telemetry or supplementary evidence rather than the universal gate for the failed-paste notification.

Critical limitation: the delayed-provider success rule is the same signal Scriber already found insufficient in Chromium. Chromium may request clipboard text while constructing a paste event and then discard it because no editable control owns focus. Therefore Wispr may also miss the exact unfocused-browser failure case. A live Wispr test in Zen with no focused textbox is needed before treating Wispr as the reference behavior for that case.

## Platform facts

- Posting a Core Graphics keyboard event delivers an event into the target event pipeline; the API does not return an editor-handled or text-inserted acknowledgement.
- A lazy `NSPasteboardItemDataProvider` callback proves that pasteboard representation was requested. It does not prove the requesting app committed that representation into an editor.
- Accessibility can sometimes expose focused roles, selected ranges, values, character counts, or text-change notifications. Absence of those signals is not evidence of absence of insertion.
- Two destination behaviors can be externally indistinguishable to Scriber: an opaque editor may read and insert the text, while another app may read the same text during Paste handling and discard it. Any proposed universal detector must explicitly address this information limit.

Apple references:

- <https://developer.apple.com/documentation/coregraphics/cgevent>
- <https://developer.apple.com/documentation/appkit/nspasteboarditemdataprovider>
- <https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification>

## Direction under investigation

### Delivery must be independent of confirmation

The baseline compatible delivery candidate is:

1. At transcription completion, target the current foreground app/cursor.
2. Wait until the dictation shortcut is fully released.
3. Put ordinary string data on the general pasteboard.
4. Post a session-level Command-V like a real user paste.
5. Keep the transcript in Dictation history regardless of delivery classification.

Accessibility can still support captured-selection behavior or supply optional evidence, but must not block this fallback.

### Evidence must not be forced into a false binary

Internally preserve at least these states:

- confirmed inserted;
- confirmed unable to dispatch or positively noneditable;
- attempted but externally unobservable.

The user-facing policy remains unresolved. The core UX constraint is:

- frequent successful pastes in opaque editors must not produce failure pills;
- a known failed paste should preserve the transcript on the clipboard and offer recovery;
- an unobservable attempt must not be described as a confirmed failure.

### Candidate high-value distinction

Retain the raw focused Accessibility element before applying text-target filters:

- positively noneditable/secure focus can strengthen failure evidence;
- missing, partial, or unknown Accessibility exposure must remain unknown rather than `no text box`.

This may separate an unfocused browser page from an opaque custom editor in many apps, but it is a hypothesis requiring live evidence. It is not a universal guarantee.

## Next research and test steps

1. Add privacy-safe per-attempt diagnostics that never record transcript contents or nearby user text. Record app bundle ID, delivery method, raw focus classification, observer registration results, signal timestamps, pasteboard-request status, and final internal classification.
2. Reproduce successful-but-unconfirmed insertion in VS Code, Zed, Notion, and ChatGPT and capture which signals are actually absent.
3. Compare each with Zen/another browser in these states: focused input, focused contenteditable, and no focused input.
4. Test session-level `CGEvent.post(tap: .cgSessionEventTap)` versus the current menu-command/PID-targeted dispatch.
5. Test shortcut-release timing and clipboard restoration at one second, informed by Freeflow's history.
6. Test with the active keyboard input sources Gaf uses; include a non-Latin IME if feasible because Freeflow has a documented silent failure there.
7. Test the same focused-textbox and no-textbox Zen cases in the installed Wispr Flow version. Record whether it reports failure, silently accepts the attempt, and restores or retains the dictated clipboard text.
8. Only after collecting the matrix, choose the internal classification and user-facing recovery policy.

## Rejected or unsafe shortcuts

- Do not accept a dispatched Paste command as proof of insertion.
- Do not accept pasteboard data consumption alone as proof of insertion.
- Do not require Accessibility mutation as proof of every successful insertion.
- Do not add per-app role exceptions without captured evidence and a clear capability boundary.
- Do not destructively select/copy/undo destination text to verify insertion; that risks corrupting user state and behaves differently across editors.
- Do not call an unobservable attempt `failed` merely to retain a binary result type.
