# Automated Verification

What a machine can check, and what it provably cannot. Everything requiring a
person is in [`ACCEPTANCE.md`](ACCEPTANCE.md).

Two standing rules, from [`../../../AGENTS.md`](../../../AGENTS.md):

- **Automated tests must never contact ElevenLabs or consume API credit**, and
  must use isolated data and services — never the real Keychain, never real
  SwiftData.
- **Never start the XCUITest suite unprompted.** It seizes the pointer and
  keyboard for its whole duration. Ask, or leave it to Gaf. Package tests,
  builds, `build-for-testing`, and bumping and installing a build need no
  permission.

## The routine pass

Run from the repository root with the Xcode 27 beta toolchain:

```bash
swiftc -frontend -parse apps/macos/Scriber/*.swift apps/macos/ScriberCore/*.swift apps/macos/ScriberCoreTests/*.swift apps/macos/ScriberUITests/*.swift
```

```bash
swiftc -module-cache-path apps/macos/.build/module-cache -typecheck apps/macos/ScriberCore/CoreModels.swift apps/macos/ScriberCore/ScribeClient.swift apps/macos/ScriberCore/CredentialStore.swift
```

```bash
swift test --package-path apps/macos
```

```bash
plutil -lint apps/macos/Scriber/Info.plist
```

Then build both configurations from `apps/macos/Scriber.xcodeproj`. Release must
use its configured `Scriber Local Code Signing` identity and contain neither an
embedded provisioning profile nor restricted Keychain entitlements. Separately
built Release bundles must satisfy the same certificate-based designated
requirement — see [`../README.md`](../README.md) for the recorded value and the
install procedure.

## The launch smoke check

**Prefer this over the UI suite for most of what the suite would be run for.** It
catches launch crashes, hangs, and startup regressions in about 20 seconds
without touching the keyboard: launch each `--ui-testing-*` configuration,
confirm the process is alive and *not* spinning, then kill it.

**It must stay invisible.** A second Scriber appearing over Gaf's work — window,
Dock icon, or menu bar mark — is the single most disruptive thing this check can
do, and all three are now suppressed. `--ui-testing-no-activate` skips
`promoteApplicationForVisibleWindow`, which otherwise calls
`NSApp.activate(ignoringOtherApps: true)` and yanks the build to the front past
any `open` flag; it also drops the app to `.accessory`, so no Dock icon. The
menu bar icon is off for every `--ui-testing` launch. The window is still
created and rendered — that is the path the check exists to exercise — it simply
never comes forward.

**Run it exactly as written.** `open -a` needs an *absolute* path: given a
relative one it fails on stderr while the script keeps going, and the
`pgrep` below then matches Gaf's **installed** Scriber and kills it. That is not
hypothetical — it happened twice on 2026-07-27. The `before_pid` guard is what
makes the `kill` safe, so do not drop it.

```bash
cd /Users/gafiegarcia/Developer/scriber
before_pid=$(pgrep -n -x Scriber || true)
APP_PATH="$(pwd)/apps/macos/.build/xcode-ui-tests/Build/Products/Debug/Scriber.app"
open -g -j -n -a "$APP_PATH" --args --ui-testing --ui-testing-no-activate --ui-testing-invalid-key-pill
sleep 6
pid=$(pgrep -n -x Scriber)
if [ "$pid" = "$before_pid" ]; then echo "REFUSING: the test build never launched" >&2; exit 1; fi
ps -p "$pid" -o pid,%cpu,command
kill "$pid"
```

Healthy is roughly 10% CPU while the window builds, settling to near zero once
idle. A pegged CPU, or a UI test that hangs for minutes,
is evidence about **the app**, not the harness. `sample <pid>` the app under test
before believing a test's account of why it failed, and read its log — note `log`
is a zsh builtin, so the absolute path is required:

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.gafiegarcia.scriber"' --style compact
```

## Looking at the app without taking it over

A visual check does not need the UI suite, and it must never need a plain
full-screen `screencapture` — that puts Gaf's own windows and files into a
transcript.

Use Claude Code's computer-use tools. `request_access` with just `Scriber`
grants that one app; every other running app is then excluded from screenshots
at the compositor level, so a capture shows Scriber and the desktop and nothing
else. This replaced a bespoke `window-shot.swift` on 2026-07-27 — the tool
predated computer-use being available here and did a worse job of the same
thing, since it could only reach one window.

Unlike that tool, this *can* move the pointer and press keys, so it reaches what
a still screenshot never could: hover states, menus, scroll-driven behaviour, a
collapsed sidebar. It also reaches the menu bar, which is not a window and was
permanently out of the old tool's range — though status items are frequently
collapsed behind a `«` chevron, so a missing icon there is not evidence of a
missing icon.

Two things to keep in mind. It drives the *real* pointer, so it takes the Mac
over for the duration — brief, but not something to start while Gaf is typing.
And what it shows is whatever is actually on screen: check which Scriber a
window belongs to before drawing conclusions, since the installed app and a
test build look nearly identical apart from their history.

## The XCUITest suite

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Scriber.xcodeproj -scheme Scriber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-ui-tests test
```

