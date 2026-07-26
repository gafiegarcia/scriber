# Native macOS Roadmap

## Current status

Scriber `0.7.0` build `15` is the current personal-installation candidate for Apple silicon on macOS 27. It carries the bug-and-polish track consolidated from the Notion sprint list and the loose notes: the settings regrouping, the history cards, the trailing-aligned overflow menu, in-flight dictations hidden from history, the no-words warning, the static menu-bar icon, and the Command-comma and Command-period bindings. It is **not yet installed or manually verified** — see the checks below. Build `14`, which fixes the startup window reopening after an early Command-W and carries a `window-lifecycle` diagnostic log, is preserved as `v0.7.0-alpha.8` and is the installed app. Build `11`, which carries the 2026-07-26 review pass, is preserved as `v0.7.0-alpha.7`. Builds `12` and `13` carry no source change and exist only as test vehicles for the Keychain re-authorization investigation below.

Carried forward from build 7, which is preserved as `v0.7.0-alpha.6`: the dedicated `Scriber/History.store`, the encrypted login-Keychain policy, and the long-lived local `Scriber Local Code Signing` identity that gives rebuilt Release bundles one stable designated requirement without a provisioning profile. macOS still requires one new “Always Allow” authorization for the login-Keychain API-key item after each rebuilt binary is installed; it then persists across launches and transcriptions of that unchanged binary. Reboot acceptance remains open. The preceding provisioned Data Protection Keychain implementation is preserved as `v0.7.0-alpha.2`.

That re-authorization is settled and is not worth reinvestigating. The ACL trusted-application list has been ruled out twice — once with an item recreated by a certificate-signed build, once with the application re-added through Keychain Access, which uses the API that records a signed app's designated requirement. Neither survived a rebuild carrying a byte-identical designated requirement. The remaining gate is the Keychain partition list, and because the local signing certificate carries no Team ID there is no stable partition identifier to name, so no change to `KeychainStore` can remove the prompt. Accepted as the cost of free-tier signing; a paid Developer ID would resolve it structurally, along with notarization. Evidence is in [`DEVELOPMENT_LOG.md`](DEVELOPMENT_LOG.md) under 2026-07-26.

Builds 8 through 11 carry the 2026-07-26 review pass. Build 8 moved delivery to the live cursor and took Accessibility off the record-start path; build 9 fixed the false-success regression that shipped with it; build 11 made delivery follow keyboard focus so dictation reaches nonactivating panels such as Raycast. The paste engine's rationale, its standing constraints, and its regression baseline live in [`PASTE_ENGINE_RESEARCH.md`](PASTE_ENGINE_RESEARCH.md) — read it before changing delivery, target selection, or confirmation.

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
- [x] Preserve the locally certificate-signed login-Keychain build as `v0.7.0-alpha.6`; live permission and reboot acceptance remains open.
- [x] Install an intentionally identified signed build at a stable path.
- [x] Add post-onboarding permission-loss recovery through the Dictation window, menu bar, and actionable pill.
- [x] Add configurable Frog/Bottle/Morse feedback, recording-time other-audio muting, robust live modifier-chord capture, and shortcut suspension while configuring bindings.
- [ ] On moving to a Developer ID identity, collapse the free-tier signing workarounds: return credential storage to the Data Protection Keychain as [`PRODUCT_SPEC.md`](PRODUCT_SPEC.md) already requires, drop the per-build “Always Allow” authorization, and simplify the build and install instructions in [`../README.md`](../README.md). The recorded designated requirement, the manual signature check, the `/Applications`-only install, and the Keychain-prompt caveat exist solely to work around signing without a Team ID; none of them survives that transition.

## Open acceptance checks

### Build 15 interface changes

None of these need a real API key except where noted.

- [ ] Settings shows General, Feedback, ElevenLabs, Dictation, Dictation History, and Permissions and Input in that order, with Accessibility above Microphone.
- [ ] Command-comma opens Settings both with the main window open and with every window closed.
- [ ] Command-period collapses and expands the sidebar, and the View menu shows it in place of Control-Command-S. Then confirm Command-period still cancels the Clear Dictation History dialog rather than toggling the sidebar behind it — Command-period is macOS's conventional Cancel, and this binding shadows it.
- [ ] Command-F still focuses search, and the placeholder carries the hint.
- [ ] The overflow menu opens fully inside the window with the window at its default width near the right edge of the screen.
- [ ] Day groups render as rounded cards, legibly, in both light and dark appearance.
- [ ] Start a dictation and watch history through the wait: no row appears until the outcome lands. Then retry a failed entry and confirm its row stays visible with the Retrying label.
- [ ] **Needs a real key.** Mute or unplug the selected input, dictate for several seconds, and confirm the no-words pill appears with the failure sound, dismisses after about six seconds, and its button scrolls Settings to the microphone picker. Confirm no history row is left behind.
- [ ] The menu bar icon matches its neighbours in size, holds steady through a full record, transcribe, and paste cycle, switches to the warning symbol when the API key is removed, and returns to the app mark when it is restored — without relaunching.

