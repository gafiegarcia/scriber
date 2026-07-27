# Manual Acceptance Checks

Everything here needs a person, an installed build, and in a few marked cases a
real API key. It is the list standing between the current build and a stable
`v0.7.0`; [`ROADMAP.md`](ROADMAP.md) holds the release gates that point at it.

Automated checks live in [`TESTING.md`](TESTING.md) and are not repeated here.
Nothing the UI test suite covers counts as one of these: it runs with services
disabled and no Accessibility trust, so it cannot speak to dictation, insertion,
shortcuts, or credentials.

**Never run a check that spends API credit without asking Gaf first.**

## Build 19 interface changes

None of these need a real API key.

- [x] The menu bar icon no longer crowds every other status item into the
      overflow. Confirmed on build 18: the neighbouring items returned as soon as
      the image was sized, and the mark measures comparably to the battery item
      beside it.
- [ ] The menu bar icon reads well at a glance next to its neighbours over a full
      day, holds steady through a record, transcribe, and paste cycle, switches to
      the warning symbol when the API key is removed, and returns to the app mark
      when it is restored, without relaunching and without the item jumping width.
      A Debug build always renders the warning state, so the mark needs the
      installed Release build. If it wants to sit a little shorter,
      `menuBarIconHeight` in `ScriberApp` is the only number to change.
- [ ] Copy a single-line entry: the icon changes to a checkmark for about a second
      and a half and **the row does not change height** while it does.
- [ ] Hovering the copy button and the overflow menu gives each a background
      subtle enough to stay out of the way, **and the glyph sits centred in it** —
      the overflow menu's background used to run wide to the right. Clicking
      anywhere else on a row does nothing: no row highlight, no copy. The
      transcript still selects by dragging and the row still right-clicks to its
      context menu.
- [ ] Scroll a history list with more than one day in it: the day label moves up
      into the count row as its group leaves the top, changes as the next group
      arrives, and disappears again when scrolled back to the top. The count row
      does not change height as it appears.
- [ ] Permission and credential banners sit directly under the title and search
      row, above the count row.
- [ ] The sidebar toggle sits over the sidebar, beside the window controls, where
      every other native app puts it. It has no tooltip — see the note in
      `MainWindowView` for why a custom item cannot go there.
- [ ] **Still open:** the toggle flickers when switching Settings → Dictation but
      not the other way. Best current explanation is that only Dictation adds a
      search field to the toolbar, so that direction restructures it. Untested.
- [ ] From the permissions pill, Review brings Scriber to the front over whatever
      app is active — with the main window already open behind that app, and with
      every window closed — and lands on Permissions and Input rather than the top
      of Settings. Same for the menu bar's "Permissions Required…" item.

## Build 16 interface changes

- [ ] Settings shows General, Feedback, ElevenLabs, Dictation, Dictation History,
      and Permissions and Input in that order, with Accessibility above Microphone.
- [ ] Command-comma opens Settings both with the main window open and with every
      window closed.
- [ ] Command-period collapses and expands the sidebar, and the View menu shows it
      in place of Control-Command-S. Then confirm Command-period still cancels the
      Clear Dictation History dialog rather than toggling the sidebar behind it —
      Command-period is macOS's conventional Cancel, and this binding shadows it.
- [ ] Command-F still focuses search, and the placeholder carries the hint.
- [ ] The overflow menu opens fully inside the window with the window at its
      default width near the right edge of the screen.
- [ ] Day groups render as rounded cards, legibly, in both light and dark
      appearance.
- [ ] Start a dictation and watch history through the wait: no row appears until
      the outcome lands. Then retry a failed entry and confirm its row stays
      visible with the Retrying label.
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
- [ ] Verify Microphone and Accessibility grants persist for the stable app.
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
      preference synchronization after Command-drag removal.

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
      competing dictation and global-shortcut tools disabled.
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

Read [`PASTE_ENGINE_RESEARCH.md`](PASTE_ENGINE_RESEARCH.md) before changing
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
