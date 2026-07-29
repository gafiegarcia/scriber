# Checks Only a Person Can Run

Everything that has to be checked by hand before a release, because no machine
here can check it. Checks a machine can run live in
[`AUTOMATED_CHECKS.md`](AUTOMATED_CHECKS.md) and are not repeated.

There is no UI test suite — it was removed in `v0.7.0` and
[`ROADMAP.md`](ROADMAP.md) records why — so this file is the only coverage the
SwiftUI shell has.

**Never run a check that spends API credit without asking Gaf first.** The items
marked **real key** do spend it.

## How to use this file

The boxes are per-release, not permanent. Reset them when a release cycle starts;
a tag's annotation records what was actually verified for that release, and git
holds the detailed session notes. An unchecked box means "not verified this
cycle", not "known broken" — anything actually broken is in
[`ROADMAP.md`](ROADMAP.md) under Known and accepted.

Checks that are already known to fail are marked **known limitation** with a
pointer. Do not re-investigate those; they are decisions, not surprises.

Some checks need real revoked permissions, a real key, or a restart. Those are
worth batching into one sitting rather than interrupting a day repeatedly.

## Interface

- [ ] The menu bar icon reads well at a glance next to its neighbours, holds
      steady through a record/transcribe/paste cycle, switches to the warning
      symbol when the API key is removed, and returns to the app mark when it is
      restored — without relaunching and without the item jumping width. If it
      ever wants to sit shorter, `menuBarIconHeight` in `ScriberApp` is the only
      number to change.
- [ ] Copy a single-line entry: the icon changes to a checkmark for about a second
      and a half and **the row does not change height** while it does. Sizing the
      icon frame on both axes is what earns this.
- [ ] The copy and overflow buttons are plain borderless icons, each taking a
      near-threshold background under the pointer. Glass was tried and rejected.
      Retry sits to their left, so copy and the overflow land on the same two
      positions in every row whether or not Retry is present.
- [ ] Failed and cancelled entries keep a copy button rather than dropping it, and
      it reads clearly as unavailable — muted well below the transcript, not
      merely a different colour. The disabled button does nothing when clicked.
- [ ] The overflow menu's Delete… asks for confirmation first, and confirming
      removes the right entry and only it. Cancelling leaves it alone. The row's
      right-click Delete… asks the same way. **Delete is not red in the menu, and
      will not be** — macOS does not tint destructive menu items, unlike iOS; see
      the note in `DictationHistoryRow`. macOS *does* tint it in the dialog.
- [ ] The overflow popup grows from the leading edge and may overhang the window.
      That is the built-in behaviour and is preferred over the custom control that
      used to align it; its hover background also sits slightly right of the
      glyph. Both are known and accepted — not worth another attempt.
- [ ] Clicking anywhere else on a row does nothing: no highlight, no copy. The row
      still right-clicks to its context menu, which offers only Delete… on an
      entry with nothing to copy and no audio to retry.
- [ ] Permission and credential banners sit directly under the title and search
      row, above the count row. The Dictation header has no overflow menu — just
      the day and the count.
- [ ] Settings → Dictation History ends with Clear Dictation History…, showing the
      entry count, disabled when there is nothing to clear, and confirming first.
- [ ] The entry time sits close to the card's leading edge and the overflow button
      close to its trailing edge, with no wide empty margin inside the card.
- [ ] Day groups render as rounded cards, legibly, in both light and dark.
- [ ] The sidebar toggle sits over the sidebar, beside the window controls. It has
      no tooltip; see the note in `MainWindowView` for why a custom item cannot go
      there. **The control is planned for removal** — see [`ROADMAP.md`](ROADMAP.md)
      — so its known flicker on Settings → Dictation is not worth chasing.
- [ ] Settings shows General, Feedback, ElevenLabs, Dictation, Dictation History,
      and Permissions and Input in that order, with Accessibility above Microphone.
- [ ] Command-comma opens Settings both with the main window open and with every
      window closed.
- [ ] Command-F focuses search from either pane, and the placeholder carries the
      `⌘F` hint.
- [ ] Command-period collapses and expands the sidebar, and the View menu shows it
      in place of Control-Command-S. **Known limitation:** it does nothing inside
      the Clear Dictation History dialog.
