# Native macOS Roadmap

What remains before the `v0.7.0` tag can be cut.
Required behavior belongs in [Product specification](PRODUCT_SPEC.md), human
checks in [Acceptance](ACCEPTANCE.md), and machine checks in
[Testing](TESTING.md). Git is the engineering history.

## Current position

The native feature track planned for `v0.7.0` is complete. Verification is most
of what remains, and the interface half of it is now done: the machine-drivable
checks in [`ACCEPTANCE.md`](ACCEPTANCE.md) were closed against a seeded build,
which left three findings and one open design question rather than a clean pass.

Gaf then worked through the sessions that need a person, on the same build. The
dictation core, shortcuts, insertion, permissions, Dock lifecycle, appearance, and
icon all passed.

On build 29 he cleared the restart check — grants, Launch at Login, and the stored
key all survived a reboot — and ran fresh onboarding, which worked but placed its
window off the bottom of the screen, under the Dock. Build 30 fixes that. One
supervised XCUITest run is the only person-only check still outstanding.

That pass produced five implementation tasks, contrary to the previous claim here
that none remained. Build 29 closed the two that changed what a user can tell
about their own dictation, and added three requested actions:

- Fixed: a microphone at zero input volume failed completely silently. Rejecting
  it below the signal threshold is still correct and still costs no credit; it now
  says so, and says something different from "no words were recognised".
- Fixed: the copied-transcript pill was too brief to read on the retry path, and
  named the same outcome two different ways.
- Added: Remove Key…, Redo Onboarding…, and chord recording that commits at the
  first key release.

Three carried forward by Gaf's decision, none of which affects whether a dictation
works:

- The floating day label never appears while scrolling, at any offset.
- The missing-permissions pill respawns and resets its timer on every window
  focus, so it obstructs the screen throughout exactly the task it is prompting.
- Command-period does nothing inside the Clear Dictation History dialog. Likely
  unfixable: SwiftUI does not expose a `confirmationDialog`'s cancel action, and
  the failure the check was written to catch — the sidebar toggling behind the
  dialog — does not happen.

[`ACCEPTANCE.md`](ACCEPTANCE.md) holds all of them with detail, plus the deferred
pill-tinting design pass.

The Xcode project is the source of truth for the current bundle build, and the
root [changelog](../../../CHANGELOG.md) lists only snapshots that were actually
tagged.

## Milestones

- [x] Capture product behavior and locked native decisions.
- [x] Implement recording, transcription, retries, and interrupted-job recovery.
- [x] Implement live-cursor insertion, clipboard-preserving fallback, and the
      cross-app regression baseline.
- [x] Implement the menu bar, pill, Dictation, Settings, onboarding, permissions,
      Dock lifecycle, feedback, other-audio muting, and configurable shortcuts.
- [x] Complete the clean Scriber identity reset, local persistence, icon
      provenance, and personal-install signing path.
- [x] Complete the planned `v0.7.0` interface and polish track.
- [x] Confirm before deleting history, one entry or all of it.
- [x] Close the machine-drivable interface checks in
      [`ACCEPTANCE.md`](ACCEPTANCE.md), which required seeding a test build's
      history so the Dictation list could be inspected without risking real
      entries or spending credit.
- [x] Validate bare `Fn` capture and suppression on macOS 27 hardware. Confirmed
      on build 28 with Wispr Flow quit: Hold fires on bare `Fn`, and because the
      modifier event is deliberately left unconsumed, `Fn`'s other jobs — the emoji
      picker, a normal Space, ordinary typing — keep working.
- [x] Report a rejected-for-silence recording instead of discarding it without a
      word, and distinguish it from a recording that carried sound but produced no
      words.
