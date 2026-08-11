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

- Typing during the first second of a held recording and pressing Escape during either recording mode each cancel with the cancellation sound.
- Holding `Fn` shows no Cancel until the pointer moves over the pill, which widens it in; moving off narrows it back out. Escape still cancels while held with the pointer elsewhere. `Fn-Space` locks hands-free: Cancel is shown unconditionally from then on (no hover needed), and the pill widens further, animating only Confirm in on its trailing edge. Hold is ignored while locked, and Toggle stops it. Bare `Fn` still opens the emoji picker and types a normal Space. **Wispr Flow must be quit first.**
- Bind Hold to a keyed chord such as `⌘⇧D`, hold it well past the auto-repeat delay, speak, and release. One recording starts, nothing restarts it, no repeated characters reach the app in front, and letting go stops it. `Fn` cannot show this: a modifier-only chord never auto-repeats, which is why the default configuration looks fine either way. Restore the preferred shortcut afterward.
- Bind Toggle to a keyed chord and hold it down to stop a hands-free recording. It stops once, does not repeat a notice, and does not start a new recording when transcription finishes.
- A refused chord such as `⌘Q` closes the recorder with its reason, leaves the stored binding alone, and leaves the keyboard usable.
- Record a new shortcut: the recorder shows the chord live and closes at the first key release, and a chord containing `fn` displays it first. Disabling Hold and Toggle independently prevents only the disabled one. Restore the preferred shortcuts afterward.
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

## When permissions or global-shortcut lifecycle change

- Revoke Microphone and Accessibility, separately and together. The toolbar's warning control appears, its popover lists every unresolved condition at once — including a missing key alongside missing permissions — and the pill and Settings route both work. Restore both grants before finishing; every warning should then leave. **macOS forces Quit & Reopen whenever Microphone access changes**, so no-relaunch recovery is observable only for Accessibility.
- A keyed Hold binding held down does not stall the machine either. The tap sits in front of every system event, and work done while its callback is on the stack delays every keystroke and click on the Mac.
- Revoking Accessibility while Scriber runs never stalls the machine. The shortcut monitor sits in front of every system event, so a monitor that will not stand down takes the pointer, clicks, and keyboard with it.
- Hold still starts a recording after the lid has been closed and reopened and after a long idle. macOS disables event taps across sleep, so this is where a shortcut monitor that fails to recover becomes visible.

## When audio capture or transcription outcomes change

- Set input volume to zero and dictate. The “No sound from the microphone” pill appears with the failure sound. This costs no credit and remains distinct from the no-words pill. Restore the input volume afterward.
- Submit audio with no recognisable words. **This spends API credit; ask first.** Scriber reports no words and leaves no history row behind.

## When installed-app lifecycle or menu-bar behavior changes

- With **Show in Dock** on, Scriber remains in the Dock and app switcher without an open window. Turning it off never closes a visible window. Restore the preferred setting afterward.
- The menu-bar icon remains steady through dictation and switches to the warning symbol when the real key is unusable. Exercise the warning only with an already unusable or disposable key; never disable the sole working key to manufacture it. Inspect the actual menu bar; do not diagnose this from `defaults`.
- Launch at login works in both directions across a macOS restart. Restore the preferred setting afterward.
- The **Window** menu keeps its full item set for as long as it stays open. Open it and wait 15 seconds, from the main window and from Settings. **Close ⌘W**, **Fill**, **Center**, **Move & Resize**, and **Full Screen Tile** come from AppKit rather than from Scriber's own commands, so anything that publishes a change while the menu is tracking makes SwiftUI reinstall the menu without them. Repeat once with a dictation running, which moves the app's phase.

## When the paste engine changes

Read [`PASTE_ENGINE.md`](PASTE_ENGINE.md) first; its table is the baseline.

- Delivery lands at the cursor in ChatGPT, Notion, Zen, Ghostty, Raycast, VS Code, and Zed, with no two-to-three-second delay at record start. **These dictations spend API credit; ask first.**
- A target with no focused text field falls back to copied rather than reporting false success — Zen on a page without a field is the case that caught this.
- Raycast running does not produce false recovery in Xcode, ChatGPT, or Notion.

## When audio muting changes

- With Music or Spotify playing, other audio goes silent only during capture and returns immediately on stop, cancel, or failure. It remains untouched when the preference is off. Denied System Audio Recording leaves dictation working and reports the muting failure only in Settings. Restore the preferred setting and permission afterward.
