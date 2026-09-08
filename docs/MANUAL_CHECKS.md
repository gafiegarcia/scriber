# Checks Only the User Can Run

This is a reusable catalog of checks that require the user's real environment, account, hardware, judgment, or physical participation. An agent selects and proposes the smallest relevant set — usually one to three checks — but never performs one itself or records completion in this file.

Agent-runnable parsing, tests, builds, isolated UI fixtures, and visual inspection belong in `AUTOMATED_CHECKS.md`, not here.

Before tagging, the user runs the baseline against the final installed candidate, then any conditional checks implicated by changes since the previous tag. Results belong in the session and annotated tag message.

Never ask the user to risk irreplaceable history, the only copy of an API key, or account quota merely to manufacture a test state. **Every check that spends API credit requires explicit approval first.**

A check says how to reach a state and what will trip you up. It does not say what must then be true — that is a requirement, it lives in one document, and the check ends with a pointer to it:

> Spec: Section name — "verbatim fragment of the rule"

Name the document when the rule is not in `PRODUCT_SPEC.md`. `./scripts/check-docs.sh` fails when a fragment stops appearing there, which is how a reworded requirement forces its checks to be re-read.

**Converting a check never edits a requirement.** Where a check and the spec disagree, say so and leave both alone — a question for the user, not something to reconcile while converting. Where a check asserts something the spec does not contain at all, that requirement is real and homeless: file it as a spec bullet in the same change rather than deleting the only copy of it.

## Baseline for a tag candidate

- From the installed app rather than a build, hold to dictate, speak, and release — then click into a different app before the transcript arrives. **Spends API credit; ask first.** Spec: Product goal — "focused when transcription completes"
- Turn **Show in Dock** off, close the last window, start a recording with the global shortcut, and cancel with Escape before transcription begins. Restore the setting afterwards. Spec: Product goal — "menu-bar and dictation services continue"; Identity and workspace boundary — "reached from the menu bar item"
- Quit Scriber and open it again, then restart macOS and open it once more. Only the installed Release app can answer this — a Debug build is re-identified on every build and prompts every time. Spec: Persistence and security — "survive a macOS restart, without a further login-Keychain prompt"

## When cancellation, retry, or recovery changes

Reach for these when the diff touches `AppCoordinator.swift`, `PillController.swift`, or `ScribeClient.swift`.

- Cancel mid-transcription so **Recover canceled dictation?** appears, then press **Recover**, watching the crossing frame by frame. Do it again but start a fresh dictation from that panel instead of recovering — that crossing always looked right and must go on doing so. **Spends API credit; ask first.** Spec: Delivery and floating pill — "A crossing between the message box and the capsule does resize the window, and is not animated"
- Dictate a few seconds, stop normally, and press Escape while the pill reads **Transcribing…**, then Escape again. **Spends API credit; ask first.** Watch the app you were dictating into, not the pill — the paste that must not happen is the whole point. Spec: Shortcuts and job lifecycle — "Canceling after the transcription request has gone out"
- Repeat that cancel, then click into a *different* app before pressing **Recover**. Spec: Shortcuts and job lifecycle — "Recover resolves its destination when it is pressed"
- Cancel a dictation of a few seconds, once with Escape and once with the pill's Cancel, then take a third press and release it in well under a quarter second. Spec: Shortcuts and job lifecycle — "at least one second long and contain detected speech"; Shortcuts and job lifecycle — "A press too brief to have been a dictation ends in silence"; Recording and transcription — "Tink once when recording is cancelled"
- Cancel mid-transcription and immediately start a second dictation without waiting. Spec: Shortcuts and job lifecycle — "**After a cancellation**, a press starts a new recording immediately"
- Cancel mid-transcription, let the pill time out without pressing anything, then open the main window. Spec: Shortcuts and job lifecycle — "History always holds the canceled dictation the pill offered"
- Retry a canceled row from History and press Escape while it runs. Spec: Shortcuts and job lifecycle — "Canceling a History retry stops in silence"

### With Wi-Fi off and no Ethernet

These four states are only reachable offline and went years unlooked-at, so look properly. None spends credit — nothing is sent.

