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

- Tap the dictation shortcut as fast as possible several times in a row, then hold it and dictate normally. Every dictation after the burst still works, nothing freezes, and the burst itself says nothing — no pill message, no **No sound from the microphone**, and no **Still transcribing** on the hold that follows. A tap pair too short to have held speech closes the way a misclick does. The burst puts a start, a stop, and a cancel inside the time the capture stack needs to close a recording, and both a recorder that refuses every later start and a deadlock between the capture queue and the main thread have reached Gaf this way. If it does freeze, run `sample Scriber 3` before quitting it: the main thread's stack and the capture queue's stack name the deadlock between them, and nothing recovered afterwards will.
- Typing during the first second of a held recording and pressing Escape during either recording mode each cancel with the cancellation sound. A press too brief to have been a dictation instead closes silently, with no sound and no pill message.
- Holding the shortcut shows no Cancel until the pointer moves over the pill, which widens it in; moving off narrows it back out. Escape still cancels while held with the pointer elsewhere. A quick tap of it locks hands-free instead: Cancel is shown unconditionally from then on (no hover needed), and the pill widens further, animating only Confirm in on its trailing edge. Tapping it again stops it. With the default binding, bare `fn` still opens the emoji picker — the tap must not swallow it. **Wispr Flow must be quit first.**
- Tap the shortcut and speak immediately, without waiting for the pill to settle. The first word is in the transcript: recording starts on the press, so nothing is dropped while the tap and the hold are being told apart.
- Hold the shortcut a beat past `DictationShortcutTiming.tapThreshold` and let go. It stops and transcribes rather than carrying on. The threshold is the only number here that a test cannot settle: it decides whether a deliberately short dictation is read as a tap, and only a hand knows where it belongs.
- Bind the shortcut to a keyed chord such as `⌘⇧D`, hold it well past the auto-repeat delay, speak, and release. One recording starts, nothing restarts it, no repeated characters reach the app in front, and letting go stops it. `fn` cannot show this: a modifier-only chord never auto-repeats, which is why the default configuration looks fine either way. Then, while holding the same chord, let go of `⇧` before `D`: the recording stops there rather than outliving the chord. Restore the preferred shortcut afterward.
- A refused chord such as `⌘Q` closes the recorder with its reason, leaves the stored binding alone, and leaves the keyboard usable. Pressing the **left** ⌘ or ⌥ alone is refused with a reason naming the right-hand one.
- Bind **Right ⌥** alone, then press the left ⌥: nothing starts. Press the right one and dictate. Then hold both, and let go of the right one while the left stays down — the recording stops there. macOS reports only that Option is down, so a release read from the flags would never come.
- Bind **Right ⌘+Right ⌥** together, then press the two left keys: nothing starts. One of each: nothing starts. Both right ones: it records, and letting go of either stops it. Restore the preferred shortcut afterward.
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

## When setup changes

Add `--ui-testing --ui-testing-onboarding --ui-testing-onboarding-unlocked` to a Debug launch to reach the gated steps without granting anything to that build. The gates still render; only Continue stops obeying them, so anything below that tests a gate has to be run without it.

### Its shortcut step

- Run setup on a keyboard with no `fn` key that macOS can see, which is most keyboards Apple did not make. The key cap never lights up however hard the key is pressed, a recorded `⌃+⌥` does light it and confirms, and Continue stays unavailable until one of them does. This is the case the step exists for and the only one that cannot be staged on Gaf's own machine.
- Choose each option in turn and press the shortcut it names. The cap fills while the key is held and empties when it comes up. Confirmation follows the choice rather than surviving it, so switching away from a confirmed shortcut disarms Continue again.
- Press a sided shortcut's left twin. It refuses to confirm, the same as any other wrong key — setup's test and the global shortcut have to agree about which key counts, or setup passes a binding that then does nothing.
- Record a custom shortcut, confirm it, and finish. The recorder still refuses a reserved chord, and the chord that reaches Settings afterwards is the one that was tested.
- On the shortcut step, press Tab and Return. Focus moves and Continue fires. The step watches for keys the whole time it is open, and a watcher that swallows them takes the keyboard with it.
- Watch the step while nothing is pressed. Nothing on it changes height on its own: the presets are always showing, so the card cannot resize under the page centred beneath the title.

