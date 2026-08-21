# Changelog

This file records intentionally identified Scriber releases and prerelease snapshots. Ordinary development builds belong in Git history, not here.

## 0.9.0 — 2026-08-15

Native bundle build 186, signed with a Developer ID Application certificate under the hardened runtime, notarized and stapled. Apple silicon, macOS 26 Tahoe or newer.

### Added

- **Setup has been rebuilt as nine steps, one decision each.** It used to be a single scrolling page that asked for everything at once and required almost none of it — the microphone was never actually tested, hands-free dictation was never mentioned, and setup finished without you ever dictating. Now each step asks one thing, will not move on until that thing is genuinely done, and the last one before the end is a real dictation into a box, so the first time Scriber works is before setup closes rather than after. If you would rather skip the whole thing, **Set Up Later** on the first step drops you into the app, and Settings tells you what is still missing.
- **Setup tells you that ElevenLabs trains on your recordings unless you say otherwise.** New accounts have **Improve models for everyone** switched on, buried three levels into a profile menu. Setup now says so on its own step, shows you where the switch is, and notes that turning it off only covers what you send afterwards.
- **Setup makes you speak before it moves on.** The microphone step shows a live meter and stays put until it actually hears you. If it never does, **Continue without testing** is there from the first second, next to a link to the input volume setting that is usually the reason.
- **The Permissions tab now mentions Screen & System Audio Recording.** It is the permission Scriber asks for when you turn on muting, and the only one macOS will not report the answer to — so the row says that plainly, points at the right pane, and claims no status it cannot know.
- **Scriber is now a download.** It is signed with an Apple Developer ID certificate and notarized by Apple, so you can install it from a disk image or with `brew install --cask gafiegarcia/tap/scriber` and open it without macOS refusing to run it. Building from source is no longer the only way in.
- Scriber tells you when a newer version has been released. It asks GitHub once a day and, when there is one, adds an item to the menu bar that opens the release page. It never downloads or installs anything by itself, and the check can be switched off in Settings → General.
- **One shortcut now does both kinds of dictation.** Hold it and talk, and letting go stops. Or tap it, and Scriber keeps listening with your hands free until you tap again. There used to be two separate shortcuts, and setup only ever taught the first — so hands-free was something you found in Settings or never found at all, and on a keyboard with no `fn` key you could not reach it even then. Your existing Hold shortcut carries over as the one shortcut; the separate hands-free binding and the switches that turned each one off are gone.
- **Setup and Settings offer the same three shortcuts, and setup makes you press yours once before moving on.** `fn`, `Right ⌘`, or `Right ⌥` — or record your own — shown as a key that lights up when you press it, and setup will not go on until the one you chose has actually reached Scriber. Most keyboards Apple did not make have no `fn` key that macOS can see, because the key is handled inside the keyboard and never reaches the Mac, so the old setup left those users pressing a shortcut that could never work with nothing on screen to say so.
- **Scriber can tell your left ⌘ and ⌥ from the right ones.** Nothing on a Mac starts a shortcut with the right-hand key, which makes `Right ⌘` and `Right ⌥` free to hold on their own — and the closest thing to `fn` that a keyboard without one has. A shortcut bound to the right key ignores its left twin, and `Right ⌘+Right ⌥` together works as well. Binding a left one instead is refused with a note pointing at the right.
- Setup starts with the Mac's built-in microphone selected, marked **(Recommended)** in the input list. You can still pick any other input.
- Setup and Settings now say where an ElevenLabs API key comes from, with links to create an account and to make a key, and name the Speech to Text access it needs. The key field used to be blank with nowhere to go.
- The disk image now opens arranged: Scriber on the left, an **Applications** shortcut on the right, and an arrow between them. It used to open unstyled, with the two the wrong way round for the drag.

### Changed

