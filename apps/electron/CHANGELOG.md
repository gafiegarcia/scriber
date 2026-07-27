# Changelog

> **Archived at 0.6.0.** This changelog belongs to the frozen Electron
> implementation. Current native release history is in the repository
> [`CHANGELOG.md`](../../CHANGELOG.md).

## Unreleased

### Fixed

- **Native title-bar controls no longer overlap the Scriber logo.** The macOS app reserves a dedicated draggable title-bar band for the traffic-light controls, while the browser layout remains unchanged.

## v0.6.0-local — 2026-07-17

This release marks Scriber's pivot from a terminal-served web app to a proper Apple-silicon macOS desktop app. The local-first web UI and private backend remain under the hood, but colleagues now launch Scriber like any other Mac app—without opening Terminal.

### Changed

- **Scriber now packages as a real macOS desktop app with a hidden private backend.** The Electron shell starts the Next.js standalone server as a managed utility process, opens a native window with no terminal, enforces single-instance and macOS close/reopen behavior, kills the backend on quit, injects a random per-launch token into renderer API requests, rejects unauthenticated loopback API calls, permits only audio capture, and blocks unsafe navigation. The arm64 bundle contains the verified redistributable FFmpeg tools, strict Electron fuses, and no downloaded nonfree or mismatched native binaries. Clean-profile launch, window lifecycle, API isolation, shutdown, and a real short ElevenLabs transcription have been smoke-tested.
- **The colleague-facing DMG command is now release-gated.** `npm run desktop:make:mac` refuses to build unless a Developer ID signing source and one complete Apple notarization credential set are configured. Release builds enable hardened runtime and electron-builder notarization, then verify the mounted DMG contents, app and nested FFmpeg signatures, stapled ticket, and Gatekeeper assessment. `desktop:package:mac` remains the explicitly unsigned local-development build; `desktop:make:mac:local` creates a clearly labeled, mount-verified internal-beta DMG without weakening the public-release gate.
- **Developer ID certificates installed normally in macOS Keychain are auto-detected.** Release signing no longer requires redundant `CSC_NAME` configuration, while CI can still use `CSC_LINK`/`CSC_NAME`. An explicit project release-mode flag ensures local beta builds remain unsigned even on a developer Mac that has a certificate installed.
- **The sole Mac download is labeled for humans, not build tooling.** Apple-silicon-only DMGs use `Apple-Silicon` instead of `arm64` in the filename, while bundle verification still enforces the real arm64 architecture internally.
- **Transcript bodies are deliberately read-only for the internal beta.** Removed the transcript Edit UI and timestamp-reconciliation prototype. Note PATCH now accepts only title and tags and rejects content, timing metadata, and unknown fields, preserving the original transcript as the source of truth. Users can copy or export clean TXT, Markdown, or SRT and edit that copy elsewhere.
- **Data backup/restore is now complete instead of note-only JSON.** Settings → Data downloads a streaming, compressed, versioned Scriber archive containing exact note files, audio, dictionary, transcription defaults, model, and theme. Restore offers Merge (skip existing note/audio conflicts) or Replace All (transactional directory swap with rollback), restores original timestamps/metadata, and reloads the UI afterward. Archives are fully staged and validated before mutation: path traversal, links, duplicate/unknown entries, oversized payloads, malformed notes/config, count mismatches, and embedded API keys are rejected. The Keychain secret is always excluded. Added end-to-end storage tests for round-trip merge/replace, audio bytes, preferences, permissions, traversal rejection, and secret rejection.
- **ElevenLabs keys now use macOS Keychain instead of plaintext config.** Existing `config.json` keys migrate automatically with a no-data-loss sequence: Scriber writes Keychain first and only then atomically scrubs the file. Keychain wins if both copies exist; locked/unavailable Keychains surface an explicit error and never trigger a plaintext fallback. Linux and Windows retain their `0600` config-file storage. Keychain items are scoped to the resolved `SCRIBER_HOME`, secrets travel to `security(1)` over stdin rather than argv, and config APIs still expose only `hasApiKey` plus the storage kind. Startup config requests now share one serialized, process-cached Keychain access, preventing repeated macOS password prompts and duplicate legacy-key migrations. Added focused tests for migration, concurrency, conflicts, failures, replacement/removal, command arguments, and file permissions.
- **Desktop Settings is now one scrollable page.** All six sections render together with more breathing room, while the left category sidebar acts as a table of contents: selecting a category scrolls to it, the active state follows manual scrolling, URL fragments survive reloads, and reduced-motion preferences are respected. Mobile retains its existing stacked layout.
- **Mac-app FFmpeg builds now have a pinned, redistributable path.** Added a repeatable source-build pipeline for official FFmpeg 8.1.2, producing Apple-silicon tools with an LGPL 2.1+ configuration and no GPL, nonfree, version-3-only, networking, device, hardware-acceleration, or external-library components. Verification gates inspect architecture, linkage, configuration, native AAC/MOV support, and a real video-to-M4A conversion; generated artifacts carry the license, exact source hash, configuration, and build metadata. The runtime now accepts `SCRIBER_FFMPEG_PATH` / `SCRIBER_FFPROBE_PATH` so the signed desktop wrapper can select its app resources.

