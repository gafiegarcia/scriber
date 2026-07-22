# Native macOS Product Specification

## Product goal

Scriber is a native macOS menu-bar dictation app intended as a direct replacement for Wispr Flow.

- Remain available from the menu bar.
- Show the Dock icon while a normal Scriber window is open. Closing the final normal window with Command-W, Command-Shift-W, or the red window control removes Scriber from the Dock while menu-bar and dictation services continue.
- Save local dictation history.
- Insert each completed transcript into the text element that was active when dictation began.
- If insertion cannot be confirmed, preserve the transcript in Dictation history, copy it when appropriate, and present recovery actions in the floating pill.

The product-wide identity, Dictation vocabulary, and future separate Transcription workspace are defined in [`../../../docs/NATIVE_IDENTITY_PLAN.md`](../../../docs/NATIVE_IDENTITY_PLAN.md). Versioning follows [`../../../docs/VERSIONING.md`](../../../docs/VERSIONING.md).

## Shortcuts and job lifecycle

- Default Hold shortcut: hold `Fn` to record; release it to stop and transcribe.
- Default Toggle shortcut: press `Fn-Space` to start hands-free recording; press either configured shortcut again to stop and transcribe.
- Both bindings are configurable.
- A custom Hold chord such as `Fn-Control-Option` must coexist correctly with Toggle.
- While converting a held recording to hands-free, modifiers used only by Hold are ignored when matching Toggle. Stopping a locked recording requires an exact configured chord.
- `Escape` cancels and discards an active recording.
- Only one recording or transcription job runs at a time in the current alpha.
- Maximum recording duration is 10 minutes.

## Recording and transcription

- Use ElevenLabs Scribe v2 batch transcription with `no_verbatim=true` and no secondary rewrite model.
- Include personal keyterms after validating them against Scribe limits.
- Retry transient failures up to three total attempts, waiting 3 seconds and then 5 seconds.
- Delete audio only after a successful transcript has been saved.
- Retain failed or interrupted audio so the job can be retried.
- Do not create a history entry or spend API credit for recordings that never cross the configured signal threshold.
- Treat empty, whitespace-only, and punctuation-only successful responses as “No words detected,” clean up their temporary record and audio, and do not offer a meaningless retry.

## Delivery and floating pill

- Capture the target text element and selection when recording begins.
- Show a floating pill at the bottom center of the active screen while recording, transcribing, and reporting terminal states.
- Preserve the previous clipboard after confirmed automatic insertion.
- Confirm observable target mutation when Accessibility exposes it. For editors that hide their text state, lazily provide the transcript through the pasteboard and require the destination to request that promised text. Never treat a dispatched Paste command alone as proof of insertion.
- If no editable target was available or insertion cannot be confirmed, keep the transcript in Dictation history and copy it to the clipboard when appropriate.
- Recovery UI may offer Copy, Open, Retry, Update Key, or View Usage according to the failure state.
- The pill must not activate Scriber merely by appearing. Actions that do not open an app window should preserve the foreground app; window-opening actions should intentionally activate Scriber.
- `Escape` or the close control dismisses the visible pill according to its current phase without deleting saved history or retained retry audio.

## Persistence and security

- Store Dictation history locally with SwiftData until the user manually deletes it.
- Store the API key in a dedicated Data Protection Keychain item using app-private access and `WhenUnlockedThisDeviceOnly` protection.
- Never log, export, or persist the key elsewhere.
- Validate credentials without uploading audio or consuming transcription credit before saving them.
- Normal automated tests must not access production credentials, contact ElevenLabs, or consume API credit.
- The Scriber identity is a deliberate clean reset. Do not migrate data from the former Scriber Dictate identity.

## Permissions and app lifecycle

- Microphone permission is required for recording.
- Accessibility permission is required for global shortcut interception and cross-app insertion.
- Launch at Login is optional, offered during onboarding, defaults on, and requires explicit consent.
- Onboarding must be complete and the credential definitively usable before recording or Dictation retry can begin.
- App Sandbox remains disabled for the native alpha because global event interception and cross-app Accessibility insertion are core behavior.

## Platform and release boundary

- Native Swift 6.4 app using SwiftUI, AppKit, SwiftData, AVFoundation, Accessibility, and Keychain APIs.
- Toolchain baseline: Xcode 27 beta with Swift 6.4 until a later explicit toolchain decision.
- Current app target: Apple silicon and macOS 27.
- Current product line: Scriber `0.7.0` build `2`, alpha-stage and not a stable `0.7.0` release.
- A real ElevenLabs smoke test is always explicit and opt-in.
