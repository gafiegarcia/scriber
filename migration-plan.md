# Scriber Monorepo Migration Plan

## Purpose

Turn the native macOS repository into the new canonical `Scriber` repository,
while retaining the old Next.js/Electron application as a history-free source
snapshot for possible Windows/Linux releases and future feature translation.

This file is a handoff for a fresh Codex task after the local project folder was
renamed from `scriber-dictate` to `scriber`.

## Current State (2026-07-19)

### New canonical repository

- Local path: `/Users/gafiegarcia/Developer/scriber`
- Branch: `main`
- HEAD: `80a64dd` (`Submit API keys with Return`)
- Working tree: clean before this plan file was added
- Remote: none
- History: the native Swift/SwiftUI Scriber Dictate development history
- Current app version: `0.1.0`
- Current product/bundle identity: Scriber Dictate / `com.gafiegarcia.scriber-dictate`

### Legacy repository

- Local path: `/Users/gafiegarcia/Developer/scriber-legacy`
- GitHub remote: `https://github.com/gafiegarcia/scriber-legacy.git`
- Branch: `main`, tracking `origin/main`
- Final archived commit: `b13274d` (`chore: archive Electron implementation`)
- Final source-change commit: `fda278b` (`fix: prevent native title-bar overlap`)
- Annotated archival tag: `electron-legacy-final`
- Existing release tag: `v0.6.0` (plus older historical tags)
- This history contains an early personal-email identity and must not be merged,
  fetched into, or pushed from the new public repository.
- The legacy working tree currently has three uncommitted title-bar changes:
  `CHANGELOG.md`, `desktop/main.cjs`, and `src/app/layout.tsx`.

### GitHub namespace

- The old GitHub repository has already been renamed to `scriber-legacy`.
- Existing legacy clones should point explicitly to `scriber-legacy.git`.
- The name `gafiegarcia/scriber` can now be used for a new repository. Reusing
  it disables GitHub's redirect from the old name to `scriber-legacy`, which is
  intentional here.

## Locked Migration Decisions

1. `/Users/gafiegarcia/Developer/scriber` is the canonical repository.
2. Preserve the native repository's Git history.
3. Do not merge, subtree-add, fetch, or otherwise import the legacy Git history.
4. Import only a committed, tracked snapshot of the legacy application.
5. Never copy the legacy `.git` directory, local recordings, environment files,
   build output, packaged DMGs, caches, or other untracked developer data.
6. Keep both implementations visibly separated under `apps/`.
7. Do not add a root `package.json` merely to make the repository look like a
   JavaScript monorepo. The Electron application owns its package files.
8. Treat product renaming, bundle-identifier migration, stored-data migration,
   and the monorepo file move as separate coherent changes.
9. Normal automated tests must not contact ElevenLabs or consume API credit.
10. Do not delete `scriber-legacy` after importing it. Keep it private and
    available as the historical archive until the new repository is verified.

## Proposed Repository Layout

```text
scriber/
├── README.md                    # Product and repository overview
├── LICENSE                      # Root project license, after Gaf confirms it
├── AGENTS.md                    # Repository-wide contributor/agent rules
├── migration-plan.md            # This temporary migration handoff
├── docs/                        # Cross-platform/product documentation
└── apps/
    ├── macos/
    │   ├── README.md
    │   ├── PROJECT_PLAN.md
    │   ├── Package.swift
    │   ├── ScriberDictate.xcodeproj/
    │   ├── ScriberDictate/
    │   ├── ScriberDictateCore/
    │   ├── ScriberDictateTests/
    │   └── ScriberDictateUITests/
    └── electron/
        ├── README.md
        ├── CHANGELOG.md
        ├── ROADMAP.md
        ├── package.json
        ├── package-lock.json
        ├── desktop/
        ├── src/
        ├── test/
        ├── scripts/
        └── other tracked files required by that application
```

`apps/macos` is the flagship and active focus. `apps/electron` is the archived
cross-platform implementation and potential Windows/Linux foundation. A future
shared directory should only be added when something is genuinely consumed by
both implementations. Swift and TypeScript code should not be described as
"shared logic" until there is an actual language-neutral boundary such as a
schema, fixture suite, or behavioral specification.

## Execution Plan

Migration progress as of 2026-07-19:

