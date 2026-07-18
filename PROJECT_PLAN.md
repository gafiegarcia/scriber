# Scriber Dictate

## Original Goal

Build a new app called Scriber Dictate, designed as a Wispr Flow direct replacement:

- Always active in the menu bar.
- Closing the app window removes it from the Dock while the app remains active in the background and visible in the menu bar. This applies to `Command-W`, `Command-Shift-W`, and the red window control.
- Default shortcuts:
  - Hold `Fn` to dictate; releasing it stops recording and starts transcription.
  - Press `Fn-Space` for hands-free recording; press either the Hold or Toggle shortcut again to stop and transcribe.
  - Both bindings are configurable. A custom Hold chord such as `Fn-Control-Option` must still coexist correctly with the Toggle chord.
- Show a floating pill at the bottom-center of the active screen while recording and transcribing.
- Save dictation history in the app.
- Automatically insert the transcription into the text box that was active when dictation began.
- If insertion fails, show Copy and Open App actions in the pill; the transcript must already be saved in History.

Product direction:

- Native macOS app written in Swift and SwiftUI, not Electron.
- ElevenLabs Scribe v2 batch API, using a bring-your-own API key.
- Minimal, modern, and based on native macOS components.

## Locked v0.1 Decisions

- Version: `0.1.0` personal Apple-silicon beta for macOS 27.
- Toolchain: Xcode 27 beta and Swift 6.4. Full Xcode is a prerequisite for app signing and end-to-end UI verification.
- Output: Scribe v2 with `no_verbatim=true`; no secondary rewrite model.
- Audio: delete after successful transcription; retain after a failed or interrupted transcription so it can be retried.
- Retry: three total attempts for transient failures, with 3-second and 5-second delays.
- Maximum recording duration: 10 minutes.
- History: local SwiftData database, retained until manually deleted.
- API key: a separate Scriber Dictate Keychain item.
- Personal keyterms are included and validated against Scribe limits.
- Launch at Login is optional, offered during onboarding, and defaults on with explicit consent.
- The Dock icon is visible while a normal app window is open and disappears after the final normal window closes.
- The target text element is captured when recording begins.
- Successful automatic insertion preserves the previous clipboard.
- `Escape` cancels and discards an active recording.
- Only one recording/transcription job runs at a time in v0.1.
- While converting a held recording to hands-free, modifiers belonging only to the Hold chord are ignored when matching Toggle. Stopping a locked recording requires an exact configured chord.

## Milestones

- [x] Capture the product outline and locked decisions.
- [x] Scaffold and compile the native app.
- [ ] Validate bare `Fn` capture and suppression on macOS 27 hardware.
- [x] Complete recording, transcription, retries, and recovery implementation.
- [x] Complete Accessibility insertion and clipboard-preserving fallback implementation.
- [x] Complete menu-bar, pill, History, Settings, onboarding, and Dock lifecycle implementation.
- [ ] Run automated and manual acceptance checks.
- [ ] Produce and install the v0.1 Release app at a stable path.

## Progress Log

### 2026-07-18

- Plan finalized from the original product outline.
- Implementation started in an empty workspace.
- Environment check initially found only Command Line Tools selected; Xcode 27 beta was subsequently found at `/Applications/Xcode-beta.app`.
- Created the Xcode application project, Info.plist, entitlements, asset catalog shell, Swift package core, and initial test target.
- Implemented the menu-bar/Dock lifecycle, onboarding, History and Settings views, shortcut recorder, non-activating pill, and Launch at Login integration.
- Implemented AVFoundation recording, 10-minute auto-stop, save-before-transcribe history, interrupted-job recovery, successful-audio cleanup, failed-audio retention, automatic/manual retry, Keychain storage, Scribe v2 multipart requests, and keyterm validation.
- Implemented the global Core Graphics shortcut tap, default and configurable chord semantics, held-to-locked transition, Escape cancellation, Accessibility target capture, direct insertion, guarded pasteboard fallback, and clipboard restoration.
- Split UI-independent behavior into `ScriberDictateCore` so it can be compiled and tested without SwiftUI/SwiftData macro expansion.
- Core sources type-check successfully; all Swift sources pass parser validation; the Xcode project and property lists pass `plutil` validation.
- Six core tests pass: exact/default shortcut matching, context-aware locking, busy-state classification, keyterm normalization/rejection, and retryable-error classification.
- Fixed Xcode 27/Swift 6.4 compiler diagnostics around AppKit notifications, actor isolation, and nested preference bindings.
- The complete app target now passes an unsigned Debug build with Xcode 27 beta. Signing, live permissions, shortcut hardware behavior, and the end-to-end ElevenLabs flow remain manual verification items.
- First hardware run exposed and fixed two issues: nested Preferences/coordinator changes are now forwarded to SwiftUI so onboarding dismisses and live status refreshes; modifier-only shortcut events are no longer consumed, preventing bare `Fn` handling from disrupting normal Space input.
- Reverified the complete unsigned Debug build and all six credit-free core tests after these fixes.
- During shortcut testing, Wispr Flow was also running and competing for the same global `Fn` events. This temporarily disrupted Space input until Wispr Flow was stopped and `Fn` was pressed again to resynchronize modifier state. Hardware acceptance tests must be run with other global dictation/shortcut tools disabled.
- Improved API-key UX in onboarding and Settings: save/update buttons now disable for blank input, successful Keychain storage receives an immediate green confirmation, failures appear inline in red, and the copy explains that the first transcription verifies the key with ElevenLabs. The app build was reverified afterward.
- Completed the first post-baseline UX pass from hardware testing:
  - Accessibility target capture now accepts only editable text controls, and pasteboard fallback reports success only when the target's observable text or selection state changes. Missing or unconfirmed targets keep the transcript in History and show Copy/Open actions instead of a false “Pasted” notice.
  - Empty and punctuation-only API results are treated as “No words detected,” with no useless Retry/Open actions and no empty History record. Two credit-free tests cover this classification.
  - Pill Open now routes through the process-lifetime app delegate, which retains and reopens the SwiftUI window even while the menu is closed.
  - Replaced the History/Settings tab strip with a persistent native sidebar. History is now a full-page chronological list with inline actions; Clear History lives in the History overflow menu. This removes the inert tab-overflow double-arrow control and keeps the native sidebar toggle available across sections.
- Reverified the complete unsigned Debug build and all eight credit-free core tests after this pass. Live acceptance checks remain required for paste confirmation across TextEdit, browsers, and code editors, plus closed-window reopening from the failure pill.

## Verification Notes

- Automated tests must not consume ElevenLabs credits.
- A real ElevenLabs smoke test is opt-in.
- Hardware verification must cover `Fn`, `Fn-Space`, `Fn-Control-Option`, target capture, TextEdit, a browser text field, a code editor, full-screen apps, multiple Spaces, and Dock auto-hide.
- Signing and Accessibility permission tests must use a stable app path because macOS privacy grants are tied to app identity.
- The current app icon asset catalog is a valid placeholder; final icon artwork is deferred until the application runs end to end.