- Dictate and stop. Then turn Wi-Fi back on with the pill still up. Spec: Shortcuts and job lifecycle — "its Retry stays disabled until this Mac has a route again"
- Dictate and stop, then leave it alone. Spec: Shortcuts and job lifecycle — "A transcription has 90 seconds in total"; Shortcuts and job lifecycle — "never appends the system's sentence to one that already says the same thing"
- Dictate, stop, and press Escape while it is retrying — then dismiss the offer with Escape, once by taking **See History**, and once by letting it time out. Spec: Shortcuts and job lifecycle — "no further attempt is made and no pill is drawn"
- Cancel during the countdown and immediately start another dictation, three or four times over. Then cancel one and press **Recover** instead. Spec: Shortcuts and job lifecycle — "An abandoned transcription touches nothing but its own history row"

## When the hold and tap split, or hands-free, changes

Reach for these when the diff touches `GlobalShortcutService.swift`, `RecordingStartGate.swift`, or `RecorderLifecycle.swift`.

- Watch a whole successful dictation through. Timing is what is being checked, not whether anything fades — AppKit fades this panel in and out by itself, so a short fade both ways is expected and is not Scriber's. What must never happen is *waiting*. Spec: Delivery and floating pill — "Scriber animates no pill on or off screen"
- Say nothing at all and release within about two seconds; then hold it wordless for more than three. Spec: Recording and transcription — "reported only when it ran at least three seconds"
- Hold a dictation for several seconds and then type; start another and type immediately. Spec: Shortcuts and job lifecycle — "any non-modifier key cancels and discards it"
- Tap the shortcut and speak immediately, without waiting for the pill to settle. Spec: Shortcuts and job lifecycle — "Recording begins on the press, before the mode is known"
- Hold the shortcut a beat past `DictationShortcutTiming.tapThreshold` and let go. This threshold is the one number no test can settle — it decides whether a deliberately short dictation reads as a tap, and only a hand knows where it belongs. Spec: Shortcuts and job lifecycle — "Released within the tap threshold"
- Holding the shortcut, move the pointer onto the pill and off again; then tap to lock hands-free and tap again to stop. With the default binding, bare `fn` must still open the emoji picker. **Wispr Flow must be quit first**, or it takes the key. Spec: Delivery and floating pill — "show Cancel on the pill's leading edge only while the pointer is over the pill"
- Tap the shortcut as fast as possible several times over, then hold it and dictate normally, and press it once more while a later pill still reads **Transcribing…**. The burst has to put a start, a stop and a cancel inside the time the capture stack needs to close a recording, so speed is the procedure. Two failures have reached the user this way — a recorder that refuses every later start, and a deadlock between the capture queue and the main thread. **If it freezes, run `sample Scriber 3` before quitting it**: the two stacks name the deadlock between them, and nothing recovered afterwards will. Spec: Shortcuts and job lifecycle — "a press is refused — those are the busy phases"

## When opening a window mid-dictation changes

Reach for these when the diff touches `ScriberApp.swift`, `MainWindow.swift`, or `Views.swift`.

- Start a hands-free dictation and open Settings by each route in turn, ending each run with Escape: **Settings** in the menu bar menu; **Settings…** in the Scriber menu; and Command-comma twice — once with the main window open and focused, once with Scriber focused and no window at all, which **Show in Dock** makes reachable. Spends no credit. Spec: Shortcuts and job lifecycle — "Opening a Scriber window changes nothing about a dictation"
- Open the main window mid-dictation from the menu bar's **Open Scriber**, keep talking, switch back to where the text is going, and stop. **Spends API credit.** This is the one that proves the transcript itself, which is why it is run apart from the Settings routes rather than folded into them. The toolbar's warning control is not a route here — it exists only while a recovery condition does, and each of those either stops the dictation starting or fails its transcription. Spec: Product goal — "focused when transcription completes"
- With a resting pill on screen — a copied result, **No words detected**, or a canceled dictation offering Recover — open a window by Command-comma and again from the menu bar, then click the pill's own action. Spec: Shortcuts and job lifecycle — "a route that is not the notice's own action must not throw away the recovery"
- While a dictation runs, try everything Settings should have greyed out: on General every preset, the recorded chord, **Record**, and **Redo Setup**; on Sound, **Check Input Level**. Then end the dictation. Spends no credit. Spec: Shortcuts and job lifecycle — "No control may change the dictation shortcut while a dictation is running"
- With no dictation running, press **Redo Setup…** on General, then start a dictation with its confirmation on screen. Spends no credit. Spec: Shortcuts and job lifecycle — "that confirmation closes when a dictation starts"

