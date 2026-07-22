# Scriber Monorepo Migration Record

Status: completed and archived. This file preserves the migration handoff and decisions as historical context; it is not the current task list. See [`../../apps/macos/docs/ROADMAP.md`](../../apps/macos/docs/ROADMAP.md) for active native work.

## Purpose

Turn the native macOS repository into the new canonical `Scriber` repository,
while retaining the old Next.js/Electron application as a history-free source
snapshot for possible Windows/Linux releases and future feature translation.

This file is a handoff for a fresh Codex task after the local project folder was
renamed from `scriber-dictate` to `scriber`.

## Current State (2026-07-20)

### New canonical repository

- Local path: `/Users/gafiegarcia/Developer/scriber`
- Branch: `main`
- HEAD before this icon-integration change: `531eac7` (`Add original Scriber icon candidates`)
- Working tree: tracked tree clean at that checkpoint; Gaf's later Figma-edited exports and Icon Composer document supplied the integration inputs
- Remote: private `origin` at `https://github.com/gafiegarcia/scriber.git`
- History: the native Swift/SwiftUI history plus the history-free Electron snapshot commits; no legacy Git graph was imported
- Current native app version: `0.7.0` build `2`
- Current native maturity: alpha-stage and untagged; see `docs/VERSIONING.md`
- Current native product/bundle identity: Scriber / `com.gafiegarcia.scriber`

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
- The final title-bar changes are included in source commit `fda278b`; the legacy working tree was clean when archived and pushed.

### GitHub namespace

- The old GitHub repository has already been renamed to `scriber-legacy`.
- Existing legacy clones should point explicitly to `scriber-legacy.git`.
- The new private `gafiegarcia/scriber` repository now exists. Reusing the name
  disables GitHub's redirect from the old name to `scriber-legacy`, which is
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
├── LICENSE                      # GNU GPL v3-or-later project license
├── AGENTS.md                    # Repository-wide contributor/agent rules
├── docs/                        # Product documentation and archived plans
│   └── archive/
│       └── MONOREPO_MIGRATION.md
└── apps/
    ├── macos/
    │   ├── README.md
    │   ├── docs/
    │   │   ├── PRODUCT_SPEC.md
    │   │   ├── ROADMAP.md
    │   │   └── DEVELOPMENT_LOG.md
    │   ├── Package.swift
    │   ├── Scriber.xcodeproj/
    │   ├── Scriber/
    │   ├── ScriberCore/
    │   ├── ScriberCoreTests/
    │   └── ScriberUITests/
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

Migration progress as of 2026-07-20:

- Phase 0 complete: repository identities and remotes verified.
- Phase 1 complete: legacy source changes verified, archived at `b13274d`, tagged `electron-legacy-final`, and pushed to `gafiegarcia/scriber-legacy`.
- Phase 2 complete: native relocation committed as `f5282c3`; the app builds and its credit-free tests pass from `apps/macos`.
- Phase 3 complete: the tracked Electron snapshot from `b13274d` was imported without legacy history in commit `48db860`; lint, 73 credit-free tests, and the production build pass.
- Phase 4 complete: `gafiegarcia/scriber` exists as a private repository, local `origin` points to it, and local/remote `main` matched at `48db860` after the initial push.
- Phase 5 complete: the approved identity plan was committed as `fa5b56d`, the Scriber product identity as `ce10f39`, and the exhaustive native project/module rename as `3a95cdf`.
- Phase 6 repository licensing and icon integration are complete: original Scriber code and documentation use `GPL-3.0-or-later`, and the documented Figma-edited icon is connected through `AppIcon.icon`. Unsigned Debug and Release builds compile matching `AppIcon.icns` resources plus Aqua, Dark Aqua, and tintable asset renditions. Signed live acceptance remains open.

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

3. Read `AGENTS.md`, `apps/macos/docs/PRODUCT_SPEC.md`, the relevant roadmap sections, and this file.
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
   the root. Keep native-only documentation and the native README under
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

Implemented product version: `0.7.0`, continuing from Electron Scriber `0.6.0`
and representing the substantial native-app pivot. The imported Electron
snapshot remains at its historical `0.6.0` unless active Electron development resumes.

This is a product-line version, not a codebase-age counter. Rewriting the app in
Swift and choosing a clean native bundle identity do not reset Scriber to
`0.1.0`. The durable decision is recorded in `docs/VERSIONING.md`.

Separate these concepts:

- User-facing app name: changed from **Scriber Dictate** to **Scriber**.
- Xcode project, target, module, source, and test names: changed to the exhaustive `Scriber` map in a dedicated verified commit.
- Marketing version: changed to `0.7.0`.
- Build number: changed to `2`.
- Prerelease state: alpha-stage; not yet represented by a frozen release tag.
- Bundle identifier: changed to `com.gafiegarcia.scriber` with an explicit clean-reset decision.

#### Bundle-identifier decision (resolved)

Changing `com.gafiegarcia.scriber-dictate` to `com.gafiegarcia.scriber` creates
a clean long-term identity, and macOS treats it as a different application.
The decision explicitly covers:

- Accessibility and Microphone permissions
- Launch at Login registration
- Data Protection Keychain access group and the existing ElevenLabs key
- SwiftData history location
- UserDefaults/onboarding/preferences
- any installed Electron app already using `com.gafiegarcia.scriber`

Gaf explicitly chose the one-time clean reset: no history, preferences,
onboarding, pending audio, Launch at Login, or Keychain credential is migrated.
The API key will be re-entered through the dedicated Keychain flow; it must never
be logged, exported, or copied elsewhere.

### Phase 6: Documentation and release boundaries

1. Update the root README and app-specific READMEs with the final names, paths,
   platform status, and build commands.
2. Consolidate repository-wide agent instructions into root `AGENTS.md`; retain
   app-specific instructions only where they genuinely differ.
3. Update the native roadmap when milestones or release gates change, and keep
   meaningful historical results in the development log.
4. Apply the product-line version and release-tag policy in
   `docs/VERSIONING.md`. Platform implementations retain their historical
   package versions unless their active product line advances.
5. Keep ordinary development commits untagged. The first intentionally frozen
   native testing snapshot may use `v0.7.0-alpha.1`; create final `v0.7.0` only
   when the corresponding stable release state is real.

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
swiftc -frontend -parse apps/macos/Scriber/*.swift apps/macos/ScriberCore/*.swift apps/macos/ScriberCoreTests/*.swift apps/macos/ScriberUITests/*.swift
swiftc -module-cache-path apps/macos/.build/module-cache -typecheck apps/macos/ScriberCore/CoreModels.swift apps/macos/ScriberCore/ScribeClient.swift apps/macos/ScriberCore/CredentialStore.swift
swift test --package-path apps/macos
```

Use Xcode 27 beta for Debug and Release builds of
`apps/macos/Scriber.xcodeproj` with the `Scriber` scheme. Preserve the existing credit-free test
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

## Current Handoff

The repository and native identity migration are implemented. Remaining work is
deliberately separate:

1. Complete live visual acceptance of the compiled icon in default, dark, tinted, Dock, Finder, and small-size contexts; source and unsigned build verification already pass.
2. Produce a signed Release build at a stable path and complete fresh onboarding, Keychain, permissions, Launch at Login, shortcut, insertion, Dictation history, Dock, and pill-activation acceptance checks.
3. Generate artifact-specific third-party notices before any public binary release.
4. Do not push additional commits unless Gaf explicitly requests it.
