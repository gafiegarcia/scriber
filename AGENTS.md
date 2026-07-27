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

- **Never start the XCUITest suite unprompted** — it seizes Gaf's pointer and keyboard for its whole duration. Ask, or leave it to him. Package tests, builds, `build-for-testing`, and bumping and installing a build need no permission; do not stop to ask for those.
- The suite runs with services disabled and no Accessibility trust, so it covers the SwiftUI shell only. Never treat its failures as evidence about dictation, insertion, shortcuts, or credentials. Read `apps/macos/docs/TESTING.md` before acting on one.
- **Never take a full-screen `screencapture`.** It puts Gaf's own windows and files into the transcript. To look at the app, use `apps/macos/Tools/window-shot.swift`, which captures one named app's window and nothing else. The menu bar is not a window and is a manual check.
- Run the launch smoke check in `TESTING.md` after any change that touches startup, the pill, or an `NSViewRepresentable`. It has caught a main-thread wedge that no test did.

## Workflow

- Before changing native behavior, read `apps/macos/docs/PRODUCT_SPEC.md` and the relevant part of `apps/macos/docs/ROADMAP.md`. Consult `DEVELOPMENT_LOG.md` only when historical context is useful.
- Use the toolchain and verification commands documented in `apps/macos/README.md` and `apps/macos/docs/TESTING.md`.
- Keep the four native docs to their jobs, and resist letting the roadmap reabsorb them: `ROADMAP.md` is what is left to do, `ACCEPTANCE.md` is what a person must check by hand, `TESTING.md` is what a machine checks and what it cannot, `DEVELOPMENT_LOG.md` is what happened. Findings and post-mortems belong in the last two, not the first.
- Update the roadmap when milestones or release gates change. Add only meaningful completed work or verification results to the development log.
- Do not push or publish unless Gaf explicitly asks.
- Never use `rm`; use `trash`. If `trash` is unavailable, ask before permanently deleting anything.
- `CLAUDE.md` is a symlink to this file. Apply edits to `AGENTS.md`; tools that refuse to write through symlinks will reject the `CLAUDE.md` path.