- [ ] Scrolling a history list with more than one day: the count row does not
      change height. **Known limitation:** the floating day label never appears.
- [ ] Start a dictation and watch history through the wait: no row appears until
      the outcome lands. Retry a failed entry and confirm its row stays visible
      with the Retrying label, and that the copied-transcript pill lasts long
      enough to read. **real key**
- [ ] Punctuation-only or no-content output leaves no history row behind.
      **real key**
- [ ] Set the input volume to zero, dictate, and confirm the "No sound from the
      microphone" pill appears with the failure sound and its button scrolls
      Settings to the microphone picker. Then mute or unplug the selected input
      mid-speech and confirm the *no-words* pill instead — these are two different
      outcomes and must stay distinguishable. Neither leaves a history row, and
      neither spends credit.
- [ ] From the permissions pill, Review brings Scriber to the front over whatever
      app is active — with the main window open behind that app, and with every
      window closed — and lands on Permissions and Input rather than the top of
      Settings. Same for the menu bar's "Permissions Required…" item. Needs real
      revoked permissions.

## Installation, identity, and lifecycle

- [ ] Build the Apple Development-signed Debug and entitlement-free locally
      certificate-signed Release configurations, and install the verified Release
      build at `/Applications/Scriber.app`.
- [ ] Complete fresh onboarding under the `com.gafiegarcia.scriber` identity:
      launch presents onboarding before setup and the Dictation window after it,
      and the setup window is centred and fully visible above the Dock. Check both
      a genuine first run and Settings → Redo Onboarding… with the main window
      already open. Reset with
      `defaults delete com.gafiegarcia.scriber onboardingComplete`.
- [ ] Microphone and Accessibility grants persist across a restart, and the stored
      key still reads back without a login-Keychain prompt.
- [ ] Revoke Microphone and Accessibility separately and together after
      onboarding: the proactive warning, permission pill, Settings route, and
      automatic shortcut-monitor recovery after regranting all behave. Note that
      **macOS itself forces Quit & Reopen whenever Microphone access changes**, so
      no-relaunch recovery can only be observed for Accessibility. **Known
      limitation:** the pill is intrusive throughout, respawning on every window
      focus.
- [ ] Launch at Login registration, first-login dictation after persistent-store
      readiness, relaunch, and opt-out — confirming it stays off.
- [ ] Command-W, Command-Shift-W, and the red window control remove the final
      normal window and Dock icon without terminating menu-bar or dictation
      services when "Show app in Dock" is disabled.
- [ ] "Show app in Dock" persists, keeps Scriber in the Dock and app switcher
      after the final window closes when enabled, and does not close a visible
      window when disabled.
- [ ] Show in Menu Bar, restoration after re-enabling, and preference
      synchronization after Command-drag removal. This has been trouble-free since
      the menu bar shipped. **Do not diagnose this from `defaults`:** a
      `NSStatusItem VisibleCC Item-0 = 0` reading alongside `showInMenuBar = 1`
      once produced a confident bug report about an icon that was never hidden.
      Look at the menu bar.

## Credentials, quota, and transcription

- [ ] Remove or corrupt the stored key, relaunch, and confirm Scriber reports it
      on its own — pill, Dictation banner, and menu bar — without waiting for a
      dictation attempt, and that restoring it clears all three without a
      relaunch. Settings → Remove Key… is the supported route; Keychain Access is
      no longer needed.
- [ ] The same for exhausted credits, with recovery routing to the usage panel
      rather than the key field.
- [ ] Retained audio older than 30 days is removed at launch while its history
      entry, transcript, and failure reason survive, and disabling the preference
      stops the sweep.
- [ ] Re-enter, save, and read back a real Speech-to-Text-scoped ElevenLabs key
      across relaunch and restart from the installed locally signed build.
      **real key**
- [ ] Startup handling for valid, revoked, tampered, restricted-scope, and
      transiently unreachable credentials. **real key**
- [ ] Subscription usage for full-scope, Speech-to-Text-only, exhausted, and
      extended-usage accounts. **real key**
- [ ] An explicitly approved real transcription smoke test; never in automation.
      **real key**