- **Mute other audio while recording** is now off until you switch it on, and switching it on asks macOS for access there and then. It used to be on by default, so the permission arrived in the middle of a first dictation — with the shortcut still held down, and the app frozen until you answered. macOS calls it "System Audio Recording", which sounds far broader than what Scriber does with it; muting works whether you allow it or decline, because Scriber never reads what other apps play. Other apps also get their sound back a moment after a dictation rather than the instant it ends, which is what used to be heard as a glitch. Your existing setting is unchanged.
- Scriber now runs on **macOS 26 or later**, rather than requiring macOS 27. On macOS 26 the dictation pill keeps its glass appearance but does not respond to interaction, which is the only visible difference.
- macOS asks for your login Keychain password once, rather than after every reinstall. The signature no longer changes between builds, so the permission you grant sticks.

### Fixed

- **Redo Setup** now starts at the beginning instead of opening on the last page of the run before it — and its **Done** button finishes setup, rather than closing the window while the main window went on saying setup was not finished.
- Setup remembers which step it was on. Granting the microphone, which macOS answers by offering to relaunch Scriber, now comes back to the step that asked instead of starting over.
- Setup no longer claims your ElevenLabs key is **Verified** when it is not there. Deleting the key from Keychain Access left setup showing a green tick and letting you carry on, because the tick was reading a remembered answer rather than looking for the key — so setup finished and the first dictation failed with nothing having warned you.

### Removed

- The **"Microphone cut out"** warning is gone. It was meant to tell you when your microphone stopped sending audio partway through a dictation, but Bluetooth earbuds send literal silence between phrases, so it fired on an ordinary pause before you stopped recording — announcing that part of your dictation was missing when all of it had arrived. A microphone that sends nothing at all is still reported, as before.

## 0.8.8 — 2026-08-14

Native bundle build 143, installed from an entitlement-free, locally signed Release build.

### Fixed

- **Launch at login** now shows what macOS actually has. Turning Scriber off in System Settings' Login Items used to leave the switch on in Scriber forever, since nothing ever looked; it now follows within a few seconds, taking **Start in the background** with it. If macOS is holding Scriber switched off under **Background App Activity** — a state Scriber cannot undo for you — turning the switch on says so and offers a button straight to Login Items, instead of quietly flicking back off. Leave it off and Scriber says nothing: it is your setting to make.
- Scriber opens its main window when macOS starts it at login, rather than only when there happened to be a window left open to restore. Quitting with the window closed used to mean the next login brought up the menu bar icon and nothing else, with no setting to explain it.
- The **Window** menu no longer drops half its items a moment after you open it. **Close ⌘W**, **Fill**, **Center**, **Move & Resize**, and **Full Screen Tile** stay put for as long as the menu is open.
- Tapping the dictation shortcut quickly several times no longer leaves Scriber unable to record. It could refuse every dictation afterwards with "the microphone recording could not start" until the app was quit and reopened, and in some cases froze the app outright with the pill stuck on screen.
- A quick tap no longer makes the built-in speaker pop. The start sound is no longer cut off partway through, which is what produced the click.
- **Dictating with Bluetooth headphones no longer freezes the Mac for about a second.** Opening the microphone pulls a headset out of music mode into call mode, and Scriber used to sit and wait for that on the same thread that handles every keystroke — so anything typed during the pause piled up and arrived late. The microphone now opens out of the way, and silencing other audio does too.
- Tapping the shortcut repeatedly no longer leaves notices behind it. A tap pair too brief to have held any speech used to come back with "No sound from the microphone", and a tap landing during one got "Still transcribing". That message is meant for a dictation given into a microphone that was muted or turned down, so it now waits for one long enough to have been that.
- Typing during a held dictation cancels it from the moment the shortcut goes down. There was a short window at the start where another key — `fn`+delete above all, which is forward delete and starts a dictation on the way past — did not reach Scriber at all, so the dictation it began carried on regardless.
- Opening Settings or the main window during a dictation now actually ends it. The pill went away but the microphone stayed open behind the window.
- **Pressing the shortcut answers immediately.** The pill and the start sound used to wait for the microphone to open, which on a slow input meant a second of nothing at all. They now arrive on the press, whatever you are recording with, and the timer and level meter start when the microphone is really listening.

