# Checks a Machine Can Run

## Safety boundaries

- Never contact ElevenLabs, consume API credit, read the real Keychain, or mutate real SwiftData.
- Never use a plain full-screen `screencapture`; it can expose unrelated windows and files.
- Every `--ui-testing` flag is **Debug only**. `isUITesting` is compiled out of Release, so an installed app takes the arguments, ignores them silently, and runs exactly as itself — a check aimed at `/Applications` looks like the feature is broken when nothing was ever switched on. Launch these from `.build/xcode-debug/Build/Products/Debug/Scriber.app`.
- A `--ui-testing` launch uses throwaway defaults, an in-memory history store, disabled external services, and no real Keychain. It can prove presentation, interaction, and routing, but never real credential validity or storage, service access, permissions, dictation, insertion, global shortcuts, or menu-bar behavior.

## Routine pass

Run from any directory inside the repository. The repo-local module cache and `--disable-sandbox` make the package tests work in managed sandboxes as well as a normal shell.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
MODULE_CACHE="$REPO_ROOT/.build/module-cache"
mkdir -p "$MODULE_CACHE"

swiftc -frontend -parse \
  "$REPO_ROOT"/Scriber/*.swift \
  "$REPO_ROOT"/ScriberCore/*.swift \
  "$REPO_ROOT"/ScriberCoreTests/*.swift

# Again with DEBUG defined. Without it, `#if DEBUG` regions are lexed but never
# parsed, so the pass above says nothing about `AppLaunchConfiguration`'s flags
# or `UITestingHistoryFixture`.
swiftc -frontend -parse -D DEBUG \
  "$REPO_ROOT"/Scriber/*.swift \
  "$REPO_ROOT"/ScriberCore/*.swift

swiftc -module-cache-path "$MODULE_CACHE" -typecheck \
  "$REPO_ROOT"/ScriberCore/*.swift

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift test --disable-sandbox --package-path "$REPO_ROOT"

plutil -lint "$REPO_ROOT/Scriber/Info.plist"
```

Neither parse invocation typechecks, so a Debug `xcodebuild` is the only real gate on `#if DEBUG` code.

## Release bundle inspection

Build instructions are in the [build guide](BUILDING.md). After building Release, inspect the exact bundle that will be installed:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_PATH="$REPO_ROOT/.build/xcode-release/Build/Products/Release/Scriber.app"

codesign -d -r- "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH"
codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -E "^(Authority|TeamIdentifier|CodeDirectory)"

if [ -e "$APP_PATH/Contents/embedded.provisionprofile" ]; then
  echo "REFUSING: Release contains a provisioning profile" >&2
  exit 1
fi
```

Four things must hold, and each has caught a real mistake:

- The requirement anchors to Apple's Developer ID chain for team `24U8BM54A3`. Anything else is a different app to macOS, and its permission grants will not carry over.
- `CodeDirectory` flags include `runtime`. Without the hardened runtime, notarization refuses the build.
- The entitlements are exactly `com.apple.security.device.audio-input`. An entitlement Scriber does not use is a notarization rejection waiting to happen; a missing one takes the microphone away at runtime rather than at build time.
- No provisioning profile is embedded. Scriber uses no entitlement that requires one, so a profile appearing means something turned on automatic signing.

## The published cask

Run after publishing a release. Nothing else checks the tap's `Casks/scriber.rb`: it lives in another repository, is not compiled, is not tested, and does not run until someone types the install command — so a wrong `sha256`, a `version` that builds a URL to nothing, a mis-set `depends_on`, or an artifact name that does not match what is inside the disk image all fail silently until a stranger meets them.

`--appdir` is what makes it runnable here. Installing the cask the ordinary way would put the release over the development build in `/Applications` and hand Homebrew that app to manage again; sent to a throwaway directory, the whole real path still runs — fetch, checksum, architecture and OS gates, mount, artifact placement — against the copy nobody is using.

```bash
APPDIR="$(mktemp -d)"
brew install --cask --appdir="$APPDIR" gafiegarcia/scriber/scriber
APP="$APPDIR/Scriber.app"

/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv --type open --context context:primary-signature "$APP"

brew uninstall --cask scriber
brew list --cask | grep scriber || echo "no longer tracked"
```

The version and build must be the release just published, the signature must verify, the ticket must validate, and `spctl` must report `source=Notarized Developer ID`.

**The uninstall quits the running Scriber**, wherever it was installed from: the cask carries `uninstall quit: "com.gafiegarcia.scriber"`, and that acts on the bundle identifier rather than on the copy being removed. Expect it, and reopen afterwards.

On a beta macOS, Homebrew prints `Warning: You are using macOS 27. We do not provide support for this pre-release version.` That is Homebrew talking about the OS, not about this cask.

The app itself needs no separate proof here. The cask fetches the same release asset already tested by hand and verifies it against the checksum computed when it was published, so what lands is byte-for-byte what was installed and used. What this check covers is the recipe.

## Launch smoke check

Run after any change to startup, the pill, or an `NSViewRepresentable`.

Run it exactly as written. `APP_PATH` must be absolute and the `before_pid` guard must stay, or a failed launch makes the final `kill` target the installed Scriber.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
xcodebuild -project "$REPO_ROOT/Scriber.xcodeproj" \
  -scheme Scriber -configuration Debug \
  -derivedDataPath "$REPO_ROOT/.build/xcode-debug" build
```

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
before_pid="$(pgrep -n -x Scriber || true)"
APP_PATH="$REPO_ROOT/.build/xcode-debug/Build/Products/Debug/Scriber.app"

if [ ! -d "$APP_PATH" ]; then
  echo "REFUSING: build the Debug app first" >&2
  exit 1
fi

open -g -j -n -a "$APP_PATH" --args \
  --ui-testing \
  --ui-testing-no-activate \
  --ui-testing-missing-permissions
sleep 6
pid="$(pgrep -n -x Scriber || true)"

if [ -z "$pid" ] || [ "$pid" = "$before_pid" ]; then
  echo "REFUSING: the test build never launched" >&2
  exit 1
fi

ps -p "$pid" -o pid,%cpu,command
kill "$pid"
```

This launch suppresses activation, Dock presence, and the menu-bar item, but still creates and renders the window. A process that stays at high CPU or never idles is an app failure worth sampling before blaming the harness.

It creates and renders a window once. It cannot put a closed one back on screen: after a window closes under this flag, `openWindow(id:)` and the front-ordering path both leave `isVisible == false`, and the `window-lifecycle` log still reports `showWindow: ordering front`, so the log agrees with a reopening that did not happen. Nothing that depends on a window being presented a second time can be measured here — `onAppear`, `didBecomeKey`, and any routing that selects a Settings tab on the way in all go quiet, and read as broken. Take reopening behaviour to an activating launch or to Gaf, never to this flag.

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.gafiegarcia.scriber"' --style compact
```

Log at `.notice`. `log show` omits `.info` and `.debug` unless asked for them by flag, so a line written at either is invisible to the command above and reads as a feature that never ran.

The subsystem holds four categories: `window-lifecycle`, `paste-target`, `permissions`, and `dictation`. Narrow to one by adding `AND category == "permissions"` to the predicate.

`dictation` carries a line per transcription attempt and per outcome, each stamped with a run number and elapsed milliseconds, plus every pill resize with its geometry and, on every dismissal, a probe of the main thread — `probeMs` is what a sleep asked for and `tookMs` what it got, so a gap between them is drawing time the thread spent elsewhere. Read it before theorising about timing or about which pill drew what: reading the source predicted the wrong cause three times where these lines answered it directly. It records run numbers, attempt numbers, outcome labels and sizes, never transcript text.

`permissions` writes a line only when a reading actually changes — the permission or the shortcut monitor, its new value, and which refresh path saw it. Silence means nothing changed, not that nothing was observed, and a launch is silent because the published values start from the same readings the first refresh takes. A `--ui-testing` launch cannot produce a transition at all: it grants no permission and its missing-permission flag injects a fixed state. Read this category on the installed app.

## A launch macOS made at login

`--simulate-login-launch` makes the app treat its launch as one macOS made at login, which is otherwise reachable only by restarting the Mac. Add it to the smoke check's arguments and the app must come up with no window ordered front and `launch: loginItem=true startsInBackground=true` in the log. Without the flag the same launch must show the window, which is the pair worth running together — one of them passing on its own proves nothing.

The flag skips the preferences the real path consults, so it holds whatever Start in the background is set to at the time. It is Debug-only and independent of `--ui-testing`, so the app can otherwise behave normally under it.

Every launch also writes `launchEvent:` twice and one `launchContext:` line, recording what macOS said about who started the app. That is what tells a launch marker arriving late from one that never arrives, and it is the only evidence available after a real login, where nothing can be attached to watch.

## Driving the app without computer-use

Most of what an inspection needs is readable, and pressable, from the accessibility tree. Reach for this before asking for computer-use or for Gaf: a build succeeding says nothing about what the app ended up showing, and SwiftUI contributes menu items, sizes, and defaults that no Scriber file names.

What this reaches: menu bar contents and menu items, window titles, sizes and positions, resize limits, tab selection, buttons and links by accessibility identifier, sheets and their contents, scroll areas and the geometry of anything inside them. What it does not: colour, translucency, glass, spacing judged by eye, and anything about appearance — those still need a computer-use tool or Gaf.

Needs Accessibility permission for whatever runs `osascript`, usually the terminal.

### Address the process by pid, not by name

`process "Scriber"` is ambiguous the moment a second Scriber exists, and the installed app is usually running. Capture the pid at launch with the `before_pid` guard and address that instead, which lets the build under test be inspected without quitting Gaf's copy:

```bash
before_pid="$(pgrep -n -x Scriber || true)"
open -n -a "$PWD/.build/xcode-debug/Build/Products/Debug/Scriber.app" --args --ui-testing
sleep 6
pid="$(pgrep -n -x Scriber || true)"
[ -n "$pid" ] && [ "$pid" != "$before_pid" ] || { echo "REFUSING: never launched" >&2; exit 1; }
```

```bash
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to get name of every menu item of (menu 1 of menu bar item \"Window\" of menu bar 1)"
```

Swap `"Window"` for any other menu title; separators report `missing value`. A named process that is not running reports `-1728`.

### Reading and pressing

Reference elements inline. Binding one to a variable across statements fails intermittently with `-1728` even while the window is open, so `set g to UI element 1 of window 1` and then using `g` is unreliable where the same expression written out works:

```bash
osascript <<OSA
tell application "System Events"
  tell (first process whose unix id is $pid)
    repeat with e in (UI elements of (item 1 of (UI elements of window 1)))
      set ep to position of e
      set es to size of e
      set idv to ""
      try
        set idv to (value of attribute "AXIdentifier" of e) as string
      end try
      log (role of e) & " y=" & (item 2 of ep) & " h=" & (item 2 of es) & " id='" & idv & "'"
    end repeat
  end tell
end tell
OSA
```

Assign `position` and `size` to variables before reading their items; concatenating them inline raises `-1700`. Press a control by its accessibility identifier rather than its index, which changes as a view does:

```bash
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to perform action \"AXPress\" of (item 4 of (UI elements of (item 1 of (UI elements of (item 1 of (UI elements of (toolbar 1 of window \"Settings\")))))))"
```

`AXPress` sends the action rather than moving the pointer, so it does not disturb whatever Gaf is doing. `set size of window 1 to {w, h}` then reading the size back is how a window's own limits are measured — what it settles on is what the app allowed, not what was asked for.

Anything a Debug build should expose to this needs an `accessibilityIdentifier`. A glyph-only button reports its SF Symbol name instead, which reads as an identifier and is not one.

## Inspecting a running Debug build

### Visual and interaction inspection

Try **Driving the app without computer-use** first. Much of what follows was written before the accessibility tree was used this way, and asks for a computer-use tool to establish something readable — a window's size, which tab is selected, what a sheet contains. Reach for computer-use for what is genuinely visual: colour, translucency, glass, spacing judged by eye.

Use a computer-use tool with the capture restricted to **Scriber**, so no other application appears.

If `CLAUDE_CODE_ENTRYPOINT=cli`, stop and ask Gaf to run these from the desktop app: `request_access` cannot see Scriber from the CLI, under any identifier.

It moves the real pointer and can press keys, so do not start one while the user is typing. Check whether the window on screen belongs to the installed app or a test build before drawing any conclusion from it.

### Onboarding

`--ui-testing-onboarding` opens the setup window, which `--ui-testing` otherwise skips by marking setup complete. Launch it with activation and the `before_pid` guard, as with seeded history below.

Add `--ui-testing-onboarding-unlocked` to reach the steps that gate on a real grant, a real microphone signal, or a real keypress. Without it those steps can only be passed by granting permissions to the Debug build, which writes that build's identity into the Mac's privacy lists. The gates still render — only Continue stops obeying them — so any check *of* a gate has to be run without the flag.

Confirm the window is centred and fully visible above the Dock, then relaunch and confirm it again — a restored frame behaves differently from a fresh one, and `fitOnboardingWindow` in `Scriber/ScriberApp.swift` is what overrides AppKit here.

Walk all seven steps. Each one fills the window without scrolling and centres in it, the footer's page dots track the step, and no step's controls move as the step changes.

Also launch ordinary `--ui-testing`, open Settings, and choose **Redo Setup…** on the General tab while the main window is already open. The setup window comes to the front, remains centred above the Dock, and shows the throwaway setup state; never reset Gaf's real `onboardingComplete` preference for this inspection.

### Seeded history

`--ui-testing-seed-history` fills the in-memory store with 23 deterministic records over four day groups, 22 of which render, so the Dictation list can be inspected without touching real entries or spending credit. `Scriber/UITestingHistoryFixture.swift` documents the fixture and its invariants.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
before_pid="$(pgrep -n -x Scriber || true)"
APP_PATH="$REPO_ROOT/.build/xcode-debug/Build/Products/Debug/Scriber.app"

open -n -a "$APP_PATH" --args --ui-testing --ui-testing-seed-history
sleep 6
pid="$(pgrep -n -x Scriber || true)"
[ -n "$pid" ] && [ "$pid" != "$before_pid" ] || { echo "REFUSING: never launched" >&2; exit 1; }
# … inspect, then …
kill "$pid"
```

While inspecting: the toolbar must read **22 dictations** — 23 means the in-flight filter regressed. Copy writes to the real `NSPasteboard.general`, so leave it untouched unless Gaf has said the current clipboard is disposable; only then confirm a known fixture transcript by pasting elsewhere. Every `--ui-testing` launch also raises the credential condition in the toolbar's warning control, because the throwaway defaults suite starts with no key.

### Scroll-load history

`--ui-testing-seed-history-large` fills the in-memory store with 406 synthetic records over 29 days, for inspecting the history list under a load the curated fixture above cannot produce — scrolling smoothness and the day strip's handover behavior across many more crossings than four days gives you. It is a separate flag from `--ui-testing-seed-history`; pass only one. `Scriber/UITestingLargeHistoryFixture.swift` documents the fixture. It is not the fixture the "22 dictations" check above depends on.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
before_pid="$(pgrep -n -x Scriber || true)"
APP_PATH="$REPO_ROOT/.build/xcode-debug/Build/Products/Debug/Scriber.app"

open -n -a "$APP_PATH" --args --ui-testing --ui-testing-seed-history-large
sleep 6
pid="$(pgrep -n -x Scriber || true)"
[ -n "$pid" ] && [ "$pid" != "$before_pid" ] || { echo "REFUSING: never launched" >&2; exit 1; }
# … scroll through the full history, then …
kill "$pid"
```

Use this same isolated launch for the window, toolbar, Settings, and history interaction checks:

- `⌘F` focuses Dictation search. In Settings, the command is disabled and leaves focus unchanged.
- Launch, the Dock icon, and reopening after `⌘W` all present the main window with search focused. Returning from another app, `⌘H`, or minimising preserves an existing transcript selection and search/scroll position.
- The main window has no displayed title. Workspace, total rendered count, and warning control stay grouped without reflow; search does not change the total.
- The titlebar's day strip names the day at the top of the list, hands over as the next day's card reaches it, and collapses when a search matches nothing. Its label stays aligned to the card's leading edge at both the minimum window size and full width, the separator appears only over scrolled content, and the cards and toolbar survive minimum window size.
- Single-entry Delete and Clear Dictation History both ask first. Clear Dictation History is on Settings' Dictation tab. Exercise Cancel and confirmation against the in-memory fixture, verify the rendered count, and never repeat this against the installed app's real history.
- Saving a dummy key and then choosing **Remove API Key…** on the ElevenLabs tab exercises only the confirmation, routing, and visible missing-key state. It is not evidence about the real Keychain.
- Every route that opens Settings to fix something selects the tab that owns the problem, and opening Settings without naming one leaves the selected tab alone: press `⌘,` twice and the second opening stays where the first was left. Scroll that tab to the bottom, close the window, and reopen it: the same tab comes back, at its top.
- Record `⌘Q` on the General tab. It is refused with a reason, the recorder closes, the stored binding is unchanged, and typing works everywhere in Scriber again. `⌘⇧D` is accepted.
- `Escape` closes Settings. While a shortcut recorder is capturing it ends the capture and leaves the window open; with a confirmation on screen it dismisses only the confirmation.
- Type a keyterm and press Return. It is added, the field clears, and the Add button stays disabled for whitespace alone.
- Every tab is reachable and usable, and the window cannot be resized on either axis. A pane taller than the window scrolls, which is expected; what is not is a control that cannot be reached at all.
- Start recording a shortcut binding on the General tab, then switch tabs. The capture ends: typing works everywhere in Scriber again, and the recorder shows its stored binding rather than a live one. A stranded recorder swallows every keystroke and suspends global shortcut matching until the window closes, and neither symptom names its own cause.

### The menu bar item

`--ui-testing-menu-bar` shows the menu bar item, which a `--ui-testing` launch otherwise never does. Without it the item is not inserted at all, so nothing in that menu can be read — a check that reads the menu has no way to run against a Debug build, and reaching it through the installed app means disturbing real state.

**Quit every running Scriber first** — the installed app, and any test build left over from an earlier check. Their marks are identical and nothing in the menu distinguishes them, so with more than one running there is no way to tell which you are clicking.

```bash
osascript -e 'quit app "Scriber"' 2>/dev/null
pkill -x Scriber 2>/dev/null
pgrep -x Scriber || echo "nothing running"
```

Never drag a test build's item out of the menu bar either: the list macOS keeps is per bundle identifier and shared with the installed app, and removal writes back to the preference.

Do not combine it with `--ui-testing-no-activate`, which is for launches nobody is watching.

This shows the menu and what is in it. It proves nothing about menu-bar *behaviour* that depends on real state — the warning symbol tracking a real key, or the recording indicator — which stays on the installed app.

### An update being available

`--ui-testing-pretend-version <version>` runs the app as that version, so the check compares it against the real latest release on GitHub. It is the only way to reach the update-available state: the state depends on a release newer than the running build, and no build can produce one for itself. Throwaway defaults hold the result, so an offer raised here never reaches the installed app — which matters, because a bogus `availableUpdate` in the real suite would be shown by it.

The launch performs the check itself, so the offer is on screen when the window opens rather than waiting for a button. It reaches GitHub and spends no API credit.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
before_pid="$(pgrep -n -x Scriber || true)"
APP_PATH="$REPO_ROOT/.build/xcode-debug/Build/Products/Debug/Scriber.app"

open -n -a "$APP_PATH" --args --ui-testing --ui-testing-pretend-version 0.8.0
sleep 6
pid="$(pgrep -n -x Scriber || true)"
[ -n "$pid" ] && [ "$pid" != "$before_pid" ] || { echo "REFUSING: never launched" >&2; exit 1; }
# … inspect, then …
kill "$pid"
```

Both directions are worth running, and the second is the one no test can show in the app itself:

Both are written against whatever release is currently newest, called `LATEST` here — the check compares against GitHub, so it stops naming a fixed version the moment one ships.

- Below `LATEST` — `0.8.0` serves until a release passes it — offers it. Settings' Updates section reads **Scriber vLATEST is available.** with **Get vLATEST** beside it, the menu bar menu carries **Update to vLATEST**, and both open the release page. Every version on screen carries the `v` that tags carry. **Check for Updates** ignores the once-a-day interval, so pressing it repeats the check rather than doing nothing.
- Above `LATEST` — raise the minor, so `0.10.0` against a `0.9.x` release — offers nothing, and the status reads **You're on the latest version.** followed by when the check last ran. Pick the pretended version so it sorts *below* `LATEST` as text while being above it numerically, which is what `0.10.0` against `0.9.x` does: that is the ordering the app depends on, and a string comparison fails it by going on offering an update to a version older than itself.

The version in the **Scriber v0.8.0 (build)** line is the pretended one, which is what says a run is simulated. The build number beside it is the real one.

#### The Homebrew route

Scriber offers a Homebrew install the `brew upgrade` command instead of the release page, and recognises one by resolving the Caskroom's symlink against its own bundle. Reaching that state on a Mac whose Scriber is not Homebrew-managed means building the link by hand, pointed at **the Debug build**, which is what will be running:

```bash
DEBUG_APP="$(git rev-parse --show-toplevel)/.build/xcode-debug/Build/Products/Debug/Scriber.app"
mkdir -p /opt/homebrew/Caskroom/scriber/0.0.0-fake
ln -sfn "$DEBUG_APP" /opt/homebrew/Caskroom/scriber/0.0.0-fake/Scriber.app
```

The version folder is named arbitrarily above: detection searches every version folder a cask holds and matches on the resolved path, never on the folder's name, so a name that could not be a real release makes it obvious the layout is hand-built.

Launch with `--ui-testing-pretend-version 0.8.0`. The button reads **Update…**, opens a dialog carrying `brew upgrade --cask scriber`, and **Copy Command** writes it to the real pasteboard. In the menu bar, the item reads **Update to vLATEST…** and opens Settings rather than a browser. Remove the link, relaunch, and the button must go back to **Get vLATEST** opening the release page, with the menu bar's item losing its ellipsis and opening it too — without that half, a detector stuck at yes would pass.

**Clean up, and treat it as required rather than tidy:**

```bash
trash /opt/homebrew/Caskroom/scriber
brew list --cask | grep scriber || echo "no longer listed"
```

That directory alone is enough for `brew list --cask` to report scriber as installed, with none of the metadata a real install leaves. It is harmless while the cask's version matches what the folder claims and becomes an upgrade Homebrew will attempt once the published cask moves ahead of it — which is a bad surprise on a Mac that runs `brew upgrade` on a schedule.

#### An offer that has already been taken

`--ui-testing-seed-update-offer <version>` puts an offer in preferences before the coordinator is built, which is the only thing that reads a stored one back. That state cannot occur here otherwise — the throwaway suite is wiped at every launch, and an offer only lands after a check that runs later — so without the flag the discard has nothing to act on and goes unexercised.

Pass no pretend version with it. The build then runs as itself, and no check runs to overwrite what was seeded, which is what isolates the discard from the check. Read the result from the throwaway suite rather than the screen:

```bash
defaults read com.gafiegarcia.scriber.ui-testing availableUpdate
```

Three runs, and the third is the one that stops a passing result meaning nothing:

- Seeded at the running version — discarded. This is the real case: the offer was taken, and the version it named is the one now running.
- Seeded below the running version — discarded.
- Seeded above the running version — **kept**. An offer that still stands must survive, or a discard that deletes everything would pass the first two.


### Simulated recovery

Use the Debug app and the same `before_pid`/absolute-`APP_PATH`/guarded-`kill` pattern above. Launch with `--ui-testing --ui-testing-missing-permissions` to inspect missing-permission recovery without changing real macOS grants.

The toolbar warning lists both permissions, the pill's Review button activates Scriber and opens Settings on the Permissions tab, and focusing and leaving Scriber does not present a second unchanged pill or restart its dismissal timer.

Launch separately with `--ui-testing --ui-testing-invalid-key-pill` when the credential-recovery pill changes. **Update Key** activates Scriber, opens Settings on the ElevenLabs tab, and focuses the key field. These fixtures prove presentation and routing only, never credential validity or service access.
