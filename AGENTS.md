# AGENTS.md — Scriber

## Scope

- Scriber is one native macOS app, built at the repository root. Preserve the Swift/SwiftUI/AppKit architecture; do not add Electron or a web renderer, and do not reintroduce a per-platform directory for a second app that does not exist.

## API Keys

- Keep the ElevenLabs key only in Scriber's dedicated Keychain item.
- Tests/checks that contact ElevenLabs or consume API credit require the user's permission — request a manual check instead when needed.

## Verification

- Run the routine pass in `docs/AUTOMATED_CHECKS.md`. Run its launch smoke check after any change to startup, the pill, or an `NSViewRepresentable`; it has caught a main-thread wedge no test did. Run it exactly as written, or its `kill` can land on the installed app.
- **A claim about what the app shows is read from the running app, never inferred from a build that succeeded.** Compiling proves the code is valid, not that it does what was intended, and the gap is widest where SwiftUI contributes what no file in this repository names — a menu item, a command, a default. Reach for the cheapest reader that answers the actual question: the accessibility tree via `osascript` settles menus and window titles without computer-use, and `AUTOMATED_CHECKS.md` carries the command. Report what it returned, and say plainly when nothing was read.
- **Checking the running app is encouraged.** Use a computer-use tool when available. If you are Claude, do not start one before asking for explicit permission; Claude's computer-use tool moves the real pointer so it will get interrupted by the user if you don't give a heads-up.
- **Do not add a UI test suite.** Not because the project lacks one by accident — the bar is a specific regression a package test cannot catch.
- **List out manual checks the user needs to do to verify the work before concluding the session.** Name the few items from `docs/MANUAL_CHECKS.md` that match what actually changed.
- **A check that reads the menu bar starts by quitting every Scriber.** The installed app and any test build put identical marks up there with nothing to tell them apart, so a check can be run against the wrong one. Say so whenever you propose one — the command is in both checks documents.
- **Finish native work by shipping it.** Refer to the `/wrap-up` skill. Bump the build, build Release, install to `/Applications`, then run the sweep in `docs/BUILDING.md`. Scriber is in daily use; do not leave a verified change in a build directory.

## Workflow

- Before changing native behavior, read `docs/PRODUCT_SPEC.md`. Read `docs/PASTE_ENGINE.md` before changing cross-app text delivery. Use `docs/BUILDING.md` for setup, building, and installation.
- Keep each document to one job: `PRODUCT_SPEC.md` defines required behavior, `ROADMAP.md` lists unbuilt work by target version, `MANUAL_CHECKS.md` and `AUTOMATED_CHECKS.md` hold checks, `PASTE_ENGINE.md` records the paste architecture, `BUILDING.md` covers building locally, and `RELEASING.md` covers publishing a download.
- **Do not hard-wrap prose in Markdown.** Write one line per paragraph and let editors soft-wrap it to whatever width the reader has. Code blocks, tables, and ASCII diagrams keep their literal line breaks.
- **Docs describe the present, never the past.** No changelogs, session notes, findings, or "why we removed X" in any doc. Git commits and tag messages are the engineering history; `CHANGELOG.md` carries user-relevant changes, under `Unreleased` until their version is tagged. If a rationale changes what someone does next, state it as an instruction; if it explains a decision already made, it belongs in the commit that made it.
- A comment says only what code and docs cannot: a platform quirk, a number no API reports, a warning against repeating a mistake, `Known and unfixed:`. Never restate code or defend a settled decision.
- Docs cite code as `File.swift:N`, and any commit that changes a file's line count moves those references. Re-point them in the same commit: extract every `File.swift:N` from `docs/` and print the line it now names, rather than trusting the number that was right when it was written.
- Every roadmap item names a target version (`## v0.8.1`, `## v0.9.0`, `## Long-term`). Do not park work in an unscheduled pile. Something broken that nobody plans to fix is not a roadmap item — put a `Known and unfixed:` comment on the code that owns it.
- Versioning policy: `docs/VERSIONING.md`. Before tagging, agents run the automated pass and propose the applicable manual checks for Gaf to run; also confirm no credentials, recordings, history, or build output ship.
- Follow Conventional Commits, using Angular's type set with no custom types added. Add a scope only when a commit is confined to one subsystem (`fix(paste):`); there is one app, so never scope by platform.
- Merges into `main` are fast-forward only: rebase the branch onto `main` first when `--ff-only` refuses, and merge locally rather than from GitHub's pull request buttons. Tag releases on `main` after the merge lands, never on the branch — a rebase gives the branch's commits new identities, and a tag made beforehand names one that never reaches `main`.
- Do not push or publish unless explicitly asked.
- `CLAUDE.md` is a symlink to this file. Apply edits to `AGENTS.md`.

## AI Collaboration

- The user is asking you for help with coding—you can ask for help from the user too when stuck. Remember that there are tasks where human involvement can be either mandatory or make the process 10x more efficient.
