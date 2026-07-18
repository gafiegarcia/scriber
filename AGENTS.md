# AGENTS.md — Scriber Dictate

## Product

Scriber Dictate is a native macOS menu-bar dictation app. Read `PROJECT_PLAN.md` before making changes; it contains the original user outline, locked decisions, milestones, and progress notes.

## Rules

- Never use `rm`. Use `trash` for normal deletion; if unavailable, ask before permanently deleting anything.
- Keep `PROJECT_PLAN.md` current after meaningful milestones or verification.
- Preserve the native Swift/SwiftUI/AppKit architecture. Do not introduce Electron, a web renderer, or a local server.
- Keep the ElevenLabs key in the dedicated Keychain item and never log or persist it elsewhere.
- Normal automated tests must never make an ElevenLabs request or consume API credit.
- Successful dictation audio is deleted only after the transcript is saved. Failed/interrupted audio remains available for retry.
- App Sandbox is intentionally disabled for v0.1 because global event interception and cross-app Accessibility insertion are core features.

## Toolchain

- Target: arm64 macOS 27
- Language: Swift 6
- Full toolchain: Xcode 27 beta
- Open `ScriberDictate.xcodeproj` to build the app.
- `Package.swift` intentionally contains only the UI-independent core and its credit-free tests; the application is an Xcode target because it needs an app bundle, Info.plist, entitlements, SwiftUI, and SwiftData.

Command Line Tools 27 on this machine are incomplete: SwiftUI/SwiftData macro plugins and parts of the Testing runtime are missing from their expected paths. Xcode 27 beta is installed at `/Applications/Xcode-beta.app`; use it directly or select it as the active command-line toolchain. The complete app passes an unsigned Debug build. Signing and UI/hardware verification remain manual.

## Verification

```bash
swiftc -frontend -parse ScriberDictate/*.swift ScriberDictateCore/*.swift ScriberDictateTests/*.swift
swiftc -module-cache-path .build/module-cache -typecheck ScriberDictateCore/CoreModels.swift ScriberDictateCore/ScribeClient.swift
swift test
```

Use Xcode 27 beta for Debug and Release builds and execute the hardware acceptance checklist in `PROJECT_PLAN.md` from a stable app path.

## Git Workflow

- Make incremental local commits throughout development.
- Commit each coherent change set after its relevant build/tests pass and before starting the next change set.
- Keep commit messages specific to the behavior changed.
- Do not push or publish commits unless Gaf explicitly asks.
