# Native macOS Product Specification

## Product goal

Scriber is a native macOS menu-bar dictation app intended as a direct replacement for Wispr Flow.

- Remain available from the menu bar.
- Menu-bar presence is user-configurable and enabled by default. Removing the item through macOS updates the same Settings preference; windows, launch-at-login, and global shortcuts continue independently.
- Show the Dock icon while a normal Scriber window is open. “Show app in Dock” is user-configurable and disabled by default; disabling it never closes a visible window. When disabled, closing the final normal window with Command-W, Command-Shift-W, or the red window control removes Scriber from the Dock while menu-bar and dictation services continue. When enabled, Scriber remains in the Dock and app switcher without an open window.
- Save local dictation history.
- Group Dictation history by local calendar date and vertically center each entry's time beside its transcript content.
- Insert each completed transcript into the text cursor that is focused when transcription completes, not the one that was focused when recording began. The user may move focus while transcription runs, and delivery follows that final cursor.
- If insertion cannot be confirmed, preserve the transcript in Dictation history, copy it when appropriate, and present recovery actions in the floating pill.

The product-wide identity, Dictation vocabulary, and future separate Transcription workspace are defined in [`../../../docs/NATIVE_IDENTITY_PLAN.md`](../../../docs/NATIVE_IDENTITY_PLAN.md). Versioning follows [`../../../docs/VERSIONING.md`](../../../docs/VERSIONING.md).

## Shortcuts and job lifecycle

- Default Hold shortcut: hold `Fn` to record; release it to stop and transcribe.
- Default Toggle shortcut: press `Fn-Space` to start hands-free recording; press the configured Toggle shortcut again to stop and transcribe. Hold never stops a hands-free recording.
- Both bindings are configurable.
- While either binding is being configured, all existing global shortcut matching is suspended without removing the Accessibility event tap. Only one shortcut recorder may listen at a time, recognized keys are displayed live, and modifier-only chords preserve the largest combination that was actually held simultaneously.
- Each binding can be disabled independently without losing its configured chord; both are enabled by default. Menu-started hands-free dictation remains available when its keyboard binding is disabled.
- A custom Hold chord such as `Fn-Control-Option` must coexist correctly with Toggle.
- While converting a held recording to hands-free, modifiers used only by Hold are ignored when matching Toggle. Stopping a locked recording requires the exact configured Toggle chord; the Hold chord is ignored while locked.
- During the first second of a held recording, any non-modifier key cancels and discards it while the key continues to the foreground app.
- `Escape` cancels either recording mode. Recordings shorter than one second are discarded; recordings at least one second long with detected speech retain their audio in Dictation history. The recovery pill can undo cancellation and resume transcription plus automatic insertion, while History retry transcribes and copies the result without inserting it.
- Only one recording or transcription job runs at a time in the current alpha.
- Maximum recording duration is 10 minutes.

## Recording and transcription

- Recording feedback sounds are enabled by default and configurable as one setting. Play the built-in macOS Frog sound only after capture starts successfully, Bottle once for a terminal recording or transcription failure, and Morse once when recording is cancelled or automatic paste falls back to a copied transcript. Silence, no-content output, and retry waits remain silent.
- Muting other app audio while recording is enabled by default and offered during onboarding. A private Core Audio process tap silences all audio except Scriber's while playback continues; destroy the tap as soon as capture stops or is cancelled. Never pause or resume another app, and never read, inspect, log, or persist tap audio.
- Failure to create the other-audio mute tap must never prevent dictation. Keep recording unmuted and expose the unavailable state in Settings.
- Use ElevenLabs Scribe v2 batch transcription with `no_verbatim=true` and no secondary rewrite model.
- Include personal keyterms after validating them against Scribe limits.
- Retry transient failures up to three total attempts, waiting 3 seconds and then 5 seconds.
- Delete audio only after a successful transcript has been saved.
- Retain failed or interrupted audio so the job can be retried.
- Do not create a history entry or spend API credit for recordings that never cross the configured signal threshold.
- Treat empty, whitespace-only, and punctuation-only successful responses as “No words detected,” clean up their temporary record and audio, and do not offer a meaningless retry.

## Delivery and floating pill