### Fixed

- **Authentic ElevenLabs audio-event tokens now survive storage and backup validation.** `audio_event` plus optional per-token `logprob` are represented in both response and stored transcript types, audio events participate in synced playback/export, and complete backup restore accepts the token shapes already present in real Scriber notes.
- **The Mac app no longer asks for the login password to access “Scriber-desktop Safe Storage.”** Scriber does not use browser accounts or cookie-backed state, so its Electron window now uses an ephemeral, cache-free session and the cookie-encryption fuse is disabled. This removes the unnecessary Keychain item and repeated password prompts seen when ad-hoc development builds changed code identity; the actual ElevenLabs key remains separately protected by Scriber's explicit Keychain adapter.
- **Bundled `ffprobe` is now native on Apple silicon.** Replaced the legacy `ffprobe-static@3.1.0` package, whose published `darwin/arm64` file was actually an Intel executable, with exact-pinned `@derhuerst/ffprobe-static@5.3.0`. Updated the shared runtime resolver, CLI bundler externals, and standalone packer for the new package layout; production packaging now preserves executable bits and both static packages' license files. Added a macOS arm64 regression test that reads the Mach-O CPU header so Rosetta can no longer mask a mislabeled binary.

### Known distribution requirements

- **The npm-downloaded static binaries must never enter `Scriber.app`.** Both report `--enable-nonfree` and are not legally redistributable. The desktop packager now consumes only the verified `.ffmpeg/darwin-arm64` artifacts and rejects the downloaded packages; a public release still needs Developer ID signing/notarization and the corresponding FFmpeg source/build information published beside the download.

## v0.5.9-local — 2026-06-13

Major dependency compatibility pass and Turbopack dev-server default.

### Changed

- **`npm run dev` now uses Turbopack.** Next.js 16 already defaults to Turbopack, so the dev script no longer forces `--webpack`. Kept explicit escape hatches: `npm run dev:turbo` forces Turbopack and `npm run dev:webpack` forces the old Webpack path for file-watching or debugging fallback.
- **Major packages upgraded where compatible.** Updated TypeScript `6.0.3`, Lucide React `1.18.0`, and Open `11.0.0`.

### Fixed

- **`127.0.0.1` dev UI hydrates correctly.** Added `localhost` and `127.0.0.1` to Next's dev-origin allowlist. Without this, opening the Turbopack dev server via `127.0.0.1:7337` could render the page shell while blocking a Next dev resource, leaving client-side controls inert.

### Held

- **ESLint 10 deferred.** `eslint-config-next@16.2.9` still depends on `eslint-plugin-react@7.37.5`, whose peer range stops at ESLint 9. Under ESLint 10, lint crashes while loading `react/display-name`, so Scriber stays on ESLint `9.39.4` until the Next/React ESLint plugin stack supports ESLint 10 cleanly.
- **Node 25 types deferred.** Scriber still declares `node >=20`, so `@types/node` stays on the Node 20 line to prevent accidentally using newer Node APIs that would break supported installs.

