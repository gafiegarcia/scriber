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
- Converted the floating pill from a custom material background to native SwiftUI Liquid Glass. Normal states now use a compact 300×62 pill with increased internal padding; actionable failures expand to 430×72 so their controls remain comfortable. The first request reads only “Transcribing…”, while retryable failures surface “Retrying 2/3…” or “Retrying 3/3…” and show the wait duration as secondary text. The Xcode Debug build passes after this change.
- Removed an AppKit layout-recursion trigger in the pill: panel size is now changed only when transitioning between compact and actionable-failure layouts, rather than on every 100 ms audio-meter update. Core Spotlight `CSInlineDonation` service errors observed in Xcode are macOS 27 beta system-service diagnostics and do not affect app behavior or stored data.
- When no editable text box was focused at dictation start, the transcript is now copied to the clipboard immediately, stored as a copied delivery, and shown in a smaller pill as “Dictation copied” with “No editable text box was focused” below it. The redundant Copy action is omitted for that case, while Open remains available. The Xcode Debug build passes after this change.
- All terminal pill states now auto-dismiss: success after 1 second, transient messages after 1.5 seconds, copied/no-target fallback after 3 seconds, and actionable paste/transcription failures after 6 seconds. The Xcode Debug build passes after this change.
- Added a small countdown ring for auto-dismiss timing. Hovering the pill pauses the countdown and cancels the active dismissal task; moving the pointer out resumes from the remaining time with a 1.25-second minimum grace period. The dismiss button hit area is also larger. The Xcode Debug build passes after this change.
- Reworked the no-editable-textbox fallback into a taller copied-result pill: successful transcription still copies immediately, then the pill shows a “Copied” indicator, the reason, a four-line transcript preview, Open, dismiss, and the countdown ring. This uses a dedicated `dictationCopied` app phase instead of presenting the copied fallback as a paste failure. The Xcode Debug build and all eight credit-free package tests pass after this change.
- Normalized the expanded copied-result pill by keeping compact states capsule-shaped while using a fixed 24-point continuous corner radius for the 560×230 transcript preview.
- Replaced system-default-only `AVAudioRecorder` capture with a selectable `AVCaptureSession` pipeline. Scriber Dictate now prefers the Mac’s built-in microphone on first launch, persists an explicit input or Automatic/System Default choice, records the same mono AAC `.m4a` format, and reports disconnected saved devices without silently switching inputs.
- Added a shared live audio waveform to the recording pill and onboarding microphone check. A deliberately low `-60 dBFS` peak threshold keeps the waveform flat for silence, scales visibly with input magnitude, and discards recordings that never cross the threshold before creating History or spending an ElevenLabs API call.
- Empty, whitespace-only, and punctuation-only text from a successful ElevenLabs response now follows one cleanup path: retained audio and the temporary recovery record are deleted, no Retry/Open controls appear, and the pill dismisses immediately. Genuine transcription failures continue to retain audio and History for retry.
- Reworked onboarding permission feedback into separate Microphone and Accessibility steps. The microphone picker and automatic live test also appear during setup, the picker remains editable in Settings, granted permissions replace Allow controls with green allowed states, denied microphone access links to System Settings, and both permissions refresh when the app becomes active again.
- Expanded the credit-free core suite to 11 tests covering built-in microphone preference, signal-threshold mapping, and successful empty-response parsing. Parser validation, core type-checking, property-list validation, package tests, and unsigned Xcode 27 beta Debug and Release builds all pass. Live microphone/device, permission, waveform, and API-empty-response acceptance checks remain manual.
- Relaxed Accessibility target capture for terminals, launchers, and other custom controls that accept normal keyboard input without exposing writable text values. Standard text roles, the editable character-count capability, and editable ancestors are now recognized; secure/disabled fields remain excluded, and character-count changes strengthen post-paste confirmation. The credit-free suite now contains 14 tests and the unsigned Debug build passes. Live insertion checks in Ghostty and Raycast remain manual.
- Unified the recording pill presentation across held and hands-free modes. Both now show “Recording” with elapsed time on the left, while the live waveform fills the right side of the compact pill. Parser validation, core type-checking, all 14 credit-free tests, and the unsigned Xcode 27 beta Debug build pass.
- Fixed manual retry feedback for failed History entries. Retrying rows now explicitly observe their SwiftData record, immediately replace the stale Failed/Retry controls with a Retrying indicator and spinner, and refresh to the completed transcript after success. Retry validation now distinguishes an active transcription, a stale record, and genuinely missing retained audio instead of reporting every case as “No retryable recording”; successful retries use the clearer “Retry complete” pill. Parser validation, core type-checking, all 14 credit-free tests, and the unsigned Xcode 27 beta Debug build pass.
- Added consistent breathing room throughout onboarding: all three setup cards now have explicit internal insets and deliberate control spacing, the waveform has a roomier nested surface, the launch/default shortcut area and footer are padded, and the sheet is slightly wider to preserve comfortable line lengths. Parser validation, core type-checking, all 14 credit-free tests, and the unsigned Xcode 27 beta Debug build pass.
- Restored reliable app termination during onboarding by replacing the inherited app-termination command with an explicit “Quit Scriber Dictate” action bound to Command-Q. The onboarding sheet remains protected from accidental dismissal, while users can always defer setup and quit normally. Parser validation, core type-checking, all 14 credit-free tests, and the unsigned Xcode 27 beta Debug build pass.
- Converted onboarding from a main-window-attached sheet into an independent, screen-centered native window. It can be moved or closed to defer setup, reopens from a “Finish Setup…” menu-bar action, dismisses itself after completion, and does not disturb the main window’s initial placement. Dictation is now strictly gated on completed onboarding: permission refreshes cannot start the global shortcut monitor early, menu and shortcut recording entry points are blocked, and History retries cannot issue API calls before setup finishes. Parser validation, core type-checking, all 14 credit-free tests, and the unsigned Xcode 27 beta Debug build pass; live positioning, movement, deferral, and shortcut suppression remain hardware checks.
- Tightened ElevenLabs credential handling. New and updated credentials now use the modern Data Protection Keychain with a code-signed, app-private access group and `WhenUnlockedThisDeviceOnly` protection. Existing legacy items are copied into the protected store and the old unrestricted copy is removed when Scriber Dictate next reads them; this replaces the deprecated `SecAccess` ACL API without suppressing warnings. API-key save/update first performs ElevenLabs' documented, non-generative `GET /v1/models` authentication request, shows a Checking state, reports invalid/restricted/rate-limited/service errors inline, and writes to Keychain only after a successful response. Parser validation, plist validation, all 15 credit-free tests, and unsigned and provisioned/signed Xcode 27 beta Debug builds pass. The signed app contains the expected application identifier and private keychain access-group entitlements. A real valid/restricted key and live legacy-item migration remain manual checks; automated tests never send a credential or contact ElevenLabs.
- Persisted API-key validity and added a once-per-launch check for the stored Keychain credential. Definitive authentication or authorization failures now block recording and History retries before audio capture, including failures discovered by a later transcription, while transient network/service failures preserve the last definitive result. The pill reports the invalid key immediately and offers an Update Key action that opens the ElevenLabs Settings section; Settings and onboarding show Verified/Invalid state, and setup requires a verified key. Parser validation, core type-checking, all 15 credit-free tests, and the unsigned Xcode 27 beta Debug build pass. Live startup checks with a tampered or revoked Keychain item remain manual verification.
- Fixed a false-negative validation exposed by a live, active Speech-to-Text-scoped key. The previous documented `GET /v1/models` probe required an unrelated endpoint scope and could reject a usable Scribe key. Validation now requests a deliberately nonexistent transcript under `/v1/speech-to-text/transcripts`, treating the expected missing/invalid-ID response as proof that authentication and Speech-to-Text authorization succeeded; it uploads no audio and consumes no credits. Parser validation, core type-checking, all 15 credit-free tests, and the unsigned Xcode 27 beta Debug build pass. A final live save/startup check with the affected key remains required.
- Added ElevenLabs credit visibility and exhaustion handling. Save and startup validation now also attempt the credit-free `GET /v1/user/subscription` request, persist the last successful usage snapshot, and show remaining/total credits, plan, reset time, refresh control, and extended-usage status in Settings. Keys without the optional User → Read scope remain verified for Speech-to-Text and show a precise scope note instead of being rejected. Dictation and History retries are blocked before recording when included credits are depleted and ElevenLabs reports no extension allowance; a live `402 insufficient_credits` response also persists the blocked state and opens the same View Usage pill path. Successful transcription refreshes usage in the background. Parser validation, core type-checking, all 16 credit-free tests, and the unsigned Xcode 27 beta Debug build pass. Live verification with full-scope, Speech-to-Text-only, exhausted, and extended-usage accounts remains required.
- Refined API-key Settings behavior from live testing. Credit-usage Retry now calls `/v1/user/subscription` directly with cache bypass and visibly enters a Checking state, so newly granted User → Read scope can refresh without resaving the key. Stored secrets are no longer loaded back into Settings or onboarding: the field stays empty as a replacement-key input, Save remains disabled until text is entered, and success/error feedback shares the Save-button row. Successful save, startup verification, or quota refresh now immediately clears any resolved invalid-key or exhausted-credit pill phase and restores Ready state. Parser validation, core type-checking, all 16 credit-free tests, and the unsigned Xcode 27 beta Debug build pass.