### Added

- Settings' General tab has **Start in the background**, beneath **Launch at login** and on by default. When macOS starts Scriber at login it comes up as a menu bar icon alone — no window, and no taking the front from whatever you were doing. It covers logins only: opening Scriber yourself always shows the window. It greys out while Launch at login is off, since it has nothing to govern then.
- Settings' ElevenLabs tab tells you what percentage of your credits is left, beside the bar that shows it.
- Settings' Sound tab has a **Check Input Level** button that shows your microphone's level as you speak, and an **Open Sound Settings** button beside it. Input volume is a macOS setting rather than a Scriber one, so a level that stays flat now points you where it can actually be fixed.
- Scriber now tells you when your microphone stopped sending audio partway through a dictation, instead of handing back a transcript quietly missing its second half. macOS can mute a microphone after recording has already begun — an input volume slid all the way down does it — and the recording sounds fine right up until it doesn't. The pill says so with **Check Input**, alongside the other microphone warnings — including when your dictation was copied to the clipboard rather than pasted, which used to report plain success.

- VoiceOver now names the two buttons in Settings' Keyterms list. The help button announced as its icon, and each term's remove button announced identically to every other, so nothing said which term it would delete; it now names its own term.

### Changed

- Dictation history has more room in it. A card's entries sit further off its sides and stand taller, and the time down the left has even space either side of it instead of being pushed up against the card's edge with a gulf between it and the transcript.
- Every row in Settings sits a little further off the sides of its card, and a keyterm in the added-terms list has more room around it.
- Settings keeps a setting and its own explanation together. A dividing line now falls only between one setting and the next, so the Sound tab's two switches read as two settings rather than four, the microphone level test reads as one thing rather than three, and the note about shortcuts sits under the group it describes instead of inside it.
- A press too quick to have been a dictation now closes in silence. A slipped finger, or `fn` pressed as part of a shortcut aimed at something else, used to answer with an alert sound and a pill; now the pill just closes and nothing is said. This also ends the occasional "Audio too short" failure from ElevenLabs: Scriber's own floor used to sit exactly on the 100 ms minimum the API accepts, so a recording rounding a hair under it was sent and refused.
- Cancelling a dictation no longer looks like something went wrong. The recovery pill drops the amber tint and the warning triangle and reads in the app's plain colours; **Undo** is still there if you want the recording back.
- The cancellation pill and the "No words detected" pill now close after 5 seconds instead of 6.
- The toolbar warning's popover is a little narrower, and its message sits closer to the sides of the box instead of leaving a wide margin there.
- The **Usage** section on Settings' ElevenLabs tab is now called **Credits**. The bar shows what is left and drains leftward as credits are spent, so a section called Usage read backwards against it. The pill that appears when your credits run out now offers **View Credits** rather than **View Usage**, matching the section it opens.

## 0.8.7 — 2026-08-06

Native bundle build 100, installed from an entitlement-free, locally signed Release build. The app itself is unchanged from `0.8.6`; this release opens the source.

### Changed

- Scriber is now under the MIT license instead of GPL-3.0-or-later.

### Removed

- The retired Electron implementation is no longer in the repository. It stopped at `0.6.0` and remains in Git history.

## 0.8.6 — 2026-08-05

Native bundle build 99, installed from an entitlement-free, locally signed Release build.

### Fixed

- Scrolling a long dictation history is noticeably smoother. The titlebar's day label was rewriting itself on every scroll frame regardless of whether the day it named actually changed, and each rewrite invalidated the whole history list, forcing it to regroup every record in the history on every frame.
- The Keyterms field in Settings' Dictation tab no longer shrinks the instant you type or overflows past the Add button on a long entry. It's back to a fixed width, sized for the short word or phrase a keyterm actually is, and its placeholder and typed text stay left-aligned instead of hugging the field's right edge.

