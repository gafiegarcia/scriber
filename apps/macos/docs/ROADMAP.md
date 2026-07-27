# Native macOS Roadmap

What is left to do, and what has to be true before `v0.7.0` is called stable.

This file used to also hold the manual acceptance checklist, the verification
commands, and a running account of what each build got wrong. Those are now
[`ACCEPTANCE.md`](ACCEPTANCE.md), [`TESTING.md`](TESTING.md), and
[`DEVELOPMENT_LOG.md`](DEVELOPMENT_LOG.md).

## Where the app is

Scriber `0.7.0` build `18` is installed at `/Applications/Scriber.app` and is the
current personal-use candidate. It carries the build 15 bug-and-polish track, the
build 16 pill and settings work, and the planned-work list that had accumulated
from live use: the menu bar icon, the sticky day header, pill activation and
permission routing, and history row polish. Build 17 shipped that track and was
corrected within the hour on live use — the menu bar icon was sized so badly it
pushed every other status item into the overflow, row click-to-copy could not be
made honest alongside selectable text, and a replacement sidebar toggle could not
be placed where AppKit puts the real one. Build 17 is superseded and should not be
installed. Build 18 is also the first installed build carrying the AttributeGraph
fix for the launch-pill wedge; build 16 was installed before that was found.

Nothing on the interface track is outstanding. What stands between here and
stable is verification, not code: [`ACCEPTANCE.md`](ACCEPTANCE.md) is the list,
and most of it needs Gaf, an installed build, and in a few cases a real API key.

Preserved snapshots: `v0.7.0-alpha.8` (build 14), `v0.7.0-alpha.7` (build 11),
`v0.7.0-alpha.6` (build 7, the login-Keychain and local signing state),
`v0.7.0-alpha.2` (the provisioned Data Protection Keychain implementation).

## Milestones

- [x] Capture product behavior and locked native decisions.
- [x] Scaffold and compile the native app.
- [x] Implement recording, transcription, retries, and interrupted-job recovery.
- [x] Implement Accessibility insertion and clipboard-preserving fallback.
- [x] Implement menu-bar, pill, Dictation, Settings, onboarding, and Dock lifecycle.
- [x] Complete the Scriber identity reset and internal rename.
- [x] Integrate documented original app-icon artwork.
- [x] Install an intentionally identified signed build at a stable path.
- [x] Add post-onboarding permission-loss recovery through the Dictation window,
      menu bar, and actionable pill.
- [x] Add configurable Frog/Bottle/Morse feedback, recording-time other-audio
      muting, robust live modifier-chord capture, and shortcut suspension while
      configuring bindings.
- [x] Clear the interface backlog raised from live use of builds 15 and 16, and
      the corrections that live use of build 17 raised against it.
- [ ] Validate bare `Fn` capture and suppression on macOS 27 hardware.
- [ ] Complete the manual acceptance checks in [`ACCEPTANCE.md`](ACCEPTANCE.md).

## Planned work

One open bug, then two features that were deliberately deferred rather than
dropped and are the natural next track when one is wanted.

- **Sidebar toggle flickers switching Settings → Dictation**, but not the other
  way. Long-standing and cosmetic. The one-directional asymmetry is the clue and
  it was not available before: **only Dictation puts a search field in the
  toolbar**, through `.searchable` on `DictationHistoryView`, so that direction
  restructures the toolbar and the other only tears an item out. Untested. The
  obvious fix — hoisting `.searchable` to `MainWindowView` so the toolbar's shape
  never changes — would show a search field on Settings, where it means nothing,
  so it needs a better idea than that. Do not solve it by replacing the toggle:
  that was tried in build 17 and there is no public toolbar placement that puts a
  custom item where AppKit puts the real one.

- **Hands-free pill controls.** The hands-free pill should read as distinct from
  hold-to-dictate, carrying a confirm and a cancel button so a locked recording
  can be stopped or discarded from the pill itself. **Decided: confirm on the
  trailing edge, cancel on the leading edge, invariant.** The failed-paste pill's
  trailing dismiss button does not conflict — that is a dismiss, not a
  destructive alternative to a confirm. A hold that converts to hands-free is the
  normal case with the default `Fn` then `Fn-Space` binding, so the pill must
  animate the two buttons in at its edges as it widens rather than swapping
  layouts. Touches `pillSize`, `applyLayout`, and `actions` in
  [`PillController.swift`](../Scriber/PillController.swift).
