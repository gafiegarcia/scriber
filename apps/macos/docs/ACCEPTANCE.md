# Manual Acceptance Checks

The list standing between the current candidate and the `v0.7.0` tag.
[`ROADMAP.md`](ROADMAP.md) holds the release gates that point at it.

Automated checks live in [`TESTING.md`](TESTING.md) and are not repeated here.
There is no longer a UI test suite, so this file is the only coverage the SwiftUI
shell has. [`ROADMAP.md`](ROADMAP.md) records why it was removed.

**Never run a check that spends API credit without asking Gaf first.**

Interface checks that need neither a real key nor real permissions can be driven
by machine now, against a build seeded with `--ui-testing-seed-history`; see the
seeded-history section of [`TESTING.md`](TESTING.md). What is left needs a person,
and [Sessions for Gaf](#sessions-for-gaf) is the plain-language version of it.

## Where this stands

Build 30 is installed and is the current candidate. Everything machine-checkable
is done, and every check that needed Gaf has been run; the record is in
[Sessions, and how they went](#sessions-and-how-they-went).

Gaf's build 29 session cleared the restart check outright and found one defect in
fresh onboarding — the window ran under the Dock. Build 30 fixes it, and he
confirmed the fix on both routes. The XCUITest suite was run once on build 30 and
then removed; see below.

**Every person-only check is now closed.** What remains is to cut the `v0.7.0`
tag with the metadata
[`VERSIONING.md`](../../../docs/VERSIONING.md) requires — bundle build, credential
and signing state, verification actually performed, known limitations, and
confirmation that no credentials, recordings, history, or machine-specific output
are included. State plainly which checks were run and which were not. Do not push
unless he asks.

The three open findings below ship as **known limitations**, by Gaf's decision.
Do not fix them as part of the tag; two are being redesigned rather than patched
(see [`ROADMAP.md`](ROADMAP.md)).

## Sessions, and how they went

Gaf worked through the acceptance sessions on build 28. Almost all of it passed;
what it turned up is in [Open findings](#open-findings), of which two are fixed in
build 29 and three are deliberately carried forward.

Build 29 also added three requested actions — Remove Key…, Redo Onboarding…, and
chord recording committing at the first key release. See
[Requested](#requested-not-defects).

Nothing remains from the original list.

### ~~1. Restart the Mac~~ — passed on build 29

Grants survived the restart, Scriber was running after login, the stored key read
back without a further password prompt, and **Launch at Login** turned off and
stayed off.

### ~~2. Redo onboarding once~~ — ran on build 29, found a defect, fixed in build 30

Onboarding appeared as it should, but the window was placed badly: cascaded down
from the main window rather than centred, and tall enough that its bottom ran off
the screen and under the Dock. Gaf offered two remedies — hide the main window
during setup, or centre setup and let it use the full height between the menu bar
and the Dock. Build 30 does the second.

What it took, because AppKit's own frame was wrong in both directions: the window
is now sized and centred explicitly every time it appears, is marked
non-restorable so a bad frame cannot outlive the launch that produced it, and its
scene no longer uses `.windowResizability(.contentSize)`, which pinned it to a
scroll view's greedy ideal height and refused an explicit frame. The setup steps
scroll if they ever do exceed the display, so nothing becomes unreachable on a
smaller screen.

Re-checked by Gaf on build 30, including **Settings → Redo Onboarding…** with the
main window already open: correct on both routes.

### ~~3. The XCUITest suite, once, end to end~~ — run on build 30, not clean

Ran end to end. **8 passed, 2 skipped by design, 3 failed.** None of the failures
is caused by this branch: every one of them reproduces on `origin/main`.

- The 3 failures are all a SwiftUI `Switch` reporting `Not hittable` while the
  same query finds it and reads its value correctly. They passed on the first run
  of the day and failed every run afterwards with no code change in between.
  `TESTING.md` records what was ruled out — regression, cross-test pollution, the
  installed app, and scroll position — and what was not: the cause.
- The 2 skips are explicit, and now include the `Update Key` case, which had been
  failing for an environmental reason rather than a product one.

**That run was the suite's last.** Gaf removed the `ScriberUITests` target rather
than repair it: it cost his own machine for every run, could only reach the
SwiftUI shell, and had earned its keep once in its lifetime.
[`ROADMAP.md`](ROADMAP.md) records the full reasoning and what stopped being
covered — in short, this file is now the shell's only coverage.

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

### ~~3. A misconfigured microphone fails completely silently~~ — fixed in build 29

With the system input volume set to **zero**, a dictation produced nothing at all:
no transcription, no history entry, no retry, no warning. The pill simply
disappeared, so a broken microphone was indistinguishable from not having spoken.

Fixed by separating the two cases, which had been sharing one silence:

- **Nothing crossed the signal threshold** → new "No sound from the microphone"
  pill, with the failure sound and a Check Input button. Still no history entry
  and still no API credit spent; only the silence is gone.
- **Sound arrived but no words came back** → the existing "No words detected"
  pill, unchanged in behaviour. Its subtitle no longer blames a muted microphone,
  which was wrong precisely when audio *had* arrived.

Needs a real key to re-check: set the input volume to zero and dictate.

### 4. The permissions pill respawns on every window focus

Unlike the credential pill, the missing-permissions pill reappears **and resets
its dismissal timer** every time Scriber's window gains focus — so every
Command-Tab brings it back. While granting permissions in System Settings, which
means switching back and forth repeatedly, it obstructs the screen almost
continuously.

### ~~5. The retry-success pill is too brief to read, and the wording is inconsistent~~ — fixed in build 29

Retrying a failed entry showed a compact "Transcript copied" pill that vanished
fast enough to miss entirely, while the same outcome from a failed paste read
"Copied" with a green checkmark and stayed long enough to register.

The retry path was reusing the generic 1.5-second `.message` phase. It now has its
own phase: the same compact shape, the same green checkmark, the same five-second
dwell, and the same single word — "Copied" — as the other route to the clipboard.

### Open question, not a failure

While a search is active, the count row keeps showing the total number of
dictations rather than the number of matches — search for one word and it still
reads "21 dictations" above a single row. That is what the code intends
(`visibleRecords.count`, not the filtered count), so it is a design question for
Gaf rather than a defect.

### Requested, not defects

Came out of the build-28 sessions. Three are done in build 29 and need a look.

- [x] **Stop chord recording at the first key release.** Waiting for the last
      release implied that letting go of one key could edit the chord already
      captured. It never could, and it cannot be made to: deciding which keys were
      "released together" has no answer, because a user correcting a mistake and a
      user finishing produce identical events. Build 29 commits at the first
      release, which yields the same chord and removes the implication.
      **Not yet checked on a real keyboard:** record `Fn-Control-Option` and
      release one key; the recorder should close immediately with the full chord.
      Not a tag blocker — it is a refinement of behaviour Gaf already reported
      working, and the logic is covered by the package tests.
- [x] **A way to remove a saved API key from Settings.** Build 29 adds
      **Remove Key…** beside Save API Key, shown only when a key is stored, and it
      confirms first. Verified end to end in a seeded build, including that
      removing it hides its own button and restores the empty-state placeholder.
      **Not yet checked against the real key**, because doing so means re-entering
      it afterwards. Not a tag blocker: the same code path was driven end to end in
      a seeded build, and the warnings it should produce are the ones Gaf already
      saw when he deleted the key through Keychain Access on build 28.
- [x] **A "Redo Onboarding" action.** Build 29 adds it at the end of Settings →
      General. Only the flag is cleared; the key, grants, and history stay, and
      onboarding presents each step's current state. Verified by Gaf on build 30,
      with the main window already open: it comes to the front, centred and whole,
      and finishing returns to Dictation intact.
- [ ] **Tint whole pills by outcome** — green for success, amber for warnings such
      as cancellation and no-words. Deferred by Gaf as a later idea: it is a design
      pass across every pill state, in light and dark on varied backgrounds, rather
      than a release edit. The wording and duration half of it is done; see
      [finding 5](#5-the-retry-success-pill-is-too-brief-to-read-and-the-wording-is-inconsistent-fixed-in-build-29).

### Withdrawn: the menu bar icon was never hidden

An earlier build-28 finding claimed macOS was hiding the menu bar item while
`showInMenuBar = 1`, inferred from `NSStatusItem VisibleCC Item-0 = 0`. That was
wrong. The icon was present the whole time; the defaults key does not mean what
was assumed, and the icon's absence was never actually confirmed — it was inferred
from failing to identify Scriber's mark among eight status items.

Gaf's standing observation is that showing, hiding, and Settings synchronization
have worked since the menu bar shipped, and build 28 was watched switching to the
warning symbol and back during the credential check. Recorded so the same key does
not mislead a second time.

## Interface acceptance

Verified on **build 28** against a seeded Debug build unless noted. None of these
needed a real API key.

- [x] The menu bar icon no longer crowds every other status item into the
      overflow. Confirmed on build 18: the neighbouring items returned as soon as
      the image was sized, and the mark measures comparably to the battery item
      beside it.
- [x] The menu bar icon reads well at a glance next to its neighbours over a full
      day, holds steady through a record, transcribe, and paste cycle, switches to
      the warning symbol when the API key is removed, and returns to the app mark
      when it is restored, without relaunching and without the item jumping width.
      Build 28: confirmed by Gaf. Removing the key showed the warning symbol;
      restoring it dismissed the banner and returned the mark, with no relaunch.
      Showing, hiding, and Settings synchronization have been trouble-free since
      the menu bar shipped, the icon-change work aside. If it ever wants to sit a
      little shorter, `menuBarIconHeight` in `ScriberApp` is the only number to
      change.
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
- [x] Day groups render as rounded cards, legibly, in both light and dark
      appearance. Build 28: dark confirmed by machine in the seeded and installed
      builds; Gaf confirmed both appearances read comfortably as clean cards.
- [x] Start a dictation and watch history through the wait: no row appears until
      the outcome lands. Then retry a failed entry and confirm its row stays
      visible with the Retrying label. Build 28: both confirmed with a real key.
      The retried row kept its place, showed Retrying, then succeeded — but its
      success pill is too brief to read; see
      [finding 5](#5-the-retry-success-pill-is-too-brief-to-read-and-the-wording-is-inconsistent).
- [x] Punctuation-only or no-content output leaves no history row behind.
      Build 28: "uh" returned no words detected and added no entry. ("um" was
      transcribed as Japanese, which is defensible — it did sound like うん.)
- [ ] **Needs a real key.** Mute or unplug the selected input, dictate for several
      seconds, and confirm the no-words pill appears with the failure sound,
      dismisses after about six seconds, and its button scrolls Settings to the
      microphone picker. Confirm no history row is left behind. Build 28: **fails
      at zero input volume** — nothing appears at all. See
      [finding 3](#3-a-misconfigured-microphone-fails-completely-silently).

## Installation, identity, and lifecycle

- [x] Build the Apple Development-signed Debug configuration and entitlement-free
      locally certificate-signed Release configuration with Xcode 27 beta.
- [x] Install the verified locally certificate-signed Release build at
      `/Applications/Scriber.app`.
- [x] Complete fresh onboarding under the `com.gafiegarcia.scriber` identity, and
      verify launch presents onboarding before setup and the main Dictation window
      after setup. Reset with
      `defaults delete com.gafiegarcia.scriber onboardingComplete`. Build 29: the
      sequence is right, but the window was placed off the bottom of the screen.
      Fixed in build 30; re-check the placement there.
- [x] Verify Microphone and Accessibility grants persist across a restart, and
      that the stored key still reads back without a login-Keychain prompt.
      Build 29: confirmed, no further password prompt.
- [x] Revoke Microphone and Accessibility separately and together after
      onboarding; verify the proactive warning, permission pill, Settings route,
      and automatic shortcut-monitor recovery after regranting. Build 28:
      confirmed. Two notes. macOS itself forces Quit & Reopen whenever Microphone
      access changes, so the no-relaunch recovery could only be observed for
      Accessibility, where Scriber handles both directions correctly. And the pill
      is intrusive throughout; see
      [finding 4](#4-the-permissions-pill-respawns-on-every-window-focus).
- [x] Verify Launch at Login registration, first-login dictation after
      persistent-store readiness, relaunch, and opt-out. Build 29, across a real
      restart: Scriber was running after login, and opting out turned it off and
      kept it off.
- [x] Verify Command-W, Command-Shift-W, and the red window control remove the
      final normal window and Dock icon without terminating menu-bar or dictation
      services when "Show app in Dock" is disabled. Build 28.
- [x] Verify "Show app in Dock" persists, keeps Scriber in the Dock and app
      switcher after the final window closes when enabled, and does not close a
      visible window when disabled. Build 28: correct with the setting both on and
      off.
- [x] Verify the Show in Menu Bar setting, restoration after re-enabling, and
      preference synchronization after Command-drag removal. Trouble-free since the
      menu bar shipped; still true on build 28. An earlier build-28 finding
      claiming otherwise was withdrawn — see
      [Withdrawn](#withdrawn-the-menu-bar-icon-was-never-hidden).

## Credentials, quota, and transcription

- [x] Remove or corrupt the stored key, relaunch, and confirm Scriber reports it
      on its own — pill, Dictation banner, and menu bar — without waiting for a
      dictation attempt. Build 28: all three reported it, and restoring the key
      cleared the banner and the menu bar mark without a relaunch. Note that
      Settings has **no way to remove a saved key**, so this had to be done through
      Keychain Access; see [Requested](#requested-not-defects).
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

- [x] Test bare `Fn`, `Fn-Space`, and custom `Fn-Control-Option` Hold behavior with
      competing dictation and global-shortcut tools disabled. **Wispr Flow is
      installed on this machine and must be quit first.** Build 28: Hold on bare
      `Fn` starts immediately; `Fn-Space` locks hands-free and Hold is correctly
      ignored while locked; a custom `Fn-Control-Option` binding works.
- [x] Confirm Scriber leaving the `Fn` key event unconsumed keeps `Fn`'s other jobs
      working. Build 28: with Hold rebound off bare `Fn`, the emoji picker on
      `Fn-E`, a normal Space, and ordinary typing all behaved. This is the
      observable consequence of `GlobalShortcutService` returning `false` for
      modifier-only chords — swallowing `flagsChanged` would leave the foreground
      app with stale modifier state.
- [x] Verify every press/release order records and live-displays
      `Fn-Control-Option`, only one binding recorder listens at a time, and neither
      configured shortcut nor global Escape handling fires while a recorder is
      listening. Build 28: recording works and displays the chord live. One
      behavioral request came out of it; see
      [Requested](#requested-not-defects).
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
- [x] Verify held-to-hands-free conversion, exact Toggle-only locked-recording stop
      semantics, and that Hold is ignored while locked. Build 28.
- [x] Verify independently disabling and re-enabling Hold and Toggle preserves each
      chord and prevents only the disabled keyboard action. Build 28: correct in
      both directions.
- [x] Verify early typing cancellation and Escape cancellation, with the
      cancellation sound. Build 28: typing during a recording cancels it, Escape
      cancels it, and Morse plays once for each. Full-screen and cross-app pill
      dismissal, Undo, and History retry from other apps are covered by daily use
      but were not separately walked through.
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
- [x] Confirm moving focus to a different app or field during transcription
      delivers to the final cursor. Build 28: started a dictation in Zen with a
      focused field, switched to the Claude app and clicked into its prompt box,
      then stopped — it landed there. Also confirmed with the cursor moved during
      transcription rather than before it: delivery followed the final position.
      Much of Gaf's build-28 report was itself dictated across those apps.
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