### Changed

- Times in the dictation list line up. The hour is zero-padded, so `08.30` sits directly under `10.30` instead of hanging a digit short of it; your Mac's locale still decides the separator, the 12- or 24-hour clock, and any AM/PM.
- The failure cue is your Mac's own system alert sound, played at your alert volume, rather than a fixed sound Scriber picked. The start and cancel cues are different system sounds too.
- The keyterms you've added now sit in their own card under the field that adds them, one row per term with a divider between them, instead of each reading as its own settings row with the same divider treatment as Language or the filler-word toggle. Rows are roomier too, so the delete button on a crowded list is easy to tie to the entry beside it at a glance.
- The Keyterms row no longer spends a permanent caption line explaining what a keyterm is. Click the small **ⓘ** beside **Keyterms** for the same explanation in a popover.

## 0.8.5 — 2026-08-04

Native bundle build 79, installed from an entitlement-free, locally signed Release build.

### Fixed

- Holding a shortcut bound to a key, such as `⌘⇧D`, no longer stalls the Mac. macOS repeats a held key about eleven times a second, and Scriber read each repeat of the chord you were holding as you starting to type — which cancelled the recording and let the next repeat start a new one, several times a second, with all of it running inside the callback the whole system's keyboard and mouse input waits on. A held Hold or Toggle chord is now one press and one release, and none of the work it triggers happens inside that callback. A modifier-only shortcut such as the default `fn` never showed this.
- A refused shortcut no longer leaves the recorder listening. It used to keep a keyboard monitor that swallowed every keystroke, so nothing in Scriber could be typed into until the window was closed.

### Added

- Shortcuts macOS already owns are refused with a reason: any chord whose only modifier is `⌘`, a single modifier held on its own, and the system combinations for screenshots, Mission Control, spaces, Spotlight, input sources, the character viewer, the Dock, locking, logging out, force quit, full screen, zoom and the other accessibility bindings, keyboard navigation, and Help. Scriber's shortcuts are taken from every app at once, so a binding on `⌘C` would replace copy everywhere.
- `Escape` closes the Settings window, unless a shortcut recorder is capturing — where it still cancels the capture — or a confirmation is on screen.
- Return adds the keyterm in the field.

### Changed

- Settings is five tabs — General, Dictation, Sound, ElevenLabs, Permissions — instead of one long scrolling pane, and every route that opens Settings to fix something now lands on the tab that owns it.
- The microphone input picker sits under Sound, beside the sounds Scriber plays and the option to mute other audio.
- Clearer labels throughout Settings: the sounds setting says what you will actually hear, keyterms explain what they are for, "Hands-free Toggle" is now "Hands-free Dictation", "Redo Onboarding…" is "Redo Setup…", and "Remove Key…" is "Remove API Key…".
- The day label in Dictation and the Settings section headers sit a little left of the cards they name, so the content is what reads as indented.

## 0.8.4 — 2026-08-03

Native bundle build 64, installed from an entitlement-free, locally signed Release build.

### Changed

- The day a group belongs to is now named in a strip inside the window's titlebar rather than on a band pinned inside the list. The strip shares the titlebar's own material, so scrolled entries pass under one continuous surface instead of meeting an opaque band and then a translucent one.
- The empty Dictation history now reads "No Dictations Yet" on its own, without the sentence that followed it.

## 0.8.3 — 2026-08-03

Native bundle build 63, installed from an entitlement-free, locally signed Release build.

### Changed