- **Pill position setting.** Let the user place the pill at the bottom, as today,
  or at the top just under the notch. Placement is computed in `PillController`
  from `screen.visibleFrame`; a top variant anchors to `maxY` rather than `minY`.
  Needs a `Preferences` key and a control in the General settings section. Low
  priority. Turning the notch itself into the pill is a separate and much larger
  idea; it is recorded, not scoped.

## Known and accepted

Things that look like bugs, are understood, and are not going to be fixed on this
line. Recorded so they are not rediscovered and reinvestigated.

- **One "Always Allow" per installed binary.** macOS requires a fresh
  login-Keychain authorization for the API-key item after each rebuilt binary is
  installed; it then persists across launches and transcriptions of that unchanged
  binary. This is settled and **not worth reinvestigating.** The ACL trusted-
  application list was ruled out twice, once with an item recreated by a
  certificate-signed build and once with the application re-added through Keychain
  Access, which uses the API that records a signed app's designated requirement.
  Neither survived a rebuild carrying a byte-identical designated requirement. The
  remaining gate is the Keychain partition list, and because the local signing
  certificate carries no Team ID there is no stable partition identifier to name —
  so no change to `KeychainStore` can remove the prompt. Accepted as the cost of
  free-tier signing. Evidence is in [`DEVELOPMENT_LOG.md`](DEVELOPMENT_LOG.md)
  under 2026-07-26.
- **Reboot acceptance for the Keychain grant is still open**, separately from the
  above.

## Deferred review findings

Raised by the 2026-07-26 full-codebase review and deliberately not acted on. None
is known to affect current behavior.

- `AppCoordinator` is roughly 1,150 lines covering permissions, credentials,
  recording, transcription, delivery, persistence, muting, and pill state. It is
  coherent rather than tangled, but it is the file where the next feature will
  hurt. History recovery and retention are the most separable pieces.
- `DictationHistoryStore.makePersistentContainer` sleeps on the main thread
  between open attempts. The happy path has a zero delay, so this only blocks a
  launch that is already failing to open the store; making it async would mean
  restructuring `AppRuntime.init`.
- `DictationHistoryView` regroups every record by day on each body evaluation, and
  `clearDictationHistory` saves once per deleted record. Both are irrelevant at
  present history sizes and would matter in the thousands.
- The global event tap swallows an `Escape` key-down while a pill is visible but
  lets its key-up through, so the foreground app can see an unmatched key-up. No
  observed consequence.
- The Release configuration does not enable Hardened Runtime. That is correct for
  the current entitlement-free local signing and becomes a prerequisite only for
  notarized distribution.
- `showInitialWindowWhenAvailable` polls for the startup window by title for up to
  two seconds. A 2026-07-26 unified-log trace showed it exhausting all 40 attempts
  without ever matching on one launch — the window was on screen anyway, placed
  there by SwiftUI — while on other launches it matched at attempt 5 or 16. So it
  is inert on some launches and, before the dismissal guard, actively raced the
  user on others. Removing it needs evidence about which launches still depend on
  it; the comment above `reconcileActivationPolicy` records the Dock-icon failure
  it was written to prevent.

## Release gates

Before promoting the personal-use line to stable `v0.7.0`:

- [ ] Complete the applicable checks in [`ACCEPTANCE.md`](ACCEPTANCE.md). A stable
      source release does not require Developer ID signing or notarization.
- [ ] Run the XCUITest suite end to end once, so the recorded pass count stops
      being stale. See [`TESTING.md`](TESTING.md) — this is Gaf's to start.
- [ ] Generate artifact-specific third-party notices before publishing a
      downloadable binary.
- [ ] Confirm the repository and release artifact contain no credentials,
      recordings, local data, or machine-specific build output.

The final `v0.7.0` tag remains reserved for behavior accepted as stable for
personal use. A supported downloadable binary is a separate distribution-ready
milestone. See [`../../../docs/VERSIONING.md`](../../../docs/VERSIONING.md).

## After v0.7.0

- On moving to a Developer ID identity, collapse the free-tier signing
  workarounds: return credential storage to the Data Protection Keychain as
  [`PRODUCT_SPEC.md`](PRODUCT_SPEC.md) already requires, drop the per-build
  "Always Allow" authorization, and simplify the build and install instructions in
  [`../README.md`](../README.md). The recorded designated requirement, the manual
  signature check, the `/Applications`-only install, and the Keychain-prompt
  caveat exist solely to work around signing without a Team ID; none of them
  survives that transition.