### Its permissions step

- Say nothing. Continue stays unavailable and the meter stays flat. Speak, and the label turns green and Continue lights up. Setup must not be completable with the microphone never tested.
- Set the input volume to zero and speak. **Continue without testing** is already on screen — it does not have to be waited for — and using it reaches the next step.
- Change the input device mid-step. The meter restarts and the confirmation resets, because it was the previous device that was proven.
- Reach the step with both grants already given. The microphone card, its meter and help, and the Accessibility row below them all fit without the page scrolling.
- Watch the menu bar's orange recording indicator across the whole flow. It appears on this step and on no other. Scriber holds the input open only where it draws a meter from it; Try it opens and closes it around the dictation itself.

### Its ElevenLabs key step

- Delete Scriber's key from Keychain Access, then open setup. The field is empty with no **Verified** badge beside it and Continue stays dead. The badge and the gate both speak for a Keychain item, and the preferences behind them do not change when that item is deleted, so setup has to look rather than remember.
- Delete the key while the step is already showing **Verified**, then step forward and back. The badge is gone. The step re-checks on every arrival, which is the only thing standing between a deleted key and a finished setup.
- Revoke the key on ElevenLabs rather than deleting it locally, then return to the step. It reads **Invalid** and Continue is dead. **Spends no transcription credit** — validation reads the account.
- Save a key, step forward, then come back. The badge still reads Verified and the field offers to replace rather than to add.
- Watch the card as the first key saves. The badge appears in a row that was already there, so nothing above it moves.

### Its shape and lifecycle

- Setup is the only window on a first run — no main window behind it or showing past its edges — and finishing opens the main window for the first time. Redo Setup is the opposite case and correct: the main window is already open there, and setup sits in front of it.
- Close setup part-way with ⌘W, before its dictation step. The menu bar carries **Finish Setup…** and reopens setup, which is the only route back with no main window to hold a warning. Quitting and reopening returns to setup rather than the main window.
- Press **Allow** for Microphone and again for Accessibility. System Settings comes to the front each time, on the right pane, rather than opening behind setup.
- Redo Setup with everything already granted and a shortcut you recorded yourself. Each step shows what is already true — Verified, allowed, your own chord — rather than asking again, and finishing leaves all of it as it was.
- Walk it on the shortest display available. The window is centred and wholly visible, and it never grows or shrinks as the steps change.
- Drag setup away from the centre and press **⌃🌐C**. The window travels to the centre exactly as it does from Window ▸ Center — same animation, same resting place, because the key is handed to that same menu item rather than centred here. AppKit resolves Control-C to the Enter character, so the default button used to answer it first and the system's Center never saw the key. Press **Return** and **⌃C** on the same step to confirm the split held: Return advances, Control-C does nothing. Check the window still cannot be resized by dragging an edge.
- Take **Redo Setup** with the main window and Settings both open. Both close and setup is the only window left; finishing it opens the main window again and the Dock still shows one Scriber, not two. Dropping to accessory in the gap between the two windows is what used to leave a second tile behind, and it only shows with **Show in Dock** off.
- Take **Set Up Later** from the first step. The main window opens and its chrome names exactly what is missing; Settings fixes all of it, and **Redo Setup** returns here.
- On the ElevenLabs data-use step, open **Show me**. The whole menu is visible rather than cut off at the bottom, its Done button reads as a normal control rather than something behind the dimming, and Escape and Done both close it.
- Grant the microphone and accept the relaunch macOS offers. Setup comes back on the microphone step rather than at the welcome page. Then revoke the key or the grant a step behind it and relaunch again: setup stops at the step that is unmet, never past it.
- Finish setup, then take **Redo Setup**. It opens on the welcome step, not on the step the last run ended on.
- Finish setup a second time from that redo and press **Done**. The main window's warning control loses **Setup is not finished** — a redo that cannot be finished leaves the app claiming setup is still owed.
- Switch Scriber off under **Background App Activity** in System Settings, reopening Scriber if it quits — it does when no window is left open — and walk setup to its last step. Ticking **Launch Scriber when I log in** clears the tick then and there, with the refusal and **Open Login Items…** under it, the same answer Settings gives; tick it again and the same answer comes back rather than the tick sticking. **Done** closes setup on the first press, the refusal having already been read.
- Reach that step on a first run without touching the box, which arrives ticked. The refusal appears on the first **Done** instead, since an untouched box has nothing to react to, and the second **Done** finishes setup. Switch the row back on afterward.

