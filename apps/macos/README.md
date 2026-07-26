# Scriber

Scriber is a native macOS menu-bar dictation app powered by ElevenLabs Scribe v2. It records only while a configured shortcut is active, stores the API key in Keychain, saves dictation history locally with SwiftData, and inserts finished text through macOS Accessibility or standard clipboard paste.

The current native line is Scriber `0.7.0` build `14`, a locally certificate-signed personal-use candidate targeting Apple silicon and macOS 27. It is installed and untagged; build `11` is preserved as `v0.7.0-alpha.7` and build `7` as `v0.7.0-alpha.6`. The last provisioned Data Protection Keychain state is preserved as `v0.7.0-alpha.2`. It continues the product lineage from the archived Electron app's `0.6.0`; it is not yet a stable `0.7.0` release. See the repository [versioning policy](../../docs/VERSIONING.md) for the distinction between product maturity, bundle builds, signing, notarization, and Git tags.

## Current prerequisites

- macOS 27
- Xcode 27 beta with Swift 6.4 (the Command Line Tools package alone does not contain the SwiftUI/SwiftData macro plugins)
- An ElevenLabs API key with Speech to Text access

## Build

Debug and UI-test builds require an Apple Development signing team, supplied through `Signing.xcconfig`. Create `Signing.local.xcconfig` beside it holding your own team identifier:

```
DEVELOPMENT_TEAM = ABCDE12345
```

That file is gitignored, so no personal team identifier reaches the repository, and it is optional at the project level — its absence leaves the team empty rather than breaking the build. Xcode reports which teams are available in the target's Signing & Capabilities tab.

The Release configuration takes no team. It uses the long-lived `Scriber Local Code Signing` identity from the login Keychain so rebuilt personal-use apps retain one designated requirement without an expiring provisioning profile. Keep the identity's password-protected `.p12` backup private and outside the repository. A free Apple ID can sign Debug builds, but its provisioning profile expires after seven days; the Release path exists precisely to avoid that.

Bump the bundle build number first. `CURRENT_PROJECT_VERSION` appears in both the Debug and Release configurations of the `Scriber` target, and the target's **General → Identity → Build** field updates both. Two installed builds sharing a build number are difficult to tell apart afterwards.

### With Xcode

1. Install Xcode 27 beta and select it in Xcode Settings → Locations → Command Line Tools.
2. Open `Scriber.xcodeproj` and choose the `Scriber` scheme.
3. `⌘<` → **Run** → **Info** → set **Build Configuration** to **Release**. Only Release uses the local signing identity. Set this back to **Debug** when returning to normal development.
4. **Product → Clean Build Folder** (`⇧⌘K`), then **Product → Build** (`⌘B`).
5. Reveal the product: **Products** group → right-click `Scriber.app` → **Show in Finder**.

### With the command line

Run from `apps/macos`:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Scriber.xcodeproj -scheme Scriber -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-release clean build
```

The product lands at `.build/xcode-release/Build/Products/Release/Scriber.app`. Without `-derivedDataPath` it goes to Xcode's shared DerivedData instead; either location works, but keep track of which one is being verified and installed.

Do not set the build number by passing `CURRENT_PROJECT_VERSION=<n>` on the command line. That overrides the value for one invocation, never writes back to `project.pbxproj`, and applies to every target in the build, so the installed app and the repository end up disagreeing about what was built.

## Verify before installing

```bash
codesign -d -r- <built>/Scriber.app
codesign --verify --strict --verbose=2 <built>/Scriber.app
```

The designated requirement must be exactly:

```
identifier "com.gafiegarcia.scriber" and certificate root = H"fb7719074d66edfec627e3108437cbe34e7b7bfd"
```

That hash is the `Scriber Local Code Signing` certificate, valid until 2036. Every Release build must reproduce this same requirement even though its `CDHash` changes, which is what lets macOS recognise a rebuilt bundle as the same app. A `cdhash`-based requirement instead means the build fell back to ad-hoc signing and macOS will treat it as a different app, discarding existing permission grants.

## Install

Replace the copy in `/Applications` rather than running the build product where it was built. Accessibility, Microphone, Launch at Login, and the Keychain ACL are all recorded against `/Applications/Scriber.app`.

```bash
osascript -e 'quit app "Scriber"'
trash /Applications/Scriber.app
ditto <built>/Scriber.app /Applications/Scriber.app
open -a Scriber
```

`ditto` is used because it preserves extended attributes, ACLs, and hard links unconditionally and behaves the same across volumes; `mv` and `cp -R` also preserve a signed bundle correctly on current macOS. Never rename an `.app` bundle — a renamed bundle fails signature verification outright.

macOS asks for the login Keychain password once per newly installed binary before releasing the ElevenLabs API key. Choose **Always Allow**; the grant then persists for that binary across launches and transcriptions. This is expected, and is not fixable while the signing certificate carries no Team ID. See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## First launch

Onboarding asks for:

- The ElevenLabs key, stored under a dedicated service in the encrypted macOS login Keychain.
- Microphone access for recording.
- Accessibility access for global shortcuts and cross-app text insertion.
- Optional Launch at Login registration.
- Whether to mute all other app audio during recording. This uses a private Core Audio mute tap driven by a private aggregate device; the callback discards every buffer without inspecting, copying, or saving system-audio samples.

Default shortcuts are Hold `Fn` and Toggle `Fn-Space`. Recording feedback uses the built-in Frog sound for a successful start, Bottle for a terminal failure, and Morse for cancellation or copied paste fallback; feedback sounds and other-audio muting can be disabled in Settings. Shortcut configuration shows the recognized chord as it is pressed. If macOS still performs a configured Globe/Fn action during hardware testing, set the Globe/Fn action to “Do Nothing” in System Settings.

## Documentation

- [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md) defines required native behavior and locked decisions.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) tracks release gates, manual acceptance, and complete verification commands.
- [`docs/PASTE_ENGINE_RESEARCH.md`](docs/PASTE_ENGINE_RESEARCH.md) preserves active paste-delivery evidence, rejected assumptions, and the cross-app investigation plan.
- [`docs/DEVELOPMENT_LOG.md`](docs/DEVELOPMENT_LOG.md) preserves chronological engineering history without burdening normal development context.

## Verification

`swift test` covers UI-independent behavior when run through the full Xcode toolchain. Tests never call ElevenLabs. Follow [`docs/ROADMAP.md`](docs/ROADMAP.md) for parser validation, core type-checking, Xcode builds, isolated UI tests, and manual acceptance.
