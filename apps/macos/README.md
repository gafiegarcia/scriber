# Scriber for macOS

This is the active native Scriber app: a Swift, SwiftUI, and AppKit dictation client for ElevenLabs Scribe v2 that lives in the menu bar by default.

## Prerequisites

- macOS 27
- Xcode 27 beta with Swift 6.4; Command Line Tools alone do not contain the
  SwiftUI and SwiftData macro plugins
- An ElevenLabs API key with Speech to Text access

## Signing setup

Debug and UI-test builds require an Apple Development team. Create
`Signing.local.xcconfig` beside `Signing.xcconfig` with your team identifier:

```text
DEVELOPMENT_TEAM = ABCDE12345
```

The local file is ignored by Git. Without it, the project leaves the team empty
instead of failing configuration loading.

Release builds use the long-lived `Scriber Local Code Signing` identity from the
login Keychain. Keep its password-protected `.p12` backup private and outside the
repository. Before producing a distinct installable candidate, increment
`CURRENT_PROJECT_VERSION` in both configurations of the Scriber target. Do not
override it on one `xcodebuild` invocation: that would make the installed binary
and checked-in project disagree.

## Build with Xcode

1. Open `Scriber.xcodeproj` and select the `Scriber` scheme.
2. For a personal install, edit the scheme and set **Run → Info → Build
   Configuration** to **Release**. Restore **Debug** for normal development.
3. Choose **Product → Clean Build Folder**, then **Product → Build**.
4. In the Products group, reveal `Scriber.app` in Finder.

## Build from the command line

Run from `apps/macos` (this directory):

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild \
  -project Scriber.xcodeproj \
  -scheme Scriber \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode-release \
  clean build
```

The app is written to
`.build/xcode-release/Build/Products/Release/Scriber.app`.

## Verify and install

Run all relevant checks in [Automated checks](docs/AUTOMATED_CHECKS.md) before replacing the
installed app. In particular, a Release build's designated requirement must be:

```text
identifier "com.gafiegarcia.scriber" and certificate root = H"fb7719074d66edfec627e3108437cbe34e7b7bfd"
```

Then replace the copy in `/Applications` rather than launching it from a build
directory:

```bash
osascript -e 'quit app "Scriber"'
trash /Applications/Scriber.app
ditto .build/xcode-release/Build/Products/Release/Scriber.app /Applications/Scriber.app
open -a Scriber
```

The stable path matters because Accessibility, Microphone, Launch at Login, and
Keychain authorization are associated with the installed application. Never
rename the `.app` bundle; doing so invalidates its signature.

On first use of a newly installed binary, macOS asks for the login Keychain
password before releasing the saved ElevenLabs key. Choose **Always Allow**. The
grant then persists for that binary; the limitation is tracked as an accepted
constraint in the [roadmap](docs/ROADMAP.md).

## Build directory housekeeping

`.build` gains a DerivedData root for every one-off `-derivedDataPath` and never
loses one. Xcode cannot prune them; it has no record of a path given on the
command line. After installing a Release candidate, sweep whatever the documented
build, test, and smoke-check commands do not use:

```bash
cd "$(git rev-parse --show-toplevel)/apps/macos/.build" || exit 1
for build_entry in */; do
  case "${build_entry%/}" in
    xcode-release|xcode-debug|module-cache|out|debug|artifacts|checkouts|repositories) ;;
    *) trash "$build_entry" ;;
  esac
done
```

## First launch

Onboarding requests the ElevenLabs key, Microphone access, Accessibility access,
the option to launch at login, and the other-audio-muting preference. Default
shortcuts are Hold `Fn` and Hands-free `Fn-Space`. If macOS still performs a Globe/Fn
action during shortcut testing, set that action to **Do Nothing** in System
Settings.

## Documentation map

- [Product specification](docs/PRODUCT_SPEC.md): required behavior and durable
  product decisions.
- [Roadmap](docs/ROADMAP.md): unbuilt work, grouped by target version.
- [Manual checks](docs/MANUAL_CHECKS.md): checks Gaf runs in the real environment; agents only select and propose the relevant ones.
- [Automated checks](docs/AUTOMATED_CHECKS.md): machine checks and their safety
  boundaries.
- [Paste engine](docs/PASTE_ENGINE.md): current cross-app delivery design and
  regression matrix.
- [Root changelog](../../CHANGELOG.md): tagged release history.
- [Versioning policy](../../docs/VERSIONING.md): versions, builds, tags, and
  distribution milestones.
