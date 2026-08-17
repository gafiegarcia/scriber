# Checks Only Gaf Can Run

This is a reusable catalog of checks that require Gaf's real environment, account, hardware, judgment, or physical participation. An agent selects and proposes the smallest relevant set — usually one to three checks — but never performs one itself or records completion in this file.

`PRODUCT_SPEC.md` defines what must hold and the current diff identifies which behavior may have moved. Agent-runnable parsing, tests, builds, isolated UI fixtures, and visual inspection belong in `AUTOMATED_CHECKS.md`, not here.

Before tagging, Gaf runs the baseline against the final installed candidate, then any conditional checks implicated by changes since the previous tag. Results belong in the session and annotated tag message.

Never ask Gaf to risk irreplaceable history, the only copy of an API key, or account quota merely to manufacture a test state. **Every check that spends API credit requires explicit approval first.**

## Baseline for a tag candidate

- From the installed app, hold to dictate, speak, and release. **This spends API credit; ask first.** The text lands at the cursor focused when transcription completes, including when focus moves to another app during transcription.
- With **Show in Dock** off, close the last window, start recording with a global shortcut, then cancel with Escape before transcription. The menu bar remains available and **Open Scriber** restores the window.
- Quit and reopen Scriber, then check again after a macOS restart. Microphone and Accessibility grants and the stored key survive both without another login-Keychain prompt.

## When recording shortcuts or the pill change

- Tap the dictation shortcut as fast as possible several times in a row, then hold it and dictate normally. Every dictation after the burst still works and nothing freezes. The burst puts a start, a stop, and a cancel inside the time the capture stack needs to close a recording, and both a recorder that refuses every later start and a deadlock between the capture queue and the main thread have reached Gaf this way. If it does freeze, run `sample Scriber 3` before quitting it: the main thread's stack and the capture queue's stack name the deadlock between them, and nothing recovered afterwards will.
- Typing during the first second of a held recording and pressing Escape during either recording mode each cancel with the cancellation sound. A press too brief to have been a dictation instead closes silently, with no sound and no pill message.
- Holding the shortcut shows no Cancel until the pointer moves over the pill, which widens it in; moving off narrows it back out. Escape still cancels while held with the pointer elsewhere. A quick tap of it locks hands-free instead: Cancel is shown unconditionally from then on (no hover needed), and the pill widens further, animating only Confirm in on its trailing edge. Tapping it again stops it. With the default binding, bare `fn` still opens the emoji picker — the tap must not swallow it. **Wispr Flow must be quit first.**
- Tap the shortcut and speak immediately, without waiting for the pill to settle. The first word is in the transcript: recording starts on the press, so nothing is dropped while the tap and the hold are being told apart.
- Hold the shortcut a beat past `DictationShortcutTiming.tapThreshold` and let go. It stops and transcribes rather than carrying on. The threshold is the only number here that a test cannot settle: it decides whether a deliberately short dictation is read as a tap, and only a hand knows where it belongs.
- Bind the shortcut to a keyed chord such as `⌘⇧D`, hold it well past the auto-repeat delay, speak, and release. One recording starts, nothing restarts it, no repeated characters reach the app in front, and letting go stops it. `fn` cannot show this: a modifier-only chord never auto-repeats, which is why the default configuration looks fine either way. Then, while holding the same chord, let go of `⇧` before `D`: the recording stops there rather than outliving the chord. Restore the preferred shortcut afterward.
- A refused chord such as `⌘Q` closes the recorder with its reason, leaves the stored binding alone, and leaves the keyboard usable. Pressing the **left** ⌘ or ⌥ alone is refused with a reason naming the right-hand one.
- Bind **Right ⌥** alone, then press the left ⌥: nothing starts. Press the right one and dictate. Then hold both, and let go of the right one while the left stays down — the recording stops there. macOS reports only that Option is down, so a release read from the flags would never come.
- Bind **Right ⌘+Right ⌥** together, then press the two left keys: nothing starts. One of each: nothing starts. Both right ones: it records, and letting go of either stops it. Restore the preferred shortcut afterward.
- Redo Setup with a sided shortcut bound, and press the left twin at the test step. It refuses to confirm, the same as any other wrong key. Setup's test and the global shortcut have to agree about which key counts, or setup passes a binding that then does nothing.
- Record a new shortcut: the recorder shows the chord live and closes at the first key release, and a chord containing `fn` displays it first. Restore the preferred shortcut afterward.
- Every pill still reads as tinted glass rather than a coloured slab, in light and dark and over both a light and a dark window behind it. Recording, transcribing, and cancellation carry no tint; a copied result is green; no-words, no-signal, permission, credential, and failure pills are amber. The glyph and the glass never disagree about which of the three a pill is.
- Compare a green pill against an amber one **in light appearance**, which is where the tint has least to work with: they must be tellable apart from each other, not merely visible. Checking each tone on its own hides the failure that matters.
- The pill's top and bottom edges carry a faint highlight, brightest at the edges and clear at the sides. It stays faint over a light background and never reads as a drawn outline over a dark one, and it follows the shape through the resize into a copied result rather than popping.
- Clicking a pill's body opens what its button would have opened, and the pointer becomes a link cursor only on the pills that do something. Clicking the body of a recording, transcribing, copied-result, or cancellation pill does nothing — in particular it never cancels a recording, spends credit, or discards the cancelled-transcript recovery. Buttons still take their own clicks.

