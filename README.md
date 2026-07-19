# Scriber

Scriber is a local-first transcription product with separate platform implementations in one repository.

- [`apps/macos`](apps/macos) contains the active, primary native macOS menu-bar dictation app built with Swift, SwiftUI, and AppKit.
- [`apps/electron`](apps/electron) contains the archived Electron/Next.js implementation retained as a foundation and feature reference for possible Windows and Linux work.

The two applications are self-contained. There is no root JavaScript package and no shared runtime layer.

## Native macOS app

Open `apps/macos/ScriberDictate.xcodeproj` with Xcode 27 beta, or run its credit-free core tests from the repository root:

```bash
swift test --package-path apps/macos
```

See [`apps/macos/README.md`](apps/macos/README.md) for setup and build details.

## Electron app

Run its credit-free checks from its own directory:

```bash
cd apps/electron
npm ci
npm run lint
npm test
npm run build
```

Do not run `npm run test:e2e` during normal verification because it can contact ElevenLabs and consume API credit.