### Its dictation step

- Reach it straight after choosing the shortcut. It is where the two ways to press it are taught, and the first place either can be tried.

- Reach the dictation step and dictate into its box. **This spends API credit; ask first.** The words land in the box itself rather than the clipboard — no other app has ever been the target here, so this is the one place that says whether Scriber can paste into its own window.
- Close setup on the dictation step without dictating. Setup counts as finished, the shortcut works everywhere, and the login item matches what the final step's checkbox would have applied.

## When permissions or global-shortcut lifecycle change

- Revoke Microphone and Accessibility, separately and together. The toolbar's warning control appears, its popover lists every unresolved condition at once — including a missing key alongside missing permissions — and the pill and Settings route both work. Restore both grants before finishing; every warning should then leave. **macOS forces Quit & Reopen whenever Microphone access changes**, so no-relaunch recovery is observable only for Accessibility.
- A keyed Hold binding held down does not stall the machine either. The tap sits in front of every system event, and work done while its callback is on the stack delays every keystroke and click on the Mac.
- With Bluetooth headphones connected and playing, hold the shortcut and immediately type into a text field. Every character appears as it is typed, with no stall. Opening the microphone drags the headset into call mode, and this is the check that says whether Scriber is waiting for that on the thread every keystroke goes through.
- Revoking Accessibility while Scriber runs never stalls the machine. The shortcut monitor sits in front of every system event, so a monitor that will not stand down takes the pointer, clicks, and keyboard with it.
- Hold still starts a recording after the lid has been closed and reopened and after a long idle. macOS disables event taps across sleep, so this is where a shortcut monitor that fails to recover becomes visible.

- Turn **Mute other audio while recording** on with System Audio Recording not yet granted, and answer the macOS prompt that follows the **Turn On** button. It arrives immediately, not during the next dictation, and Scriber stays responsive while it is on screen. This needs Scriber's row removed from System Settings → Privacy & Security → Screen & System Audio Recording first: `tccutil reset ScreenCapture com.gafiegarcia.scriber` reports success and changes nothing there, and while the row exists no prompt is raised at all.

- Dictate with music playing, on the built-in speakers and again on Bluetooth headphones. The music returns cleanly both times, and the pause before it returns is short enough to go unnoticed. Then quit Scriber immediately after a dictation, and switch the setting off immediately after one: both bring the sound straight back rather than leaving the Mac silent.

## When audio capture or transcription outcomes change

- Watch Scriber in Activity Monitor through a dictation, and again with Settings' input test running. Both sit near the cost of the capture itself — a few percent — not tens of percent. Two things put it there before: a level published on `AppCoordinator`, which republishes the whole object and so re-renders every open window and the menu bar ten times a second, and an implicit animation interpolating every bar of the meter between ticks. Neither shows up as the meter in a profile; both read as SwiftUI layout.

