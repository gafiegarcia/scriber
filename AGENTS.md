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

## Workflow

- Before changing native behavior, read `apps/macos/docs/PRODUCT_SPEC.md` and the relevant part of `apps/macos/docs/ROADMAP.md`. Consult `DEVELOPMENT_LOG.md` only when historical context is useful.
- Use the toolchain and verification commands documented in `apps/macos/README.md` and `apps/macos/docs/ROADMAP.md`.
- Update the roadmap when milestones or release gates change. Add only meaningful completed work or verification results to the development log.
- Make an incremental local commit after each coherent, verified change. Do not push or publish unless Gaf explicitly asks.
- Never use `rm`; use `trash`. If `trash` is unavailable, ask before permanently deleting anything.