## When shortcut binding or matching changes

Reach for these when the diff touches `GlobalShortcutService.swift` or `ReservedShortcuts`. Restore the preferred shortcut after every one.

- Bind a keyed chord such as `⌘⇧D`, hold it well past the auto-repeat delay, speak, and release. Then hold it again and let go of `⇧` before `D`. `fn` cannot show either half — a modifier-only chord never auto-repeats, which is why the default binding looks fine whatever is broken. Spec: Shortcuts and job lifecycle — "A keyed chord ends its hold when any of its modifiers is released"
- Press the **left** ⌘ or ⌥ alone. Spec: Shortcuts and job lifecycle — "Refusing a left twin says the right one is free"
- Bind **Right ⌥** alone, press the left ⌥, then the right one, then hold both and let go of the right while the left stays down. macOS reports only that Option is down, so a release read from the flags would never come. Spec: Shortcuts and job lifecycle — "Neither the modifier flags nor the event's report of them carry a side"
- Bind **Right ⌘+Right ⌥** together, then press the two left keys, then one of each, then both right ones. Spec: Shortcuts and job lifecycle — "is a different shortcut from"
- Record a new shortcut and watch the recorder as the chord is held. Spec: Shortcuts and job lifecycle — "recognized keys are displayed live"
- Pick each preset in turn, and confirm the shortcut takes effect with no confirm step. Spec: Shortcuts and job lifecycle — "Presets and the recorded chord are one choice, not two"

## When the pill's appearance changes

Judged by eye, so these are the user's alone — the accessibility tree cannot answer any of them.

- Every pill, in light and dark, over both a light and a dark window behind it. Spec: Delivery and floating pill — "Tint, never fill"
- A green pill against an amber one **in light appearance**, which is where the tint has least to work with. Checking each tone on its own hides the failure that matters — they must be tellable apart from each other, not merely visible. Spec: Delivery and floating pill — "A success and a warning must be tellable apart at a glance"
- The pill's top and bottom edges over a light background and over a dark one, and through the resize into a copied result. Spec: Delivery and floating pill — "Light the pill's top and bottom edges"
- Click each pill's surface in turn, away from every control, and then the glass between two controls. Nothing happens, and the pointer stays an arrow throughout. Spec: Delivery and floating pill — "A pill acts only through its own visible controls"
- Bring the pointer to a held recording pill's edge slowly and leave it resting there, from the left and then from the right. Cancel arrives once and stays; if it loops in and out, the region deciding hover has started moving again. Spec: Delivery and floating pill — "The pointer region that decides hover is the capsule itself"
- Lock a recording hands-free with the pointer away from the pill, and watch the timer rather than the controls. It travels inward once, in one direction, and does not drift back — a swing out and a correction back is the fault this is looking for, and the pill's own width must not change at all. Spec: Delivery and floating pill — "Nothing the user can see may be positioned by that animation and by a frame AppKit is interpolating at the same time"
- Click a text field level with a recording pill and a centimetre to either side of it. The click reaches that field, not the pill's window. Spec: Delivery and floating pill — "Show a floating pill at the bottom center"

## When visual design changes

Judged by eye. Switch appearance only — a Scriber window cannot see the desktop, so changing wallpaper proves nothing about any of these except the pill.

- On a window whose size is fixed, check **Window ▸ Center** is enabled rather than greyed, then press ⌃🌐C with a confirmation on screen, where the default button is the one that confirms. Spec: Identity and workspace boundary — "a disabled menu item does not consume its key"
- The toolbar, the sticky day headers, the warning control, the list's row separators, and the copy toast, in both appearances. Spec: Identity and workspace boundary — "Every surface reads comfortably in both light and dark appearance"
- The pill over both a light and a dark desktop. Wallpaper is a real variable here and nowhere else. Spec: Identity and workspace boundary — "the one place the wallpaper behind it is a real variable"
- Scroll a Settings tab taller than the window — General is one — in both appearances, watching the scroll indicator and the cards' margins. Spec: Identity and workspace boundary — "A Settings tab scrolls under its toolbar"
- The end-of-tab buttons on General and ElevenLabs, side by side, and against System Settings where the same shape appears at the bottom of a pane. Reading each tab on its own hides this: the gap only looks wrong beside a correct one. Spec: Product goal — "The gap above such an action is what says it is the tab's"

## When real history or transcription recovery changes

