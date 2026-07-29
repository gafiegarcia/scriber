# Native macOS Roadmap

## v0.7.1

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
      Calendar app. **Blocked: the design is the user's and is not written
      down — ask before starting.** Worth knowing when measuring a replacement:
      `.coordinateSpace(.named(_:))` on a `List` appears to name the scrolled
      content rather than the viewport, so a label's `minY` never goes negative.

## v0.8.0

- [ ] **Split `Views.swift` and `AppCoordinator.swift`.** History recovery and
      retention are the clearest coordinator boundary. Do this before the
      Transcription workspace lands, not after.
- [ ] **Build the long-form Transcription workspace.** Settings is already grouped
      so Dictation options and Transcription options can sit side by side.
- [ ] **Tint pills by outcome** — green for success, amber for warnings such as
      cancellation and no-words. A design pass across every pill state in light and
      dark on varied backgrounds, not a small edit.
- [ ] **Offer a top pill position** beneath the notch, alongside the current
      bottom placement. A pill integrated *into* the notch is a larger, separate
      idea.

## Long-term

- [ ] **Move to a Developer ID identity.** Then return credential storage to the
      Data Protection Keychain, drop the per-binary **Always Allow** step from the
      README, and add Hardened Runtime, which the local Release configuration
      deliberately omits.
- [ ] **Notarize a downloadable binary**, generating artifact-specific third-party
      notices at that point. A source tag does not need them: the native app
      declares no third-party Swift package dependency, so
      [`THIRD_PARTY_NOTICES.md`](../../../THIRD_PARTY_NOTICES.md) is already
      complete.
- [ ] **Clear the Scriber trademark** before treating the name as settled or
      distributing widely.
- [ ] **Decide contributor terms** before accepting substantial outside
      contributions, if relicensing should stay possible.