## v0.5.8-local — 2026-06-13

NPM maintenance catch-up after a quiet stretch.

### Security

- **Dev-tooling audit cleared.** Refreshed the lockfile so `esbuild` resolves to `0.28.1`, `tsx` resolves to `4.22.4`, and the vulnerable transitive `brace-expansion` copy resolves to `5.0.6`. `npm audit` now reports zero vulnerabilities.

### Changed

- **Patch/minor dependency refresh.** Updated the safe non-major set: Base UI `1.5.0`, Tailwind `4.3.1`, Tailwind PostCSS plugin `4.3.1`, `tailwind-merge` `3.6.0`, React/React DOM `19.2.7`, Next.js and `eslint-config-next` `16.2.9`, plus current React/Node type packages.
- **Tailwind kept as build-time tooling.** Let npm remove the duplicate runtime `tailwindcss` dependency entry; Scriber only needs Tailwind during build/dev through the existing dev dependency.

### Held

- **Major-version upgrades deferred.** Left ESLint `10`, TypeScript `6`, Lucide React `1.x`, Open `11`, and Node types `25` for separate compatibility passes.

## v0.5.7-local — 2026-05-27

Dev-server failure clarity.

### Fixed

- **Stale browser shell now says when the server is gone.** Added a lightweight `/api/health` watcher in the app shell. If the terminal process is stopped while the browser still has Scriber cached, the UI now shows an explicit server-offline banner instead of silently leaving API-backed features broken.
- **LAN dev URL works cleanly.** `next.config.ts` now allows the machine's active local IPv4 addresses as Next dev origins, so opening the `Network:` URL printed by `npm run dev` no longer causes Next.js to block internal dev resources.

## v0.5.6-local — 2026-05-27

Transcribe screen cleanup and shortcut polish.

### Changed

- **Transcribe page creation methods simplified.** Removed the visible **Type** entry points from mobile and desktop; the Transcribe screen now focuses on upload and recording. Existing text notes remain supported in the Notes list/detail views.
- **Home-page attribution removed.** Dropped the "Powered by ElevenLabs Scribe v2" footer copy from the Transcribe page; the ElevenLabs attribution remains tucked into Settings -> About.
- **Desktop drop zone tightened.** Reduced the desktop hero drop zone height so the page feels less oversized now that the secondary actions are simpler.

### Added

- **`T` global shortcut for New transcription.** Pressing `T` navigates back to the Transcribe page, while focused fields, dialogs, buttons, and links keep their normal typing/interaction behavior. The desktop New transcription button now shows the `T` hint next to the label.

## v0.5.5-local — 2026-05-24

Notes UX polish on the recently-redesigned desktop sidebar, plus a guard against a long-standing silent-fail in the note Edit flow. Also a pass on the global design tokens — stock shadcn grays were too close to the background in both modes; bumped contrast across the board.

### Changed