- Create a disposable retryable dictation by speaking for more than one second and cancelling with Escape, then retry that generated entry. **Retry spends API credit; ask first.** Delete only this synthetic entry afterwards, having checked its content and timestamp tell it apart from real history. Spec: Shortcuts and job lifecycle — "History retry transcribes and copies the result without inserting it"
- On the first launch after an update that changes the retention sweep, count the history before and after. **Irreplaceable history is at stake, so read Settings → Dictation first** — whatever **Delete failed and cancelled dictations** says is what will have been applied, and **Never** must leave the count untouched. Spec: Persistence and security — "it may keep an entry past its period but never deletes one before it"

## When the data-use guidance changes

- Settings ▸ ElevenLabs: press **Privacy Policy**, and open the help button's popover. Spec: Permissions and app lifecycle — "Settings offers the same guidance on demand"
- Press **Configure Data Use…** twice — one window, not two. Open **Show me where to turn it off** from inside it, then **Close**. Check the Window menu and the Dock while it is up. Spec: Identity and workspace boundary — "None of Scriber's windows appear in the system Window menu"
- Switch **Show in menu bar** off on General, then press **Configure Data Use…** again. This is the trap: a button that reaches its window through the menu bar icon rather than through its own view stops working exactly here, and does it silently. Spec: Product goal — "windows, launch-at-login, and global shortcuts continue independently"

## When credentials, Keychain storage, or usage change

- **Only with a disposable second key whose full value is held outside Scriber.** Save it, quit and reopen Scriber, restart macOS, then use Settings → ElevenLabs → Remove API Key…. Restore the intended key afterwards, and never run this against the only recoverable one. Spec: Persistence and security — "survive a macOS restart, without a further login-Keychain prompt"
- **Only when an already exhausted account or a disposable zero-quota key is available** — never consume credits to reach exhaustion. Take the recovery action and see where it lands. Spec: Delivery and floating pill — "One destination keeps one name across every pill that reaches it"
- With User → Read disabled on an otherwise valid Speech-to-Text key, dictate, then restore User → Read and retry. **Spends API credit; ask first.** Spec: Recording and transcription — "A key with Speech-to-Text access remains verified and usable"

## When signing, the disk image, or distribution change

- Dictate with music playing. This is the entitlement check that fails silently rather than at build time: the hardened runtime withholds microphone and Core Audio access from a process whose entitlements do not cover it, and the mute tap is the likeliest path to lose. **Spends API credit; ask first.** Spec: Platform and release boundary — "carrying the audio-input entitlement and no provisioning profile"
- Turn **Mute other audio while dictating** on, watching whether the explanation appears before the toggle moves, that cancelling leaves it off, and where the caption's link lands. Then dictate with music playing. **Spends API credit; ask first.** Spec: Permissions and app lifecycle — "turning it on asks macOS for the grant immediately"
- With the release published, open Settings → General → Updates and choose **Check for Updates**. Reaches GitHub, spends no API credit. Spec: Platform and release boundary — "Check at most once a day, on launch and on demand"
- Take the update itself, then reopen Settings and look at the menu bar too. This is the only place the whole path — check, offer, install, relaunch — runs end to end; the mechanism alone is checked before shipping with `--ui-testing-seed-update-offer`. A version that goes on offering itself is what a regression looks like, because nothing clears a stored offer except a check that comes back empty and the next one is not due for a day. Spec: Platform and release boundary — "Discard a stored offer that no longer names something newer"

### On a Mac or an account that has never run Scriber

Gatekeeper is exercised by the quarantine flag and the notarization ticket, never by where the image came from — so any route that marks it as downloaded serves, and no published release is needed. AirDrop is the easy one. **Confirm the flag arrived before opening anything**: `xattr -p com.apple.quarantine <image>` must print a value, because a file that lost it says nothing about what a stranger sees. Copying into a second account on the same Mac loses the flag irrecoverably, so read that account for its fresh permission, Keychain and onboarding state, and take the Gatekeeper half from the machine that received the image.

- Install the candidate disk image from `.build/` in an account that has never run Scriber, and walk setup from scratch. **Saving a key and dictating spends API credit; ask first.** Spec: Permissions and app lifecycle — "Every launch presents onboarding until setup is complete"
- Open that same image on a Mac running the oldest supported macOS, which has never had Xcode installed. The only check that exercises the deployment floor. Spec: Platform and release boundary — "Supported target: Apple silicon and macOS 26 or later"
- After the first launch of a build signed with a **new certificate**, restart and check Microphone and Accessibility again. A changed signing identity is a different app to macOS, and a stale entry has to be removed and re-added rather than toggled. Spec: Persistence and security — "survive a macOS restart, without a further login-Keychain prompt"

