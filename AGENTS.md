# AGENTS.md — Scriber

## Scope

- Scriber is one native macOS app, built at the repository root. Preserve the Swift/SwiftUI/AppKit architecture; do not add Electron or a web renderer, and do not reintroduce a per-platform directory for a second app that does not exist.

## API Keys

- Keep the ElevenLabs key only in Scriber's dedicated Keychain item.
- Tests/checks that contact ElevenLabs or consume API credit require the user's permission — request a manual check instead when needed.

## Verification

- Run `./scripts/check.sh` after any change to Swift. Run `./scripts/smoke.sh` after any change to startup, the pill, or an `NSViewRepresentable`; it has caught a main-thread wedge no test did. `docs/AUTOMATED_CHECKS.md` explains what each script proves and what it cannot.
- **A claim about what the app shows is read from the running app, never inferred from a build that succeeded.** Compiling proves the code is valid, not that it does what was intended, and the gap is widest where SwiftUI contributes what no file in this repository names — a menu item, a command, a default. Reach for the cheapest reader that answers the actual question; **Driving the app without computer-use** in `AUTOMATED_CHECKS.md` says what the accessibility tree can and cannot settle. Use a computer-use tool only for what the tree cannot answer. Report what was read, and say plainly when nothing was.
- **A check that runs is not a check that answers.** Before reporting one as done, say what it would have looked like had it failed. A check with no such answer — a setting toggled with nothing observable following, a row that would have survived on age alone whatever the code did — proves nothing and must not be counted.
- **A screen recording is measurable evidence, not just an illustration.** When the user reports something that flickers, stretches, or happens too fast to describe, ask for a recording and read it frame by frame, as **Reading a screen recording** in `AUTOMATED_CHECKS.md` describes. It answers shape and duration questions the accessibility tree cannot.
- **Do not add a UI test suite.** The bar for one is a specific regression a package test cannot catch.
- **Installing a verified change is its own action, not the last step of anything.** Bump the build, build Release, run `./scripts/inspect-release.sh`, and install per `docs/BUILDING.md` whenever a verified change should reach the app the user actually uses — mid-session included. Scriber is in daily use; do not leave a verified change in a build directory waiting for a session to end.

## Workflow

- Before changing native behavior, read `docs/PRODUCT_SPEC.md`. Read `docs/PASTE_ENGINE.md` before changing cross-app text delivery. Use `docs/BUILDING.md` for setup, building, and installation.
- Keep each document to one job: `PRODUCT_SPEC.md` defines required behavior, `ROADMAP.md` names committed work and links each item to the Notion task holding its detail, `MANUAL_CHECKS.md` holds the checks only the user can run, `AUTOMATED_CHECKS.md` explains what the scripts prove, `PASTE_ENGINE.md` records the paste architecture, `BUILDING.md` covers building locally, and `RELEASING.md` covers publishing a download. `scripts/` holds every check a machine can run. A rule belongs in exactly one of them; naming the owner is not restating it.
- **Do not hard-wrap prose in Markdown.** Write one line per paragraph and let editors soft-wrap it to whatever width the reader has. Code blocks, tables, and ASCII diagrams keep their literal line breaks.
- **Docs describe the present, never the past.** No changelogs, session notes, findings, or "why we removed X" in any doc. Git commits and tag messages are the engineering history; `CHANGELOG.md` carries user-relevant changes, under `Unreleased` until their version is tagged. If a rationale changes what someone does next, state it as an instruction; if it explains a decision already made, it belongs in the commit that made it.
- **Every inline comment you write or edit carries one of five tags:**

    ```swift
    // Platform: a macOS, SwiftUI or AppKit behavior no API documents
    // Measured: a number, and what produced it
    // Do not: a mistake already made once, so it is not made again
    // Legacy: what this defends against, and whether that state is still reachable
    // Known and unfixed: a defect nobody plans to fix
    ```

    A `Legacy:` comment must say whether the live code can still produce the state it guards against; without that, the guard reads as evidence of a live bug. Don't delete an untagged comment on sight: if it holds something a tag covers, tag it; delete it only when it restates the code or no longer matches it.

- **A doc comment (`///`) is governed by length, not by tag**: what the symbol is for, plus any parameter whose meaning is not already in its name.
- **Docs cite code by symbol, never by line**: `` `discardExpiredDictations` (`DictationHistoryMaintenance.swift`) ``, qualified by type where the same name appears in two files. Where the interesting line is a statement rather than a declaration, cite the declaration enclosing it; where it is a string the user sees, quote the string. This holds in Notion task bodies too, which no script can reach. `./scripts/check-docs.sh` is the gate.
- Roadmap items live under `## Upcoming` or `## Long-term` and are one line: a title and a link to the Notion task holding the detail. Something broken that nobody plans to fix is not a roadmap item — put a `Known and unfixed:` comment on the code that owns it.
- Versioning policy: `docs/VERSIONING.md`. Before tagging, run `./scripts/check.sh` and confirm no credentials, recordings, history, or build output ship.
- Follow Conventional Commits, using Angular's type set with no custom types added. Add a scope only when a commit is confined to one subsystem (`fix(paste):`); there is one app, so never scope by platform.
- **In a worktree, run `git log --oneline HEAD..main` before bumping the build.** If it returns anything, rebase onto `main` and bump past the number `main` now holds. Several sessions run against this repository at once, so a worktree goes stale within the hour — a build made from a stale one installs over the app in daily use and silently removes whatever landed on `main` meanwhile, while both branches claim the same build number. Neither the build nor `inspect-release.sh` can see this; only that command can.
- Merges into `main` are fast-forward only: rebase the branch onto `main` first when `--ff-only` refuses, and merge locally rather than from GitHub's pull request buttons. Tag releases on `main` after the merge lands, never on the branch — a rebase gives the branch's commits new identities, and a tag made beforehand names one that never reaches `main`.
- Do not push or publish unless explicitly asked.
- `CLAUDE.md` is a symlink to this file. Apply edits to `AGENTS.md`.
- Skills are intentionally gitignored.

## AI Collaboration

- Ask the user rather than pushing on alone: when a decision is theirs to make, when two readings of a request would produce different work, or when a second attempt at the same problem has failed. Spending a turn on the question beats spending a session on the wrong answer.
