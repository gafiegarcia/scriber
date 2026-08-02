# Native macOS Roadmap

## v0.8.2
- [x] **Tint pills by outcome** — green for success, amber for warnings such as cancellation and no-words. A design pass across every pill state in light and dark on varied backgrounds, not a small edit. Take the outcome-to-tone mapping from `ScriberCore/Toasts.swift`, which the window's toast stack already uses, so the two surfaces cannot disagree.
- [x] **Define whole-pill default actions.** Map every pill phase to an explicit, unsurprising whole-pill click before enabling that interaction; copied and cancelled outcomes need deliberate choices alongside their existing buttons.
- [x] **Reduce the app icon shadow.**
- [x] **Verify Speech-to-Text-only API keys.** With account-usage access disabled, confirm Scriber accepts the key, allows dictation, and reports credit usage as unavailable without marking the key invalid.

## v0.8.3

- [x] Change tintAlpha of pill to 0.07.
- [ ] **Show Cancel during held recording too.** Give every recording mode the
      leading Cancel control, so locking into hands-free animates only Confirm
      in rather than both. `showsHandsFreeRecordingControls` in
      `ScriberCore/CoreModels.swift` gates both today and has to split; the
      pill's held width and its expansion animation both change with it.
- [ ] **Add specular highlight to pill.** Add specular highlights at the sides of the pill (the automatic shiny border liquid glass effect, if available).
- [ ] **Overhaul the backdrop for date label.** Current implementation is adding an opaque background spanning the full width of the label, but I don't like the discontinuity it creates when scrolling: entries text going up when scrolled goes under an opaque background under the date label, but then goes under a *translucent* background under the toolbar. My idea is experiment with no opaque background at all (date label text now fighting against scrolled entries) *but* add a text shadow to the label. Might look corny, but worth to explore.


## v0.9.0

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

- [ ] **Relicense Scriber under MIT.** Replace GPL-3.0-or-later with the standard
      MIT license for original Scriber code, documentation, and branding assets.
      Remove `COPYRIGHT.md` and the root `THIRD_PARTY_NOTICES.md`; keep only
      distribution guidance that remains relevant inside the archived Electron
      app, and retain every third-party component's own terms. Reduce
      `ICON_PROVENANCE.md` to the current artwork's useful provenance, update the
      READMEs, package metadata, duplicate license files, and all remaining GPL
      references, then verify that no code or asset outside Gaf's rights is
      presented as relicensed.
- [ ] **Build the long-form Transcription workspace.** Settings is already grouped
      so Dictation options and Transcription options can sit side by side, and the
      main window's workspace control becomes a picker when this lands.
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
