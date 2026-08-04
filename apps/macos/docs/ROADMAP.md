# Native macOS Roadmap

## v0.9.0

- [ ] **Redesign the menu bar menu.** Follow the Claude menu reference: lead with
      Scriber, show the marketing version and build beneath it, and place an Open
      control on the trailing edge.
- [ ] **Search Settings.** Type "mic" in the Settings window and land on the
      setting, whichever of the five tabs holds it. Tabs made Settings scannable;
      this is for the case where the user knows the setting's name but not which
      tab owns it. SwiftUI supplies nothing here — it needs an index of every
      setting with its keywords, a field, results, and a jump that shows which
      control it landed on.
- [ ] **Show ElevenLabs credit usage in the menu bar menu.** Reuse the existing
      subscription-usage state and make unavailable or restricted usage explicit.
- [ ] **Offer a top pill position** beneath the notch, alongside the current
      bottom placement.
- [ ] **Integrate the pill into the MacBook notch.** Treat this as a separate
      capability from placing the existing pill beneath it.
- [ ] **Make a card's date readable without scrolling it to the top.** The
      titlebar's day strip only names the day at the very top of the list, so a
      card lower down — especially on a light day with only a few entries — has
      no visible date at all until it is scrolled there. The cheap fix: show the
      card's full date, greyed out, in its three-dot menu, above **Delete…**, so
      the date is at least reachable per-entry without scrolling. The fuller fix:
      put the date directly on each card and have it hand off to the titlebar
      label exactly when the card reaches the top — the same crossing point
      `DictationHistoryView.currentTitle` already computes — so the label never
      exists in both places at once. Try the cheap fix first; the transition in
      the fuller one is the hard part and may not be worth it.

## Long-term

- [ ] **Cap dictation history to a configurable maximum.** A year of daily use
      could mean thousands of records loaded into memory every time the main
      window opens, similar to how a shell caps its command history
      (`HISTSIZE`). Add a Settings option — generous by default — for the
      maximum number of retained dictations, and decide what happens to
      entries past the cap: delete oldest-first, matching how `Clear Dictation
      History` already removes retained audio, or offer an export first.
      Confirm the cap is actually needed before building it — measure real
      memory use at a few thousand records rather than assuming.
- [ ] **Relicense Scriber under MIT.** Replace GPL-3.0-or-later with the standard
      MIT license for original Scriber code, documentation, and branding assets.
      Remove `COPYRIGHT.md` and the root `THIRD_PARTY_NOTICES.md`; keep only
      distribution guidance that remains relevant inside the archived Electron
      app, and retain every third-party component's own terms. Reduce
      `ICON_PROVENANCE.md` to the current artwork's useful provenance, update the
      READMEs, package metadata, duplicate license files, and all remaining GPL
      references, then verify that no code or asset outside Gaf's rights is
      presented as relicensed.
- [ ] **Build the long-form Transcription workspace.** Settings has a Dictation
      tab, and Transcription options get their own tab beside it. The main
      window's workspace control becomes a picker when this lands.
- [ ] **Order the toolbar for two workspaces.** When the workspace control stops
      being a plain name, lay the toolbar out like this:

      ```
      [ Dictation | Transcription ]  353 dictations   ·gap·   ⚙  ⚠        ·······  [ Search ]
      └──────── what you're looking at ────────┘        └── app-level ──┘
      ```

      The switcher leads because
      it is the subject every other item describes and the one control aimed at
      by muscle memory; the count follows it as its subtitle, and being adjacent
      is what keeps it reading as one rather than as a clickable fact of its
      own. The fixed gap stands in for the trailing cluster this toolbar cannot
      have, marking Settings as app-level rather than part of the workspace, and
      it survives the switcher being wider than a word of text. Settings before
      the warning, so the permanent control holds the fixed position and the
      transient one grows into the gap.
- [ ] **Decide the workspace switcher's control.** Apple's guidance is a tab view
      for view switching and a segmented control only in a toolbar or inspector,
      and this switcher is in a toolbar — so both readings are defensible.
      Evaluate `TabView` first, because Dictation and Transcription are two
      top-level destinations with their own list, query, and scroll position,
      which is what a tab view models and a picker only imitates. Reject it if
      it cannot mount its bar in the existing toolbar beside the count, Settings,
      and search, or if it wants per-tab toolbar items: a toolbar whose items
      vary by destination is what this window crashed on.
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