- Starting a recording must never send an Accessibility message. Accessibility calls are synchronous cross-process requests whose cost is controlled by the destination app, so target discovery belongs to delivery time only. Recording start may resolve the pill's screen from the window server, which does not traverse another app's Accessibility tree.
- Confirming delivery is explicitly allowed to be slow. Waiting several seconds for a destination to request the promised transcript is correct; reporting a false failure is not.
- Show a floating pill at the bottom center of the active screen while recording, transcribing, and reporting terminal states.
- Preserve the previous clipboard after confirmed automatic insertion.
- Mark the temporary promised-text pasteboard item as transient, concealed, and autogenerated so compatible clipboard-history tools do not consume it or expose private in-flight dictation. Treat a request for that concealed text as operational confirmation that the foreground destination handled the paste; observable Accessibility mutation may also provide positive confirmation, but missing Accessibility evidence must never turn a successful opaque-editor paste into failure.
- If the foreground destination does not request the promised text before the bounded timeout and no observable mutation occurs, keep the transcript in Dictation history, republish it as ordinary clipboard text, and present the copied-result recovery UI. Merely dispatching a Paste command is never confirmation.
- Recovery UI may offer Copy, Open, Retry, Update Key, or View Usage according to the failure state.
- The pill must not activate Scriber merely by appearing. Actions that do not open an app window should preserve the foreground app; window-opening actions should intentionally activate Scriber.
- `Escape` or the close control dismisses the visible pill according to its current phase without deleting saved history or retained retry audio.

## Persistence and security

- Store Dictation history locally with SwiftData until the user manually deletes it.
- Retained audio from failed or cancelled dictations expires after 30 days. This is user-configurable and enabled by default. Expiry removes only the recording: the history entry, its transcript, and why it failed are always preserved, and the entry reports that it can no longer be retried. Audio that no dictation references is removed on the same schedule.
- Keep Scriber's SwiftData history in its dedicated `Scriber/History.store`; never use the generic Application Support `default.store` shared by unsandboxed apps.
- Store the API key in the default encrypted macOS login Keychain using modern `SecItem` APIs. This is an interim personal-use workaround for free-team provisioning expiry; never store the key in a plaintext file or `UserDefaults`.
- Keep the storage policy capable of returning to the Data Protection Keychain. A future provisioned build must prefer and migrate the current login-Keychain value before considering an older protected item.
- Never log, export, or persist the key elsewhere.
- Validate credentials without uploading audio or consuming transcription credit before saving them.
- Normal automated tests must not access production credentials, contact ElevenLabs, or consume API credit.
- The Scriber identity is a deliberate clean reset. Do not migrate data from the former Scriber Dictate identity.

## Permissions and app lifecycle

- Microphone permission is required for recording.
- Accessibility permission is required for global shortcut interception and cross-app insertion.
- The system-audio usage description exists solely for optional recording-time muting. Scriber drives its private mute tap with a private aggregate device and an IOProc whose callback discards the buffers untouched; it never inspects, copies, records, or saves system-audio samples.
- After onboarding, missing or revoked Microphone or Accessibility permission must be visible immediately in the Dictation window and menu bar. Scriber must present an actionable permission pill on launch, when a grant is revoked, and when it can observe an attempted dictation; the pill and in-app warning route to Scriber Settings.
- Accessibility revocation prevents Scriber from observing the global shortcut itself, so Scriber must monitor permission state independently, stop unavailable shortcut monitoring, and restart it automatically when the grant returns. It must never rely on the blocked keypress as the only warning path.
- Launch at Login is optional, offered during onboarding, defaults on, and requires explicit consent.
- Every launch presents onboarding until setup is complete, then presents the main Dictation window. Closing the final normal window still leaves menu-bar and dictation services running.
- Onboarding must be complete and the credential definitively usable before recording or Dictation retry can begin.
- App Sandbox remains disabled for the native alpha because global event interception and cross-app Accessibility insertion are core behavior.

## Platform and release boundary

- Native Swift 6.4 app using SwiftUI, AppKit, SwiftData, AVFoundation, Accessibility, and Keychain APIs.
- Toolchain baseline: Xcode 27 beta with Swift 6.4 until a later explicit toolchain decision.
- Current app target: Apple silicon and macOS 27.
- Personal Release builds use the long-lived `Scriber Local Code Signing` identity from the login Keychain, with no provisioning profile or restricted entitlements. Its private-key backup remains outside the repository; Developer ID signing and notarization remain separate future distribution work.
- Current product line: Scriber `0.7.0` build `11`, the `v0.7.0-alpha.7` candidate carrying the 2026-07-26 review pass. The final provisioned Data Protection state is preserved as `v0.7.0-alpha.2`; the locally certificate-signed login-Keychain build is the `v0.7.0-alpha.6` candidate and is not yet a stable `0.7.0` release.
- A real ElevenLabs smoke test is always explicit and opt-in.
