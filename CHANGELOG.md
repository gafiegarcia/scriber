# Changelog

This file records intentionally identified Scriber releases and prerelease
snapshots. Ordinary development builds belong in Git history, not here.

## Unreleased

## 0.8.6 — 2026-08-05

Native bundle build 96, installed from an entitlement-free, locally signed
Release build.

### Fixed

- Scrolling a long dictation history is noticeably smoother. The titlebar's day
  label was rewriting itself on every scroll frame regardless of whether the
  day it named actually changed, and each rewrite invalidated the whole
  history list, forcing it to regroup every record in the history on every
  frame.
- The Keyterms field in Settings' Dictation tab no longer shrinks the instant
  you type or overflows past the Add button on a long entry. It's back to a
  fixed width, sized for the short word or phrase a keyterm actually is, and
  its placeholder and typed text stay left-aligned instead of hugging the
  field's right edge.

### Changed

- Times in the dictation list line up. The hour is zero-padded, so `08.30`
  sits directly under `10.30` instead of hanging a digit short of it; your
  Mac's locale still decides the separator, the 12- or 24-hour clock, and any
  AM/PM.
- The failure cue is your Mac's own system alert sound, played at your alert
  volume, rather than a fixed sound Scriber picked. The start and cancel cues
  are different system sounds too.
- The keyterms you've added now sit in their own card under the field that
  adds them, one row per term with a divider between them, instead of each
  reading as its own settings row with the same divider treatment as Language
  or the filler-word toggle. Rows are roomier too, so the delete button on a
  crowded list is easy to tie to the entry beside it at a glance.
- The Keyterms row no longer spends a permanent caption line explaining what a
  keyterm is. Click the small **ⓘ** beside **Keyterms** for the same
  explanation in a popover.

## 0.8.5 — 2026-08-04

Native bundle build 79, installed from an entitlement-free, locally signed
Release build.

### Fixed

- Holding a shortcut bound to a key, such as `⌘⇧D`, no longer stalls the Mac.
  macOS repeats a held key about eleven times a second, and Scriber read each
  repeat of the chord you were holding as you starting to type — which cancelled
  the recording and let the next repeat start a new one, several times a second,
  with all of it running inside the callback the whole system's keyboard and
  mouse input waits on. A held Hold or Toggle chord is now one press and one
  release, and none of the work it triggers happens inside that callback.
  A modifier-only shortcut such as the default `fn` never showed this.
- A refused shortcut no longer leaves the recorder listening. It used to keep a
  keyboard monitor that swallowed every keystroke, so nothing in Scriber could
  be typed into until the window was closed.

### Added

- Shortcuts macOS already owns are refused with a reason: any chord whose only
  modifier is `⌘`, a single modifier held on its own, and the system
  combinations for screenshots, Mission Control, spaces, Spotlight, input
  sources, the character viewer, the Dock, locking, logging out, force quit,
  full screen, zoom and the other accessibility bindings, keyboard navigation,
  and Help. Scriber's shortcuts are taken from every app at once, so a binding
  on `⌘C` would replace copy everywhere.
- `Escape` closes the Settings window, unless a shortcut recorder is capturing —
  where it still cancels the capture — or a confirmation is on screen.
- Return adds the keyterm in the field.

### Changed

- Settings is five tabs — General, Dictation, Sound, ElevenLabs, Permissions —
  instead of one long scrolling pane, and every route that opens Settings to fix
  something now lands on the tab that owns it.
- The microphone input picker sits under Sound, beside the sounds Scriber plays
  and the option to mute other audio.
- Clearer labels throughout Settings: the sounds setting says what you will
  actually hear, keyterms explain what they are for, "Hands-free Toggle" is now
  "Hands-free Dictation", "Redo Onboarding…" is "Redo Setup…", and "Remove Key…"
  is "Remove API Key…".
- The day label in Dictation and the Settings section headers sit a little left
  of the cards they name, so the content is what reads as indented.

## 0.8.4 — 2026-08-03

Native bundle build 64, installed from an entitlement-free, locally signed
Release build.

### Changed

- The day a group belongs to is now named in a strip inside the window's
  titlebar rather than on a band pinned inside the list. The strip shares the
  titlebar's own material, so scrolled entries pass under one continuous
  surface instead of meeting an opaque band and then a translucent one.