- [x] Decide whether the three carried-forward findings ship as known limitations
      of `v0.7.0` or block it. Gaf's call: they ship. None affects whether a
      dictation works, and two of the three are about to be redesigned rather than
      patched. See [Known and accepted](#known-and-accepted).
- [x] Verify a restart preserves the Microphone and Accessibility grants, the
      stored key, and the Launch at Login setting in both directions. Build 29.
- [x] Give the onboarding window a placement that fits the screen. It was
      cascaded from the main window and ran under the Dock; it is now sized to the
      display and centred on every appearance, and scrolls rather than overflowing.
- [x] Run the XCUITest suite end to end on build 30. Done, but not clean: 8
      passed, 2 skipped by design, 3 failed. Every failure reproduces on
      `origin/main`, so none is a regression from this branch; all three are a
      SwiftUI `Switch` reporting `Not hittable` while reading its value
      correctly. See [`ACCEPTANCE.md`](ACCEPTANCE.md) and
      [`TESTING.md`](TESTING.md).
- [ ] **Gaf's decision, and the last thing before the tag:** whether an unclean
      suite blocks `v0.7.0`, given the failures predate the branch, are confined
      to the SwiftUI shell, and contradict by-hand checks of the same behaviour
      that pass.

## Non-blocking deferred work

These items are deliberately outside the `v0.7.0` gate. They remain
recorded so they are not mistaken for forgotten release blockers.

- **The sidebar toggle is planned for removal, not repair.** It has cost more
  vibe-coding effort than it has ever returned: its placement cannot be reproduced
  by a custom control, it cannot carry a tooltip, and it flickers on the
  Settings → Dictation transition but not the reverse — because only Dictation
  contributes a `.searchable` toolbar item, so that direction restructures the
  toolbar. Hoisting search to the shared window would wrongly expose it in
  Settings. Do not spend further effort on the flicker; the control is going away.
  Removing it also settles the `⌘.` binding question, since there would be nothing
  left for it to toggle.
- **The floating day label is to be redesigned, not fixed.** It never appears
  today (see [`ACCEPTANCE.md`](ACCEPTANCE.md)), and Gaf intends to replace the
  whole idea rather than repair the current one. The reference is the macOS
  Calendar app's date behaviour. **The design is Gaf's and has not been written
  down yet — ask him for it before touching this.** The existing diagnosis of why
  the current implementation never fires is still worth keeping, since a
  replacement will face the same measurement problem.
- **Hands-free pill controls:** add a confirm control on the trailing edge and a
  cancel control on the leading edge; that ordering is invariant. When Hold is
  converted to hands-free, widen the existing pill and animate both controls in
  rather than swapping layouts.
- **Pill position:** offer bottom placement, as today, or top placement beneath
  the notch. A pill integrated into the notch is a separate, larger idea and is
  not scoped here.

## Known and accepted

These three ship with `v0.7.0`. Gaf decided each is a known limitation rather than
a blocker; none affects whether a dictation works.

- The floating day label never appears while scrolling. Being redesigned, not
  repaired — see the deferred-work note above.
- The missing-permissions pill respawns and resets its dismissal timer on every
  window focus, so it obstructs the screen throughout the System Settings trip it
  is prompting. The most worth fixing of the three; a `0.7.1` candidate.
- `⌘.` does nothing inside the Clear Dictation History dialog. It does **not**
  toggle the sidebar behind the dialog, which was the actual risk. Likely
  unfixable as written, since SwiftUI does not expose a `confirmationDialog`'s
  cancel action — and moot once the sidebar toggle is removed.


- A newly installed locally signed binary requires one login-Keychain password
  prompt for the ElevenLabs item. Choosing **Always Allow** persists for that
  unchanged binary, but a rebuild prompts again because the local certificate
  has no Team ID suitable for a stable Keychain partition. This is the accepted
  cost of the personal signing path, not an open `KeychainStore` investigation.
- Reboot acceptance for the Keychain grant remains open and is covered by the
  installation checks in [`ACCEPTANCE.md`](ACCEPTANCE.md).

## Deferred technical work

None of these findings is known to affect current behavior.

- Do not split `Views.swift` or `AppCoordinator.swift` before `v0.7.0`.
  Afterwards, separate coherent feature areas—history recovery and retention are
  the clearest coordinator boundary—before adding the Transcription workspace.
- `DictationHistoryStore.makePersistentContainer` sleeps on the main thread only
  between failed store-open attempts. Making that path asynchronous requires an
  `AppRuntime` initialization redesign.
- `DictationHistoryView` regroups records by day on each body evaluation, and
  clearing history saves once per record. Revisit only if large histories make
  either measurable.
- The global event tap consumes Escape key-down while a pill is visible but lets
  the matching key-up reach the foreground app. No consequence has been
  observed.
- Hardened Runtime is intentionally absent from the entitlement-free local
  Release configuration. It becomes required for notarized distribution.
- `showInitialWindowWhenAvailable` polls for the startup window by title. Remove
  it only after proving which launch paths still depend on it; the adjacent code
  comment records the Dock-lifecycle constraint.

## Release gates

Before creating `v0.7.0`:

- [ ] Complete the applicable checks in [`ACCEPTANCE.md`](ACCEPTANCE.md). A source
      release does not require Developer ID signing or notarization.
- [ ] Run the XCUITest suite end to end once. Gaf must start it because it takes
      over the pointer and keyboard; see [`TESTING.md`](TESTING.md). Run on
      build 30 and **not clean** — three pre-existing failures that also occur on
      `main`. Whether that meets this gate is Gaf's call, not an assumption to
      make here.
- [ ] Generate artifact-specific third-party notices before publishing a
      downloadable binary. Not a gate on a source tag: the native app declares no
      third-party Swift package dependency, so
      [`THIRD_PARTY_NOTICES.md`](../../../THIRD_PARTY_NOTICES.md) is already the
      complete inventory for it. This becomes real work only when a binary ships.
- [x] Confirm the repository and release artifact contain no credentials,
      recordings, local data, or machine-specific build output. Checked on build
      28: no key-shaped literals in tracked content, `.gitignore` covers audio,
      local signing config, and every build root, and the Release bundle carries
      no entitlements and no provisioning profile.

The tag is reserved for behavior accepted for personal use, and claims nothing
beyond that. A supported downloadable binary is a separate distribution
milestone; see the [versioning policy](../../../docs/VERSIONING.md), which also
records how versions move after `v0.7.0`.

## After v0.7.0

- On moving to a Developer ID identity, return credential storage to the Data
  Protection Keychain, remove the per-binary **Always Allow** workaround, and
  simplify the local-signing installation guidance.
- Complete trademark clearance before treating Scriber as a settled public name
  or distributing it broadly.
- Decide contributor terms before accepting substantial outside contributions
  if future relicensing or dual licensing should remain possible.
- Revisit the deferred Swift file boundaries before expanding the product with a
  separate long-form Transcription workspace.