- Set input volume to zero and dictate. Where the built-in microphone is the Mac's only input, the waveform stays healthy for five to seven seconds before flattening — macOS keeps sending signal at a level the slider reads as zero — so hold past that to reach **“No sound from the microphone”**. Connect any second input device, even one Scriber is not set to use, and the same test flattens from the first moment instead. Both are worth running: the second input is what makes this look like it behaves. Costs no credit; restore the input volume afterward.
- Submit audio with no recognisable words. **This spends API credit; ask first.** Scriber reports no words and leaves no history row behind.

## When installed-app lifecycle or menu-bar behavior changes

- With **Show in Dock** on, Scriber remains in the Dock and app switcher without an open window. Turning it off never closes a visible window. Restore the preferred setting afterward.
- The menu-bar icon remains steady through dictation and switches to the warning symbol when the real key is unusable. Exercise the warning only with an already unusable or disposable key; never disable the sole working key to manufacture it. Inspect the actual menu bar; do not diagnose this from `defaults`.
- Launch at login works in both directions across a macOS restart. Quit Scriber before restarting and clear **Reopen windows when logging back in** in the restart dialog, or the result means nothing: that feature relaunches whatever was running, so Scriber comes back whether or not the login item fired. Tell the two apart in the log — a real login launch reports `loginItem=true`, a restored one reports `loginItem=false`. Restore the preferred setting afterward.
- The Launch at login switch follows System Settings, not Scriber's last request. With Scriber's Settings open, remove Scriber from System Settings' Login Items: the switch turns off within a few seconds and **Start in the background** greys out with it. Then switch Scriber off under **Background App Activity**, the lower list on the same page and the only one with a per-item switch — removing the entry and switching it off are different states, and only this one produces the message. Scriber's switch turns off and stays quiet about it. Keep a window open throughout: macOS stops a background item the moment it is disallowed, and Scriber quits with it when nothing is on screen to hold it. Now turn its switch on: it refuses, and only then explains that macOS is holding it off and offers a button back to Login Items. Switch the row back on in System Settings and the message clears itself within a few seconds, with Scriber's window untouched. Restore the preferred setting afterward.
- With Launch at login and **Start in the background** both on, logging back in brings Scriber up with no window and no stolen focus, and a dictation shortcut works straight away. Quit Scriber and clear **Reopen windows when logging back in** first, as above — a restored Scriber opens its window and looks exactly like this check failing. Turn Start in the background off and log in again: the main window opens as usual. Opening Scriber yourself from Finder always shows the window, whichever way the setting is set — that is what separates a working launch-source check from a setting that suppresses everything. `log show --predicate 'subsystem == "com.gafiegarcia.scriber" AND category == "window-lifecycle"'` reports `loginItem=` and `startsInBackground=` for each launch if one of these surprises you.
- The **Window** menu keeps its full item set for as long as it stays open. Open it and wait 15 seconds, from the main window and from Settings. **Close ⌘W**, **Fill**, **Center**, **Move & Resize**, and **Full Screen Tile** come from AppKit rather than from Scriber's own commands, so anything that publishes a change while the menu is tracking makes SwiftUI reinstall the menu without them. Starting a dictation while the menu is open still prunes it; that case is marked `Known and unfixed:` in `Scriber/ScriberApp.swift` and is not a failure of this check.

## When the paste engine changes

Read [`PASTE_ENGINE.md`](PASTE_ENGINE.md) first; its table is the baseline.

- Delivery lands at the cursor in ChatGPT, Notion, Zen, Ghostty, Raycast, VS Code, and Zed, with no two-to-three-second delay at record start. **These dictations spend API credit; ask first.**
- A target with no focused text field falls back to copied rather than reporting false success — Zen on a page without a field is the case that caught this.
- Raycast running does not produce false recovery in Xcode, ChatGPT, or Notion.

## When audio muting changes

- With Music or Spotify playing, other audio goes silent only during capture and returns immediately on stop, cancel, or failure. It remains untouched when the preference is off. Denied System Audio Recording leaves dictation working and reports the muting failure only in Settings. Restore the preferred setting and permission afterward.
