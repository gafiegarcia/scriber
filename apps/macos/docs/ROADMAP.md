# Native macOS Roadmap

## Current status

Scriber `0.7.0` build `4` is the `v0.7.0-alpha.3` personal-installation candidate for Apple silicon on macOS 27. The preceding provisioned Data Protection Keychain implementation is preserved by annotated tag `v0.7.0-alpha.2`. Build 4 uses the encrypted login Keychain and an ad-hoc Release signature to avoid free-team provisioning expiry; stable-path installation and manual acceptance remain open. The paste-confirmation investigation remains resolved for personal use and its rationale lives in [`PASTE_ENGINE_RESEARCH.md`](PASTE_ENGINE_RESEARCH.md).

## Milestones

- [x] Capture product behavior and locked native decisions.
- [x] Scaffold and compile the native app.
- [x] Implement recording, transcription, retries, and interrupted-job recovery.
- [x] Implement Accessibility insertion and clipboard-preserving fallback.
- [x] Implement menu-bar, pill, Dictation, Settings, onboarding, and Dock lifecycle.
- [x] Complete the Scriber identity reset and internal rename.
- [x] Integrate documented original app-icon artwork.
- [ ] Validate bare `Fn` capture and suppression on macOS 27 hardware.
- [ ] Complete automated and signed manual acceptance checks.
- [x] Preserve the final provisioned Data Protection Keychain state as annotated tag `v0.7.0-alpha.2`.
- [ ] Accept and tag the ad-hoc login-Keychain build as `v0.7.0-alpha.3`.
- [ ] Install an intentionally identified signed build at a stable path.

## Open acceptance checks

### Installation, identity, and lifecycle

- [x] Build the Apple Development-signed Debug configuration and entitlement-free ad-hoc-signed Release configuration with Xcode 27 beta.
- [x] Install the verified ad-hoc Release build at `/Applications/Scriber.app`.
- [ ] Complete fresh onboarding under the `com.gafiegarcia.scriber` identity.
- [ ] Verify Microphone and Accessibility grants persist for the stable app.
- [ ] Verify Launch at Login registration, relaunch, and opt-out.
- [ ] Verify launch presents onboarding before setup and the main Dictation window after setup.
- [ ] Verify Command-W, Command-Shift-W, and the red window control remove the final normal window and Dock icon without terminating menu-bar or dictation services when “Show app in Dock” is disabled.
- [ ] Verify “Show app in Dock” persists, keeps Scriber in the Dock and app switcher after the final window closes when enabled, and does not close a visible window when disabled.
- [ ] Verify the Show in Menu Bar setting, restoration after re-enabling, and preference synchronization after Command-drag removal.

### Credentials, quota, and transcription

- [ ] Re-enter, save, and read back a real Speech-to-Text-scoped ElevenLabs key across relaunch and restart from the installed ad-hoc build.
- [ ] Verify startup handling for valid, revoked, tampered, restricted-scope, and transiently unreachable credentials.
- [ ] Verify subscription usage for full-scope, Speech-to-Text-only, exhausted, and extended-usage accounts.
- [ ] Run an explicitly approved real transcription smoke test; never include this in normal automation.
- [ ] Verify empty/punctuation-only API output and retained-audio retry behavior live.

### Recording and shortcuts

- [ ] Test bare `Fn`, `Fn-Space`, and custom `Fn-Control-Option` Hold behavior with competing dictation and global-shortcut tools disabled.
- [ ] Verify held-to-hands-free conversion, exact Toggle-only locked-recording stop semantics, and that Hold is ignored while locked.
- [ ] Verify independently disabling and re-enabling Hold and Toggle preserves each chord and prevents only the disabled keyboard action.
- [ ] Verify early typing cancellation, short and recoverable Escape cancellation, Undo, History retry, and pill dismissal across other apps and full-screen windows.
- [ ] Verify 10-minute auto-stop, silence rejection, selected/default/disconnected microphone behavior, and live waveform response.
- [ ] Confirm the configured macOS Globe/Fn action does not interfere; use “Do Nothing” during testing if necessary.

### Insertion and fallback

- [x] Close the paste-confirmation regression with Raycast running: Xcode, ChatGPT, and Notion confirm success without a false recovery panel, while Zen with no focused text box produces copied recovery.
- [ ] Verify target capture, selection restoration, confirmed insertion, clipboard restoration, and copied fallback in TextEdit.
- [ ] Repeat insertion checks in Ghostty, Raycast, Zen with a focused field, Zen without a focused field, VS Code, Zed, Notion, ChatGPT, and Codex without treating missing Accessibility evidence as failure.
- [ ] Verify behavior when the focused target disappears, moves its selection, is secure/disabled, or exposes no focused Accessibility element.
- [ ] Verify menu-command and PID-targeted paste fallbacks without false success reporting, including with Raycast clipboard history running and the transient/concealed markers honored.

### Pill, windows, and visual behavior

- [ ] Check compact and copied-result pill shape, glass, countdown, hover pause, transitions, and dismissal on varied light and dark backgrounds.
- [ ] Verify pill placement in full-screen apps, multiple Spaces, multiple displays, and with Dock auto-hide.
- [ ] With Scriber in accessory mode and Finder frontmost, click Update Key; confirm Settings and the key field become focused, then verify one Command-Tab returns to Scriber after switching to Finder.
- [ ] Repeat using non-window pill actions and confirm Finder remains focused while Scriber stays absent from the Dock and Command-Tab.
- [ ] Review the app icon in Dock, Finder, default, dark, tinted, and small-size contexts.

## Automated verification

Run from the repository root with the Xcode 27 beta toolchain:

```bash
swiftc -frontend -parse apps/macos/Scriber/*.swift apps/macos/ScriberCore/*.swift apps/macos/ScriberCoreTests/*.swift apps/macos/ScriberUITests/*.swift
swiftc -module-cache-path apps/macos/.build/module-cache -typecheck apps/macos/ScriberCore/CoreModels.swift apps/macos/ScriberCore/ScribeClient.swift apps/macos/ScriberCore/CredentialStore.swift
swift test --package-path apps/macos
plutil -lint apps/macos/Scriber/Info.plist
```

Build Debug and Release configurations from `apps/macos/Scriber.xcodeproj` with Xcode 27 beta. Release must use its configured ad-hoc identity and contain neither an embedded provisioning profile nor restricted Keychain entitlements.

Run isolated UI regressions from `apps/macos`:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Scriber.xcodeproj -scheme Scriber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-ui-tests test
```

The first UI-test run requires a signed test host and macOS UI Automation approval. Automated tests must use isolated data and services and must never access the real Keychain, mutate real SwiftData, contact ElevenLabs, or consume API credit.

## Release gates

Before promoting the personal-use line to stable `v0.7.0`:

- [ ] Complete the applicable functional checks above; a stable source release does not require Developer ID signing or notarization.
- [x] Decide that the remaining formal acceptance gaps are acceptable for the first personal alpha snapshot.
- [x] Increment the login-Keychain personal candidate to bundle build `4`.
- [ ] Generate artifact-specific third-party notices before publishing a downloadable binary.
- [ ] Confirm the repository and release artifact contain no credentials, recordings, local data, or machine-specific build output.

The final `v0.7.0` tag remains reserved for behavior accepted as stable for personal use. A supported downloadable binary remains a separate distribution-ready milestone. See [`../../../docs/VERSIONING.md`](../../../docs/VERSIONING.md).