- Phase 0 complete: repository identities and remotes verified.
- Phase 1 complete: legacy source changes verified, archived at `b13274d`, tagged `electron-legacy-final`, and pushed to `gafiegarcia/scriber-legacy`.
- Phase 2 complete: native relocation committed as `f5282c3`; the app builds and its credit-free tests pass from `apps/macos`.
- Phase 3 verified: the tracked Electron snapshot from `b13274d` is present without legacy history; lint, 73 credit-free tests, and the production build pass; commit pending.

### Phase 0: Re-anchor the fresh Codex task

1. Open `/Users/gafiegarcia/Developer/scriber` as the Codex project.
2. Confirm the repository identity before editing:

   ```bash
   pwd
   git rev-parse --show-toplevel
   git status --short --branch
   git log -1 --oneline --decorate
   git remote -v
   ```

3. Read `AGENTS.md`, `PROJECT_PLAN.md`, and this file completely.
4. Confirm `/Users/gafiegarcia/Developer/scriber-legacy` still exists and its
   `origin` points to `gafiegarcia/scriber-legacy.git`.
5. Do not push or publish anything without Gaf's explicit request.

### Phase 1: Resolve and freeze the legacy snapshot

1. Inspect the three uncommitted legacy changes. They appear to be one coherent
   Electron title-bar fix, but verify them and run the relevant legacy tests.
2. Ask Gaf before discarding them. Prefer committing them in the legacy
   repository if they are valid, so the imported snapshot comes from a clean,
   reproducible commit rather than a dirty working tree.
3. Record the final legacy commit ID in this document.
4. Optionally create an annotated archival tag such as
   `electron-legacy-final` in the legacy repository. Do not treat it as a new
   semantic release unless its package version and release state justify that.
5. Audit the tracked snapshot before import:

   ```bash
   git -C /Users/gafiegarcia/Developer/scriber-legacy status --short
   git -C /Users/gafiegarcia/Developer/scriber-legacy ls-files
   ```

6. Ensure sensitive or machine-local files are not tracked. In particular,
   exclude `.env.local`, `.local/`, build caches, `dist-desktop/`, FFmpeg build
   output, screenshots that are not intentional documentation, and `.DS_Store`.

### Phase 2: Establish the monorepo structure

Make this a file-movement-only phase. Do not rename the application or change
its bundle identifier at the same time.

1. Create `apps/macos` and move the native project into it with `git mv` so Git
   can recognize the relocation.
2. Keep the root-level repository documents that apply to the whole product at
   the root. Move the native-only `PROJECT_PLAN.md` and native README into
   `apps/macos`.
3. Create a concise root README that explains:
   - Scriber is one product with two platform implementations.
   - The native macOS app is active and primary.
   - The Electron app is retained for Windows/Linux work and feature reference.
   - How to build and test each app from its own directory.
4. Update `.gitignore` for both ecosystems without accidentally ignoring source
   or required Xcode project files.
5. Update paths inside documentation and scripts affected by the move.
6. Verify the native project from its new path before committing.
7. Commit this as a coherent native-layout change.

### Phase 3: Import the Electron application without history

1. Export only the tracked tree from the frozen legacy commit using
   `git archive`; do not copy the repository directory wholesale.