### Installation, identity, and lifecycle

- [x] Build the Apple Development-signed Debug configuration and entitlement-free locally certificate-signed Release configuration with Xcode 27 beta.
- [x] Install the verified locally certificate-signed Release build at `/Applications/Scriber.app`.
- [ ] Complete fresh onboarding under the `com.gafiegarcia.scriber` identity.
- [ ] Verify Microphone and Accessibility grants persist for the stable app.
- [ ] Revoke Microphone and Accessibility separately and together after onboarding; verify the proactive warning, permission pill, Settings route, and automatic shortcut-monitor recovery after regranting.
- [ ] Verify Launch at Login registration, first-login dictation after persistent-store readiness, relaunch, and opt-out.
- [ ] Verify launch presents onboarding before setup and the main Dictation window after setup.
- [ ] Verify Command-W, Command-Shift-W, and the red window control remove the final normal window and Dock icon without terminating menu-bar or dictation services when “Show app in Dock” is disabled.
- [ ] Verify “Show app in Dock” persists, keeps Scriber in the Dock and app switcher after the final window closes when enabled, and does not close a visible window when disabled.
- [ ] Verify the Show in Menu Bar setting, restoration after re-enabling, and preference synchronization after Command-drag removal.

### Credentials, quota, and transcription

- [ ] Remove or corrupt the stored key, relaunch, and confirm Scriber reports it on its own — pill, Dictation banner, and menu bar — without waiting for a dictation attempt.
- [ ] Confirm the same for exhausted credits, and that recovery routes to the usage panel rather than the key field.
- [ ] Confirm retained audio older than 30 days is removed at launch while its history entry, transcript, and failure reason survive, and that disabling the preference stops the sweep.

- [ ] Re-enter, save, and read back a real Speech-to-Text-scoped ElevenLabs key across relaunch and restart from the installed locally signed build.
- [ ] Verify startup handling for valid, revoked, tampered, restricted-scope, and transiently unreachable credentials.
- [ ] Verify subscription usage for full-scope, Speech-to-Text-only, exhausted, and extended-usage accounts.
- [ ] Run an explicitly approved real transcription smoke test; never include this in normal automation.
- [ ] Verify empty/punctuation-only API output and retained-audio retry behavior live.

### Recording and shortcuts

- [ ] Test bare `Fn`, `Fn-Space`, and custom `Fn-Control-Option` Hold behavior with competing dictation and global-shortcut tools disabled.
- [ ] Verify every press/release order records and live-displays `Fn-Control-Option`, only one binding recorder listens at a time, and neither configured shortcut nor global Escape handling fires while a recorder is listening.
- [ ] Verify Frog plays once after Hold, Toggle, and menu capture starts; Bottle plays once for terminal microphone/transcription failures; Morse plays once for cancellation and copied paste fallback; silence, no-content output, and retries remain silent; confirm the preference disables all feedback.
- [ ] With Music, Spotify, Safari, and QuickTime, verify other audio advances silently only during capture, newly started audio is also muted, Frog remains audible, output returns immediately on stop/cancel/failure, and disabling the setting leaves audio unchanged.
- [ ] Verify tap creation with System Audio Recording allowed and denied on macOS 27; denial or Core Audio failure must continue dictation unmuted and report the unavailable state only in Settings.
- [ ] Verify held-to-hands-free conversion, exact Toggle-only locked-recording stop semantics, and that Hold is ignored while locked.
- [ ] Verify independently disabling and re-enabling Hold and Toggle preserves each chord and prevents only the disabled keyboard action.
- [ ] Verify early typing cancellation, short and recoverable Escape cancellation, Undo, History retry, and pill dismissal across other apps and full-screen windows.
- [ ] Verify 10-minute auto-stop, silence rejection, selected/default/disconnected microphone behavior, and live waveform response.
- [ ] Confirm the configured macOS Globe/Fn action does not interfere; use “Do Nothing” during testing if necessary.

### Insertion and fallback

