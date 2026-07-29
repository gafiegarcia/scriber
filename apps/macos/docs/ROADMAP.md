# Roadmap

Work that is planned but not built, grouped by the release it is meant for. An
item stays here until it ships, then leaves — the changelog and git hold what
already happened.

Every item names a version. If a new task has no obvious home, decide its version
when it arrives rather than parking it in a list of unscheduled ideas.

## 0.7.1

- [ ] **Stop the missing-permissions pill respawning.** It reappears and restarts
      its dismissal timer whenever a Scriber window gains focus, so it covers the
      screen for the whole System Settings trip it is asking for.
- [ ] **Remove the sidebar toggle.** Its placement cannot be reproduced by a
      custom control, it cannot carry a tooltip, and it flickers on
      Settings → Dictation because only Dictation contributes a `.searchable`
      toolbar item. Hoisting search to the shared window would wrongly expose it
      in Settings. Removing the control also ends the `⌘.` question, since nothing
      would be left to toggle.
- [ ] **Confirm and cancel controls on the hands-free pill.** Confirm on the
      trailing edge, cancel on the leading edge; that ordering is fixed. When Hold
      converts to hands-free, widen the existing pill and animate both controls in
      rather than swapping layouts.
- [ ] **Redesign the floating day label.** The current one never appears at any
      scroll offset. It is being replaced, not repaired; the reference is the macOS
      Calendar app. **Blocked: the design is Gaf's and is not written down — ask
      him before starting.** Worth knowing when measuring a replacement:
      `.coordinateSpace(.named(_:))` on a `List` appears to name the scrolled
      content rather than the viewport, so a label's `minY` never goes negative.

## 0.8.0

The long-form Transcription workspace, and what has to happen before it.

- [ ] **Split `Views.swift` and `AppCoordinator.swift`.** Left whole through
      `0.7.0` deliberately. History recovery and retention are the clearest
      coordinator boundary. Do this before the workspace lands, not after.
- [ ] **Build the Transcription workspace.** Settings is already grouped so that
      Dictation options and Transcription options can sit side by side.
- [ ] **Tint pills by outcome** — green for success, amber for warnings such as
      cancellation and no-words. A design pass across every pill state in light and
      dark on varied backgrounds, not a small edit.
- [ ] **Offer a top pill position** beneath the notch, alongside the current
      bottom placement. A pill integrated *into* the notch is a larger, separate
      idea.

## Distribution

Not scheduled, and independent of the version number. No `0.x` release implies
any of it.

- [ ] **Move to a Developer ID identity.** Then return credential storage to the
      Data Protection Keychain, drop the per-binary **Always Allow** step from the
      README, and add Hardened Runtime, which the local Release configuration
      deliberately omits.
- [ ] **Notarize a downloadable binary**, and generate artifact-specific
      third-party notices at that point. A source tag does not need them: the
      native app declares no third-party Swift package dependency, so
      [`THIRD_PARTY_NOTICES.md`](../../../THIRD_PARTY_NOTICES.md) is already
      complete.
- [ ] **Clear the Scriber trademark** before treating the name as settled or
      distributing widely.
- [ ] **Decide contributor terms** before accepting substantial outside
      contributions, if relicensing should stay possible.

## Known issues with no fix planned

Wrong, and staying wrong for now. Anything here that gets scheduled moves up into
a version above.

- `DictationHistoryStore.makePersistentContainer` sleeps on the main thread
  between failed store-open attempts. Making it asynchronous requires redesigning
  `AppRuntime` initialization.
- `DictationHistoryView` regroups records by day on every body evaluation, and
  clearing history saves once per record. Only worth revisiting if a large history
  makes either measurable.
- The global event tap consumes Escape key-down while a pill is visible but lets
  the key-up through. No consequence observed.
- `showInitialWindowWhenAvailable` polls for the startup window by title. Remove
  it only after proving which launch paths still depend on it; the adjacent code
  comment records the Dock-lifecycle constraint.