- **Design-token contrast bumped across light and dark themes.** Stock shadcn tokens were perceptually too close to the background — `--border` at `oklch(0.922 0 0)` against `oklch(1 0 0)` is roughly 1.15:1, so borders, inputs, hover fills, and focus rings were all near-invisible. Pushed every gray away from its respective extreme in both modes. **Light:** `--border` 0.922 → 0.85, `--input` → 0.83, `--ring` 0.708 → 0.63, `--muted-foreground` 0.556 → 0.50, `--card`/`--popover` 1.0 → 0.99, `--sidebar` 0.985 → 0.975, filled states (`--muted`/`--accent`/`--secondary` and their sidebar counterparts) 0.97 → 0.95. **Dark:** `--border` and `--input` swapped from alpha-based (`oklch(1 0 0 / 10%)` and `/ 15%` — these mathematically can't reach high contrast on a near-black surface) to solid `oklch(0.38 0 0)` and `oklch(0.44 0 0)`; `--ring` 0.556 → 0.65, `--muted-foreground` 0.708 → 0.75, `--card`/`--popover` 0.205 → 0.22, `--sidebar` 0.205 → 0.18, filled states 0.269 → 0.32. Chart vars and brand-coloured tokens (`--destructive`, `--sidebar-primary`) left alone.
- **Desktop notes-list pane reads as one surface with the note detail.** Dropped `bg-sidebar/30` from the master-detail list pane in `notes-shell.tsx` — the `border-r` still separates the columns visually. The freed `/30` tint moved to the desktop sidebar (was `bg-sidebar/60`), keeping the chrome a touch subtler now that the inner borders carry their own weight.

### Added

- **Tag filter on the desktop sidebar.** Mobile NotesList has had horizontal tag chips below the search bar for a while; `DesktopListPane` was built independently and never got one, so filtering by tag was unreachable on desktop. Added the missing chip row, sized down to fit the 320 px sidebar (`px-2.5 / py-0.5 / text-[11px]` vs mobile's `px-3 / py-1 / text-xs`), reusing the same active/inactive styling.

### Fixed

- **Sort dropdowns now show `cursor-pointer`.** Both the mobile NotesList and the desktop sidebar sort `SelectTrigger` had no default cursor, so the chip felt non-interactive on hover. The base UI `SelectTrigger` only ships `disabled:cursor-not-allowed`, so the fix lives at the call sites.
- **Transcript width constrained on desktop.** The transcript stretched the full width of the main pane after the v0.5.0 master-detail layout, hurting readability. Wrapped the transcript (both the editing textarea and the read-only branches — `SyncedTranscript`, `DiarizedTranscript`, plaintext) in a centered `max-w-prose` (~65ch) container. Title, metadata row, tags, actions, and the sticky audio player stay full-width. Mobile is unaffected since the viewport is already narrower than 65ch.
- **Note Edit gated when word-level audio sync is active.** When `hasAudio && hasTimestamps`, the transcript renders via `SyncedTranscript` (reading `note.metadata.words`), but `handleSaveContent` only patches `note.content` — so edits visibly no-op for those notes. The proper fix (splicing edits into the `TranscriptWord[]` timeline so click-to-seek and highlighting survive the edit) is logged in ROADMAP under Bugs; this release disables the Edit button with a tooltip explaining why, so users don't hit the silent failure.

## v0.5.4-local — 2026-05-24

Desktop sidebar redesign: ⌘K is now discoverable, recent notes are one click away, and theme controls live only in Settings.

### Changed

- **Sidebar layout.** Replaced the `Transcribe` tab (redundant with the **New transcription** primary button) with a dedicated **Search notes** row that shows the `⌘K` hint and triggers the same focus-the-Notes-search behavior as the shortcut. Added a **Recents** section below **All notes** that lists the 5 newest notes with their source icons (mic for recordings, upload arrow for uploads, file icon for text) — each row links straight to `/notes/[id]` and highlights when active.
- **Settings moved to the bottom bar.** On desktop, Settings is now a gear icon in the bottom rail instead of a tab in the main nav. Active state highlights when on `/settings`. Mobile bottom tabs are unchanged.
- **Theme toggle removed from every view.** Cycling Light → Dark → System via a header/sidebar button is gone; the theme picker lives only in **Settings → Appearance**. Removed from the desktop sidebar bottom bar (replaced by the Settings gear) and the mobile top header (now just logo + Exit). `src/components/theme-toggle.tsx` deleted as fully orphaned.

### Internal

- Extracted `triggerNotesSearch(router, pathname)` from `useGlobalShortcuts` in `src/lib/hooks/use-keyboard-shortcuts.ts` so the `⌘K` keydown handler and the new sidebar **Search notes** button share one code path. The module-level `pendingFocus` flag stays private to the hook.

## v0.5.3-local — 2026-05-24

Live progress feedback for the transcribe flow, plus a build-blocking CSS fix.

### Added

- **Real-time progress in the transcribe loader.** The home-page loader no longer sits on one undifferentiated spinner — it now shows a distinct label per stage: `Uploading… NN%` (with a real progress bar driven by XHR upload events) → `Scribing…` (or `Converting & scribing…` for video uploads) → `Saving…`. The processing phase gets a live `m:ss` elapsed counter so long ElevenLabs jobs don't look frozen, plus a "Long recordings can take a few minutes." hint after 30 s. The mobile floating Upload button shows the upload `%` inline (replacing the spinner during upload) and threads the phase label through `aria-label` / `title`.

### Fixed

- **Build was broken on `main`.** Commit `3d2b429` ("chore: drop shadcn CLI as a dependency") removed the `shadcn` npm package but left `@import "shadcn/tailwind.css";` in `src/app/globals.css`, so `npm run build` and `npm run dev` both 500'd with `Can't resolve 'shadcn/tailwind.css'`. Dropped the broken import and vendored just the nine `@custom-variant data-*` definitions the shadcn UI primitives (`dialog`, `dropdown-menu`, `select`, `switch`, `alert-dialog`) actually depend on — the rest of what `shadcn/tailwind.css` shipped (accordion keyframes, `no-scrollbar`) was either unused here or already defined locally.

### Internal

- `useTranscribeFile` switched from `fetch` to `XMLHttpRequest` for `POST /api/transcribe` — fetch doesn't expose upload progress on the browser side. The abort signal is forwarded to `xhr.abort()` so Cancel still works. Phase shape changed from `idle|converting|transcribing|saving` to `idle|uploading|processing|saving`, plus new `uploadProgress`, `elapsedMs`, `activeFile`, and derived `isVideo` outputs.

## v0.5.2-local — 2026-05-22

Security dependency bump.

### Security

- **Next.js 16.2.4 → 16.2.6** — clears 13 advisories rolled up in `next@16.0.0–16.2.5` (SSRF via WebSocket upgrades, middleware/proxy bypass via segment-prefetch and dynamic route param injection, RSC and image-optimization DoS, CSP-nonce XSS, cache poisoning). `eslint-config-next` bumped in lockstep.

## v0.5.1-local — 2026-05-04

Polish and lint cleanup pass on the v0.5.0 desktop redesign.

### Fixed

- **Transcribe page (desktop)** — Record and Options are now a cohesive group below the hero drop-zone: a full-width `or` divider (with hairline rules on each side), the centered secondary Record action, and Options directly underneath. Previously Options was a separate element rendered outside `TranscribeHero` with a disconnected `mt-6` gap.
- **Notes sidebar flicker (desktop)** — Navigating from `/notes` to `/notes/[id]` no longer causes the sidebar to flash its skeleton. A new `src/app/notes/layout.tsx` makes Next.js treat the sidebar as a persistent layout segment — `DesktopListPane` and its `useNotes()` instance survive the route change instead of remounting.
- **Exit overlay not covering full viewport** — The "Scriber stopped" screen now fills the entire browser window. Previously `DesktopSidebar`'s `backdrop-blur-xl` created a `backdrop-filter` containing block that confined `position: fixed` children to the sidebar column; fixed by rendering the overlay via `createPortal` into `document.body`.

### Internal

- All ESLint errors resolved: `durationRef.current` assignment moved out of render into a sync `useEffect`; `DictionaryProvider` now uses a lazy `useState` initializer for the localStorage cache instead of calling `setState` in an effect; `use-notes` deps destructured from the `options` object so the React Compiler can correctly analyze the `useMemo` dependency array; stale `eslint-disable` directive removed from `synced-transcript.tsx`.

## v0.5.0-local — 2026-05-04

Full desktop redesign — the app now has a proper responsive layout for ≥1024 px screens without changing anything on mobile.

### Added

- **Persistent desktop sidebar** — a 240 px left sidebar (visible at `lg:` breakpoint and above) replaces the bottom tab bar on desktop. Contains the Scriber logo, a "New transcription" shortcut, Search notes, All notes, Recents, Settings, and Exit. `⌘K` focuses the Notes search flow from anywhere, and `T` returns to New transcription.
- **Transcribe page drop-zone hero** — on desktop the home page shows a large drag-and-drop zone (click or drop an audio/video file) with Record and Options as secondary actions below. Mobile shows Upload, Record, and Options.
- **Notes master-detail layout** — on desktop, `/notes` and `/notes/[id]` both render a split-pane shell: a 320 px list pane on the left (with search and sort controls) and a detail pane on the right. Selecting a note updates the detail without a full navigation. Mobile single-pane behaviour is unchanged.
- **Settings two-pane layout** — Settings on desktop mirrors macOS System Settings: a 224 px sub-sidebar with category navigation (Appearance, API Key, Transcription, Dictionary, Data, About) and a scrollable content pane showing only the active section.

### Internal

- `src/lib/hooks/use-keyboard-shortcuts.ts` — `useGlobalShortcuts()` hook + `SCRIBER_FOCUS_SEARCH_EVENT` constant powering `T` for New transcription and `⌘K` for Notes search.
- `src/lib/hooks/use-transcribe-file.ts` — file→transcribe logic extracted from `FileUpload` into a shared hook; consumed by both `FileUpload` (mobile) and `TranscribeHero` (desktop drop-zone).
- `src/components/desktop-sidebar.tsx` — persistent sidebar component; mounts `useGlobalShortcuts()`.
- `src/components/transcribe-hero.tsx` — large drop-zone with drag-over state, phase-aware progress, cancel/retry for the desktop home page.
- `src/components/notes-shell.tsx` — unified shell that branches into mobile single-pane or desktop master-detail at the `lg:` breakpoint.
- `src/components/note-detail.tsx` — back-button now `lg:hidden` (the list pane is always visible on desktop).

## v0.4.1-local — 2026-05-03

Maintenance patch — security dependency upgrades and two bug fixes.

### Security

- **next** 16.2.1 → 16.2.4 — patches a DoS via Server Components (GHSA-q4gf-8mx6-v5v3)
- **esbuild** ^0.24.2 → ^0.28.0 — patches dev-server open to cross-origin reads (GHSA-67mh-4wv8-2f99)
- **postcss** override ≥8.5.10 — forces Next.js's bundled postcss off the vulnerable nested copy (GHSA-qx2v-qp2m-jg93)

### Fixed

- Settings → About version was hardcoded as `v0.2.0`; now reads from `package.json` so it stays in sync automatically on every build.
- Dictionary section caused a React hydration mismatch on first paint — server rendered empty state while client had localStorage terms. Deferred the localStorage read to `useEffect` so both sides start from `[]`.

## v0.4.0-local — 2026-04-28

Native video input support — drop a `.mov`, `.mp4`, `.mkv`, `.webm`, `.m4v`, or `.avi` file into the web app or pipe it through `scriber transcribe`, and Scriber strips the video track locally via bundled ffmpeg before sending the audio to ElevenLabs. Uploads stay small (~30 MB/hr instead of GB-scale), `~/.scriber/audio/` only stores audio, and the in-app player no longer breaks silently on H.264-bearing containers.

### Added

- **Server-side video → audio conversion** via ffmpeg. Web flow: `/api/transcribe` materializes the upload to a temp file, runs ffprobe to detect a video stream, and (if found) re-encodes to AAC/M4A (mono 48 kHz 96 kbps with `+faststart`). The converted audio is returned to the client as base64 inside the JSON response and stored as the note's audio. The original video is never persisted.
- **CLI parity** — `scriber transcribe` accepts the same video extensions and runs the same conversion locally (no temp upload needed; reads the file path directly).
- **Bundled binaries** — `ffmpeg-static` + `ffprobe-static` are pulled at install time (~60 MB combined). If the postinstall download is blocked, Scriber falls back to a system `ffmpeg`/`ffprobe` on `PATH`. If neither is available, video uploads return a clear "Video support unavailable. Install ffmpeg…" error.
- **Phase-aware upload spinner** — the web button surfaces "Converting video to audio…" / "Transcribing…" / "Saving…" via tooltip + aria-label so the user knows what's happening on long uploads.
- **`AudioExtractError`** — non-zero ffmpeg exits surface a clean "Could not extract audio" message in both web and CLI, with the full stderr captured server-side for diagnostics.

### Internal

- New `src/lib/core/audio-extract.ts` — `hasVideoStream()`, `extractAudio()`, `writeUploadToTemp()`. Consumed by both the API route and the CLI command.
- New `src/lib/core/ffmpeg-runtime.ts` — `resolveFfmpegPaths()` (memoized, prefers bundled, falls back to `which`-resolved system binary) + `assertFfmpegAvailable()`.
- `scripts/pack-standalone.js` now explicitly copies `node_modules/ffmpeg-static/ffmpeg{,.exe}` and `node_modules/ffprobe-static/bin/<platform>/<arch>/ffprobe{,.exe}` into the standalone bundle and preserves `0o755` exec bits — Next.js's tracer follows JS imports and routinely misses native binaries reached via path-export tricks.
- `scripts/build-cli.js` marks `ffmpeg-static` and `ffprobe-static` external in the esbuild bundle so the packages' `__dirname`-based path lookup keeps resolving to the real install location at runtime.
- `/api/transcribe` `maxDuration` raised from 300s → 600s to cover multi-hour video conversions plus transcription on the same request.
- New `test/core/audio-extract.test.ts` — generates a synthetic 1s mp4 fixture (h264 + AAC, 64x64 red color + 440 Hz sine) via the bundled ffmpeg, asserts video detection + a non-empty M4A output starting with the `ftyp` magic. Skips cleanly when neither bundled nor system ffmpeg is available.

## v0.3.0-local — 2026-04-25

Adds a proper headless CLI so Scriber can plug into automation pipelines (video-clipper workflows, batch captioning, scripts) without opening a browser.

### Added

- **`scriber transcribe <file>`** — new subcommand. Transcribes an audio file and prints the result as JSON to stdout (text, word-level timestamps, language, speaker IDs when diarized). Progress and errors go to stderr.
- **Multi-format file output** via `-o <path...>`. Extension picks the format: `.json`, `.srt`, `.md`, `.txt`. Repeat targets to write multiple formats in one call: `scriber transcribe a.mp3 -o a.json a.srt a.md`.
- **Full ElevenLabs option surface** as flags: `--language`, `--diarize`, `--num-speakers`, `--tag-audio-events`, `--keyterm` (repeatable, appended to config dictionary), `--no-keyterms`, `--title`. Config defaults are used when a flag isn't passed.
- **`--no-store`** to skip the default `~/.scriber/` Note + audio copy; the transcription is only delivered via stdout / `-o`.
- **`--quiet` / `-q`** silences stderr progress for scripted use.

### Internal

- New shared module `src/lib/core/transcribe.ts` holds the ElevenLabs fetch + retry/backoff loop, consumed by both the `/api/transcribe` route and the CLI command. Routes are now thin adapters over core logic — this is the seam that the future managed-mode storage adapter will sit alongside.
- New `src/cli/` tree (entry + command + formatters) compiled to a standalone CommonJS bundle at `.scriber-cli/index.cjs` by `scripts/build-cli.js` (esbuild). The bundle is self-contained — no runtime TS loader, no external deps at CLI time.
- `prepack` now runs the CLI bundle step after the Next.js build + standalone pack.
- `esbuild` and `tsx` added as devDependencies.
- New `test/` tree using `node:test`: 22 unit tests for the four formatters, 8 CLI error-path tests that spawn `bin/scriber.js` subprocesses, and 2 gated e2e tests that hit ElevenLabs against the smallest audio file in `~/.scriber/audio/` (opt-in via `SCRIBER_E2E=1`). `npm test` runs the cheap ones in ~0.4s; `npm run test:e2e` includes the real API call.
- Two formatter bugs caught by the new tests and fixed: `md.ts` was over-quoting YAML scalars containing any dash (e.g. `my-note` → `"my-note"`), and `srt.ts` was flushing cues after the 7th word, orphaning trailing punctuation into a `","`-only cue 2. SRT now flushes at the boundary before the next incoming word, keeping punctuation attached.

## v0.2.0-local — 2026-04-21

First local-first release. Scriber is no longer a hosted PWA — it's an `npm i -g`-installable CLI that runs the web UI on `127.0.0.1`. You bring your own ElevenLabs key, notes and audio live as files under `~/.scriber/`, and nothing persists server-side.

This is an early pre-1.0 release — the core flow works end-to-end but the surface is small and there are rough edges. See [ROADMAP.md](ROADMAP.md) for what's next.

### Major changes

- **BYOK**: ElevenLabs API key entered via a first-run modal, stored in `~/.scriber/config.json`, and proxied through `/api/transcribe` on the server. Never exposed to the client.
- **Filesystem storage**: notes are one JSON file per note (`notes/<ISO-timestamp>_<shortid>.json`), audio is one file per note (`audio/…[__slug].<ext>`). Both sort chronologically by filename and are greppable / backup-friendly.
- **`scriber` CLI**: `bin/scriber.js` boots Next.js' standalone server programmatically, with port fallback (3000 → 3001 → random) and `--no-open` for headless use. Binds to `127.0.0.1` only.
- **Multi-tab sync** via `BroadcastChannel("scriber-notes")` plus revalidate-on-focus.
- **CSRF mitigation**: mutating API routes reject requests whose `Origin` header doesn't match the server host. Combined with the `127.0.0.1` bind, the server is not reachable from the network.
- **Config-backed preferences**: transcribe defaults + dictionary keyterms live in `config.json`, with localStorage as a fast-boot cache and write-through on every change.
- **Route layout flattened**: `/app/*` was collapsed to `/`, `/notes`, `/settings`. The authenticated-app namespace is gone because there's no longer any authentication.
- **Standalone packaging**: `next.config.ts` now emits `.next/standalone`; `scripts/pack-standalone.js` copies `.next/static` and `public/` into it as a `prepublishOnly` step so the published tarball is self-contained.

### Removed

- Firebase Auth, Firestore, and the `firebase` / `firebase-tools` dependencies.
- Google OAuth login, anonymous dev-bypass, and the entire `(auth)` route group.
- IndexedDB audio store (`audio-db.ts`) — replaced by filesystem audio via `/api/audio/[id]`.
- Landing page mockup (`src/app/page.tsx`), pricing mockup (`src/app/pricing/`), and `stitch_scriber_landing_desktop/` — all pre-Firebase visual direction artifacts, preserved in the `v0.1-firebase-pwa` tag.
- `PRICING.md` (credit-based pricing model is out of scope for a local BYOK tool).
- `NEXT_PUBLIC_FIREBASE_*`, `NEXT_PUBLIC_DEV_PASSWORD`, and `ELEVENLABS_API_KEY` env vars. Only `SCRIBER_HOME` (optional) remains.

### Internal

- New server module `src/lib/server/storage.ts` (guarded with `import "server-only"`) — atomic writes via tmp file + rename, lazy directory creation, orphan audio sweep on server boot.
- New client wrappers `src/lib/notes-client.ts`, `audio-client.ts`, `config-client.ts` that replace `firestore.ts` and `audio-db.ts` with API-fetching equivalents.
- New API routes: `/api/notes`, `/api/notes/[id]`, `/api/audio/[id]`, `/api/config`, `/api/config/test`.
- Client-generated note IDs via `crypto.randomUUID()` — audio is PUT first, then the note JSON is POSTed with the same id, eliminating the old create-then-save race.
- Engines bumped to Node ≥ 20.

### Preserved

The previous Firestore + Google Auth PWA implementation remains available
through Git history.
