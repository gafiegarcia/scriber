# Checks Only a Person Can Run

**Never run a check that spends API credit without asking first.**

This is the full list for a release. For ordinary work, do not run all of it —
the agent proposes the few checks that match what changed, at the end of the
session.

Checks are grouped by what they need in hand, so the awkward ones can be batched
into a single sitting. Boxes are per-release; reset them when a cycle starts.

## Needs nothing but the installed app

- [ ] Hold to dictate, speak, release: the text lands at the cursor in whatever
      app was focused, including one you switch to *during* transcription.
- [ ] Typing and Escape each cancel a recording, each with the cancellation sound.
- [ ] `Fn-Space` locks hands-free, Hold is ignored while locked, and Toggle stops
      it. Bare `Fn` still opens the emoji picker and types a normal Space.
      **Wispr Flow must be quit first.**
- [ ] Record a new shortcut: the recorder shows the chord live and closes at the
      *first* key release. Disabling Hold and Toggle independently prevents only
      the disabled one.
- [ ] `⌘,` opens Settings both with a window open and with all windows closed.
      `⌘F` focuses search from either pane.
- [ ] Delete one history entry and clear all history: both confirm first, and
      cancelling leaves everything alone. Copy puts the right transcript on the
      clipboard.
- [ ] With **Show app in Dock** off, closing the last window leaves dictation and
      the menu bar working. With it on, Scriber stays in the Dock and app
      switcher.
- [ ] The menu bar icon holds steady through a dictation and switches to the
      warning symbol when the key is unusable. Do not diagnose this from
      `defaults` — look at the menu bar.
- [ ] Light and dark both read comfortably, and the app icon looks right in the
      Dock and Finder.
- [ ] Set the input volume to zero and dictate: the "No sound from the microphone"
      pill appears with the failure sound. This costs no credit and must stay
      distinct from the no-words pill.

## Needs a real ElevenLabs key — spends credit, ask first

- [ ] A real dictation succeeds, and a retry from history keeps its row visible
      with the Retrying label, then confirms with a pill that lasts long enough to
      read.
- [ ] Output with no recognisable words leaves no history row behind.
- [ ] Exhausted credit routes recovery to the usage panel rather than the key
      field.
- [ ] The key saves and reads back across relaunch and restart, and Settings →
      Remove Key… removes it.

## Needs revoked permissions

- [ ] Revoke Microphone and Accessibility, separately and together: the warning,
      the pill, and the Settings route all appear, and recovery works after
      regranting. **macOS forces Quit & Reopen whenever Microphone access
      changes**, so no-relaunch recovery is only observable for Accessibility.
- [ ] The pill's Review button brings Scriber forward over whatever app is active
      and lands on Permissions and Input, not the top of Settings.

## Needs a restart

- [ ] Microphone and Accessibility grants survive, the stored key reads back with
      no further login-Keychain prompt, and Launch at Login works in both
      directions.

## Needs onboarding reset

`defaults delete com.gafiegarcia.scriber onboardingComplete`

- [ ] Launch presents onboarding before setup and Dictation after it, and the
      setup window is centred and fully visible above the Dock. Check a genuine
      first run *and* Settings → Redo Onboarding… with the main window already
      open.

## Only when the paste engine changes

Read [`PASTE_ENGINE.md`](PASTE_ENGINE.md) first; its table is the baseline.

- [ ] Delivery lands at the cursor in ChatGPT, Notion, Zen, Ghostty, Raycast,
      VS Code, and Zed, with no two-to-three-second delay at record start.
- [ ] A target with no focused text field falls back to copied rather than
      reporting a false success — Zen on a page without a field is the case that
      caught this before.
- [ ] Raycast running does not produce a false recovery panel in Xcode, ChatGPT,
      or Notion.

## Only when audio muting changes

- [ ] With Music or Spotify playing: other audio goes silent only during capture,
      returns immediately on stop, cancel, or failure, and is untouched when the
      preference is off. Denied System Audio Recording must leave dictation
      working and report the failure only in Settings.
