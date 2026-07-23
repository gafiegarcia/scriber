# Scriber

Scriber is a native macOS menu-bar dictation app powered by ElevenLabs Scribe v2. It records only while a configured shortcut is active, stores the API key in Keychain, saves dictation history locally with SwiftData, and inserts finished text through macOS Accessibility or standard clipboard paste.

The current native line is Scriber `0.7.0` build `7`, the locally certificate-signed personal-use candidate for `v0.7.0-alpha.6`, targeting Apple silicon and macOS 27. The last provisioned Data Protection Keychain state is preserved as `v0.7.0-alpha.2`. It continues the product lineage from the archived Electron app's `0.6.0`; it is not yet a stable `0.7.0` release. See the repository [versioning policy](../../docs/VERSIONING.md) for the distinction between product maturity, bundle builds, signing, notarization, and Git tags.

## Current prerequisites

- macOS 27
- Xcode 27 beta with Swift 6.4 (the Command Line Tools package alone does not contain the SwiftUI/SwiftData macro plugins)
- An ElevenLabs API key with Speech to Text access

## Build

1. Install Xcode 27 beta and select it in Xcode Settings → Locations → Command Line Tools.
2. Open `Scriber.xcodeproj`.
3. Choose the `Scriber` scheme and the local Mac destination.
4. Debug and UI-test builds may use an Apple Development signing team. The Release configuration uses the long-lived `Scriber Local Code Signing` identity from the login Keychain so rebuilt personal-use apps retain one designated requirement without an expiring provisioning profile. Keep the identity's password-protected `.p12` backup private and outside the repository.
5. Build and run.

For stable Accessibility and Launch at Login permissions, archive a Release build and keep `Scriber.app` in `/Applications` rather than repeatedly moving it.

## First launch

Onboarding asks for:

- The ElevenLabs key, stored under a dedicated service in the encrypted macOS login Keychain.
- Microphone access for recording.
- Accessibility access for global shortcuts and cross-app text insertion.
- Optional Launch at Login registration.

Default shortcuts are Hold `Fn` and Toggle `Fn-Space`. If macOS still performs a configured Globe/Fn action during hardware testing, set the Globe/Fn action to “Do Nothing” in System Settings.

## Documentation

- [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md) defines required native behavior and locked decisions.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) tracks release gates, manual acceptance, and complete verification commands.
- [`docs/PASTE_ENGINE_RESEARCH.md`](docs/PASTE_ENGINE_RESEARCH.md) preserves active paste-delivery evidence, rejected assumptions, and the cross-app investigation plan.
- [`docs/DEVELOPMENT_LOG.md`](docs/DEVELOPMENT_LOG.md) preserves chronological engineering history without burdening normal development context.

## Verification

`swift test` covers UI-independent behavior when run through the full Xcode toolchain. Tests never call ElevenLabs. Follow [`docs/ROADMAP.md`](docs/ROADMAP.md) for parser validation, core type-checking, Xcode builds, isolated UI tests, and manual acceptance.
