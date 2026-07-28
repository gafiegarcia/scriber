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
icon all passed. What remains open is a restart check, a fresh-onboarding pass, and
one supervised XCUITest run.

Contrary to the previous claim here that no implementation task remained, five
now exist. None is a correctness bug in dictation itself:

- The floating day label never appears while scrolling, at any offset.
- A microphone at zero input volume fails completely silently — no transcript, no
  entry, no warning.
- The missing-permissions pill respawns and resets its timer on every window
  focus, so it obstructs the screen throughout exactly the task it is prompting.
- The retry-success pill is too brief to read, and the same outcome is worded two
  different ways across pills.
- Command-period does nothing inside the Clear Dictation History dialog.

[`ACCEPTANCE.md`](ACCEPTANCE.md) holds all five with detail, plus four requested
improvements that are not defects.

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
- [ ] Resolve the five open findings in [`ACCEPTANCE.md`](ACCEPTANCE.md), or
      consciously accept each as a known limitation of the tag.
- [ ] Finish the last three person-only checks in
      [`ACCEPTANCE.md`](ACCEPTANCE.md): a restart, a fresh onboarding pass, and the
      XCUITest suite.

## Non-blocking deferred work

These items are deliberately outside the `v0.7.0` gate. They remain
recorded so they are not mistaken for forgotten release blockers.

- **Sidebar-toggle flicker:** Settings → Dictation briefly flickers while the
  reverse transition does not. Only Dictation contributes a `.searchable`
  toolbar item, so that direction changes toolbar structure. Hoisting search to
  the shared window would incorrectly expose it in Settings, and replacing the
  native sidebar control cannot reproduce AppKit's placement. Keep this cosmetic
  issue deferred until there is a better design.
- **Hands-free pill controls:** add a confirm control on the trailing edge and a
  cancel control on the leading edge; that ordering is invariant. When Hold is
  converted to hands-free, widen the existing pill and animate both controls in
  rather than swapping layouts.
- **Pill position:** offer bottom placement, as today, or top placement beneath
  the notch. A pill integrated into the notch is a separate, larger idea and is
  not scoped here.

## Known and accepted

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
      over the pointer and keyboard; see [`TESTING.md`](TESTING.md).
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