- The empty Dictation history now reads "No Dictations Yet" on its own, without
  the sentence that followed it.

## 0.8.3 — 2026-08-03

Native bundle build 63, installed from an entitlement-free, locally signed
Release build.

### Changed

- The floating pill now shows Cancel while holding a recording, not only once
  it locks into hands-free. Locking in now only animates Confirm into the pill
  instead of both controls.
- Cancel during a held recording only appears once the pointer is over the
  pill, which widens to make room and narrows back out when the pointer
  leaves; Escape still cancels without hovering. Hands-free continues to show
  Cancel unconditionally.
- The pill's top and bottom edges now catch a faint highlight, so its glass
  reads as a lit edge rather than a flat panel.
- The pill's outcome tint is stronger in light mode. Light glass washed the
  accents out far enough that a green success and an amber warning looked the
  same, which is the one thing that tint exists to tell apart.

## 0.8.2 — 2026-08-02

Native bundle build 47, installed from an entitlement-free, locally signed
Release build.

### Fixed

- Speech-to-Text-only ElevenLabs keys remain verified and usable without account-
  usage access. When current credits cannot be read, Settings now identifies and
  subdues the cached values as last-known information and offers one retry action
  instead of presenting stale usage as current beside two refresh buttons.
- Turning Scriber's Accessibility access off while it was running could lock up
  the whole Mac for about a minute — the pointer still moved, but clicks, the
  Dock, and the keyboard all stopped responding. Scriber kept switching its
  shortcut monitor back on after macOS switched it off, and because every event
  on the machine passes through that monitor, the two fighting held up
  everything else. Scriber now shuts the monitor down instead.

### Changed

- The floating pill now tints toward its outcome — amber for a recoverable
  problem, green for a copied or pasted result — and its body is clickable
  wherever a button already was, with the same link cursor. A recording or an
  in-progress pill still takes no click.
- The copied-result pill's title always reads "Copied to clipboard," with the
  live reason underneath, and every "Open"/"Open History" button now reads
  "See History."
- When automatic paste can't find a focused text box after dispatching Paste,
  the copied-result pill now says "No text box was focused to paste into"
  instead of telling you to select one.
- The app icon has a lighter shadow so its shape reads more cleanly in the Dock
  and Finder.
- Every permission button now says "Allow," in Settings and in onboarding alike.
  The buttons used to change their own label — "Allow" or "Open Settings" —
  depending on how far macOS thought you had got, which told you nothing you
  wanted to know and, for Accessibility, sometimes did nothing at all. One
  button, one word, and it always takes you to the place that can grant the
  permission.
- The Accessibility "Allow" button opens System Settings and nothing else. It
  used to also raise the system permission prompt, so two things appeared at
  once — and since that prompt cannot grant the permission, granting it in
  System Settings left the prompt stranded on screen.

## 0.8.1 — 2026-07-31

Native bundle build 39, installed from an entitlement-free, locally signed
Release build.

### Changed

- Opening the main window now puts the cursor in the toolbar's search field, so
  the first thing you type searches instead of pressing a button on the first
  entry. Switching back to a window that was already open leaves your place, and
  your text selection, alone.
- The workspace name in the toolbar is plain text. It was the only thing in that
  group that looked tappable while doing nothing.
- Row separators inside a day card now reach the card's edge.
- The pinned day label lost its outlined capsule. It now sits flat against the
  page in the same colour, so entries scrolling past simply disappear under it
  instead of sliding behind a visible shape.

## 0.8.0 — 2026-07-30

### Changed

- Settings has moved out of the main window into its own window, and the sidebar
  it lived in is gone. The main window's toolbar now carries the workspace name,
  the dictation count, and search. Settings opens with `⌘,`, from the app menu,
  or from the menu bar item.
- Dictation history now scrolls under that toolbar, keeps the day label pinned
  while its day is on screen, and gives each day one transparent card. The
  transcript returns to the standard text size.
- Missing permissions and an unusable key no longer take the top of the history
  page. They appear as a warning control in the toolbar whose popover lists
  every unresolved condition at once, and they leave when resolved.
- Copy confirmations arrive in a stack in the window's bottom-right corner,
  tinted by outcome.
- Hands-free recording now puts Cancel on the pill's leading edge and Confirm on
  its trailing edge, animating both controls in when a held recording locks.
- Shortcut labels put `fn` before the other modifiers.