## When setup changes

Add `--ui-testing --ui-testing-onboarding --ui-testing-onboarding-unlocked` to a Debug launch to reach the gated steps without granting anything to that build. The gates still render; only Continue stops obeying them, so anything below that tests a gate has to be run without it.

### Its shortcut step

- **On a keyboard with no `fn` key macOS can see** — most keyboards Apple did not make. Press the key as hard as you like, then record `⌃+⌥` instead. This is the case the step exists for, and the only one that cannot be staged on the user's own machine. Spec: Permissions and app lifecycle — "a shortcut that was actually pressed"
- Choose each option in turn and press the shortcut it names, then switch away from a confirmed one. Confirmation follows the choice rather than surviving it. Spec: Permissions and app lifecycle — "A step gates only on what it exists to establish"
- Press a sided shortcut's left twin. Setup's test and the global shortcut have to agree about which key counts, or setup passes a binding that then does nothing. Spec: Shortcuts and job lifecycle — "the global tap and setup's own test of it both"
- Record a custom shortcut, confirm it, finish, and check what reaches Settings. Spec: Shortcuts and job lifecycle — "The last recorded chord is kept when a preset is chosen"
- Press Tab and Return on the shortcut step. The step watches for keys the whole time it is open, and a watcher that swallows them takes the keyboard with it. Spec: Shortcuts and job lifecycle — "Every other key reaches the foreground app unchanged"
- Watch the step while nothing is pressed. The presets are always showing, so the card cannot resize under the page centred beneath the title. Spec: Permissions and app lifecycle — "Nothing may appear on a step that is not that decision"

### Its permissions step

- Say nothing at all, then speak. Setup must not be completable with the microphone never tested. Spec: Permissions and app lifecycle — "a microphone that was actually heard"
- Set the input volume to zero and speak, then use **Continue without testing** — which is on screen from the first second and does not have to be waited for. Spec: Permissions and app lifecycle — "nothing Scriber can read distinguishes a Mac with no microphone from one whose input is silent"
- Change the input device mid-step. It was the previous device that was proven, so the meter restarts and the confirmation resets. Spec: Permissions and app lifecycle — "A step gates only on what it exists to establish"
- Reach the step with both grants already given, and check the whole card fits without the page scrolling. Spec: Permissions and app lifecycle — "Each step reads live state"
- Watch the menu bar's orange recording indicator across the whole flow. It appears on this step and on no other — Scriber holds the input open only where it draws a meter from it, and Try it opens and closes it around the dictation itself. Spec: Recording and transcription — "A level meter runs only when asked"

### Its ElevenLabs key step

- Delete Scriber's key from Keychain Access, then open setup. The badge and the gate both speak for a Keychain item, and the preferences behind them do not change when that item is deleted, so setup has to look rather than remember. Spec: Permissions and app lifecycle — "a key that verified"
- Delete the key while the step already shows **Verified**, then step forward and back. Re-checking on every arrival is the only thing standing between a deleted key and a finished setup. Spec: Permissions and app lifecycle — "Each step reads live state"
- Revoke the key on ElevenLabs rather than deleting it locally, then return to the step. **Spends no transcription credit** — validation reads the account. Spec: Persistence and security — "Validate credentials without uploading audio or consuming transcription credit"
- Save a key, step forward, then come back; and watch the card as the first key saves. Spec: Permissions and app lifecycle — "Nothing may appear on a step that is not that decision"

### Its shape and lifecycle