- [ ] Empty and punctuation-only API output, and retained-audio retry, live.
      **real key**

## Recording and shortcuts

- [ ] Bare `Fn`, `Fn-Space`, and a custom `Fn-Control-Option` Hold binding, with
      competing dictation and global-shortcut tools disabled. **Wispr Flow is
      installed on this machine and must be quit first.**
- [ ] Scriber leaving the `Fn` key event unconsumed keeps `Fn`'s other jobs
      working — the emoji picker, a normal Space, ordinary typing. This is the
      observable consequence of `GlobalShortcutService` returning `false` for
      modifier-only chords; swallowing `flagsChanged` would leave the foreground
      app with stale modifier state.
- [ ] Every press/release order records and live-displays `Fn-Control-Option`,
      the recorder closes at the *first* key release with the full chord, only one
      recorder listens at a time, and neither configured shortcut nor global
      Escape fires while one is listening.
- [ ] Frog plays once after Hold, Toggle, and menu capture starts; Bottle once for
      terminal microphone and transcription failures; Morse once for cancellation
      and copied paste fallback; silence, no-content output, and retries stay
      silent. The preference disables all of it.
- [ ] With Music, Spotify, Safari, and QuickTime: other audio advances silently
      only during capture, newly started audio is also muted, Frog stays audible,
      output returns immediately on stop/cancel/failure, and disabling the setting
      leaves audio unchanged.
- [ ] Tap creation with System Audio Recording allowed and denied on macOS 27.
      Denial or Core Audio failure must continue dictation unmuted and report the
      unavailable state only in Settings.
- [ ] Held-to-hands-free conversion, exact Toggle-only locked-recording stop
      semantics, and Hold ignored while locked.
- [ ] Independently disabling and re-enabling Hold and Toggle preserves each chord
      and prevents only the disabled action.
- [ ] Early typing cancellation and Escape cancellation, each with the
      cancellation sound.
- [ ] 10-minute auto-stop, silence rejection, selected/default/disconnected
      microphone behaviour, and live waveform response.
- [ ] The configured macOS Globe/Fn action does not interfere; use "Do Nothing"
      during testing if necessary.

## Insertion and fallback

Read [`PASTE_ENGINE.md`](PASTE_ENGINE.md) before changing anything these checks
cover. Its table is the regression baseline.

- [ ] Recording starts immediately — no two-to-three-second delay — in ChatGPT,
      Notion, and Zen.
- [ ] Delivery lands at the cursor focused when the transcript arrives, and a
      target with no focused field falls back to copied rather than reporting a
      false success.
- [ ] Paste confirmation with Raycast running: Xcode, ChatGPT, and Notion confirm
      success without a false recovery panel, while Zen with no focused text box
      produces copied recovery.
- [ ] Ghostty, Raycast, VS Code, and Zed. Raycast's command bar and its Notes
      window both deliver correctly. Codex remains unchecked.
- [ ] Moving focus to a different app or field *during* transcription delivers to
      the final cursor, not the original one.
- [ ] The pill appears on the screen holding the app that was frontmost at record
      start.
- [ ] Target capture, selection restoration, confirmed insertion, clipboard
      restoration, and copied fallback in TextEdit.
- [ ] Behaviour when the focused target disappears, moves its selection, is
      secure or disabled, or exposes no focused Accessibility element.
- [ ] Menu-command and PID-targeted paste fallbacks without false success
      reporting, including with Raycast clipboard history running and the
      transient and concealed markers honoured.

## Pill, windows, and visual behaviour

- [ ] Compact and copied-result pill shape, glass, countdown, hover pause,
      transitions, and dismissal on varied light and dark backgrounds.
- [ ] Pill placement in full-screen apps, multiple Spaces, multiple displays, and
      with Dock auto-hide.
- [ ] With Scriber in accessory mode and Finder frontmost, click Update Key:
      Settings and the key field become focused, and one Command-Tab returns to
      Scriber after switching to Finder.
- [ ] The same using non-window pill actions, confirming Finder stays focused
      while Scriber stays absent from the Dock and Command-Tab.
- [ ] The app icon in Dock, Finder, default, dark, tinted, and small-size
      contexts.