### Fixed

- Focusing Scriber no longer respawns an unchanged missing-permissions pill or
  restarts its dismissal timer.
- Scriber no longer crashes shortly after launch when the missing-permissions
  warning appears.

## 0.7.0 — 2026-07-29

The first release without a prerelease suffix. It does not claim v1 polish; it
marks the point where versions move by plain semver instead of alpha numbering.
See [`docs/VERSIONING.md`](docs/VERSIONING.md).

Native bundle build 30, installed from an entitlement-free, locally signed
Release build.

### Added

- Settings can remove the stored ElevenLabs key, so recovering from a bad key no
  longer means opening Keychain Access.
- Settings can send you back through onboarding.

### Changed

- Deleting a single dictation now asks for confirmation, matching Clear Dictation
  History. A transcript has no undo, and deleting one entry was the only
  destructive action in the app that happened on a single click.
- Recording a shortcut finishes the moment you release a key, instead of waiting
  for you to let go of all of them.
- Reworked Dictation history into calmer day-grouped cards, moved Clear
  Dictation History into Settings, and refined row controls and spacing through
  live review.
- Regrouped Settings and added the standard Settings, search, and sidebar
  keyboard routes.
- Rendered the menu-bar mark at its true vector aspect ratio instead of rounding
  its fractional width, kept it stable during normal work, and reserved its
  warning state for conditions that prevent dictation.

### Fixed

- The setup window no longer opens partly off the bottom of the screen, under the
  Dock. It is centred and sized to the display every time it appears, and its
  steps scroll if they ever do not fit.
- A microphone that produces no sound at all — muted, wrong device, input volume
  at zero — now says so, instead of the dictation vanishing with no transcript, no
  history entry, and no warning. It is reported separately from a recording that
  did carry sound but produced no recognisable words.
- The pill confirming a transcript reached the clipboard stays long enough to read
  after a History retry, and both routes to the clipboard now say the same thing.
- Empty ElevenLabs results now produce an actionable microphone warning instead
  of disappearing silently.
- In-flight dictations remain hidden until an outcome exists, while explicit
  retries stay visible.
- Launch-time permission pills no longer trigger SwiftUI/AppKit update cycles,
  and the launch smoke check no longer activates or visibly duplicates Scriber.

### Known limitations

- The floating day label never appears while scrolling Dictation history. Being
  redesigned rather than repaired.
- The missing-permissions pill reappears and restarts its timer whenever a
  Scriber window gains focus, so it stays on screen through the System Settings
  trip it is asking for.
- Command-period does nothing inside the Clear Dictation History dialog. Clicking
  Cancel works.

## 0.7.0-alpha.8 — 2026-07-27

- Preserved native bundle build 14 after fixing the main window reopening when
  Command-W was pressed soon after launch.
- Moved the local development team setting out of the Xcode project while
  preserving the Release signing requirement.
- Recorded the first end-to-end run of the native UI suite.

## 0.7.0-alpha.7 — 2026-07-26

- Preserved native bundle build 11 after the full-codebase review and signed
  cross-app acceptance pass.
- Moved delivery to the cursor focused when transcription completes and followed
  keyboard focus into nonactivating panels such as Raycast.
- Removed Accessibility work from recording start, reported unusable credentials
  at launch, protected recovered history from overwrite, and added 30-day
  retained-audio expiry.

## 0.7.0-alpha.6 — 2026-07-23

- Preserved native bundle build 7 with a dedicated SwiftData history store,
  orphaned-audio recovery, and the long-lived local Release signing identity.

## 0.7.0-alpha.2 — 2026-07-23

- Preserved the final bundle-build-3 checkpoint using provisioned Data
  Protection Keychain storage before the personal-use login-Keychain transition.

## 0.7.0-alpha.1 — 2026-07-22

- Preserved native bundle build 3 as the first intentionally frozen personal-use
  source snapshot.
- Included shortcut-driven dictation, local history, retryable transcription,
  automatic insertion, copied fallback, and credit-free automated coverage.

The names `0.7.0-alpha.3`, `.4`, and `.5` were used while discussing installation
candidates, but no Git tags with those names were created. They are not releases
and therefore do not receive changelog entries.

Electron `0.6.0` and earlier are recorded in the frozen
[Electron changelog](apps/electron/CHANGELOG.md).
