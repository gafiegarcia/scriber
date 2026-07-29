# AGENTS.md — Scriber

## Scope

- `apps/macos` is the active native app. Ignore the archived `apps/electron` implementation unless Gaf explicitly asks about it.
- Preserve the native Swift/SwiftUI/AppKit architecture; do not add Electron, a web renderer, or a local server.

## Native invariants

- Keep the ElevenLabs key only in Scriber's dedicated Keychain item; never log or persist it elsewhere.
- Automated tests must never contact ElevenLabs or consume API credit.
- Delete dictation audio only after its transcript is saved. Preserve failed or interrupted audio for retry.
- App Sandbox remains disabled while global shortcuts and cross-app Accessibility insertion are core features.

## Verification

- **Do not add a UI test suite.** Not because the project lacks one by accident — the bar is a specific regression a package test provably cannot catch.
- Run the routine pass in `apps/macos/docs/AUTOMATED_CHECKS.md`. Run its launch smoke check after any change to startup, the pill, or an `NSViewRepresentable`; it has caught a main-thread wedge no test did. Run it exactly as written, or its `kill` can land on Gaf's installed app.
- **Looking at the running app is encouraged** — `request_access` for `Scriber` alone, then drive it with computer-use. Other apps are excluded from the capture, so menus, hover states, and the menu bar are all reachable. It moves the *real* pointer, so never start one while Gaf is typing.
- **End a session by proposing manual checks.** Name the few items from `apps/macos/docs/MANUAL_CHECKS.md` that match what actually changed. Never ask him to run the whole file, and never spend API credit without asking first.
- **Finish native work by shipping it.** Bump the build, build Release, install to `/Applications`, then run the sweep in `apps/macos/README.md`. Gaf uses Scriber daily; do not leave a verified change in a build directory.

## Workflow

- Before changing native behavior, read `apps/macos/docs/PRODUCT_SPEC.md`. Read `apps/macos/docs/PASTE_ENGINE.md` before changing cross-app text delivery. Use `apps/macos/README.md` for setup, building, and installation.
- Keep each document to one job: `PRODUCT_SPEC.md` defines required behavior, `ROADMAP.md` lists unbuilt work by target version, `MANUAL_CHECKS.md` and `AUTOMATED_CHECKS.md` hold checks, and `PASTE_ENGINE.md` records the paste architecture.
- **Docs describe the present, never the past.** No changelogs, session notes, findings, or "why we removed X" in any doc. Git commits and tag messages are the engineering history; `CHANGELOG.md` carries user-relevant tagged releases. If a rationale changes what someone does next, state it as an instruction; if it explains a decision already made, it belongs in the commit that made it.
- Every roadmap item names a target version. Do not park work in an unscheduled pile.
- Versioning policy: `docs/VERSIONING.md`. Before tagging, run the automated pass, the applicable manual checks, and confirm no credentials, recordings, history, or build output ship.
- Do not push or publish unless Gaf explicitly asks.
- Never use `rm`; use `trash` (`/usr/bin/trash`). If unavailable, ask before permanently deleting anything.
- `CLAUDE.md` is a symlink to this file. Apply edits to `AGENTS.md`.
