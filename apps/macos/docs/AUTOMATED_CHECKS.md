# Checks a Machine Can Run

## Safety boundaries

- Never contact ElevenLabs, consume API credit, read the real Keychain, or mutate
  real SwiftData.
- Never use a plain full-screen `screencapture`; it can expose unrelated windows
  and files.
- A `--ui-testing` launch runs with services disabled and no Accessibility trust.
  It shows the SwiftUI shell only — never treat it as evidence about dictation,
  insertion, shortcuts, or credentials.

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
  "$REPO_ROOT/apps/macos/ScriberCore/CredentialStore.swift"

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
must stay, or a failed launch makes the final `kill` target Gaf's installed
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
  --ui-testing-invalid-key-pill
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

## Visual inspection

Use computer-use with access restricted to **Scriber**. Compositor-level app-only
capture excludes every other application while still allowing hover states, menus,
scrolling, and the menu bar to be checked.

It moves the real pointer and can press keys, so do not start one while Gaf is
typing. Check whether the window on screen belongs to the installed app or a test
build before drawing any conclusion from it.

### Onboarding

`--ui-testing-onboarding` opens the setup window, which `--ui-testing` otherwise
skips by marking setup complete. Launch it with activation and the `before_pid`
guard, as with seeded history below.

Confirm the window is centred and fully visible above the Dock, then relaunch and
confirm it again — a restored frame behaves differently from a fresh one, and
`fitOnboardingWindow` in `Scriber/ScriberApp.swift` is what overrides AppKit here.

### Seeded history

`--ui-testing-seed-history` fills the in-memory store with 23 deterministic
records over four day groups, 22 of which render, so the Dictation list can be
inspected without touching Gaf's real entries or spending credit.
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

While inspecting: the header must read **22 dictations** — 23 means the in-flight
filter regressed. Copy writes to the real `NSPasteboard.general`, so it clobbers
the clipboard, and which transcript landed there can only be confirmed by pasting
elsewhere. Every `--ui-testing` launch also shows the credential banner, because
the throwaway defaults suite starts with no key.