### 2026-07-19

- Moved the floating pill from a SwiftUI content-level glass modifier to an AppKit `NSGlassEffectView` that embeds the entire hosted interface. The pill now uses untinted regular system glass, native interaction response, phase-appropriate native corner radii, and no duplicate generic panel shadow, bringing its backdrop sampling and edges closer to macOS-owned overlays. Parser validation, core type-checking, all 15 credit-free tests, and the unsigned Xcode 27 beta Debug build pass; the final appearance across light, dark, and varied desktop backgrounds remains a live visual check.
- The first timing-only foreground attempt from the pill remained ineffective in live testing because macOS no longer guarantees background activation requests. The pill is now passively ordered without activating Scriber Dictate when it appears, but is an activating AppKit panel when the user intentionally clicks it; window-opening actions also restore the regular activation policy synchronously with that click. An isolated live check confirmed that presenting the invalid-key pill leaves Finder frontmost. Parser validation, core type-checking, all 16 credit-free tests, and the unsigned Xcode 27 beta Debug build pass; the intentional-click transition requires final live confirmation.
- Made the Settings API-key entry visibly editable by using a native rounded secure field with a true replacement-key placeholder while preserving an accessibility label. Parser validation, core type-checking, all 16 credit-free tests, and the unsigned Xcode 27 beta Debug build pass.

## Verification Notes

- Automated tests must not consume ElevenLabs credits.
- A real ElevenLabs smoke test is opt-in.
- Hardware verification must cover `Fn`, `Fn-Space`, `Fn-Control-Option`, target capture, TextEdit, Ghostty, Raycast, a browser text field, a code editor, full-screen apps, multiple Spaces, and Dock auto-hide.
- Signing and Accessibility permission tests must use a stable app path because macOS privacy grants are tied to app identity.
- The current app icon asset catalog is a valid placeholder; final icon artwork is deferred until the application runs end to end.
