# Scriber

Scriber is a local-first transcription product with separate platform implementations in one repository.

- [`apps/macos`](apps/macos) contains the active, primary native macOS menu-bar dictation app built with Swift, SwiftUI, and AppKit.
- [`apps/electron`](apps/electron) contains the archived Electron/Next.js implementation retained as a foundation and feature reference for possible Windows and Linux work.

The two applications are self-contained. There is no root JavaScript package and no shared runtime layer.

## Version status

The active native app is alpha-stage Scriber `0.7.0` build `2`, continuing the product lineage from the archived Electron app's `0.6.0`. The Swift rewrite and clean native identity do not reset the product version. Development builds remain untagged until a specific test snapshot is intentionally frozen; see the [versioning policy](docs/VERSIONING.md).

## Native macOS app

Open `apps/macos/Scriber.xcodeproj` with Xcode 27 beta, or run its credit-free core tests from the repository root:

```bash
swift test --package-path apps/macos
```

See [`apps/macos/README.md`](apps/macos/README.md) for setup and build details. Native requirements, current release gates, and historical progress are separated under [`apps/macos/docs`](apps/macos/docs). Product-wide references are indexed in [`docs`](docs).

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

## License

Original Scriber source code and documentation are copyright © 2026 Gafie Garcia and licensed under the [GNU General Public License, version 3 or later](LICENSE).

Third-party components and assets retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The GPL does not grant permission to use the Scriber name or logo as trademarks or to imply endorsement of a modified version. See [COPYRIGHT.md](COPYRIGHT.md) for the scope and trademark boundary.
