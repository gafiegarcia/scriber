# Scriber

Scriber is a local-first transcription product. Its active implementation is a
native macOS menu-bar dictation app built with Swift, SwiftUI, and AppKit.

## Repository

- [`apps/macos`](apps/macos) contains the active native app.
- [`apps/electron`](apps/electron) is the frozen `0.6.0` Electron/Next.js
  implementation, retained as a feature reference and possible foundation for
  future Windows or Linux work.

The implementations are self-contained. There is no root JavaScript package or
shared runtime layer.

The native line continues the product version after Electron `0.6.0`. The Xcode
project is the source of truth for the bundle build number. See the
[changelog](CHANGELOG.md) for released snapshots and the
[versioning policy](docs/VERSIONING.md) for how versions, builds, and tags differ.

## Native macOS app

See the [native README](apps/macos/README.md) for prerequisites, building,
verification, installation, and first launch. Required behavior and the current
stable-release gates live under [`apps/macos/docs`](apps/macos/docs).

## License

Original Scriber source code and documentation are copyright © 2026 Gafie
Garcia and licensed under the [GNU General Public License, version 3 or
later](LICENSE).

Third-party components retain their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The GPL does not grant
trademark rights in the Scriber name or logo; see [COPYRIGHT.md](COPYRIGHT.md).
