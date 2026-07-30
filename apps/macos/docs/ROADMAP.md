# Native macOS Roadmap

## v0.7.2

- [ ] **Reduce the app icon shadow.** **Blocked: the user will edit it in Icon
      Composer and provide the updated icon asset.**

## v0.8.0

- [ ] **Split `AppCoordinator.swift`.** History recovery and retention are the
      clearest coordinator boundary. Do this before the Transcription workspace
      lands, not after.
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
      dark on varied backgrounds, not a small edit. Take the outcome-to-tone
      mapping from `ScriberCore/Toasts.swift`, which the window's toast stack
      already uses, so the two surfaces cannot disagree.
- [ ] **Offer a top pill position** beneath the notch, alongside the current
      bottom placement.
- [ ] **Integrate the pill into the MacBook notch.** Treat this as a separate
      capability from placing the existing pill beneath it.

## Long-term

- [ ] **Extend window-owned search to Transcription.** After the long-form
      Transcription workspace exists, reuse the persistent native search item
      with a contextual `Search Transcriptions` placeholder, retain a separate
      query for each workspace, and make Command-F focus the active searchable
      workspace.
- [ ] **Add an all-content search scope.** After Dictation and Transcription
      search both exist, let users broaden the current query without replacing
      it, keep the selected scope visible while text is present, and present
      mixed results grouped by workspace.
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
