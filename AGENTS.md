# AGENTS.md — Scriber

## Scope

- `apps/macos` is the active native app. Ignore the archived `apps/electron` implementation unless Gaf explicitly asks about it.
- Keep both implementations self-contained. Do not describe code as shared without a real language-neutral boundary.
- Preserve the native Swift/SwiftUI/AppKit architecture; do not add Electron, a web renderer, or a local server.

## Native invariants

- Keep the ElevenLabs key only in Scriber's dedicated Keychain item; never log or persist it elsewhere.
- Automated tests must never contact ElevenLabs or consume API credit.
- Delete dictation audio only after its transcript is saved. Preserve failed or interrupted audio for retry.
- App Sandbox remains disabled while global shortcuts and cross-app Accessibility insertion are core features.

## Verification

- **There is no UI test suite.** The XCUITest target was removed in `v0.7.0`; `apps/macos/docs/ROADMAP.md` records why and what stopped being covered. Do not reintroduce one because a project is expected to have it — the bar is a specific regression a package test provably cannot catch. Package tests, builds, and bumping and installing a build need no permission; do not stop to ask for those.
- **Finish native work by shipping it to him.** Bump the build, build Release, install to `/Applications`, then run the sweep in `apps/macos/README.md`. Gaf uses Scriber daily and wants the installed binary current; do not leave a verified change sitting in a build directory.
- Any `--ui-testing` launch runs with services disabled and no Accessibility trust, so it shows the SwiftUI shell only. Never treat what it does as evidence about dictation, insertion, shortcuts, or credentials. Read `apps/macos/docs/AUTOMATED_CHECKS.md` before drawing a conclusion from one.
- **Looking at the running app is available and encouraged** — `request_access` for `Scriber` alone, then drive it with the computer-use tools. Every other app is excluded from the capture at the compositor level, and the pointer and keyboard are available, so hover states, menus, and the menu bar are all reachable rather than manual. It moves the *real* pointer, so do not start one while Gaf is typing. The one thing to avoid outright is a plain full-screen `screencapture`, which puts his own windows and files into the transcript. See `apps/macos/docs/AUTOMATED_CHECKS.md`.
- **The launch smoke check must never surface a second Scriber.** Run it exactly as written in `AUTOMATED_CHECKS.md`: an absolute `APP_PATH`, `--ui-testing-no-activate`, and the `before_pid` guard. A relative path fails silently and the `kill` then lands on Gaf's installed app.
- Run the launch smoke check in `AUTOMATED_CHECKS.md` after any change that touches startup, the pill, or an `NSViewRepresentable`. It has caught a main-thread wedge that no test did.

## Workflow

- Before changing native behavior, read `apps/macos/docs/PRODUCT_SPEC.md` and the relevant part of `apps/macos/docs/ROADMAP.md`. Read `apps/macos/docs/PASTE_ENGINE.md` before changing cross-app text delivery.
- Use `apps/macos/README.md` for setup, building, and installation. Use `apps/macos/docs/AUTOMATED_CHECKS.md` for machine verification and its safety boundaries.
- Keep each document to one job: `PRODUCT_SPEC.md` defines required behavior, `ROADMAP.md` tracks remaining work and release gates, `MANUAL_CHECKS.md` covers human verification, `AUTOMATED_CHECKS.md` covers machine verification and its limits, and `PASTE_ENGINE.md` records the current paste architecture.
- Git commits are the engineering history. Do not create or rebuild a development diary. Put only user-relevant tagged release history in the root `CHANGELOG.md`.
- Update the roadmap when milestones or release gates change. Do not copy the current bundle build into prose; the Xcode project is its source of truth.
- Do not push or publish unless Gaf explicitly asks.
- Never use `rm`; use `trash`. If `trash` is unavailable, ask before permanently deleting anything.
- `CLAUDE.md` is a symlink to this file. Apply edits to `AGENTS.md`; tools that refuse to write through symlinks will reject the `CLAUDE.md` path.