## When visual design changes

- Both appearances read comfortably in the window: the toolbar, the titlebar's day strip, the warning control, day cards, separators, and the copy toast. Switch appearance only. The window is opaque and its translucent parts sample the app's own background, so the desktop behind it cannot reach them and changing wallpaper proves nothing about any of these.
- Both appearances read comfortably over both a light and a dark desktop for the pill, which is a borderless panel floating on the desktop rather than in a window. Wallpaper is a real variable here and nowhere else.
- The app icon looks right in the Dock and Finder.

## When real history or transcription recovery changes

- Copy a known, non-sensitive history entry and paste it into a scratch field. The correct transcript arrives and the copy toast does not move the source row. This replaces the current clipboard.
- Create a disposable retryable dictation by speaking for more than one second and cancelling with Escape, then retry that generated entry. **Retry spends API credit; ask first.** Its row remains visible with the Retrying label and success is confirmed by a readable pill. Delete only this synthetic entry afterward, after checking its content and timestamp distinguish it from real history.

## When credentials, Keychain storage, or usage change

- Only with a disposable second key whose full value has been retained outside Scriber: save it, quit and reopen Scriber, restart macOS, and use Settings → ElevenLabs → Remove API Key…. The key reads back across both launches, and removal makes dictation unavailable. Restore the intended key afterward. Never use this procedure on the only recoverable key.
- Only when an already exhausted account or a disposable zero-quota key is available: confirm recovery opens the Credits section rather than focusing the key field. Never consume credits merely to reach exhaustion.
- With User → Read disabled on an otherwise valid Speech-to-Text key, the key remains verified and dictation works across relaunch. **Dictation spends API credit; ask first.** Cached credits are labelled as last known and subdued, only one usage-retry action appears, and a failed retry never marks the key invalid. Restoring User → Read and retrying returns the current credits display, with its percentage beside the bar.

## When signing, the disk image, or distribution change

