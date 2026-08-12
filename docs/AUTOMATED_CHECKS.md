# Checks a Machine Can Run

## Safety boundaries

- Never contact ElevenLabs, consume API credit, read the real Keychain, or mutate real SwiftData.
- Never use a plain full-screen `screencapture`; it can expose unrelated windows and files.
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
  "$REPO_ROOT/ScriberCore/CoreModels.swift" \
  "$REPO_ROOT/ScriberCore/ScribeClient.swift" \
  "$REPO_ROOT/ScriberCore/CredentialStore.swift" \
  "$REPO_ROOT/ScriberCore/RecoveryConditions.swift" \
  "$REPO_ROOT/ScriberCore/Toasts.swift"

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

if [ -e "$APP_PATH/Contents/embedded.provisionprofile" ]; then
  echo "REFUSING: Release contains a provisioning profile" >&2
  exit 1
fi
```

It must reproduce the designated requirement recorded in the README, carry no provisioning profile, and hold no restricted Keychain entitlement.

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

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.gafiegarcia.scriber"' --style compact
```

The subsystem holds three categories: `window-lifecycle`, `paste-target`, and `permissions`. Narrow to one by adding `AND category == "permissions"` to the predicate.

`permissions` writes a line only when a reading actually changes — the permission or the shortcut monitor, its new value, and which refresh path saw it. Silence means nothing changed, not that nothing was observed, and a launch is silent because the published values start from the same readings the first refresh takes. A `--ui-testing` launch cannot produce a transition at all: it grants no permission and its missing-permission flag injects a fixed state. Read this category on the installed app.

## A launch macOS made at login

`--simulate-login-launch` makes the app treat its launch as one macOS made at login, which is otherwise reachable only by restarting the Mac. Add it to the smoke check's arguments and the app must come up with no window ordered front and `launch: loginItem=true startsInBackground=true` in the log. Without the flag the same launch must show the window, which is the pair worth running together — one of them passing on its own proves nothing.

The flag skips the preferences the real path consults, so it holds whatever Start in the background is set to at the time. It is Debug-only and independent of `--ui-testing`, so the app can otherwise behave normally under it.

Every launch also writes `launchEvent:` twice and one `launchContext:` line, recording what macOS said about who started the app. That is what tells a launch marker arriving late from one that never arrives, and it is the only evidence available after a real login, where nothing can be attached to watch.

## Inspecting a running Debug build

### Visual and interaction inspection

Use a computer-use tool with the capture restricted to **Scriber**, so no other application appears.

Run these from a Claude desktop app session. From Claude Code CLI, `request_access` answers `not_installed` for **Scriber**, for the bundle identifier, for a process id, and for the full bundle path alike — with the app running or quit, and with a window open or not — so nothing below this heading can be driven from there. The desktop app's list of available applications is built from what is currently running; the CLI's does not appear to be, and the mechanism behind that is unknown, so treat the difference as observed rather than explained. Do not spend attempts working around it: use a desktop session, or hand the check to Gaf.

It moves the real pointer and can press keys, so do not start one while the user is typing. Check whether the window on screen belongs to the installed app or a test build before drawing any conclusion from it.

### Onboarding

`--ui-testing-onboarding` opens the setup window, which `--ui-testing` otherwise skips by marking setup complete. Launch it with activation and the `before_pid` guard, as with seeded history below.

Confirm the window is centred and fully visible above the Dock, then relaunch and confirm it again — a restored frame behaves differently from a fresh one, and `fitOnboardingWindow` in `Scriber/ScriberApp.swift` is what overrides AppKit here.

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
- Every route that opens Settings to fix something selects the tab that owns the problem, and opening Settings without naming one leaves the selected tab alone: press `⌘,` twice and the second opening stays where the first was left.
- Record `⌘Q` on the General tab. It is refused with a reason, the recorder closes, the stored binding is unchanged, and typing works everywhere in Scriber again. `⌘⇧D` is accepted.
- `Escape` closes Settings. While a shortcut recorder is capturing it ends the capture and leaves the window open; with a confirmation on screen it dismisses only the confirmation.
- Type a keyterm and press Return. It is added, the field clears, and the Add button stays disabled for whitespace alone.
- Every section header sits left of its card's leading edge, on every tab, and every tab still fits the window's 660x560 minimum without scrolling. Shrink Settings as far as it goes; that size is the floor the window enforces, so a tab that scrolls there scrolls at every size a user can reach.
- Start recording a shortcut binding on the General tab, then switch tabs. The capture ends: typing works everywhere in Scriber again, and the recorder shows its stored binding rather than a live one. A stranded recorder swallows every keystroke and suspends global shortcut matching until the window closes, and neither symptom names its own cause.

### Simulated recovery

Use the Debug app and the same `before_pid`/absolute-`APP_PATH`/guarded-`kill` pattern above. Launch with `--ui-testing --ui-testing-missing-permissions` to inspect missing-permission recovery without changing real macOS grants.

The toolbar warning lists both permissions, the pill's Review button activates Scriber and opens Settings on the Permissions tab, and focusing and leaving Scriber does not present a second unchanged pill or restart its dismissal timer.

Launch separately with `--ui-testing --ui-testing-invalid-key-pill` when the credential-recovery pill changes. **Update Key** activates Scriber, opens Settings on the ElevenLabs tab, and focuses the key field. These fixtures prove presentation and routing only, never credential validity or service access.
