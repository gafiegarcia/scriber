# AGENTS.md — Scriber

## Scope

- Scriber is one native macOS app, built at the repository root. Preserve the Swift/SwiftUI/AppKit architecture; do not add Electron or a web renderer, and do not reintroduce a per-platform directory for a second app that does not exist.

## API Keys

- Keep the ElevenLabs key only in Scriber's dedicated Keychain item.
- Tests/checks that contact ElevenLabs or consume API credit require the user's permission — request a manual check instead when needed.

## Verification

- Run `./scripts/check.sh` after any change to Swift. Run `./scripts/smoke.sh` after any change to startup, the pill, or an `NSViewRepresentable`; it has caught a main-thread wedge no test did. `docs/AUTOMATED_CHECKS.md` explains what each script proves and what it cannot.
- **A claim about what the app shows is read from the running app, never inferred from a build that succeeded.** Compiling proves the code is valid, not that it does what was intended, and the gap is widest where SwiftUI contributes what no file in this repository names — a menu item, a command, a default. Reach for the cheapest reader that answers the actual question: the accessibility tree via `osascript` settles menus, window geometry and resize limits, tab selection, sheets, and pressing a control by identifier — all without computer-use, and all on a build addressed by pid so the user's installed copy can stay open. `AUTOMATED_CHECKS.md` carries the commands under **Driving the app without computer-use**, and names what it cannot answer: colour, translucency, glass, and spacing judged by eye are the user's or a computer-use tool's, never the tree's. Report what it returned, and say plainly when nothing was read.
- **A check that runs is not a check that answers.** Before reporting one as done, say what it would have looked like had it failed. A check with no such answer — a setting toggled with nothing observable following, a row that would have survived on age alone whatever the code did — proves nothing and must not be counted.
- **A screen recording is measurable evidence, not just an illustration.** When the user reports something that flickers, stretches, or happens too fast to describe, ask for a recording and read it frame by frame — `ffmpeg -i clip.mov -fps_mode passthrough f%03d.png`, then a `crop`/`scale`/`tile` filter to lay every frame out as one contact sheet, and `ffprobe -show_entries frame=pts_time` for the timing. A screen recording captures a frame only when the screen changes, so a gap in those timestamps is itself a reading: it says nothing was drawn, and a state that lasted one frame is a state that was drawn. This answers shape and duration questions the accessibility tree cannot, and it is what finally settled a pill geometry bug that five readings of the source had got wrong.
- **Checking the running app is encouraged.** Use a computer-use tool when available. If you are Claude, do not start one before asking for explicit permission; Claude's computer-use tool moves the real pointer so it will get interrupted by the user if you don't give a heads-up.
- **Do not add a UI test suite.** Not because the project lacks one by accident — the bar is a specific regression a package test cannot catch.
- **Shipping is its own action, not the last step of anything.** Bump the build, build Release, run `./scripts/inspect-release.sh`, and install per `docs/BUILDING.md` whenever a verified change should reach the app the user actually uses — mid-session included. Scriber is in daily use; do not leave a verified change in a build directory waiting for a session to end.

## Workflow

- **Edit files with the Edit and Write tools, never with `sed` or a Python replace script.** A script that fails partway leaves nothing written while its earlier replacements look like they succeeded, which has produced confident reports of edits that never happened. Delete this line once the harness stops recommending shell edits in Auto mode.
- Before changing native behavior, read `docs/PRODUCT_SPEC.md`. Read `docs/PASTE_ENGINE.md` before changing cross-app text delivery. Use `docs/BUILDING.md` for setup, building, and installation.
- Keep each document to one job: `PRODUCT_SPEC.md` defines required behavior, `ROADMAP.md` names committed work and links each item to the Notion task holding its detail, `MANUAL_CHECKS.md` holds the checks only the user can run, `AUTOMATED_CHECKS.md` explains what the scripts prove, `PASTE_ENGINE.md` records the paste architecture, `BUILDING.md` covers building locally, and `RELEASING.md` covers publishing a download. `scripts/` holds every check a machine can run. A rule belongs in exactly one of them; naming the owner is not restating it.
- **Do not hard-wrap prose in Markdown.** Write one line per paragraph and let editors soft-wrap it to whatever width the reader has. Code blocks, tables, and ASCII diagrams keep their literal line breaks.
- **Docs describe the present, never the past.** No changelogs, session notes, findings, or "why we removed X" in any doc. Git commits and tag messages are the engineering history; `CHANGELOG.md` carries user-relevant changes, under `Unreleased` until their version is tagged. If a rationale changes what someone does next, state it as an instruction; if it explains a decision already made, it belongs in the commit that made it.
- **Every inline comment you write or edit carries one of five tags.** What is already in this code is not a model for what to write: nearly all of it predates this rule.

    ```swift
    // Platform: a macOS, SwiftUI or AppKit behavior no API documents
    // Measured: a number, and what produced it
    // Do not: a mistake already made once, so it is not made again
    // Legacy: what this defends against, and whether that state is still reachable
    // Known and unfixed: a defect nobody plans to fix
    ```

    `Legacy:` carries an obligation the others do not: say **whether the live code can still produce** the state being defended against. A guard whose comment explains its rule but not its provenance reads as evidence of a live bug, and has already produced a confident report of one against correct code.

    An existing untagged comment is not a licence to delete on sight. Delete one when it restates the code it sits on, or while you are already editing that code and it no longer describes what is there. If it carries something a tag covers — a measured number, a platform behavior, a mistake worth not repeating — **give it the tag instead of deleting it.** Much of what is untagged is the only record of a finding: the rule about a separator landing a point from the day label's own is a measurement nothing else holds.

- **A doc comment (`///`) is governed by length, not by tag**: what the symbol is for, plus any parameter whose meaning is not already in its name.
- **Docs cite code by symbol, never by line**: `` `discardExpiredDictations` (`DictationHistoryMaintenance.swift`) ``, qualified by type where the same name appears in two files. Where the interesting line is a statement rather than a declaration, cite the declaration enclosing it; where it is a string the user sees, quote the string. This holds in Notion task bodies too, which no script can reach. `./scripts/check-docs.sh` is the gate.
- Roadmap items live under `## Upcoming` or `## Long-term` and are one line: a title and a link to the Notion task holding the detail. Something broken that nobody plans to fix is not a roadmap item — put a `Known and unfixed:` comment on the code that owns it.
- Versioning policy: `docs/VERSIONING.md`. Before tagging, run the automated pass and confirm no credentials, recordings, history, or build output ship.
- Follow Conventional Commits, using Angular's type set with no custom types added. Add a scope only when a commit is confined to one subsystem (`fix(paste):`); there is one app, so never scope by platform.
- Merges into `main` are fast-forward only: rebase the branch onto `main` first when `--ff-only` refuses, and merge locally rather than from GitHub's pull request buttons. Tag releases on `main` after the merge lands, never on the branch — a rebase gives the branch's commits new identities, and a tag made beforehand names one that never reaches `main`.
- Do not push or publish unless explicitly asked.
- `CLAUDE.md` is a symlink to this file. Apply edits to `AGENTS.md`.
- Skills are intentionally gitignored.

## AI Collaboration

- The user is asking you for help with coding—you can ask for help from the user too when stuck. Remember that there are tasks where human involvement can be either mandatory or make the process 10x more efficient.
