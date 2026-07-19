# Scriber Dictate

Scriber Dictate is a native macOS menu-bar dictation app powered by ElevenLabs Scribe v2. It records only while a configured shortcut is active, stores the API key in Keychain, saves transcript history locally with SwiftData, and inserts finished text through macOS Accessibility.

The initial `0.1.0` release is a personal Apple-silicon beta targeting macOS 27.

## Current prerequisites

- macOS 27
- Xcode 27 beta (the Command Line Tools package alone does not contain the SwiftUI/SwiftData macro plugins)
- An ElevenLabs API key with Speech to Text access

## Build

1. Install Xcode 27 beta and select it in Xcode Settings → Locations → Command Line Tools.
2. Open `ScriberDictate.xcodeproj`.
3. Choose the `ScriberDictate` scheme and the local Mac destination.
4. Configure an Apple Development signing team if Xcode requests one.
5. Build and run.

For stable Accessibility and Launch at Login permissions, archive a Release build and keep `Scriber Dictate.app` in `/Applications` rather than repeatedly moving it.

## First launch

Onboarding asks for:

- The ElevenLabs key, stored under a dedicated Keychain service.
- Microphone access for recording.
- Accessibility access for global shortcuts and cross-app text insertion.
- Optional Launch at Login registration.

Default shortcuts are Hold `Fn` and Toggle `Fn-Space`. If macOS still performs a configured Globe/Fn action during hardware testing, set the Globe/Fn action to “Do Nothing” in System Settings.

## Verification

`swift test` covers non-UI behavior once run through the full Xcode toolchain. Tests never call ElevenLabs. See `PROJECT_PLAN.md` for the complete acceptance matrix and live progress notes.