2. Extract that archive into `apps/electron`.
3. Do not bring legacy root-governance files into the new root automatically.
   Review `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, license files, and general docs
   individually. Keep app-specific documentation inside `apps/electron`.
4. Adjust paths that assumed the Electron project lived at repository root.
   Likely areas include Electron Builder configuration, packaging scripts,
   standalone Next.js packing, FFmpeg scripts, and documentation.
5. Run the Electron app's credit-free checks from `apps/electron`.
6. Commit the result as one clearly labeled snapshot import, for example:

   ```text
   Import legacy Electron app snapshot
   ```

The snapshot commit should mention the source legacy commit ID in its body, but
must not connect the two Git histories.

### Phase 4: Create and connect the new GitHub repository

1. On GitHub, create a new empty repository named `gafiegarcia/scriber`.
   Do not initialize it with a README, license, or `.gitignore`.
2. Add it as `origin` to `/Users/gafiegarcia/Developer/scriber`.
3. Verify that `origin` points to the new repository and that the legacy clone
   still points to `scriber-legacy`.
4. Review all local branches and tags before the first push. Do not push any
   legacy refs or personal-email history.
5. Push only after Gaf explicitly asks.

### Phase 5: Adopt the unified product name and version

Do this only after both apps build in their monorepo locations.

Recommended product version: `0.7.0`, continuing from Electron Scriber `0.6.0`
and representing the substantial native-app pivot. Keep the imported Electron
snapshot at its historical `0.6.0` unless active Electron development resumes.

Separate these concepts:

- User-facing app name: change from **Scriber Dictate** to **Scriber**.
- Xcode project/target/module names: may remain `ScriberDictate` initially to
  avoid a risky mechanical rename, then be cleaned up in a dedicated change.
- Marketing version: change the active native app to `0.7.0`.
- Build number: increment appropriately.
- Bundle identifier: requires an explicit migration decision.

#### Bundle-identifier decision required

Changing `com.gafiegarcia.scriber-dictate` to `com.gafiegarcia.scriber` creates
a clean long-term identity, but macOS may treat it as a different application.
Before changing it, decide how to handle:

- Accessibility and Microphone permissions
- Launch at Login registration
- Data Protection Keychain access group and the existing ElevenLabs key
- SwiftData history location
- UserDefaults/onboarding/preferences
- any installed Electron app already using `com.gafiegarcia.scriber`

Because this is still an early personal beta, accepting a one-time reset and
re-entering the API key may be simpler than implementing a full migration. That
must be Gaf's explicit choice. Never log, export, or copy the API key outside the
dedicated Keychain flow.

### Phase 6: Documentation and release boundaries

1. Update the root README and app-specific READMEs with the final names, paths,
   platform status, and build commands.
2. Consolidate repository-wide agent instructions into root `AGENTS.md`; retain
   app-specific instructions only where they genuinely differ.
3. Update the native `PROJECT_PLAN.md` after each meaningful milestone and
   verification result.
4. Add a root changelog or release notes policy only after deciding whether
   versions apply product-wide or independently per app.
5. Do not create `v0.7.0` until the corresponding release state is real. A
   pre-migration/native archival tag can use a descriptive prerelease name
   instead of pretending that an unreleased build is final.

## Verification Checklist

### Repository hygiene

- `git status` is clean after each coherent commit.
- `git log --all` contains only the native repository history plus new snapshot
  commits; it does not contain the legacy repository's commit graph.
- No `.git` directory exists below `apps/electron`.
- No environment files, API keys, recordings, local notes, packaged apps, DMGs,
  caches, or machine-specific build output are tracked.
- Root documentation makes the two implementations and their status obvious.

### Native macOS app

Run from the new paths, updating commands as needed:

```bash
swiftc -frontend -parse apps/macos/ScriberDictate/*.swift apps/macos/ScriberDictateCore/*.swift apps/macos/ScriberDictateTests/*.swift
swiftc -module-cache-path apps/macos/.build/module-cache -typecheck apps/macos/ScriberDictateCore/CoreModels.swift apps/macos/ScriberDictateCore/ScribeClient.swift
swift test --package-path apps/macos
```

Use Xcode 27 beta for Debug and Release builds of
`apps/macos/ScriberDictate.xcodeproj`. Preserve the existing credit-free test
guarantees. Hardware permissions, shortcuts, Accessibility insertion, Keychain,
and real transcription remain manual acceptance checks.

### Electron app

Run inside `apps/electron`:

```bash
npm ci
npm run lint
npm test
npm run build
```

Do not run `npm run test:e2e` during ordinary migration verification because it
can make a real ElevenLabs request and consume credit.

## Completion Criteria

The migration is complete when:

1. The new repository has a clear root and two self-contained app directories.
2. Native and Electron credit-free tests/builds pass from their new locations.
3. The Electron code is traceable to a recorded legacy commit but no legacy Git
   objects or sensitive history are present.
4. The new GitHub `gafiegarcia/scriber` remote is connected correctly.
5. `scriber-legacy` remains intact and points to its renamed remote.
6. Product naming/version changes are documented and verified separately.
7. Nothing has been pushed until Gaf explicitly authorizes publication.

## First Prompt for the Fresh Codex Task

Suggested prompt:

> Read `AGENTS.md`, `PROJECT_PLAN.md`, and `migration-plan.md` completely. Verify
> that this is `/Users/gafiegarcia/Developer/scriber` at native HEAD `80a64dd`
> and that `/Users/gafiegarcia/Developer/scriber-legacy` points to the legacy
> GitHub remote. Then execute the migration incrementally from Phase 1. Preserve
> native history, import the Electron app only as a history-free tracked
> snapshot, run credit-free verification after each coherent change, make local
> commits, and do not push without my explicit permission.
