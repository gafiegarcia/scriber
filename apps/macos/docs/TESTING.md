# Automated Verification

This file contains machine checks and their safety boundaries. Checks that need
a person or real service state belong in [Acceptance](ACCEPTANCE.md).

## Safety boundaries

- Automated tests must never contact ElevenLabs, consume API credit, read the
  real Keychain, or mutate real SwiftData.
- Never start XCUITest without Gaf's permission. It controls the real pointer and
  keyboard for the duration. Package tests, builds, and `build-for-testing` do
  not need permission.
- Never use a plain full-screen `screencapture`; it can expose unrelated windows
  and files.

## Routine pass

Run from any directory inside the repository. The absolute repo-local module
cache and `--disable-sandbox` make the package tests work in managed Codex
sandboxes as well as a normal shell.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
MODULE_CACHE="$REPO_ROOT/apps/macos/.build/module-cache"
mkdir -p "$MODULE_CACHE"

swiftc -frontend -parse \
  "$REPO_ROOT"/apps/macos/Scriber/*.swift \
  "$REPO_ROOT"/apps/macos/ScriberCore/*.swift \
  "$REPO_ROOT"/apps/macos/ScriberCoreTests/*.swift \
  "$REPO_ROOT"/apps/macos/ScriberUITests/*.swift

swiftc -module-cache-path "$MODULE_CACHE" -typecheck \
  "$REPO_ROOT/apps/macos/ScriberCore/CoreModels.swift" \
  "$REPO_ROOT/apps/macos/ScriberCore/ScribeClient.swift" \
  "$REPO_ROOT/apps/macos/ScriberCore/CredentialStore.swift"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift test --disable-sandbox --package-path "$REPO_ROOT/apps/macos"

plutil -lint "$REPO_ROOT/apps/macos/Scriber/Info.plist"
```

Use the [native README](../README.md) for build and signing instructions. A
Release candidate must have no embedded provisioning profile or restricted
Keychain entitlement, must pass strict signature verification, and must reproduce
the designated requirement recorded there.

After building the Release app, inspect the exact bundle that will be installed:

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

## Worktree-safe launch smoke check

Run this after changes to startup, the pill, or an `NSViewRepresentable`. It
launches the rendered UI-test configuration without activating it, checks that a
new process exists, and stops only that process.

Run it exactly as written. `APP_PATH` must be absolute, and the `before_pid`
guard must remain: otherwise a failed launch can make the final `kill` target the
installed Scriber.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
before_pid="$(pgrep -n -x Scriber || true)"
APP_PATH="$REPO_ROOT/apps/macos/.build/xcode-ui-tests/Build/Products/Debug/Scriber.app"

if [ ! -d "$APP_PATH" ]; then
  echo "REFUSING: build the UI-test host first" >&2
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

The UI-test launch suppresses activation, Dock presence, and the menu-bar item;
the window is still created and rendered. A process that remains at high CPU or
never idles is an app failure worth sampling before blaming the harness.

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.gafiegarcia.scriber"' --style compact
```

## Visual inspection

Visual inspection is available and encouraged. Use computer-use with access
restricted to **Scriber**; compositor-level app-only capture excludes other
applications while still allowing hover states, menus, scrolling, and the menu
bar to be checked. It moves the real pointer and can press keys, so do not begin
while Gaf is typing, and verify whether the visible window belongs to the
installed app or a test build.

## XCUITest

Only Gaf may authorize starting the suite. From the repository root:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project "$REPO_ROOT/apps/macos/Scriber.xcodeproj" \
  -scheme Scriber \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$REPO_ROOT/apps/macos/.build/xcode-ui-tests" \
  test
```

Use `-only-testing` before `test` for a focused case, for example:

```text
-only-testing:ScriberUITests/ScriberUITests/testCommandFFocusesDictationSearch
```

The test host must be signed and macOS must allow UI Automation. Under
`--ui-testing`, services are disabled: no global shortcut monitor, recording,
transcription, credential validation, production Keychain, or persistent
history. Preferences and history are isolated, and permission failure can only
be simulated. Therefore the suite covers the SwiftUI shell, navigation, focus
routing, window/Dock lifecycle, and simulated pill layouts—not dictation,
cross-app insertion, global shortcuts, credentials, or real permissions.

The persistent-pill Escape test intentionally skips unless its generated test
host has Accessibility trust; granting every DerivedData binary that trust is
not an acceptable automation requirement. Do not publish a current pass count
until Gaf has run the complete suite again.
