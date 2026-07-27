# Manual Acceptance Checks

The list standing between the current candidate and the `v0.7.0` tag.
[`ROADMAP.md`](ROADMAP.md) holds the release gates that point at it.

Automated checks live in [`TESTING.md`](TESTING.md) and are not repeated here.
Nothing the UI test suite covers counts as one of these: it runs with services
disabled and no Accessibility trust, so it cannot speak to dictation, insertion,
shortcuts, or credentials.

**Never run a check that spends API credit without asking Gaf first.**

Interface checks that need neither a real key nor real permissions can be driven
by machine now, against a build seeded with `--ui-testing-seed-history`; see the
seeded-history section of [`TESTING.md`](TESTING.md). What is left needs a person,
and [Sessions for Gaf](#sessions-for-gaf) is the plain-language version of it.

## Sessions for Gaf

Grouped so each prerequisite is set up once. Every check below is also recorded
in technical form in the sections further down; this is the same work written to
be done rather than filed.

### 1. Turn the menu bar icon back on — do this first, it blocks session 4

Right now Scriber's little icon is **not in your menu bar**, even though its
setting says it should be. macOS is hiding it (see [finding 3](#3-the-menu-bar-icon-is-hidden-while-the-setting-says-it-is-shown)).

- Open Scriber → Settings → General. Switch **Show in Menu Bar** off, then on
  again.
- **You should see:** the Scriber icon reappear in the menu bar.
- If it does not come back, Command-drag it back into place from wherever macOS
  put it, or tell me and I will look again.
- Then leave it alone and just notice, over the next day of normal use, whether it
  reads clearly next to your other icons and whether it ever jumps wider or
  narrower. If it feels a touch too tall, say so — one number changes it.

### 2. One dictation session with your real key

This is the only session that spends ElevenLabs credit. Five or six short
dictations covers all of it.

- **Dictate normally into a text box.** You should see the words land at your
  cursor, and a new row appear in Dictation history *only after* it finishes —
  nothing should show up while it is still thinking.
- **Mute your microphone (or unplug it) and dictate for a few seconds.** You
  should hear the failure sound and see a pill saying no words were detected. It
  should disappear on its own after about six seconds, and its button should take
  you to Settings scrolled to the microphone picker. **Check afterwards that no
  leftover row was added to history.**
- **Say only "um, uh"** or just punctuation-ish noise, and see what the row says.
- **Find a failed row in history and press Retry.** The row should stay where it
  is and show a "Retrying" label rather than vanishing and coming back.
- **Dictate with nothing focused** — click the desktop first, then dictate. You
  should get the copied-to-clipboard pill instead of text being typed anywhere.
- **Dictate, then click into a different app while it is still transcribing.** The
  text should land wherever your cursor ended up, not where it started.

### 3. One shortcut session

**Quit Wispr Flow first.** It is installed and it wants the same Fn key Scriber
does; leaving it running makes the results meaningless. Also open System Settings
→ Keyboard and set the Globe/Fn key action to **Do Nothing** for the duration.

- **Hold Fn** and speak, then let go. Recording should start immediately, with the
  Frog sound once.
- **Press Fn-Space** to start hands-free, then Fn-Space again to stop. While it is
  locked hands-free, holding Fn should do nothing.
- **Hold Fn, keep holding, and let it convert to hands-free.**
- **Start recording, then just start typing.** It should cancel.
- **Start recording, then press Escape.** It should cancel, with the Morse sound.
- **Press Fn on its own in a text box, without recording** — a normal Space and
  normal typing should still work afterwards. This is the one I most want to hear
  about: bare Fn is deliberately *not* swallowed, because swallowing it breaks
  ordinary typing, so the question is whether Scriber still reliably notices it.
- **In Settings, record a custom shortcut** of Fn-Control-Option, pressing and
  releasing the keys in a few different orders. It should show what you are
  holding as you hold it. While you are recording a shortcut, your normal Scriber
  shortcut should not fire.
- **Turn Hold off, leaving Toggle on** — then only the disabled one should stop
  working, and each should remember its own key combination.

### 4. One key-and-permissions session

- **Remove your ElevenLabs key** (Settings → ElevenLabs), then quit and reopen
  Scriber. Scriber should tell you on its own, without you trying to dictate: a
  pill, a banner on the Dictation page, and the menu bar icon changing to a
  warning symbol. Then **put the key back** and confirm the icon returns to the
  normal mark without needing a relaunch.
- **Turn off Microphone access** in System Settings → Privacy & Security, then
  Accessibility, then both. Each time, Scriber should warn you, offer a pill, and
  the pill's button should take you to the right place in Settings. After you
  grant them back, dictation shortcuts should start working again on their own —
  no relaunch.
- **Restart the Mac** and confirm both grants survived and the key still reads
  back without asking for your login password again.

### 5. One lifecycle session

- With **Show app in Dock** off: press Command-W, and separately Command-Shift-W
  and the red close button. The window and Dock icon should go away, but Scriber
  should keep working — shortcuts still dictate.
- Turn **Show app in Dock** on: Scriber should stay in the Dock and in Command-Tab
  after the last window closes, and turning it off should not close a window you
  are looking at.
- Confirm **Launch at Login** works: restart, and check Scriber is running and that
  a dictation right after login works. Then turn it off and confirm it stays off.
- Delete Scriber's onboarding state (or ask me how) and confirm a fresh install
  shows onboarding first, and the Dictation window after setup.

### 6. Two quick looks

- **Switch macOS to Light appearance** and look at the Dictation history. The day
  groups should still read as clean rounded cards, and the text should still be
  comfortably readable. Switch back to Dark and compare.
- **Look at the app icon** in the Dock, in Finder, and with a tinted Dock, and at
  small sizes. Just say whether anything looks wrong.

### 7. The XCUITest suite, once, end to end

Only you can start this — it takes over the pointer and keyboard for its whole
run, so do not start it while you need the machine. The command is in
[`TESTING.md`](TESTING.md). One case intentionally skips itself unless its
generated test binary has Accessibility trust; that skip is expected.

---

## Open findings

Things that were checked and did **not** pass. Recorded rather than quietly
retried.

### 1. The floating day label never appears while scrolling

The count row is supposed to pick up the current day's name once that day's own
label scrolls out of sight. It never does, at any scroll position, in a list with
four day groups. Stepping down in single notches across the whole boundary region
showed nothing appear at any offset.

The one part of that item that *does* pass: the count row never changes height.
The fixed-height blank placeholder is doing its job, so the list does not shift
when scrolling starts.

Most likely cause, not yet confirmed: `DictationHistoryView` measures each day
label with `proxy.frame(in: .named(scrollSpace))` and then picks
`anchors.last { $0.minY <= 0 }`. If `.coordinateSpace(.named(_:))` on a `List`
names the *scrolled content* rather than the visible viewport, a label's `minY`
never goes negative as it scrolls away, so that condition is never true and the
title stays nil. The competing explanation — that `List` unmounts the off-screen
label so its measurement disappears — would predict the label working in a narrow
band right at the boundary, and no such band exists.

Not fixed in this sprint: it needs a real diagnosis pass in the running app, and
it is cosmetic. It is the last thing in the interface track that is actually
broken rather than merely unverified.

### 2. Command-period does not cancel the Clear Dictation History dialog

The good news is the failure this item was written to catch does **not** happen:
with the dialog open, Command-period does not toggle the sidebar behind it.

But it does not cancel the dialog either — it does nothing at all. Since
Command-period is macOS's conventional Cancel, that gesture is dead while the
dialog is up. Clicking Cancel works.

Escape also failed to dismiss the dialog under synthetic key events. That half is
**unconfirmed**: synthetic Escape could not be independently shown to reach a
sheet at all, so this needs one press on a real keyboard. It is in
[session 5](#5-one-lifecycle-session) territory — worth ten seconds next time the
dialog is open.

### 3. The menu bar icon is hidden while the setting says it is shown

Scriber's own preferences hold `showInMenuBar = 1`, while macOS holds
`NSStatusItem VisibleCC Item-0 = 0` for the same item — so no icon is displayed.

`MenuBarExtra`'s `isInserted` binding is two-way and writes the preference back
when the item is removed, so the two being out of step is exactly the
"preference synchronization after Command-drag removal" case in
[Installation, identity, and lifecycle](#installation-identity-and-lifecycle).
Whether it is a live sync bug or stale state left over from an earlier install is
not yet distinguishable.

Consequence: **every menu-bar icon check is blocked** until the icon is restored,
which is why [session 1](#1-turn-the-menu-bar-icon-back-on--do-this-first-it-blocks-session-4)
comes first.

### Open question, not a failure

While a search is active, the count row keeps showing the total number of
dictations rather than the number of matches — search for one word and it still
reads "21 dictations" above a single row. That is what the code intends
(`visibleRecords.count`, not the filtered count), so it is a design question for
Gaf rather than a defect.

## Interface acceptance

Verified on **build 28** against a seeded Debug build unless noted. None of these
needed a real API key.

- [x] The menu bar icon no longer crowds every other status item into the
      overflow. Confirmed on build 18: the neighbouring items returned as soon as
      the image was sized, and the mark measures comparably to the battery item
      beside it.
- [ ] The menu bar icon reads well at a glance next to its neighbours over a full
      day, holds steady through a record, transcribe, and paste cycle, switches to
      the warning symbol when the API key is removed, and returns to the app mark
      when it is restored, without relaunching and without the item jumping width.
      **Blocked** by [finding 3](#3-the-menu-bar-icon-is-hidden-while-the-setting-says-it-is-shown):
      no icon is currently displayed. Needs the installed Release build — a Debug
      build has no menu bar item at all and always renders the warning state. If
      it wants to sit a little shorter, `menuBarIconHeight` in `ScriberApp` is the
      only number to change.
- [x] Copy a single-line entry: the icon changes to a checkmark for about a second
      and a half and **the row does not change height** while it does. Build 28:
      the checkmark is green and lasts 1.4s; captured before and after the click,
      the row's text baseline and both separators sit at identical positions.
      Sizing the icon frame on both axes is what earns this.
- [x] The copy and overflow buttons are plain borderless icons again — glass was
      tried on build 22/23 and rejected — each taking a near-threshold background
      under the pointer. Retry sits to their left so copy and the overflow land on
      the same two positions in every row. Build 28: the hover background is
      genuinely near-threshold, visible only by comparing a hovered button against
      an unhovered one in the same capture. Alignment confirmed across five
      adjacent rows, two of which have Retry and three of which do not — copy and
      the overflow do not move.
- [x] Failed and cancelled entries keep a copy button rather than dropping it,
      and it reads clearly as unavailable — muted well below the transcript, not
      merely a different colour. Build 28: side by side with a succeeded row's
      blue icon, the muted grey reads as unavailable at a glance rather than as a
      different shade of live.
- [x] The overflow menu opens, its Delete… asks for confirmation first, and
      confirming removes the right entry. Cancelling leaves the entry alone. The
      row's right-click Delete… asks the same way. Build 28: Cancel left the entry
      and the count at 22; confirming removed exactly that entry and only it,
      22 → 21, with both neighbours intact. Both routes raise the same dialog.
      **Delete is not red in the menu, and will not be** — macOS does not tint
      destructive menu items, unlike iOS; see the note in `DictationHistoryRow`.
      Note that macOS *does* tint it in the dialog, so the destructive action now
      carries the colour the menu could never give it.
- [x] The overflow popup grows from the leading edge and may overhang the window;
      that is the built-in behaviour and is preferred over the custom control that
      used to align it. Its hover background also sits slightly right of the glyph
      — known, accepted, and not worth a fourth attempt. Build 28: with the window
      at its default width near the right edge of the screen, the popup overhangs
      the window slightly and stays comfortably inside the screen. This supersedes
      the earlier item that asked for it to stay inside the window; that was
      written before the built-in placement was accepted.
- [x] The disabled copy button on a failed entry does nothing when clicked.
      Build 28: no checkmark, no change.
- [x] Clicking anywhere else on a row does nothing: no row highlight, no copy.
      Build 28: clicking the empty space beside the transcript produced neither.
      The row still right-clicks to its context menu, which correctly offers only
      Delete… on an entry with nothing to copy and no audio to retry.
- [ ] Scroll a history list with more than one day in it: the day label moves up
      into the count row as its group leaves the top, changes as the next group
      arrives, and disappears again when scrolled back to the top.
      **Fails** — see [finding 1](#1-the-floating-day-label-never-appears-while-scrolling).
      The second half of the original item does pass: the count row does not
      change height.
- [x] Permission and credential banners sit directly under the title and search
      row, above the count row. Build 28.
- [x] The Dictation page's header has no overflow menu at all — just the day and
      the count. Build 28.
- [x] Settings → Dictation History ends with Clear Dictation History…, showing the
      entry count and disabled when there is nothing to clear. It confirms first.
      Build 28: read "21 entries" against a seeded store and matched the Dictation
      page; disabled and reading "0 entries" against an empty one. The dialog was
      raised and cancelled, not confirmed.
- [x] The entry time sits close to the card's leading edge and the overflow button
      close to its trailing edge, with no wide empty margin inside the card on
      either side. Build 28.
- [x] The sidebar toggle sits over the sidebar, beside the window controls, where
      every other native app puts it. It has no tooltip — see the note in
      `MainWindowView` for why a custom item cannot go there. Build 28, in both
      the expanded and collapsed states.
- [ ] **Still open and deliberately deferred:** the toggle flickers when switching
      Settings → Dictation but not the other way. Best current explanation is that
      only Dictation adds a search field to the toolbar, so that direction
      restructures it. Not attempted this sprint; see `ROADMAP.md`.
- [ ] From the permissions pill, Review brings Scriber to the front over whatever
      app is active — with the main window already open behind that app, and with
      every window closed — and lands on Permissions and Input rather than the top
      of Settings. Same for the menu bar's "Permissions Required…" item. Needs real
      revoked permissions; [session 4](#4-one-key-and-permissions-session).
- [x] Settings shows General, Feedback, ElevenLabs, Dictation, Dictation History,
      and Permissions and Input in that order, with Accessibility above Microphone.
      Build 28: exactly that order, Accessibility then Microphone then the input
      picker.
- [x] Command-comma opens Settings both with the main window open and with every
      window closed. Build 28: verified in both states.
- [x] Command-period collapses and expands the sidebar, and the View menu shows it
      in place of Control-Command-S. Build 28: View reads "Toggle Sidebar ⌘.", and
      it works in both directions. The dialog half of this item is
      [finding 2](#2-command-period-does-not-cancel-the-clear-dictation-history-dialog).
- [x] Command-F still focuses search, and the placeholder carries the hint.
      Build 28: the placeholder reads "Search past transcripts (⌘F)", Command-F
      takes focus, and typing filtered 21 rows to the single matching one.
- [ ] Day groups render as rounded cards, legibly, in both light and dark
      appearance. Dark confirmed on build 28, in both the seeded build and the
      installed build against real history. Light needs a system appearance
      change; [session 6](#6-two-quick-looks).
- [ ] Start a dictation and watch history through the wait: no row appears until
      the outcome lands. Then retry a failed entry and confirm its row stays
      visible with the Retrying label. Needs a real key;
      [session 2](#2-one-dictation-session-with-your-real-key). The seeded
      in-flight record does prove the filter itself hides a transcribing row.
- [ ] **Needs a real key.** Mute or unplug the selected input, dictate for several
      seconds, and confirm the no-words pill appears with the failure sound,
      dismisses after about six seconds, and its button scrolls Settings to the
      microphone picker. Confirm no history row is left behind.

## Installation, identity, and lifecycle

- [x] Build the Apple Development-signed Debug configuration and entitlement-free
      locally certificate-signed Release configuration with Xcode 27 beta.
- [x] Install the verified locally certificate-signed Release build at
      `/Applications/Scriber.app`.
- [ ] Complete fresh onboarding under the `com.gafiegarcia.scriber` identity.
- [ ] Verify Microphone and Accessibility grants persist for the installed app.
- [ ] Revoke Microphone and Accessibility separately and together after
      onboarding; verify the proactive warning, permission pill, Settings route,
      and automatic shortcut-monitor recovery after regranting.
- [ ] Verify Launch at Login registration, first-login dictation after
      persistent-store readiness, relaunch, and opt-out.
- [ ] Verify launch presents onboarding before setup and the main Dictation window
      after setup.
- [ ] Verify Command-W, Command-Shift-W, and the red window control remove the
      final normal window and Dock icon without terminating menu-bar or dictation
      services when "Show app in Dock" is disabled.
- [ ] Verify "Show app in Dock" persists, keeps Scriber in the Dock and app
      switcher after the final window closes when enabled, and does not close a
      visible window when disabled.
- [ ] Verify the Show in Menu Bar setting, restoration after re-enabling, and
      preference synchronization after Command-drag removal. Currently out of
      step; see [finding 3](#3-the-menu-bar-icon-is-hidden-while-the-setting-says-it-is-shown).

## Credentials, quota, and transcription

- [ ] Remove or corrupt the stored key, relaunch, and confirm Scriber reports it
      on its own — pill, Dictation banner, and menu bar — without waiting for a
      dictation attempt.
- [ ] Confirm the same for exhausted credits, and that recovery routes to the
      usage panel rather than the key field.
- [ ] Confirm retained audio older than 30 days is removed at launch while its
      history entry, transcript, and failure reason survive, and that disabling
      the preference stops the sweep.
- [ ] Re-enter, save, and read back a real Speech-to-Text-scoped ElevenLabs key
      across relaunch and restart from the installed locally signed build.
- [ ] Verify startup handling for valid, revoked, tampered, restricted-scope, and
      transiently unreachable credentials.
- [ ] Verify subscription usage for full-scope, Speech-to-Text-only, exhausted,
      and extended-usage accounts.
- [ ] Run an explicitly approved real transcription smoke test; never include this
      in normal automation.
- [ ] Verify empty/punctuation-only API output and retained-audio retry behavior
      live.

## Recording and shortcuts

- [ ] Test bare `Fn`, `Fn-Space`, and custom `Fn-Control-Option` Hold behavior with
      competing dictation and global-shortcut tools disabled. **Wispr Flow is
      installed on this machine and must be quit first.**
- [ ] Verify every press/release order records and live-displays
      `Fn-Control-Option`, only one binding recorder listens at a time, and neither
      configured shortcut nor global Escape handling fires while a recorder is
      listening.
- [ ] Verify Frog plays once after Hold, Toggle, and menu capture starts; Bottle
      plays once for terminal microphone/transcription failures; Morse plays once
      for cancellation and copied paste fallback; silence, no-content output, and
      retries remain silent; confirm the preference disables all feedback.
- [ ] With Music, Spotify, Safari, and QuickTime, verify other audio advances
      silently only during capture, newly started audio is also muted, Frog remains
      audible, output returns immediately on stop/cancel/failure, and disabling the
      setting leaves audio unchanged.
- [ ] Verify tap creation with System Audio Recording allowed and denied on
      macOS 27; denial or Core Audio failure must continue dictation unmuted and
      report the unavailable state only in Settings.
- [ ] Verify held-to-hands-free conversion, exact Toggle-only locked-recording stop
      semantics, and that Hold is ignored while locked.
- [ ] Verify independently disabling and re-enabling Hold and Toggle preserves each
      chord and prevents only the disabled keyboard action.
- [ ] Verify early typing cancellation, short and recoverable Escape cancellation,
      Undo, History retry, and pill dismissal across other apps and full-screen
      windows.
- [ ] Verify 10-minute auto-stop, silence rejection, selected/default/disconnected
      microphone behavior, and live waveform response.
- [ ] Confirm the configured macOS Globe/Fn action does not interfere; use "Do
      Nothing" during testing if necessary.

## Insertion and fallback

Read [`PASTE_ENGINE.md`](PASTE_ENGINE.md) before changing
anything these checks cover. Its table is the regression baseline.

- [x] Confirm recording starts immediately in the apps that previously took two to
      three seconds. Verified on build 8 in ChatGPT, Notion, and Zen.
- [x] Confirm delivery lands at the cursor focused when the transcript arrives.
      Verified on build 8: ChatGPT `pasted`, Notion `pasted`, Zen with a focused
      field `pasted`, Zen on `x.com` without one `copied`.
- [x] Close the build 8 false-success regression. Build 9 classified 14
      consecutive dictations correctly across `claude.ai`, the Claude desktop app,
      ChatGPT, Notion, `x.com`, and Finder, including the no-focused-field case on
      both a live page and a native app.
- [x] Close the paste-confirmation regression with Raycast running: Xcode, ChatGPT,
      and Notion confirm success without a false recovery panel, while Zen with no
      focused text box produces copied recovery.
- [x] Repeat insertion checks in Ghostty, Raycast, VS Code, and Zed. Raycast needed
      the build 11 keyboard-focus fix; its command bar and its Notes window both
      deliver correctly now. Codex remains unchecked.
- [ ] Confirm moving focus to a different app or field during transcription
      delivers to the final cursor.
- [ ] Confirm the pill still appears on the screen holding the app that was
      frontmost at record start, now that its screen comes from the window server
      rather than Accessibility.
- [ ] Verify target capture, selection restoration, confirmed insertion, clipboard
      restoration, and copied fallback in TextEdit.
- [ ] Verify behavior when the focused target disappears, moves its selection, is
      secure/disabled, or exposes no focused Accessibility element.
- [ ] Verify menu-command and PID-targeted paste fallbacks without false success
      reporting, including with Raycast clipboard history running and the
      transient/concealed markers honored.

## Pill, windows, and visual behavior

- [ ] Check compact and copied-result pill shape, glass, countdown, hover pause,
      transitions, and dismissal on varied light and dark backgrounds.
- [ ] Verify pill placement in full-screen apps, multiple Spaces, multiple
      displays, and with Dock auto-hide.
- [ ] With Scriber in accessory mode and Finder frontmost, click Update Key;
      confirm Settings and the key field become focused, then verify one
      Command-Tab returns to Scriber after switching to Finder.
- [ ] Repeat using non-window pill actions and confirm Finder remains focused while
      Scriber stays absent from the Dock and Command-Tab.
- [ ] Review the app icon in Dock, Finder, default, dark, tinted, and small-size
      contexts.