- On a first run, look for a main window behind setup or showing past its edges, and watch what finishing opens. Redo Setup is the opposite case and correct — the main window is already open there, and setup sits in front of it. Spec: Permissions and app lifecycle — "Setup is the only window on a first run"
- Close setup part-way with ⌘W, before its dictation step, then use the menu bar's **Finish Setup…**, then quit and reopen. That menu item is the only route back when there is no main window to hold a warning. Spec: Permissions and app lifecycle — "Every launch presents onboarding until setup is complete"
- Press **Allow** for Microphone and again for Accessibility, watching where System Settings lands each time. Spec: Permissions and app lifecycle — "one click raises one thing"
- Redo Setup with everything already granted and a shortcut you recorded yourself, then finish it. Spec: Permissions and app lifecycle — "a Redo Setup shows what is already granted as done"
- Walk it on the shortest display available — the most scaled option under **Displays**, the setting someone picks for their eyesight. A display changed while setup is already open is not handled: close and reopen it, and it fits the new one. Spec: Permissions and app lifecycle — "gives up height — never width"
- Drag setup off centre and press **⌃🌐C**, then press **Return** and **⌃C** on the same step to confirm the split held. Then drag the window's bottom edge as far as it goes. Spec: Identity and workspace boundary — "a disabled menu item does not consume its key"; Permissions and app lifecycle — "height is draggable down to a documented minimum"
- Take **Redo Setup** with the main window and Settings both open, then finish it, with **Show in Dock** off. Dropping to accessory in the gap between the two windows is what used to leave a second Dock tile, and it shows only with that setting off. Spec: Product goal — "disabling it never closes a visible window"
- Take **Set Up Later** from the first step, fix everything from Settings, then **Redo Setup**. Spec: Permissions and app lifecycle — "Onboarding must be complete and the credential definitively usable"
- On the data-use step, open **Show me where to turn it off**, scroll it, close it with Escape and again with **Done**. Then reopen it on a window dragged to its shortest and resize the window while it is open. Its bars are hand-built rather than a real toolbar — the only control in Scriber that is — so look whenever the window's size can change. Spec: Permissions and app lifecycle — "Both surfaces show one shared copy of that wording"
- Grant the microphone and accept the relaunch macOS offers, then revoke the key or a grant a step behind and relaunch again. Spec: Permissions and app lifecycle — "returns to the step that is unmet, never past it"
- Finish setup, take **Redo Setup**, finish it a second time and press **Done**. A redo that cannot be finished leaves the app claiming setup is still owed. Spec: Permissions and app lifecycle — "opens on the welcome step, not on the step the last run ended at"
- Switch Scriber off under **Background App Activity** in System Settings — reopening Scriber if it quits, which it does when no window is left — and walk setup to its last step. Tick **Launch Scriber when I log in**, then tick it again. Then reach the same step on a first run without touching the box, which arrives ticked. Switch the row back on afterwards. Spec: Permissions and app lifecycle — "Scriber cannot turn it back on"

### Its dictation step

- Reach it straight after choosing the shortcut, which is where both ways to press it are taught. Spec: Permissions and app lifecycle — "Setup teaches hands-free dictation before holding"
- Dictate into its box. **Spends API credit; ask first.** No other app has ever been the target here, so this is the one place that says whether Scriber can paste into its own window. Spec: Permissions and app lifecycle — "Setup is complete on reaching its dictation step"
- Start a dictation on **Try it!** and leave the step without stopping it — once with **Back**, once with **Skip**, and once by closing the window with `⌘W`. Take all three: the two buttons share a route the close does not, so a fix reaching only them passes on the buttons alone. Spends no credit. Spec: Permissions and app lifecycle — "A dictation started on setup's dictation step ends when that step is left"
- Close setup on the dictation step without dictating. Spec: Permissions and app lifecycle — "closing the window there leaves setup finished rather than half-done"

## When permissions or global-shortcut lifecycle change

- With both grants in place, press every button on Settings' Permissions tab and see where each lands. No automated check reaches this — the buttons exist only once a grant is real, and a `--ui-testing` launch has none. Spec: Permissions and app lifecycle — "each names a different destination"
- Revoke Microphone and Accessibility, separately and together, then restore both. **macOS forces Quit & Reopen whenever Microphone access changes**, so recovery without a relaunch is observable only for Accessibility. Spec: Permissions and app lifecycle — "appear together in the main window's chrome, never auto-dismiss"
- Hold a keyed binding down and type; then, with Bluetooth headphones connected and playing, hold the shortcut and immediately type into a text field. Opening the microphone drags a headset into call mode, and this is the check that says whether Scriber waits for that on the thread every keystroke goes through. Spec: Shortcuts and job lifecycle — "Work done inside the tap delays the user's own typing everywhere"
- Revoke Accessibility while Scriber runs, and use the pointer and keyboard immediately afterwards. A monitor that will not stand down takes them with it. Spec: Permissions and app lifecycle — "stop unavailable shortcut monitoring"
- Hold to record after the lid has been closed and reopened, and again after a long idle. macOS disables event taps across sleep, so this is where a monitor that fails to recover becomes visible. Spec: Permissions and app lifecycle — "restart it automatically when the grant returns"