- The floating pill now shows Cancel while holding a recording, not only once it locks into hands-free. Locking in now only animates Confirm into the pill instead of both controls.
- Cancel during a held recording only appears once the pointer is over the pill, which widens to make room and narrows back out when the pointer leaves; Escape still cancels without hovering. Hands-free continues to show Cancel unconditionally.
- The pill's top and bottom edges now catch a faint highlight, so its glass reads as a lit edge rather than a flat panel.
- The pill's outcome tint is stronger in light mode. Light glass washed the accents out far enough that a green success and an amber warning looked the same, which is the one thing that tint exists to tell apart.

## 0.8.2 — 2026-08-02

Native bundle build 47, installed from an entitlement-free, locally signed Release build.

### Fixed

- Speech-to-Text-only ElevenLabs keys remain verified and usable without account-usage access. When current credits cannot be read, Settings now identifies and subdues the cached values as last-known information and offers one retry action instead of presenting stale usage as current beside two refresh buttons.
- Turning Scriber's Accessibility access off while it was running could lock up the whole Mac for about a minute — the pointer still moved, but clicks, the Dock, and the keyboard all stopped responding. Scriber kept switching its shortcut monitor back on after macOS switched it off, and because every event on the machine passes through that monitor, the two fighting held up everything else. Scriber now shuts the monitor down instead.

### Changed

- The floating pill now tints toward its outcome — amber for a recoverable problem, green for a copied or pasted result — and its body is clickable wherever a button already was, with the same link cursor. A recording or an in-progress pill still takes no click.
- The copied-result pill's title always reads "Copied to clipboard," with the live reason underneath, and every "Open"/"Open History" button now reads "See History."
- When automatic paste can't find a focused text box after dispatching Paste, the copied-result pill now says "No text box was focused to paste into" instead of telling you to select one.
- The app icon has a lighter shadow so its shape reads more cleanly in the Dock and Finder.
- Every permission button now says "Allow," in Settings and in onboarding alike. The buttons used to change their own label — "Allow" or "Open Settings" — depending on how far macOS thought you had got, which told you nothing you wanted to know and, for Accessibility, sometimes did nothing at all. One button, one word, and it always takes you to the place that can grant the permission.
- The Accessibility "Allow" button opens System Settings and nothing else. It used to also raise the system permission prompt, so two things appeared at once — and since that prompt cannot grant the permission, granting it in System Settings left the prompt stranded on screen.

## 0.8.1 — 2026-07-31

Native bundle build 39, installed from an entitlement-free, locally signed Release build.

### Changed

- Opening the main window now puts the cursor in the toolbar's search field, so the first thing you type searches instead of pressing a button on the first entry. Switching back to a window that was already open leaves your place, and your text selection, alone.
- The workspace name in the toolbar is plain text. It was the only thing in that group that looked tappable while doing nothing.
- Row separators inside a day card now reach the card's edge.
- The pinned day label lost its outlined capsule. It now sits flat against the page in the same colour, so entries scrolling past simply disappear under it instead of sliding behind a visible shape.

## 0.8.0 — 2026-07-30

### Changed

- Settings has moved out of the main window into its own window, and the sidebar it lived in is gone. The main window's toolbar now carries the workspace name, the dictation count, and search. Settings opens with `⌘,`, from the app menu, or from the menu bar item.
- Dictation history now scrolls under that toolbar, keeps the day label pinned while its day is on screen, and gives each day one transparent card. The transcript returns to the standard text size.
- Missing permissions and an unusable key no longer take the top of the history page. They appear as a warning control in the toolbar whose popover lists every unresolved condition at once, and they leave when resolved.
- Copy confirmations arrive in a stack in the window's bottom-right corner, tinted by outcome.
- Hands-free recording now puts Cancel on the pill's leading edge and Confirm on its trailing edge, animating both controls in when a held recording locks.
- Shortcut labels put `fn` before the other modifiers.

### Fixed

- Focusing Scriber no longer respawns an unchanged missing-permissions pill or restarts its dismissal timer.
- Scriber no longer crashes shortly after launch when the missing-permissions warning appears.

## 0.7.0 — 2026-07-29

