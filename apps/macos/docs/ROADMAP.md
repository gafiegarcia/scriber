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
- [ ] **Constrain the Dictation history page width.** Cap its content at the
      Settings page width on large windows so the cards retain balanced side
      margins instead of stretching across the screen.
- [ ] **Restyle the Dictation history cards.** Use a transparent interior with a
      subtle matching border and row separators; retain the continuous corners
      and keep each day label aligned with its card.
- [ ] **Lead shortcut chords with `fn`.** When `fn` is part of a multi-modifier
      shortcut, display it before Control, Option, Shift, and Command.
- [ ] **Show transcript copy confirmation as a toast.** Copying from Dictation
      history presents a brief toast instead of changing the row's copy icon.
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
- [ ] **Reduce the app icon shadow.** **Blocked: the user will edit it in Icon
      Composer and provide the updated icon asset.**

## v0.8.0

- [ ] **Split `Views.swift` and `AppCoordinator.swift`.** History recovery and
      retention are the clearest coordinator boundary. Do this before the
      Transcription workspace lands, not after.
- [ ] **Build the long-form Transcription workspace.** Settings is already grouped
      so Dictation options and Transcription options can sit side by side.
- [ ] **Explore Apple Foundation Models for dictation post-processing.** Confirm
      Scriber can read adjacent context, derive a conservative word limit from
      half the smaller input/output budget or half the context window when
      separate limits are unavailable, and reject requests that exceed it.
- [ ] **Define whole-pill default actions.** Map every pill phase to an explicit,
      unsurprising whole-pill click before enabling that interaction; copied and
      cancelled outcomes need deliberate choices alongside their existing buttons.
- [ ] **Redesign the menu bar menu.** Follow the Claude menu reference: lead with
      Scriber, show the marketing version and build beneath it, and place an Open
      control on the trailing edge.
- [ ] **Show ElevenLabs credit usage in the menu bar menu.** Reuse the existing
      subscription-usage state and make unavailable or restricted usage explicit.
- [ ] **Tint pills by outcome** — green for success, amber for warnings such as
      cancellation and no-words. A design pass across every pill state in light and
      dark on varied backgrounds, not a small edit.
- [ ] **Offer a top pill position** beneath the notch, alongside the current
      bottom placement.
- [ ] **Integrate the pill into the MacBook notch.** Treat this as a separate
      capability from placing the existing pill beneath it.

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
