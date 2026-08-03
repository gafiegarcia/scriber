# Checks a Machine Can Run

## Safety boundaries

- Never contact ElevenLabs, consume API credit, read the real Keychain, or mutate
  real SwiftData.
- Never use a plain full-screen `screencapture`; it can expose unrelated windows
  and files.
- A `--ui-testing` launch uses throwaway defaults, an in-memory history store,
  disabled external services, and no real Keychain. It can prove presentation,
  interaction, and routing, but never real credential validity or storage,
  service access, permissions, dictation, insertion, global shortcuts, or
  menu-bar behavior.

## Routine pass

Run from any directory inside the repository. The repo-local module cache and
`--disable-sandbox` make the package tests work in managed sandboxes as well as a
normal shell.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
MODULE_CACHE="$REPO_ROOT/apps/macos/.build/module-cache"
mkdir -p "$MODULE_CACHE"

swiftc -frontend -parse \
  "$REPO_ROOT"/apps/macos/Scriber/*.swift \
  "$REPO_ROOT"/apps/macos/ScriberCore/*.swift \
  "$REPO_ROOT"/apps/macos/ScriberCoreTests/*.swift

# Again with DEBUG defined. Without it, `#if DEBUG` regions are lexed but never
# parsed, so the pass above says nothing about `AppLaunchConfiguration`'s flags
# or `UITestingHistoryFixture`.
swiftc -frontend -parse -D DEBUG \
  "$REPO_ROOT"/apps/macos/Scriber/*.swift \
  "$REPO_ROOT"/apps/macos/ScriberCore/*.swift

swiftc -module-cache-path "$MODULE_CACHE" -typecheck \
  "$REPO_ROOT/apps/macos/ScriberCore/CoreModels.swift" \
  "$REPO_ROOT/apps/macos/ScriberCore/ScribeClient.swift" \
  "$REPO_ROOT/apps/macos/ScriberCore/CredentialStore.swift" \
  "$REPO_ROOT/apps/macos/ScriberCore/RecoveryConditions.swift" \
  "$REPO_ROOT/apps/macos/ScriberCore/Toasts.swift"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift test --disable-sandbox --package-path "$REPO_ROOT/apps/macos"

plutil -lint "$REPO_ROOT/apps/macos/Scriber/Info.plist"
```

Neither parse invocation typechecks, so a Debug `xcodebuild` is the only real gate
on `#if DEBUG` code.

## Release bundle inspection

Build instructions are in the [native README](../README.md). After building
Release, inspect the exact bundle that will be installed:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_PATH="$REPO_ROOT/apps/macos/.build/xcode-release/Build/Products/Release/Scriber.app"

codesign -d -r- "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH"

if [ -e "$APP_PATH/Contents/embedded.provisionprofile" ]; then
  echo "REFUSING: Release contains a provisioning profile" >&2
  exit 1
fi
```

It must reproduce the designated requirement recorded in the README, carry no
provisioning profile, and hold no restricted Keychain entitlement.

## Launch smoke check

Run after any change to startup, the pill, or an `NSViewRepresentable`.

Run it exactly as written. `APP_PATH` must be absolute and the `before_pid` guard
must stay, or a failed launch makes the final `kill` target the installed
Scriber.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
xcodebuild -project "$REPO_ROOT/apps/macos/Scriber.xcodeproj" \
  -scheme Scriber -configuration Debug \
  -derivedDataPath "$REPO_ROOT/apps/macos/.build/xcode-debug" build
```

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
before_pid="$(pgrep -n -x Scriber || true)"
APP_PATH="$REPO_ROOT/apps/macos/.build/xcode-debug/Build/Products/Debug/Scriber.app"

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

This launch suppresses activation, Dock presence, and the menu-bar item, but
still creates and renders the window. A process that stays at high CPU or never
idles is an app failure worth sampling before blaming the harness.

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.gafiegarcia.scriber"' --style compact
```

## Inspecting a running Debug build

### Visual and interaction inspection

Use a computer-use tool with the capture restricted to **Scriber**, so no other
application appears.

It moves the real pointer and can press keys, so do not start one while the user
is typing. Check whether the window on screen belongs to the installed app or a
test build before drawing any conclusion from it.

### Onboarding

`--ui-testing-onboarding` opens the setup window, which `--ui-testing` otherwise
skips by marking setup complete. Launch it with activation and the `before_pid`
guard, as with seeded history below.

Confirm the window is centred and fully visible above the Dock, then relaunch and
confirm it again — a restored frame behaves differently from a fresh one, and
`fitOnboardingWindow` in `Scriber/ScriberApp.swift` is what overrides AppKit here.

Also launch ordinary `--ui-testing`, open Settings, and choose **Redo Setup…**
on the General tab while the main window is already open. The setup window comes to
the front, remains centred above the Dock, and shows the throwaway setup state;
never reset Gaf's real `onboardingComplete` preference for this inspection.

### Seeded history

`--ui-testing-seed-history` fills the in-memory store with 23 deterministic
records over four day groups, 22 of which render, so the Dictation list can be
inspected without touching real entries or spending credit.
`Scriber/UITestingHistoryFixture.swift` documents the fixture and its invariants.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
before_pid="$(pgrep -n -x Scriber || true)"
APP_PATH="$REPO_ROOT/apps/macos/.build/xcode-debug/Build/Products/Debug/Scriber.app"

open -n -a "$APP_PATH" --args --ui-testing --ui-testing-seed-history
sleep 6
pid="$(pgrep -n -x Scriber || true)"
[ -n "$pid" ] && [ "$pid" != "$before_pid" ] || { echo "REFUSING: never launched" >&2; exit 1; }
# … inspect, then …
kill "$pid"
```

While inspecting: the toolbar must read **22 dictations** — 23 means the in-flight
filter regressed. Copy writes to the real `NSPasteboard.general`, so leave it
untouched unless Gaf has said the current clipboard is disposable; only then
confirm a known fixture transcript by pasting elsewhere. Every `--ui-testing`
launch also raises the credential condition in the toolbar's warning control,
because the throwaway defaults suite starts with no key.

Use this same isolated launch for the window, toolbar, Settings, and history
interaction checks:

- `⌘F` focuses Dictation search. In Settings, the command is disabled and leaves
  focus unchanged.
- Launch, the Dock icon, and reopening after `⌘W` all present the main window
  with search focused. Returning from another app, `⌘H`, or minimising preserves
  an existing transcript selection and search/scroll position.
- The main window has no displayed title. Workspace, total rendered count, and
  warning control stay grouped without reflow; search does not change the total.
- The titlebar's day strip names the day at the top of the list, hands over as
  the next day's card reaches it, and collapses when a search matches nothing.
  Its label stays aligned to the card's leading edge at both the minimum window
  size and full width, the separator appears only over scrolled content, and the
  cards and toolbar survive minimum window size.
- Single-entry Delete and Clear Dictation History both ask first. Clear
  Dictation History is on Settings' Dictation tab. Exercise Cancel and
  confirmation against the in-memory fixture, verify the rendered count, and
  never repeat this against the installed app's real history.
- Saving a dummy key and then choosing **Remove API Key…** on the ElevenLabs tab
  exercises only the confirmation, routing, and visible missing-key state. It is
  not evidence about the real Keychain.
- Every route that opens Settings to fix something selects the tab that owns the
  problem, and opening Settings without naming one leaves the selected tab alone:
  press `⌘,` twice and the second opening stays where the first was left.
- Start recording a shortcut binding on the General tab, then switch tabs. The
  capture ends: typing works everywhere in Scriber again, and the recorder shows
  its stored binding rather than a live one. A stranded recorder swallows every
  keystroke and suspends global shortcut matching until the window closes, and
  neither symptom names its own cause.

### Simulated recovery

Use the Debug app and the same `before_pid`/absolute-`APP_PATH`/guarded-`kill`
pattern above. Launch with `--ui-testing --ui-testing-missing-permissions` to
inspect missing-permission recovery without changing real macOS grants.

The toolbar warning lists both permissions, the pill's Review button activates
Scriber and opens Settings on the Permissions tab, and focusing and leaving
Scriber does not present a second unchanged pill or restart its dismissal timer.

Launch separately with `--ui-testing --ui-testing-invalid-key-pill` when the
credential-recovery pill changes. **Update Key** activates Scriber, opens
Settings on the ElevenLabs tab, and focuses the key field. These fixtures prove presentation and
routing only, never credential validity or service access.