Run selectively where possible; it makes checking one thing cheap:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Scriber.xcodeproj -scheme Scriber -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-ui-tests -only-testing:ScriberUITests/ScriberUITests/testCommandFFocusesDictationSearch test
```

The first run requires a signed test host and macOS UI Automation approval.

### What the suite can and cannot cover

Under `--ui-testing` the app runs with `servicesAllowed: false`, so
`startServices()` never runs: no shortcut monitoring, no audio, no API-key
validation, no Keychain access. History is in-memory, preferences come from a
throwaway defaults suite wiped each launch, permission state can only be
*simulated* by `--ui-testing-missing-permissions`, and the `.build/` binary holds
no Accessibility trust.

That leaves the shell — SwiftUI navigation, keyboard focus routing, window and
Dock lifecycle, pill layout from simulated states. **Dictation, cross-app
insertion, global shortcuts, transcription, and credentials are verifiable only
live, on an installed build, by Gaf.** Never treat a failure here as evidence
about any of them.

### Known state

The suite has never been fully green, and log entries before 2026-07-26 recording
"all UI tests pass" describe a four-test suite that has since grown to eleven.
The one end-to-end run, on build 14, was eight pass and three fail; the same
three failed identically at `d183b4d`, so they predate the 2026-07-26 review
pass.

**That count is stale and should not be quoted.** Two of the three have been
explained and acted on since, and the suite has not been run end to end after
either. Build 15 and build 16 each ran only affected subsets. Re-run it end to
end before recording anything further about pass counts.

- `testEscapeDismissesPersistentPill` **cannot pass unattended**, and now skips
  explicitly instead of failing. Escape reaches the app through
  `GlobalShortcutService`'s `CGEvent` tap, which needs Accessibility trust. The
  test host is a throwaway binary in `.build/`, not `/Applications/Scriber.app`,
  so it is untrusted and the tap never arms. Fixing this means granting a
  DerivedData binary Accessibility, which is worse than the failure. It is
  `XCTSkipUnless(AXIsProcessTrusted())`, so the body still runs if a trusted host
  ever drives it; treat it as manual-only.
- `testUpdateKeyForegroundsSettingsAndFocusesAPIKeyField` was failing on a real
  app bug, since fixed: **any pill presented at launch wedged the main thread at
  100% CPU, forever.** See the note below.
- `testClosingFinalWindowUsesAccessoryActivationPolicy` **passes on its own** at
  build 16, in about 8 seconds. Whatever failed it on 2026-07-26 was not the
  `setActivationPolicy` return value — that hypothesis is disproven below — and
  may have been fixed since or may be order-dependent within the full suite.

### Two findings worth not rediscovering

**The `setActivationPolicy` hypothesis is disproven. Do not change
`reconcileActivationPolicy`.** A unified-log trace on 2026-07-27 caught the exact
transition under XCUITest: `reconcile: policy=accessory hasVisibleManaged=false
applied=true`. macOS demoted the app to `.accessory` while the runner held
Scriber active, so the discarded `Bool` was `true` and the frontmost-app theory
is wrong.

**A pill presented at launch used to wedge the main thread.** The test never
reached its Command-W — it hung inside `app.launch()` with no `window-lifecycle`
log output at all, and XCUITest waited for an app that would never idle again.
`sample` put every one of 2175 main-thread samples in `AG::Graph::print_cycle`,
entered through `TrailingAlignedMenuButton.updateNSView` → `NSButton.isEnabled` →
`NSControl.setEnabled:`. AppKit invalidates the window's key-view loop there and
rebuilds it by asking the hosting view for its responder node, which reads the
SwiftUI attribute graph from inside the update pass that is writing the property.
That re-entry is a graph cycle and AttributeGraph spins on it. Reproduced 4/4
with `--ui-testing-invalid-key-pill` or `--ui-testing-missing-permissions`, 0/2
with no pill, entirely without XCUITest — the app wedged on its own. Fixed by
writing `isEnabled` only on a real change and one main-actor turn later; a
change-guard alone is **not** enough, since the first genuine write still cycles.

The code lesson worth carrying: `NSViewRepresentable.updateNSView` runs inside a
SwiftUI update, so any AppKit setter there that can call back into the view tree —
`setEnabled:` is one — belongs on a later turn.