- Dictate with music playing and confirm other audio is silenced. The hardened runtime withholds microphone and Core Audio access from a process whose entitlements do not cover it, and the process tap that mutes other apps is the path most likely to fail silently rather than at build time.
- Install the candidate disk image from `.build/` in a macOS account that has never run Scriber. Setup requests Microphone and Accessibility from scratch, the ElevenLabs key saves, and no warning claims the app cannot be opened or its developer cannot be verified. **Saving a key and dictating spends API credit; ask first.**
- Open that same image on a Mac running the oldest supported macOS, which has never had Xcode installed. This is the only check that exercises the deployment floor.
- Gatekeeper is exercised by the quarantine flag and the notarization ticket, never by where the image came from, so any route that marks it as downloaded serves and no published release is needed. AirDrop to another Mac is the easy one. Confirm the flag arrived before opening anything — `xattr -p com.apple.quarantine <image>` must print a value — because a file that lost it says nothing about what a stranger sees. Copying into a second account on the same Mac loses the flag and cannot get it back, so read that check for its fresh permission, Keychain, and onboarding state, and take the Gatekeeper half from the machine that received the image instead.
- After the first launch of a build signed with a new certificate, confirm Microphone and Accessibility survive a restart. A changed signing identity is a different app to macOS, and a stale entry has to be removed and re-added rather than toggled.
- Turn **Mute other audio while recording** on and confirm the explanation appears before the toggle moves, that cancelling leaves it off, and that the caption's link lands on Screen & System Audio Recording rather than the top of Privacy & Security. Then dictate with music playing.
- With the release published, open Settings → General → Updates and choose **Check Now**. It reports the running version as current. This reaches GitHub but spends no API credit.

- Pick each preset in turn: the chosen one is tinted and the others are not, and the shortcut takes effect without any confirm step. Record a custom chord, switch to a preset, and switch back — the recorded chord is still offered as its own button.

## When setup's shortcut step changes

- Run setup on a keyboard with no `fn` key that macOS can see, which is most keyboards Apple did not make. The `fn` choice refuses to confirm however hard the key is pressed, a recorded `⌃+⌥` confirms, and Finish Setup stays unavailable until one of them does. This is the case the step exists for and the only one that cannot be staged on Gaf's own machine.
- Choose each option in turn and press the shortcut it names. Confirmation follows the choice rather than surviving it, so switching away from a confirmed shortcut disarms Finish Setup again.
- Record a custom shortcut, confirm it, and finish. The recorder still refuses a reserved chord, and the chord that reaches Settings afterwards is the one that was tested.
- Start the test, then click into the API key field above it and type. Keys reach the field. A test that listens when it was not asked to swallows every key on the page.
- Redo Setup with a shortcut you recorded yourself. The picker opens on the shortcut you already hold rather than resetting to `fn`, and finishing leaves it as you set it.
- Setup is the only window on a first run — no main window behind it or showing past its edges — and finishing opens the main window for the first time. Redo Setup is the opposite case and correct: the main window is already open there, and setup sits in front of it.
- Close setup part-way with ⌘W. The menu bar carries **Finish Setup…** and reopens setup, which is the only route back with no main window to hold a warning. Quitting and reopening returns to setup rather than the main window.
- Press **Allow** for Microphone and again for Accessibility. System Settings comes to the front each time, on the right pane, rather than opening behind setup.

## When permissions or global-shortcut lifecycle change

- Revoke Microphone and Accessibility, separately and together. The toolbar's warning control appears, its popover lists every unresolved condition at once — including a missing key alongside missing permissions — and the pill and Settings route both work. Restore both grants before finishing; every warning should then leave. **macOS forces Quit & Reopen whenever Microphone access changes**, so no-relaunch recovery is observable only for Accessibility.
- A keyed Hold binding held down does not stall the machine either. The tap sits in front of every system event, and work done while its callback is on the stack delays every keystroke and click on the Mac.
- Revoking Accessibility while Scriber runs never stalls the machine. The shortcut monitor sits in front of every system event, so a monitor that will not stand down takes the pointer, clicks, and keyboard with it.
- Hold still starts a recording after the lid has been closed and reopened and after a long idle. macOS disables event taps across sleep, so this is where a shortcut monitor that fails to recover becomes visible.

## When audio capture or transcription outcomes change

