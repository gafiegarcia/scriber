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

# Again with DEBUG defined. Without it, `#if DEBUG` regions are lexed but not
# parsed as code, so the pass above says nothing about `AppLaunchConfiguration`'s
# flags or `UITestingHistoryFixture` — the whole test-only surface.
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

Neither parse invocation typechecks, so a Debug `xcodebuild` remains the only
real gate on `#if DEBUG` code. The `-D DEBUG` pass catches syntax there for the
cost of a second; it will not catch an actor-isolation or type error.

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

### Onboarding

`--ui-testing-onboarding` opens the setup window, which `--ui-testing` otherwise
skips by marking setup complete. Without it the only way to see onboarding is to
delete Gaf's real `onboardingComplete` default and restart the installed app,
which means walking back through setup to get out again. Use it the same way as
the seeded-history launch below — with activation, and with the `before_pid`
guard — substituting the flag.

Check that the window is centred and fully visible above the Dock. That is the
build-29 defect it exists to catch, and AppKit's own frame is not to be trusted
here: see `fitOnboardingWindow` in `Scriber/ScriberApp.swift`. Relaunch once more
before believing it, because the original failure only appeared on the *second*
launch, from a restored frame.

### Seeded history

`--ui-testing-seed-history` fills the in-memory store with 23 deterministic
records over four day groups, 22 of which render. It exists so the Dictation list
can be inspected at all: the test store is otherwise empty, which left every
history check reachable only through Gaf's real entries — where confirming that
Delete removes the right row means destroying a real transcript, and adding a row
costs API credit. `Scriber/UITestingHistoryFixture.swift` documents the fixture
and the four invariants behind it.

Launch it **with** activation, since the window has to be clickable, and keep the
`before_pid` guard so the closing `kill` cannot land on the installed app:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
before_pid="$(pgrep -n -x Scriber || true)"
APP_PATH="$REPO_ROOT/apps/macos/.build/xcode-ui-tests/Build/Products/Debug/Scriber.app"

open -n -a "$APP_PATH" --args --ui-testing --ui-testing-seed-history
sleep 6
pid="$(pgrep -n -x Scriber || true)"
[ -n "$pid" ] && [ "$pid" != "$before_pid" ] || { echo "REFUSING: never launched" >&2; exit 1; }
# … inspect, then …
kill "$pid"
```

Two things to know while inspecting a seeded build. The header must read **22
dictations**; 23 means the in-flight filter regressed. And Copy writes to the real
`NSPasteboard.general`, so it clobbers the clipboard, and *which* transcript
landed there is not observable inside Scriber — that needs a paste elsewhere.

Every `--ui-testing` launch also shows the credential banner, because the
throwaway defaults suite starts with no key. It costs list height and blocks
nothing.

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

Two tests skip unless the generated test host has Accessibility trust, which no
`.build/` binary has and none should be granted:

- **`testEscapeDismissesPersistentPill`** — Escape reaches the pill through a
  `CGEvent` tap that only arms for a trusted process.
- **`testUpdateKeyForegroundsSettingsAndFocusesAPIKeyField`** — the simulated
  credential pill is superseded by a *real* missing-Accessibility pill, so
  `Update Key` matches only the in-window banner, which the test's own
  Command-W then closes.

### Three switch tests fail on this machine, and did so before this branch

`testShowAppInDockKeepsRegularActivationPolicyAfterClosingWindows`,
`testDisablingShowAppInDockKeepsVisibleWindowOpen`, and
`testRecordingFeedbackDefaultsCanBeDisabled` each report **`Not hittable`** on a
SwiftUI `Switch` that the same query finds and reads a correct `value` from.

What is established:

- It is **not** a regression from the `v0.7.0` sprint. The identical failure,
  at the same coordinates, reproduces on `origin/main` in a separate worktree.
- It is not cross-test pollution — a single test in isolation fails the same way.
- It is not the installed app occluding the test window; the failure survives
  quitting `/Applications/Scriber.app`.
- It is not scroll position. Scrolling until the switch reports hittable, in
  both directions, never succeeds — so a taller Settings pane is not the cause,
  and the blind `swipeUp()` in these tests was left alone.
- It is machine-state dependent rather than absolute: all three **passed** on the
  first run of the day and have failed every run since, with no code change
  between.

What is not established: why. Every switch the suite clicks is affected and no
button or text field is, which points at `Switch` hit-testing under this macOS
27 beta rather than at Scriber. Do not treat these as evidence about the Dock
lifecycle or the feedback preferences; both are covered by hand in
[`ACCEPTANCE.md`](ACCEPTANCE.md) and pass there.

Do not publish a current pass count until Gaf has run the complete suite again.