The first release without a prerelease suffix. It does not claim v1 polish; it marks the point where versions move by plain semver instead of alpha numbering. See [`docs/VERSIONING.md`](docs/VERSIONING.md).

Native bundle build 30, installed from an entitlement-free, locally signed Release build.

### Added

- Settings can remove the stored ElevenLabs key, so recovering from a bad key no longer means opening Keychain Access.
- Settings can send you back through onboarding.

### Changed

- Deleting a single dictation now asks for confirmation, matching Clear Dictation History. A transcript has no undo, and deleting one entry was the only destructive action in the app that happened on a single click.
- Recording a shortcut finishes the moment you release a key, instead of waiting for you to let go of all of them.
- Reworked Dictation history into calmer day-grouped cards, moved Clear Dictation History into Settings, and refined row controls and spacing through live review.
- Regrouped Settings and added the standard Settings, search, and sidebar keyboard routes.
- Rendered the menu-bar mark at its true vector aspect ratio instead of rounding its fractional width, kept it stable during normal work, and reserved its warning state for conditions that prevent dictation.

### Fixed

- The setup window no longer opens partly off the bottom of the screen, under the Dock. It is centred and sized to the display every time it appears, and its steps scroll if they ever do not fit.
- A microphone that produces no sound at all — muted, wrong device, input volume at zero — now says so, instead of the dictation vanishing with no transcript, no history entry, and no warning. It is reported separately from a recording that did carry sound but produced no recognisable words.
- The pill confirming a transcript reached the clipboard stays long enough to read after a History retry, and both routes to the clipboard now say the same thing.
- Empty ElevenLabs results now produce an actionable microphone warning instead of disappearing silently.
- In-flight dictations remain hidden until an outcome exists, while explicit retries stay visible.
- Launch-time permission pills no longer trigger SwiftUI/AppKit update cycles, and the launch smoke check no longer activates or visibly duplicates Scriber.

### Known limitations

- The floating day label never appears while scrolling Dictation history. Being redesigned rather than repaired.
- The missing-permissions pill reappears and restarts its timer whenever a Scriber window gains focus, so it stays on screen through the System Settings trip it is asking for.
- Command-period does nothing inside the Clear Dictation History dialog. Clicking Cancel works.

## 0.7.0-alpha.8 — 2026-07-27

- Preserved native bundle build 14 after fixing the main window reopening when Command-W was pressed soon after launch.
- Moved the local development team setting out of the Xcode project while preserving the Release signing requirement.
- Recorded the first end-to-end run of the native UI suite.

## 0.7.0-alpha.7 — 2026-07-26

- Preserved native bundle build 11 after the full-codebase review and signed cross-app acceptance pass.
- Moved delivery to the cursor focused when transcription completes and followed keyboard focus into nonactivating panels such as Raycast.
- Removed Accessibility work from recording start, reported unusable credentials at launch, protected recovered history from overwrite, and added 30-day retained-audio expiry.

## 0.7.0-alpha.6 — 2026-07-23

- Preserved native bundle build 7 with a dedicated SwiftData history store, orphaned-audio recovery, and the long-lived local Release signing identity.

## 0.7.0-alpha.2 — 2026-07-23

- Preserved the final bundle-build-3 checkpoint using provisioned Data Protection Keychain storage before the personal-use login-Keychain transition.

## 0.7.0-alpha.1 — 2026-07-22

- Preserved native bundle build 3 as the first intentionally frozen personal-use source snapshot.
- Included shortcut-driven dictation, local history, retryable transcription, automatic insertion, copied fallback, and credit-free automated coverage.

The names `0.7.0-alpha.3`, `.4`, and `.5` were used while discussing installation candidates, but no Git tags with those names were created. They are not releases and therefore do not receive changelog entries.

Electron `0.6.0` and earlier belong to the retired Electron implementation. Its source and changelog were never tagged under their own version; they remain in Git history, and `v0.8.6` is the last tag whose tree still contains them.