### Muting other audio

- **First remove Scriber's row from System Settings → Privacy & Security → Screen & System Audio Recording.** `tccutil reset ScreenCapture com.gafiegarcia.scriber` reports success and changes nothing there, and while the row exists no prompt is raised at all. Then turn **Mute other audio while dictating** on and answer the prompt that follows **Turn On**. Spec: Permissions and app lifecycle — "turning it on asks macOS for the grant immediately"
- Dictate with music playing, on the built-in speakers and again on Bluetooth headphones. Then quit Scriber immediately after a dictation, and switch the setting off immediately after one. **Spends API credit; ask first.** Spec: Permissions and app lifecycle — "Quitting Scriber and turning the setting off both restore immediately"
- Dictate with the preference off, and with System Audio Recording denied. Spec: Recording and transcription — "Failure to create the other-audio mute tap must never prevent dictation"

## When audio capture or transcription outcomes change

- Watch Scriber in Activity Monitor through a dictation, and again with Settings' input test running. Both must sit near the cost of the capture itself, a few percent, not tens of percent. Two things put it there before, and neither shows up as the meter in a profile — both read as SwiftUI layout: a level published on `AppCoordinator`, which republishes the whole object and re-renders every open window and the menu bar ten times a second, and an implicit animation interpolating every bar between ticks. Spec: Recording and transcription — "A level meter runs only when asked"
- Set the input volume to zero and dictate. Where the built-in microphone is the Mac's only input the waveform stays healthy for five to seven seconds before flattening — macOS keeps sending signal at a level the slider reads as zero — so hold past that. Then connect any second input device, even one Scriber is not set to use, and repeat: it flattens from the first moment. Run both, because the second input is what makes this look like it behaves. Costs no credit; restore the volume afterwards. Spec: Shortcuts and job lifecycle — "belongs to a dictation someone actually gave"
- Submit audio with no recognisable words. **Spends API credit; ask first.** Spec: Recording and transcription — "clean up their temporary record and audio"
- Dictate into a Bluetooth input, then switch the device off mid-sentence and keep speaking for a few seconds. The timer must stop rather than count on beside a flat waveform, and the amber **Microphone disconnected** panel must appear while the shortcut is still held. Press **Recover**: what you said before the device went is transcribed and pasted. Then repeat and let the panel time out instead — the dictation must be waiting in History with its audio. **Spends API credit; ask first.** Spec: Recording and transcription — "ends the dictation where the device went"
- Start the input test on a Bluetooth device, switch the device off, then switch it back on. The meter must stay stopped behind its **unavailable** message until **Check Input Level** is pressed again — a device returning is not a second request for the microphone. Costs no credit. Spec: Recording and transcription — "A level meter runs only when asked"
- Repeat that with a device holding no speech — switch it off within a second of pressing the shortcut, before saying anything. It reports **Microphone "…" disconnected** with no button, because there is nothing to offer. Costs no credit. Spec: Recording and transcription — "not made offerable by the reason it ended"

## When installed-app lifecycle or menu-bar behavior changes

Every check below reads the actual menu bar, so **quit every running Scriber first** — the installed app, and any test build left over from an earlier check. Two instances put two identical marks up there with nothing to tell them apart, so a check can be run against the wrong one and pass or fail for the wrong reason.

```bash
osascript -e 'quit app "Scriber"' 2>/dev/null
pkill -x Scriber 2>/dev/null
pgrep -x Scriber || echo "nothing running"
```

Never drag a test build's item out of the menu bar: the list macOS keeps is per bundle identifier and shared with the installed app.

- With **Show in Dock** on, close every window; then turn it off with a window open. Restore the preferred setting afterwards. Spec: Product goal — "Scriber remains in the Dock and app switcher without an open window"
- Watch the menu-bar icon through a dictation, and again with an unusable key. Exercise the warning only with an already unusable or disposable key — never disable the sole working one to manufacture it. Read the actual menu bar; `defaults` cannot diagnose this. Spec: Platform and release boundary — "never in the menu bar icon, which reports configuration problems alone"
- Open the **Window** menu from the main window and again from Settings, and leave it open 15 seconds. **Close ⌘W**, **Fill**, **Center**, **Move & Resize** and **Full Screen Tile** come from AppKit rather than from Scriber's commands, so anything publishing a change while the menu tracks makes SwiftUI reinstall it without them. Starting a dictation with the menu open still prunes it — that is `Known and unfixed:` in `ScriberApp.swift`, not a failure here. Spec: Identity and workspace boundary — "None of Scriber's windows appear in the system Window menu"