- Set input volume to zero and dictate for as little as clears the too-brief-to-be-a-dictation guard. The **“No sound from the microphone”** pill appears with the failure sound, and the waveform is flat from the first moment. No duration is needed beyond that guard: a zero input volume sends nothing from the first buffer, so anything longer only hides a regression that shortened it. This costs no credit. Restore the input volume afterward.
- Submit audio with no recognisable words. **This spends API credit; ask first.** Scriber reports no words and leaves no history row behind.

## When installed-app lifecycle or menu-bar behavior changes

- With **Show in Dock** on, Scriber remains in the Dock and app switcher without an open window. Turning it off never closes a visible window. Restore the preferred setting afterward.
- The menu-bar icon remains steady through dictation and switches to the warning symbol when the real key is unusable. Exercise the warning only with an already unusable or disposable key; never disable the sole working key to manufacture it. Inspect the actual menu bar; do not diagnose this from `defaults`.
- Launch at login works in both directions across a macOS restart. Quit Scriber before restarting and clear **Reopen windows when logging back in** in the restart dialog, or the result means nothing: that feature relaunches whatever was running, so Scriber comes back whether or not the login item fired. Tell the two apart in the log — a real login launch reports `loginItem=true`, a restored one reports `loginItem=false`. Restore the preferred setting afterward.
- The Launch at login switch follows System Settings, not Scriber's last request. With Scriber's Settings open, remove Scriber from System Settings' Login Items: the switch turns off within a few seconds and **Start in the background** greys out with it. Then switch Scriber off under **Background App Activity**, the lower list on the same page and the only one with a per-item switch — removing the entry and switching it off are different states, and only this one produces the message. Scriber's switch turns off and stays quiet about it. Now turn Scriber's switch on: it refuses, and only then explains that macOS is holding it off and offers a button back to Login Items. Switch the row back on in System Settings and the message clears itself within a few seconds, with Scriber's window untouched. Restore the preferred setting afterward.
- With Launch at login and **Start in the background** both on, logging back in brings Scriber up with no window and no stolen focus, and a dictation shortcut works straight away. Quit Scriber and clear **Reopen windows when logging back in** first, as above — a restored Scriber opens its window and looks exactly like this check failing. Turn Start in the background off and log in again: the main window opens as usual. Opening Scriber yourself from Finder always shows the window, whichever way the setting is set — that is what separates a working launch-source check from a setting that suppresses everything. `log show --predicate 'subsystem == "com.gafiegarcia.scriber" AND category == "window-lifecycle"'` reports `loginItem=` and `startsInBackground=` for each launch if one of these surprises you.
- The **Window** menu keeps its full item set for as long as it stays open. Open it and wait 15 seconds, from the main window and from Settings. **Close ⌘W**, **Fill**, **Center**, **Move & Resize**, and **Full Screen Tile** come from AppKit rather than from Scriber's own commands, so anything that publishes a change while the menu is tracking makes SwiftUI reinstall the menu without them. Starting a dictation while the menu is open still prunes it; that case is marked `Known and unfixed:` in `Scriber/ScriberApp.swift` and is not a failure of this check.

## When the paste engine changes

Read [`PASTE_ENGINE.md`](PASTE_ENGINE.md) first; its table is the baseline.

- Delivery lands at the cursor in ChatGPT, Notion, Zen, Ghostty, Raycast, VS Code, and Zed, with no two-to-three-second delay at record start. **These dictations spend API credit; ask first.**
- A target with no focused text field falls back to copied rather than reporting false success — Zen on a page without a field is the case that caught this.
- Raycast running does not produce false recovery in Xcode, ChatGPT, or Notion.

## When audio muting changes

- With Music or Spotify playing, other audio goes silent only during capture and returns immediately on stop, cancel, or failure. It remains untouched when the preference is off. Denied System Audio Recording leaves dictation working and reports the muting failure only in Settings. Restore the preferred setting and permission afterward.
