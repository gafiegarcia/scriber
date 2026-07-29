# AGENTS.md — Scriber

## Scope

- `apps/macos` is the active native app. Ignore the archived `apps/electron` implementation unless the user explicitly asks about it.
- Preserve the native Swift/SwiftUI/AppKit architecture; do not add Electron or a web renderer.

## Native invariants

- Keep the ElevenLabs key only in Scriber's dedicated Keychain item; never log or persist it elsewhere.
- Automated tests/checks must not contact ElevenLabs or consume API credit—request a manual check by the user instead when truly needed.
- App Sandbox remains disabled while global shortcuts and cross-app Accessibility insertion are core features.

## Verification

- **Do not add a UI test suite.** Not because the project lacks one by accident — the bar is a specific regression a package test provably cannot catch.
- Run the routine pass in `apps/macos/docs/AUTOMATED_CHECKS.md`. Run its launch smoke check after any change to startup, the pill, or an `NSViewRepresentable`; it has caught a main-thread wedge no test did. Run it exactly as written, or its `kill` can land on the installed app.
- **Checking the running app is encouraged.** Use a computer-use tool, with the capture restricted to Scriber so other applications are excluded. If you are Claude, do not start one before asking for explicit permission; Claude's computer-use tool moves the real pointer so it will get interrupted by the user if you don't give a heads-up.
- **End a session by proposing manual checks.** Name the few items from `apps/macos/docs/MANUAL_CHECKS.md` that match what actually changed. Never ask for the whole file to be run, and never spend API credit without asking first.
- **Finish native work by shipping it.** Bump the build, build Release, install to `/Applications`, then run the sweep in `apps/macos/README.md`. Scriber is in daily use; do not leave a verified change in a build directory.

## Workflow

- Before changing native behavior, read `apps/macos/docs/PRODUCT_SPEC.md`. Read `apps/macos/docs/PASTE_ENGINE.md` before changing cross-app text delivery. Use `apps/macos/README.md` for setup, building, and installation.
- Keep each document to one job: `PRODUCT_SPEC.md` defines required behavior, `ROADMAP.md` lists unbuilt work by target version, `MANUAL_CHECKS.md` and `AUTOMATED_CHECKS.md` hold checks, and `PASTE_ENGINE.md` records the paste architecture.
- **Docs describe the present, never the past.** No changelogs, session notes, findings, or "why we removed X" in any doc. Git commits and tag messages are the engineering history; `CHANGELOG.md` carries user-relevant tagged releases. If a rationale changes what someone does next, state it as an instruction; if it explains a decision already made, it belongs in the commit that made it.
- Comments earn their place by saying what the code cannot: a platform quirk, a non-obvious ordering, a `Known and unfixed:` note. Do not restate the code, label sections, or explain what something *used to be*.
- Every roadmap item names a target version (`## v0.7.1`, `## v0.8.0`, `## Long-term`). Do not park work in an unscheduled pile. Something broken that nobody plans to fix is not a roadmap item — put a `Known and unfixed:` comment on the code that owns it.
- Versioning policy: `docs/VERSIONING.md`. Before tagging, run the automated pass, the applicable manual checks, and confirm no credentials, recordings, history, or build output ship.
- Do not push or publish unless explicitly asked.
- `CLAUDE.md` is a symlink to this file. Apply edits to `AGENTS.md`.

## Vibe-coding, ownership, and assuming a more active role

- Scriber is a fully vibe-coded project, meaning all of the code are written by GPT and Claude models.
- Because of that, be proactive in suggesting changes and improvements, as well as voicing opinions.
- LLMs like you tend to fix things by adding things and not substracting things, but a healthy development process always includes some sort of deletion to a certain degree. If you genuinely believe that an overhaul, code deletion/simplification, or even a redesign—of some parts, or the entirety of the app—is the best path forward for the app and beneficial for me, the user of this app, please suggest so. Ideas are always welcomed—we can always discuss.
- Existing code is evidence of past decisions not a constraint nor immutable truth about what the app will be.
- The user is asking you for help with coding—you can ask for help from the user too when stuck. Remember that there are tasks where human involvement can be either mandatory or make the process 10x more efficient.
