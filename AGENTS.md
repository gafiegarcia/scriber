# AGENTS.md — Scriber

## Repository

Scriber contains two self-contained implementations under `apps/`. The native macOS app in `apps/macos` is the active flagship. The Electron/Next.js app in `apps/electron` is an archived cross-platform implementation and possible Windows/Linux foundation.

Read `apps/macos/PROJECT_PLAN.md` before changing the native app; it contains the original user outline, locked decisions, milestones, and progress notes.

## Rules

- Never use `rm`. Use `trash` for normal deletion; if unavailable, ask before permanently deleting anything.
- Keep `apps/macos/PROJECT_PLAN.md` current after meaningful native milestones or verification.
- Preserve the native Swift/SwiftUI/AppKit architecture in `apps/macos`. Do not introduce Electron, a web renderer, or a local server into the native app.
- Keep the implementations self-contained. Do not describe code as shared until a real language-neutral boundary exists.
- Keep the ElevenLabs key in the dedicated Keychain item and never log or persist it elsewhere.
- Normal automated tests must never make an ElevenLabs request or consume API credit.
- Successful dictation audio is deleted only after the transcript is saved. Failed/interrupted audio remains available for retry.
- App Sandbox is intentionally disabled for v0.1 because global event interception and cross-app Accessibility insertion are core features.

## Toolchain

- Target: arm64 macOS 27
- Language: Swift 6
- Full toolchain: Xcode 27 beta
- Open `apps/macos/ScriberDictate.xcodeproj` to build the app.
- `Package.swift` intentionally contains only the UI-independent core and its credit-free tests; the application is an Xcode target because it needs an app bundle, Info.plist, entitlements, SwiftUI, and SwiftData.

Command Line Tools 27 on this machine are incomplete: SwiftUI/SwiftData macro plugins and parts of the Testing runtime are missing from their expected paths. Xcode 27 beta is installed at `/Applications/Xcode-beta.app`; use it directly or select it as the active command-line toolchain. The complete app passes an unsigned Debug build. Signing and UI/hardware verification remain manual.

## Verification

```bash
swiftc -frontend -parse apps/macos/ScriberDictate/*.swift apps/macos/ScriberDictateCore/*.swift apps/macos/ScriberDictateTests/*.swift
swiftc -module-cache-path apps/macos/.build/module-cache -typecheck apps/macos/ScriberDictateCore/CoreModels.swift apps/macos/ScriberDictateCore/ScribeClient.swift
swift test --package-path apps/macos
```

Use Xcode 27 beta for Debug and Release builds and execute the hardware acceptance checklist in `apps/macos/PROJECT_PLAN.md` from a stable app path.

## Git Workflow

- Make incremental local commits throughout development.
- Commit each coherent change set after its relevant build/tests pass and before starting the next change set.
- Keep commit messages specific to the behavior changed.
- Do not push or publish commits unless Gaf explicitly asks.
