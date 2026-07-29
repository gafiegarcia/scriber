# Native macOS Roadmap

What is left to build after `v0.7.0`.
Required behavior belongs in [Product specification](PRODUCT_SPEC.md), human
checks in [Manual checks](MANUAL_CHECKS.md), and machine checks in
[Automated checks](AUTOMATED_CHECKS.md). Git is the engineering history.

## Where things stand

`v0.7.0` is tagged at native bundle build 30, installed and in daily use. The
tag's own annotation is the record of what was verified for it and what was not;
git holds the session detail. This file tracks what comes next.

Three limitations ship with it by decision rather than oversight, and two of them
are waiting on redesigns rather than fixes. See
[Known and accepted](#known-and-accepted).

The Xcode project is the source of truth for the current bundle build, and the
root [changelog](../../../CHANGELOG.md) lists only tagged snapshots.

## Milestones

Everything planned for `v0.7.0` is done: the product behaviour and native
decisions, recording and transcription with retries and interrupted-job recovery,
live-cursor insertion with clipboard-preserving fallback, the full interface —
menu bar, pill, Dictation, Settings, onboarding, permissions, Dock lifecycle,
feedback, other-audio muting, configurable shortcuts — the identity reset, local
persistence, icon provenance, and the personal-install signing path. Git holds
the per-milestone history.

## The sprint list this release came from

Gaf's nine-item list is complete except for one, checked against the code rather
than from memory. Items 1–7 and 9 shipped in `v0.7.0`; git and the changelog
record them.

- [ ] **8. Confirm and cancel controls on the hands-free pill.** The recording
      pill still has no interactive controls. Routed to `0.7.1` by Gaf's own plan
      on the sprint page — bug fixes to `v0.7.0`, features after it. The design is
      in [Non-blocking deferred work](#non-blocking-deferred-work).

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
  today (see [`MANUAL_CHECKS.md`](MANUAL_CHECKS.md)), and Gaf intends to replace the
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

## The XCUITest suite was removed

Deleted on build 30, with the `ScriberUITests` target, by Gaf's decision. This
records why, so it is not reintroduced by default reasoning about what a project
"should" have.

It cost more than it returned, and the cost fell on the wrong resource. XCUITest
drives the real pointer and keyboard, so every run took Gaf's machine away from
him for its duration — and because the suite was unreliable, a single question
usually took several runs. There is no CI here. On a hosted runner a flaky UI
suite wastes machine minutes; on a solo, vibe-coded project it spends the one
resource actually in short supply, on a utility app that is a nice-to-have.

By Gaf's own count it earned its keep once, for the commit that made Command-F
reachable from anywhere. Set against that:

- **It could only ever test the shell.** Under `--ui-testing` every service is
  disabled, so it never covered dictation, insertion, shortcuts, credentials, or
  real permissions — the parts that can actually fail a user.
- **Five of thirteen tests could not produce a verdict.** Two skipped by design,
  needing Accessibility trust no `.build/` binary has or should be granted;
  three failed for an unidentified reason that also reproduces on `main`.
- **It duplicated the acceptance list.** The behaviour the failing tests covered
  — Dock lifecycle, feedback preferences — is checked by hand in
  [`MANUAL_CHECKS.md`](MANUAL_CHECKS.md) and passes there.
- **Untrustworthy results cost more than absent ones.** Most of the session that
  ran it went into proving three failures were not regressions.

What is no longer covered automatically: focus routing, the Command-F routes,
sidebar selection, activation-policy and Dock-lifecycle transitions, and the
simulated pill layouts. These now rest on [`MANUAL_CHECKS.md`](MANUAL_CHECKS.md) and
on Gaf using Scriber daily, which surfaces a shell regression within hours.

What remains, and is doing the real work: the 66 package tests, which run in
milliseconds, need nobody present, and cover actual logic; and the launch smoke
check, which is one command and has caught a main-thread wedge that no test did.

If UI coverage is ever wanted again, the bar is a specific regression that a
package test provably cannot catch — not a general belief that a UI suite is
good practice.

## Known and accepted

Shipped in `v0.7.0` as known limitations by Gaf's decision rather than as
oversights. None affects whether a dictation works. The first three are also
listed in the changelog.

- The floating day label never appears while scrolling. Being redesigned, not
  repaired — see the deferred-work note above.
- The missing-permissions pill respawns and resets its dismissal timer on every
  window focus, so it obstructs the screen throughout the System Settings trip it
  is prompting. The most worth fixing of the three; a `0.7.1` candidate.
- `⌘.` does nothing inside the Clear Dictation History dialog. It does **not**
  toggle the sidebar behind the dialog, which was the actual risk. Likely
  unfixable as written, since SwiftUI does not expose a `confirmationDialog`'s
  cancel action — and moot once the sidebar toggle is removed.

Two more, both consequences of the personal signing path rather than defects:

- A newly installed locally signed binary requires one login-Keychain password
  prompt for the ElevenLabs item. Choosing **Always Allow** persists for that
  unchanged binary, but a rebuild prompts again because the local certificate
  has no Team ID suitable for a stable Keychain partition. This is the accepted
  cost of the personal signing path, not an open `KeychainStore` investigation.
- The key survives a reboot without a further password prompt. Confirmed for
  `v0.7.0`; it stays on the installation checks in
  [`MANUAL_CHECKS.md`](MANUAL_CHECKS.md) because a rebuild can reintroduce the
  prompt.

## Deferred technical work

None of these findings is known to affect current behavior.

- `Views.swift` and `AppCoordinator.swift` were deliberately left whole through
  `v0.7.0`. They can now be split along coherent feature areas — history recovery
  and retention are the clearest coordinator boundary — and should be, before the
  Transcription workspace lands.
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

All met for `v0.7.0`. Kept as the shape of the next release; reset the boxes when
a cycle starts.

- [x] Complete the applicable checks in [`MANUAL_CHECKS.md`](MANUAL_CHECKS.md). A source
      release does not require Developer ID signing or notarization. Every check
      that needs a person has been run. Two refinements added in build 29 —
      chord commit-on-release against a real keyboard, and removing the *real*
      API key — are recorded as not yet exercised, with the reasoning for why
      neither blocks; see [Requested](MANUAL_CHECKS.md#requested-not-defects).
- [x] ~~Run the XCUITest suite end to end once.~~ **Gate retired.** It was run on
      build 30 and was not clean; Gaf then removed the suite rather than repair
      it. A gate cannot be met by deleting what it measures, so it is withdrawn
      rather than marked passed. The shell behaviour it covered is verified by
      hand in [`MANUAL_CHECKS.md`](MANUAL_CHECKS.md). See
      [The XCUITest suite was removed](#the-xcuitest-suite-was-removed).
- [ ] Generate artifact-specific third-party notices before publishing a
      downloadable binary. Not a gate on a source tag: the native app declares no
      third-party Swift package dependency, so
      [`THIRD_PARTY_NOTICES.md`](../../../THIRD_PARTY_NOTICES.md) is already the
      complete inventory for it. This becomes real work only when a binary ships.
- [x] Confirm the repository and release artifact contain no credentials,
      recordings, local data, or machine-specific build output. Checked on build
      28: no key-shaped literals in tracked content, `.gitignore` covers audio,
      local signing config, and every build root, and the Release bundle carries
      no entitlements and no provisioning profile. Re-confirmed on build 30 after
      the UI-test target was removed: strict verification passes, the designated
      requirement is unchanged, there is no provisioning profile, and the Release
      binary contains no test-only symbols or launch-argument literals.

The tag is reserved for behavior accepted for personal use, and claims nothing
beyond that. A supported downloadable binary is a separate distribution
milestone; see the [versioning policy](../../../docs/VERSIONING.md), which also
records how versions move after `v0.7.0`.

## Longer-term, not scheduled

- On moving to a Developer ID identity, return credential storage to the Data
  Protection Keychain, remove the per-binary **Always Allow** workaround, and
  simplify the local-signing installation guidance.
- Complete trademark clearance before treating Scriber as a settled public name
  or distributing it broadly.
- Decide contributor terms before accepting substantial outside contributions
  if future relicensing or dual licensing should remain possible.
- Revisit the deferred Swift file boundaries before expanding the product with a
  separate long-form Transcription workspace.