### Launch at login

**Quit Scriber before restarting, and clear "Reopen windows when logging back in" in the restart dialog**, or every result below means nothing — that feature relaunches whatever was running, so Scriber comes back whether or not the login item fired. The log tells them apart: `log show --predicate 'subsystem == "com.gafiegarcia.scriber" AND category == "window-lifecycle"'` reports `loginItem=` and `startsInBackground=` per launch. Restore the preferred setting after each.

- Switch it on, restart, and log back in; then switch it off and do the same. Spec: Permissions and app lifecycle — "Launch at login is optional"
- With **Start in the background** also on, log back in and press the shortcut straight away. Then turn Start in the background off and log in again, and separately open Scriber yourself from Finder — which must show the window whichever way the setting is set, and is what separates a working launch-source check from a setting that suppresses everything. Spec: Permissions and app lifecycle — "A launch macOS makes at login opens no window"
- With Scriber's Settings open, remove Scriber from System Settings' **Login Items**. Then switch it off under **Background App Activity** — the lower list on the same page, the only one with a per-item switch; removing the entry and switching it off are different states and only this one produces the message. Then turn Scriber's own switch on, and finally switch the System Settings row back on. **Keep a window open throughout**: macOS stops a background item the moment it is disallowed, and Scriber quits with it when nothing is on screen to hold it. Spec: Permissions and app lifecycle — "Scriber cannot turn it back on"

## When the paste engine changes

Read [`PASTE_ENGINE.md`](PASTE_ENGINE.md) first; its **Regression baseline** lists the destinations delivery must reach, and these say how to reach them and what trips a run up.

- Work through that roster. **These dictations spend API credit; ask first.** Spec: PASTE_ENGINE.md, Regression baseline — "The destinations delivery is expected to reach"
- Dictate with no text field focused in a native app — Calendar with nothing focused is the case. Listen for one alert sound, not two. Spec: Delivery and floating pill — "Report two outcomes, never three"
- Watch for a double paste, particularly in an app that was slow to respond. Spec: Delivery and floating pill — "Confirm delivery only from the destination requesting the promised transcript"
- Start a hands-free dictation, then keep physically holding the shortcut keys down while it finishes and pastes. Repeat with a chord using Option or Control, not only the default. What this protects: Scriber builds its Command-V from a private event source in `postPasteShortcut` (`PasteService.swift`), so only the flags it sets travel with the keystroke. Built from the combined session state, whatever is physically held merges in and Command-V arrives as Option-Command-V — a different command, or none. A failure looks like the dictation not landing, or landing wrongly formatted, rather than like a crash. Spec: Delivery and floating pill — "Ask a destination to paste with a targeted Command-V"
- Dictate into a password field — Scriber's own API key field is the easiest. Spec: Delivery and floating pill — "the notice must name that as the reason rather than reporting a generic failure"

### The clipboard

All three spend API credit; ask first.

- Copy something, dictate somewhere that accepts it, then paste by hand and check a clipboard manager for a new entry. Spec: Delivery and floating pill — "Leave the clipboard as it was found when a dictation lands"
- Copy a **file** in Finder, dictate successfully, then paste in Finder. Spec: Delivery and floating pill — "Mark the temporary promised-text pasteboard item as transient"
- Dictate with nothing focused so delivery fails, then paste by hand. Spec: Delivery and floating pill — "Leave the transcript on the clipboard as ordinary text when delivery fails"

### The delivery log

After any of the above, read the lines the delivery wrote:

```bash
log show --last 30m --predicate 'subsystem == "com.gafiegarcia.scriber" AND category == "paste-target"' --style compact
```

It returned nothing at all before the engine was rebuilt, so an empty result is itself the regression. On a delivery that worked `asked` is 1 or more; on one that failed, `asked=0`. A line reporting `outcome=inserted` with `asked=0` is the bug this engine exists to remove. Spec: Delivery and floating pill — "Merely dispatching a Paste command is never confirmation"