- [x] Confirm recording starts immediately in the apps that previously took two to three seconds. Verified on build 8 in ChatGPT, Notion, and Zen.
- [x] Confirm delivery lands at the cursor focused when the transcript arrives. Verified on build 8: ChatGPT `pasted`, Notion `pasted`, Zen with a focused field `pasted`, Zen on `x.com` without one `copied`.
- [x] Close the build 8 false-success regression. Build 9 classified 14 consecutive dictations correctly across `claude.ai`, the Claude desktop app, ChatGPT, Notion, `x.com`, and Finder, including the no-focused-field case on both a live page and a native app. The table in [`PASTE_ENGINE_RESEARCH.md`](PASTE_ENGINE_RESEARCH.md) is the regression baseline.
- [ ] Confirm moving focus to a different app or field during transcription delivers to the final cursor.
- [ ] Confirm the pill still appears on the screen holding the app that was frontmost at record start, now that its screen comes from the window server rather than Accessibility.

- [x] Close the paste-confirmation regression with Raycast running: Xcode, ChatGPT, and Notion confirm success without a false recovery panel, while Zen with no focused text box produces copied recovery.
- [ ] Verify target capture, selection restoration, confirmed insertion, clipboard restoration, and copied fallback in TextEdit.
- [x] Repeat insertion checks in Ghostty, Raycast, VS Code, and Zed. Raycast needed the build 11 keyboard-focus fix; its command bar and its Notes window both deliver correctly now. Codex remains unchecked.
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

Build Debug and Release configurations from `apps/macos/Scriber.xcodeproj` with Xcode 27 beta. Release must use its configured `Scriber Local Code Signing` identity and contain neither an embedded provisioning profile nor restricted Keychain entitlements. Separately built Release bundles must satisfy the same certificate-based designated requirement.

Run isolated UI regressions from `apps/macos`:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Scriber.xcodeproj -scheme Scriber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-ui-tests test
```

The first UI-test run requires a signed test host and macOS UI Automation approval. Automated tests must use isolated data and services and must never access the real Keychain, mutate real SwiftData, contact ElevenLabs, or consume API credit.

### Known state of the UI suite

The suite has never been fully green, and earlier log entries recording "all UI tests pass" describe a four-test suite that has since grown to eleven. The first end-to-end run was 2026-07-26 on build 14: **eight pass, three fail**. The same three fail identically at `d183b4d`, so they predate the 2026-07-26 review pass. Do not read these as regressions from recent work.

**Build 15 ran the four affected tests only, and all four pass:** `testCommandFFocusesDictationSearch`, `testCommandFFromSettingsRoutesToDictationSearch`, `testRecordingFeedbackDefaultsCanBeDisabled`, and `testReturnSubmitsAPIKeyFromSettings`, in about 19 seconds. Those are the tests that read the controls the settings regrouping moved, plus the one that locates the search field by its prompt — a string build 15 changed and updated in the test alongside. The full suite was not run: it seizes the pointer and keyboard for its whole duration, and the three known failures each burn a full timeout first, so it is not something to start while the Mac is in use. Expect the same three failures when it is run; a **fourth** is a real regression.

Selective runs are worth knowing about, since they make this cheap:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Scriber.xcodeproj -scheme Scriber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-ui-tests -only-testing:ScriberUITests/ScriberUITests/testCommandFFocusesDictationSearch test
```

- `testEscapeDismissesPersistentPill` **cannot pass unattended.** Escape reaches the app through `GlobalShortcutService`'s `CGEvent` tap, which needs Accessibility trust. The test host is a throwaway binary in `.build/`, not `/Applications/Scriber.app`, so it is untrusted and the tap never arms. Fixing this means granting a DerivedData binary Accessibility, which is worse than the failure. Treat it as manual-only.
- `testClosingFinalWindowUsesAccessoryActivationPolicy` and `testUpdateKeyForegroundsSettingsAndFocusesAPIKeyField` both fail on the same assertion: the process does not drop to `.accessory` after Command-W. **The product behavior is correct** — verified by hand on build 14, where the Dock icon disappears. The unconfirmed hypothesis is that `reconcileActivationPolicy` discards the `Bool` from `setActivationPolicy`, and macOS refuses to demote the frontmost application; under XCUITest the runner holds Scriber active, while a manual close hands focus to another app. Confirm that return value before changing anything here — an unverified "fix" to activation policy risks the Dock-icon bugs this code was written to prevent.

## Planned work

Raised from live use of build 15 on 2026-07-27 and not yet acted on.

- **Sticky date-group header.** The date label is small and easy to miss where it
  sits. Move it into the row that currently holds the dictation count, transitioning
  in place as the user scrolls between day groups, and move the permission and
  credential warning banners above it — directly under the title and search row.
  This restructures `DictationHistoryView`'s header and its `List` together and is
  the largest of these; do it as its own change, not folded into a polish pass.
