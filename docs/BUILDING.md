# Building Scriber

Prerequisites, signing, building, installing, and first launch. The [README](../README.md) describes what the app is.

## Prerequisites

- macOS 26 or later to run the app; macOS 27 to build it, since the toolchain below requires it
- Xcode 27 beta with Swift 6.4; Command Line Tools alone do not contain the SwiftUI and SwiftData macro plugins
- An ElevenLabs API key with Speech to Text access

## Signing setup

Debug and UI-test builds require an Apple Development team. Create `Signing.local.xcconfig` beside `Signing.xcconfig` with your team identifier:

```text
DEVELOPMENT_TEAM = ABCDE12345
```

The local file is ignored by Git. Without it, the project leaves the team empty instead of failing configuration loading.

A free Apple ID works here. The seven-day expiry people associate with free accounts is an iOS provisioning-profile rule; this app ships no entitlements and no embedded profile, so nothing expires out from under a macOS build.

Release builds sign with a **Developer ID Application** certificate for team `24U8BM54A3` under the hardened runtime, using `Scriber/Scriber.entitlements`. That certificate exists only on Gaf's machine; if you are not Gaf, build Debug with your own team and ignore this configuration. Keep the password-protected `.p12` backup private and outside the repository — Apple caps how many Developer ID certificates an account may hold, so losing it is expensive.

The identity is what keeps the app's designated requirement stable across rebuilds, so Accessibility, Microphone, Launch at Login, and Keychain grants survive a reinstall. An automatic `Apple Development` signature changes identity every build and loses them.

The hardened runtime withholds the microphone from a process without `com.apple.security.device.audio-input`, which covers both `AVCaptureDevice` capture and the Core Audio process tap that mutes other apps. Nothing in the app uses Apple Events, so it carries no automation entitlement.

Before producing a distinct installable candidate, increment `CURRENT_PROJECT_VERSION` in both configurations of the Scriber target. Do not override it on one `xcodebuild` invocation: that would make the installed binary and checked-in project disagree.

## Adding a source file

Put it in `Scriber/` or `ScriberCore/` and build. Both are file-system synchronized groups, so the target compiles whatever the folder holds and `project.pbxproj` never names a source file — a commit that adds one touches no project file at all.

Two files inside `Scriber/` are deliberately not members: `Info.plist` and `Scriber.entitlements`, which the target reads through `INFOPLIST_FILE` and `CODE_SIGN_ENTITLEMENTS`. They are listed in the target's exception set. Anything else you put in either folder is compiled into the app on the next build, whether or not you meant it to be. That includes a helper written only for tests: `ScriberCore` is built into the app as well as into the package, so a test-only file there is dead code inside the app people download. Put those in `ScriberCoreTests/`, which the app target does not read.

## Build with Xcode

1. Open `Scriber.xcodeproj` and select the `Scriber` scheme.
2. For a personal install, edit the scheme and set **Run → Info → Build Configuration** to **Release**. Restore **Debug** for normal development.
3. Choose **Product → Clean Build Folder**, then **Product → Build**.
4. In the Products group, reveal `Scriber.app` in Finder.

## Build from the command line

Run from the repository root. This builds Release, so it completes only with the local identity described above; build `-configuration Debug` with your own team instead if you are not Gaf.

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

The app is written to `.build/xcode-release/Build/Products/Release/Scriber.app`.

## Verify and install

Run all relevant checks in [Automated checks](AUTOMATED_CHECKS.md) before replacing the installed app. Read the signature the build actually carries:

```bash
codesign -d --requirements - --verbose=4 .build/xcode-release/Build/Products/Release/Scriber.app
```

It must name the bundle identifier and anchor to Apple's Developer ID chain for team `24U8BM54A3`, and the flags must include `runtime`. A build that anchors anywhere else is not the app macOS granted Accessibility to, and the grants will not carry over.

Then replace the copy in `/Applications` rather than launching it from a build directory:

```bash
osascript -e 'quit app "Scriber"'
trash /Applications/Scriber.app
ditto .build/xcode-release/Build/Products/Release/Scriber.app /Applications/Scriber.app
open -a Scriber
```

The stable path matters because Accessibility, Microphone, Launch at Login, and Keychain authorization are associated with the installed application. Never rename the `.app` bundle; doing so invalidates its signature.

A Developer ID signature does not change between builds, so the login-Keychain authorization for the stored ElevenLabs key is granted once and then holds. Debug builds still prompt on each freshly built binary, because `Apple Development` re-identifies the app every time.

## When Accessibility looks enabled but is not

macOS records the signing identity of the app it granted Accessibility to, and revalidates it on every launch. Sign with an identity that changes between builds and the entry stops matching: Scriber reports Accessibility as missing and global shortcuts stay dead while System Settings still shows the checkbox ticked.

Unchecking and rechecking does not fix it. Remove Scriber from **Privacy & Security → Accessibility** entirely, then add it back by dragging `Scriber.app` from `/Applications` into the list.

Both configurations above sign with a stable identity, so this only arises after overriding one with ad-hoc signing (`CODE_SIGN_IDENTITY="-"`), which has no certificate to anchor to and identifies the app by a hash of the binary itself.

## Build directory housekeeping

`.build` gains a DerivedData root for every one-off `-derivedDataPath` and never loses one. Xcode cannot prune them; it has no record of a path given on the command line. After installing a Release candidate, sweep whatever the documented build, test, and smoke-check commands do not use:

```bash
cd "$(git rev-parse --show-toplevel)/.build" || exit 1
for build_entry in */; do
  case "${build_entry%/}" in
    xcode-release|xcode-debug|module-cache|out|debug|artifacts|checkouts|repositories) ;;
    *) trash "$build_entry" ;;
  esac
done
```

## First launch

Onboarding requests the ElevenLabs key, Microphone access, Accessibility access, the option to launch at login, and the other-audio-muting preference. Default shortcuts are Hold `Fn` and Hands-free `Fn-Space`. If macOS still performs a Globe/Fn action during shortcut testing, set that action to **Do Nothing** in System Settings.
