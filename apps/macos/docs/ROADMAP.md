# Native macOS Roadmap

## v0.8.1

- [ ] make it so that opening the app for the first time, or opening the window again (like when clicking "Open Scriber"
      via menubar) will move focus to the search bar. I hate that the first-focused element is the first button on the first entry
- [ ] remove liquid glass styling on “Dictation” top row bar (what’s it called? top bar? menu bar? title bar? top row?). let it be just text for now.
- [ ] make the separators between entries in a card extend full width, touching the card's border; refer to [the design mockup](../../../.designs/redesign-idea-v0.7.1.html)
- [ ] make the date group label have similar styling to my mockup, gradual transparency instead of a solid liquid glass capsule

## v0.8.2
- [ ] **Tint pills by outcome** — green for success, amber for warnings such as
      cancellation and no-words. A design pass across every pill state in light and
      dark on varied backgrounds, not a small edit. Take the outcome-to-tone
      mapping from `ScriberCore/Toasts.swift`, which the window's toast stack
      already uses, so the two surfaces cannot disagree.
- [ ] **Define whole-pill default actions.** Map every pill phase to an explicit,
      unsurprising whole-pill click before enabling that interaction; copied and
      cancelled outcomes need deliberate choices alongside their existing buttons.
- [ ] **Reduce the app icon shadow.** **Blocked: the user will edit it in Icon
      Composer and provide the updated icon asset.**

## v0.9.0

- [ ] **Split `AppCoordinator.swift`.** History recovery and retention are the
      clearest coordinator boundary. Do this before the Transcription workspace
      lands, not after.
- [ ] **Build the long-form Transcription workspace.** Settings is already grouped
      so Dictation options and Transcription options can sit side by side, and the
      main window's workspace control becomes a picker when this lands.
- [ ] **Redesign the menu bar menu.** Follow the Claude menu reference: lead with
      Scriber, show the marketing version and build beneath it, and place an Open
      control on the trailing edge.
- [ ] **Show ElevenLabs credit usage in the menu bar menu.** Reuse the existing
      subscription-usage state and make unavailable or restricted usage explicit.
- [ ] **Offer a top pill position** beneath the notch, alongside the current
      bottom placement.
- [ ] **Integrate the pill into the MacBook notch.** Treat this as a separate
      capability from placing the existing pill beneath it.

## Long-term

- [ ] **Explore Apple Foundation Models for dictation post-processing.** Confirm
      Scriber can read adjacent context, derive a conservative word limit from
      half the smaller input/output budget or half the context window when
      separate limits are unavailable, and reject requests that exceed it.
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