- **Pill "Review" does not fully arrive.** From the permissions pill, Review opens
  the window and selects Settings, but it does not bring Scriber forward when the
  window is already open behind another app, and it does not scroll to Permissions
  and Input, which sits at the bottom of a long Settings pane. The scroll needs a
  `MainWindowDestination` case anchored on that section, matching how `.apiKey` and
  `.microphone` already work. The activation half needs diagnosis first —
  `AppDelegate.showWindow` does call `activate`, so establish why it does not take
  effect before changing it.
- **Sidebar toggle tooltip.** Should read "Hide Sidebar (⌘.)" / "Show Sidebar (⌘.)".
  The control is supplied by `NavigationSplitView`, so this likely means providing
  a toolbar item rather than configuring the built-in one.
- **Sidebar toggle button flickers** when switching between Dictation and Settings,
  as though the toolbar is torn down and rebuilt on each selection change.
  Long-standing, cosmetic, cause unknown.

### Deferred to a later track

Deliberately not built with the build 15 track, and recorded here so the Notion
notes they came from are no longer the source of truth.

- **Hands-free pill controls.** The hands-free pill should read as distinct from
  hold-to-dictate, carrying a confirm and a cancel button so a locked recording can
  be stopped or discarded from the pill itself. **Decided: confirm on the trailing
  edge, cancel on the leading edge, invariant.** The failed-paste pill's trailing
  dismiss button does not conflict — that is a dismiss, not a destructive
  alternative to a confirm. A hold that converts to hands-free is the normal case
  with the default `Fn` then `Fn-Space` binding, so the pill must animate the two
  buttons in at its edges as it widens rather than swapping layouts. Touches
  `pillSize`, `applyLayout`, and `actions` in [`PillController.swift`](../Scriber/PillController.swift).
- **Pill position setting.** Let the user place the pill at the bottom, as today, or
  at the top just under the notch. Placement is computed in `PillController` from
  `screen.visibleFrame`; a top variant anchors to `maxY` rather than `minY`. Needs a
  `Preferences` key and a control in the General settings section. Low priority.
  Turning the notch itself into the pill is a separate and much larger idea; it is
  recorded, not scoped.

## Deferred review findings

Raised by the 2026-07-26 full-codebase review and deliberately not acted on. None
of these is known to affect current behavior; each is recorded so it does not have
to be rediscovered.

- `AppCoordinator` is roughly 1,150 lines covering permissions, credentials, recording, transcription, delivery, persistence, muting, and pill state. It is coherent rather than tangled, but it is the file where the next feature will hurt. History recovery and retention are the most separable pieces.
- `DictationHistoryStore.makePersistentContainer` sleeps on the main thread between open attempts. The happy path has a zero delay, so this only blocks a launch that is already failing to open the store; making it async would mean restructuring `AppRuntime.init`.
- `DictationHistoryView` regroups every record by day on each body evaluation, and `clearDictationHistory` saves once per deleted record. Both are irrelevant at present history sizes and would matter in the thousands.
- The global event tap swallows an `Escape` key-down while a pill is visible but lets its key-up through, so the foreground app can see an unmatched key-up. No observed consequence.
- The Release configuration does not enable Hardened Runtime. That is correct for the current entitlement-free local signing and becomes a prerequisite only for notarized distribution.
- `showInitialWindowWhenAvailable` polls for the startup window by title for up to two seconds. A 2026-07-26 unified-log trace showed it exhausting all 40 attempts without ever matching on one launch — the window was on screen anyway, placed there by SwiftUI — while on other launches it matched at attempt 5 or 16. So it is inert on some launches and, before the dismissal guard, actively raced the user on others. Removing it needs evidence about which launches still depend on it; the comment above `reconcileActivationPolicy` records the Dock-icon failure it was written to prevent.

## Release gates

Before promoting the personal-use line to stable `v0.7.0`:

- [ ] Complete the applicable functional checks above; a stable source release does not require Developer ID signing or notarization.
- [x] Decide that the remaining formal acceptance gaps are acceptable for the first personal alpha snapshot.
- [x] Increment the login-Keychain personal candidate to bundle build `7`.
- [x] Increment the review-pass candidate through bundle builds `8` to `11`, ending with the keyboard-focus delivery fix.
- [x] Increment to bundle build `15` for the consolidated bug-and-polish track.
- [ ] Generate artifact-specific third-party notices before publishing a downloadable binary.
- [ ] Confirm the repository and release artifact contain no credentials, recordings, local data, or machine-specific build output.

The final `v0.7.0` tag remains reserved for behavior accepted as stable for personal use. A supported downloadable binary remains a separate distribution-ready milestone. See [`../../../docs/VERSIONING.md`](../../../docs/VERSIONING.md).
