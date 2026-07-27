# Roadmap

> **Archived at 0.6.0.** This is a frozen Electron-era scratchpad, not the active
> product roadmap. Native macOS work is tracked in
> [`../macos/docs/ROADMAP.md`](../macos/docs/ROADMAP.md).

A running scratchpad for what's next. Add freely, reorder freely, strike through or move to "Shipped" when done.

Format tip: keep each item to one line. Add a short `—` note for context if it helps. add `-${AUTHOR}` (like `-gaf` or `-claude`) at the end to indicate the author of the item.

**Current focus (2026-07-18):** prioritize the native app experience. REPL and terminal-launch UX work is deferred unless CLI demand makes it important again. -Codex

## Bugs

<!-- Things that are broken or wrong. -->

- **Desktop release remaining human gate.** The Apple-silicon wrapper bundles only verified LGPL FFmpeg artifacts. The release command signs the nested tools, enables hardened runtime/notarization, and verifies Gatekeeper/stapling—but intentionally refuses to run until Developer ID + Apple notarization credentials exist. -Codex

## Improvements

<!-- Small quality-of-life fixes to existing features. -->

- add "paste YouTube link" input method. use something like yt-dlp. just found out yt-dlp is dependent on python, so might not be a good fit. alternatives: lux, yt-dlv, YouTubei.js -gaf
- actually have the New Transcription button to behave differently than just navigating to Transcribe tab (the Transcribe tab is just below it, so now it's basically redundant). Floating menu recycling components from the mobile-version of the three input options would be nice. -gaf
- add `logprob?: number` to `ScribeWord` in `src/lib/types/elevenlabs.ts` — ElevenLabs now returns a per-word log-probability (confidence in log space; closer to 0 = more confident) that flows through our JSON output transparently but isn't declared on the type. Not clipper-critical (the workflow just passes JSON through), but surfacing it on the type unlocks downstream uses: filter low-confidence spans before picking highlights, render a confidence heatmap on the transcript in the web app, expose a `--min-logprob` flag on `scriber transcribe` to fail or warn when a recording is too mumbled. Audit callers of `ScribeWord` after adding the field; none should break since it's optional. -claude
- (in addition to the repl idea below) in the terminal, running scriber web app still means running a next.js server, which prints "Next.js blabla" and the continuous logs. the "don't close this terminal" and "press ctrl + c to stop" message gets buried up top, and the logs are scary for non-tech users. can we do it so that:
  - the localhost runs without next.js logs (unless opted in with something like `scriber serve/start/launch --dev)
  - ctrl + c still terminate the process immediately, *and* make the web app not working or give warning (because right now, when the terminal process is terminated, the web app in browser still kinda works to a certain extent because it's cached, except "loading..." message everywhere; I want it explicit to the user that the terminal process is already gone and they have to run it again to use the web app)
  - **Deferred (2026-07-18):** the native macOS app now removes Terminal from the primary user experience. Keep the existing CLI behavior for headless/automation use and revisit its launch UX only if user demand justifies it. -Codex

## Ideas

<!-- Bigger things worth exploring but not committed to. -->
- Let's create proper REPL (inspired by `ollama`) — `ollama` is an interactive REPL, so you probably can try to run it to get a snippet of the repl first response, peeking its interface. I want `scriber` to launch similar interactive REPL where human user can cycle between options like: 
  1. Launch Scriber app

     > *equivalent to `scriber serve`* (or perhaps rename it to `scriber start` or "launch" something more user-friendly towards non-technical users? any subcommands naming idea?)

  2. Configure settings (needs better wording)

     > *configure api key, blabla (additional settings we might add later, which can also be configured easily through the Settings tab in the web app)*

     > *equivalent to `scriber config` (or something)*
  
  3. and so on (if there's any)

  -gaf

  - **Decision (2026-04-21):** defer until there are ≥2 meaningful subcommands (right now just `start` = one menu item = pointless menu). Minimum viable set: `start` + `config` + `transcribe`. Primary command rename agreed: `serve` → `start` (matches `npm start`, `docker start`; friendlier for non-tech users). Keep `serve` as a hidden alias so scripts/docs don't break. Bare `scriber` (no args) still defaults to the primary command. Recommended TUI library: `@inquirer/prompts` (already flagged as a candidate in the pre-v0.2 pivot plan). -claude
  - **Note (2026-04-21):** cli has been upgraded, so this can be considered for implementation. there are options: bubble tea, Ink, openTUI(new, typescript, but need to switch runtime to `bun` if I'm not mistaken), ratatui, and so on. the choice should consider both claude's confidence in its knowledge of the framework *and* which framework is the best fit for the purpose. don't forget we have context7 mcp.
  - **Deferred again (2026-07-18):** focus has shifted to making the native app experience excellent. Preserve this design discussion for a future CLI-focused phase; do not treat the REPL as an active near-term task. -Codex

- move to https://mediabunny.dev/ — dependency-free client-side JS library for reading, writing, and converting video and audio files. Directly in the browser -gaf
- separate scriber web app and scriber cli later; some people might only need the cli and vice versa.
- users should be able to configure the port in both the web app's Settings and the REPL (later). -gaf
  - **Deferred (2026-07-18):** REPL configuration follows the broader REPL deferral. Reconsider app/web port configuration separately if it becomes useful. -Codex
- the web app should show version beside the logo **and** check for latest update on start, prompting the user to run `npm i -g @gafiegarcia/scriber` again (with "copy command" button, just to make it easier) when there's a new update. I don't know how is the best way to check for this, but perhaps on app start or periodically, let's discuss this later.
- I don't know if this is important or not, but I wonder if updating to the latest next.js version is good or not. since v0.1, we've beenusing webpack instead of Turbopack because of hot reload issues that we couldn't solve before, but I wonder if there are things we're missing by using webpack instead of turbopack.
  - **Shipped in v0.5.9 (2026-06-13):** `npm run dev` now uses Next 16's default Turbopack path. `npm run dev:webpack` remains as a fallback if file watching regresses on this machine. -Codex
- Scriber web app was designed with mobile-first in mind in the beginning. So while it's now somewhat "working" on desktop, it looks pretty bad. we need to have a redesign session to make it look good and easy to use on desktop (padding/max-width, the overly-wide nav bar at the bottom which was designed for mobile, etc. etc.)

- **OSS + managed-hosting business model** — keep Scriber OSS and BYOK-first (the current local CLI), but offer a paid hosted version at e.g. `scriber.app` where users skip self-hosting and buy credits/subscription instead of bringing their own ElevenLabs key. n8n-style: self-hosters get the full app, paying users get convenience + managed servers + no key management. Paid users might *also* get a CLI flavor (for automation/scripting), just with different internals than the OSS CLI — same UX surface, different wiring underneath. -gaf

  - **Approach (option 2 from the chat: env-flag, single app):** introduce `SCRIBER_MODE=local` (default, OSS behavior) vs `SCRIBER_MODE=managed` (the hosted build). One codebase, one Next.js app, branching behavior at a few clear seams. Private repo only holds what doesn't belong in OSS anyway: auth, billing, managed storage adapter, credit-metering, marketing pages, and (if we ship it) the managed CLI build. No fork. -claude

  - **Architecture fit — what's already favorable:**
    - Server-only storage is one module (`src/lib/server/storage.ts`) with a narrow API (`readConfig` / `writeConfig` / `listNotes` / `createNote` / `writeAudio` / `readAudioStream` / ...). Swapping it for a tenant-aware DB + object-storage adapter is a clean refactor, not a rewrite.
    - `/api/transcribe` already reads the key at request time and proxies to ElevenLabs — in managed mode the same route instead reads a platform-held key, checks credits, and meters usage. Small, contained diff.
    - API routes are the only callers of storage; no client-side leakage. CSRF middleware (`src/middleware.ts`) already rejects cross-origin mutations — carries over unchanged on hosted.
    - Next.js 16 App Router + standalone build runs the same whether it's bound to `127.0.0.1` (CLI) or deployed to a hosting provider (managed).
    - `bin/scriber.js` is thin — just port selection + handoff to the standalone server. A future managed CLI can reuse the shape but point at a remote API + use an auth token from a keychain, rather than spawning a local server.
    - BYOK / no-auth / filesystem already proves the OSS story works end-to-end — keeps the OSS version "honestly self-hostable," which is the architectural discipline the chat flagged as the one that matters.

  - **Architecture fit — what's missing / needs design:**
    - **No auth layer.** Everything currently assumes a single local user. Managed mode needs sessions, login, password reset, etc. Plan: use a library (Auth.js / BetterAuth / Clerk), don't roll our own. Every `/api/*` route in managed mode needs a session check; the managed CLI would use a long-lived personal access token.
    - **Storage is single-tenant.** Notes live in `~/.scriber/notes/` keyed by note id only, not user id. For managed mode, either (a) refactor storage to take a `tenantId` arg throughout, or (b) define a `StorageAdapter` interface and have `FilesystemAdapter` (local) vs `DatabaseAdapter` (managed) selected by env. (b) is cleaner. Worth introducing the abstraction early even while only the filesystem adapter exists, so the seam is designed, not retrofitted.
    - **Config is single-tenant.** `config.json` holds one user's key + defaults + dictionary. In managed mode, defaults/dictionary become per-user DB rows; `apiKey` disappears from the user-facing schema (platform holds it) and is replaced by credit balance / subscription status.
    - **No billing / metering.** `/api/transcribe` needs a `deductCredits(user, audioDurationSec)` hook post-success (or pre-check for long files). Stripe + webhook for subscription state. All of this lives in the private repo.
    - **Audio I/O is filesystem streams.** `writeAudio` / `readAudioStream` would need an object-storage adapter (S3/R2) in managed mode — same adapter-interface idea as above.

  - **Suggested near-term discipline (before this becomes real work):** when touching storage, start treating it as an adapter. Even a trivial refactor — rename `storage.ts` internals to live behind an exported `storage` object — makes the eventual swap a one-line import change. No new code needed today; just don't reach around the adapter when adding new server-side features. -claude

  - **Backend Choice — Postgres/Supabase over Firebase:** While an existing Firebase project from the v0.1 era exists, a PostgreSQL-based backend (e.g., Supabase) is the strategically superior choice for the managed version.
    - **Why Postgres?** 
      1. **Relational Data:** Better for organizing notes, folders, and tags than NoSQL (Firestore).
      2. **AI Readiness:** Native vector support via `pgvector` enables "Chat with your notes" (RAG) and semantic search, which are key competitive AI features.
      3. **Predictable Costs:** Resource-based pricing (CPU/RAM) is more stable than Firebase's operation-based (read/write) pricing, avoiding "surprise bills" from inefficient queries.
      4. **Portability:** Standard SQL reduces vendor lock-in; moving from Supabase to a self-hosted Postgres is a standard migration, not a rewrite.
    - The existing Firebase project is kept as historical context/fallback, but the `DatabaseAdapter` should be designed with Postgres as the primary target for the managed offering. -claude
    

## Shipped

<!-- Move items here when done, newest first, with the tag or date. -->

- **2026-07-17 — read-only transcript bodies for the internal beta** (-gaf decision, -Codex implementation):
  - The earlier timestamp-safe editing prototype requested by -claude was removed before release. Note PATCH accepts only title and tags; transcript text and timing metadata remain the immutable source of truth.
  - Users copy or export clean TXT, Markdown, or SRT and edit in their preferred external app. This keeps synced playback and exports deterministic while avoiding a complex editing promise in the beta.

- **2026-07-17 — native macOS desktop wrapper (unsigned internal beta)** (-Codex):
  - Electron runs the Next standalone backend as a hidden utility process, owns single-instance/window/quit lifecycle, and presents Scriber as a normal app with no terminal.
  - Per-launch API authentication, exact-origin navigation, deny-by-default permissions, ephemeral Chromium state, strict fuses, sanitized standalone resources, and LGPL FFmpeg verification are packaged and tested.
  - Clean-profile launch, password-prompt regression, 401 loopback isolation, close/reopen, backend shutdown, one real short ElevenLabs transcription pass, and the unsigned internal-beta DMG's integrity/mounted contents. Public DMG release remains credential-gated for Developer ID/notarization.
  - Platform scope is deliberately Apple-silicon macOS only. If a second desktop platform is added later, prioritize Windows rather than Intel Mac support. -gaf

- **2026-07-17 — complete streaming backup/restore** (-Codex):
  - Replaced note-only JSON export/import with a versioned compressed archive containing notes, audio, dictionary, transcription defaults/model, and theme; macOS Keychain secrets are explicitly excluded.
  - Restore supports Merge (skip current conflicts) and Replace All (validated directory swap with rollback), preserving original note timestamps, word metadata, filenames, and audio bytes.
  - The server streams backup creation and extraction rather than base64-buffering audio. Every archive is staged privately and rejected before mutation if it contains traversal, links, duplicate/unknown/oversized entries, malformed data, manifest mismatches, or an API key.
  - Round-trip tests cover merge + replace, exact audio, settings, private modes, path traversal, and embedded-secret rejection.

- **2026-07-17 — macOS Keychain-backed API-key storage** (-Codex):
  - API keys now live in a profile-scoped macOS login Keychain item; Linux/Windows keep the existing private config-file fallback.
  - Existing plaintext keys migrate Keychain-first, then are atomically removed from `config.json`. Keychain failures preserve the file byte-for-byte and surface as an unavailable state instead of silently weakening storage.
  - Concurrent startup requests share one serialized, process-cached Keychain access, preventing duplicate migration attempts and repeated macOS password prompts. Secrets are passed to `/usr/bin/security` over stdin, never argv; config files/directories are tightened to `0600`/`0700`.
  - Unit coverage includes command construction, concurrency, migration conflicts/failures, preference-only writes, replacement/removal, and cross-platform fallback behavior.
  - The Electron shell uses a separate ephemeral, cookie-free Chromium session with cookie encryption disabled. This prevents Electron's unrelated “Scriber-desktop Safe Storage” item from triggering login-password prompts; it does not weaken the explicit ElevenLabs Keychain storage.

- **2026-07-17 — desktop Settings scroll navigation** (-gaf request, -Codex implementation):
  - Desktop Settings now shows every section in one scrollable content pane instead of swapping a single active card.
  - The category sidebar is now an accessible table of contents with section links, active-section tracking, URL fragments, reduced-motion-aware scrolling, and clearer spacing between cards. Mobile keeps its existing stacked layout.

- **2026-05-27 — transcribe screen cleanup + `T` shortcut** (-Codex):
  - Removed the "Powered by ElevenLabs Scribe v2" footer copy from the Transcribe page and kept that attribution in Settings -> About.
  - Removed the main-page "Type" creation entry points for now while preserving support for existing text notes; tightened the desktop drop zone from `h-72` to `h-60`.
  - Added a plain `T` global shortcut for New transcription, with guards so text fields, dialogs, links, and buttons keep normal keyboard behavior. Desktop sidebar now advertises the shortcut beside the New transcription button.

- **2026-05-24 — ElevenLabs credit-usage display in Settings + `scriber credits` CLI** (-gaf request, -claude impl):
  - New section under Settings → API Key: shows tier, remaining vs. total credits with a thin progress bar, "X used this period", next-reset date, and a Refresh button. Auto-loads when the key is configured; gracefully degrades to a scope-restricted message for STT-only keys.
  - New CLI: `scriber credits` prints a formatted summary (tier, used/limit with ASCII bar, remaining, next reset, billing period). Flags: `--json` for raw JSON, `-q/--quiet` for a single "remaining / limit" line. Exit codes: 0 ok / 1 no-key or usage / 2 ElevenLabs failure.
  - Architecture: pure fetcher in `src/lib/core/subscription.ts` consumed by both the new `GET /api/subscription` route and the CLI command (matches the `core/` seam discipline). Same 401/403 scope-detection heuristic as `/api/config/test`.
  - Tests: two new spawn-based CLI tests (help output, no-key error path); full suite (35 tests) green. Lint, typecheck, and prod build all clean. Real-API exercise of the credits display deferred until a key is configured locally.

- **2026-05-24 — fix: broken `shadcn/tailwind.css` import on main** (-claude):
  - Commit `3d2b429` ("chore: drop shadcn CLI as a dependency") removed the `shadcn` npm package but left `@import "shadcn/tailwind.css";` in [src/app/globals.css](src/app/globals.css), so `npm run build` and `npm run dev` both 500'd with `Can't resolve 'shadcn/tailwind.css'` on the first request.
  - Inspected shadcn@4.6.0's `dist/tailwind.css`: it shipped (a) accordion keyframes — unused here, (b) a `no-scrollbar` utility — already defined locally in `globals.css`, and (c) nine `@custom-variant data-*` definitions (`data-open`, `data-closed`, `data-checked`, `data-unchecked`, `data-selected`, `data-disabled`, `data-active`, `data-horizontal`, `data-vertical`) that are *heavily* used by the shadcn UI primitives in `src/components/ui/` (dialog, dropdown-menu, select, switch, alert-dialog).
  - Fix: dropped the broken `@import`, vendored just the nine `@custom-variant` definitions into `globals.css` with a comment pointing back to their origin. Verified `npm run build` ✓, `npm run dev` 200s the home page, lint + typecheck still pass.

- **2026-05-24 — transcription progress feedback** (-gaf request, -claude impl):
  - The home-page transcribe loader no longer just spins. It now tells the user which stage the job is in, with a distinct label per phase: `Uploading… NN%` (with a real progress bar driven by XHR upload events) → `Scribing…` (or `Converting & scribing…` for video uploads) → `Saving…`. The "processing" phase gets a live `m:ss` elapsed counter so long ElevenLabs jobs don't look frozen, plus a "Long recordings can take a few minutes." subtext that appears after 30 s.
  - Mobile floating Upload button shows the upload `%` inline (replacing the spinner during upload) and uses the phase label in its `aria-label`/title.
  - Behind the scenes: `useTranscribeFile` switched from `fetch` to `XMLHttpRequest` for the `POST /api/transcribe` call so we can observe `upload.onprogress` and `upload.onload` — fetch doesn't expose upload progress on the browser side. The abort signal is forwarded to `xhr.abort()` so Cancel still works. Phase shape changed from `idle|converting|transcribing|saving` to `idle|uploading|processing|saving`, plus new `uploadProgress`, `elapsedMs`, `activeFile`, and derived `isVideo` outputs.
  - Verification: typecheck + lint + unit tests pass; dev server returns 200 on the home page (desktop + mobile) with all CSS intact. End-to-end exercise of the `Uploading…` / `Scribing…` / m:ss-elapsed states against a real long ElevenLabs job not yet performed — would need a 100 MB+ file and an API key to see the upload-progress bar fill meaningfully.

- **v0.4.0-local (2026-04-28) — first-class video input via local ffmpeg**: -claude
  - Drop a `.mov`, `.mp4`, `.mkv`, `.webm`, `.m4v`, or `.avi` into the web app or `scriber transcribe`; Scriber strips the video track locally before sending the audio to ElevenLabs. Solves three downstream pains at once: the in-app `<audio>` player no longer breaks silently on H.264-bearing containers, uploads shrink ~30x for typical video (1 GB `.mov` → ~30 MB AAC), and `~/.scriber/audio/` only stores audio.
  - Bundled `ffmpeg-static` + `ffprobe-static` (~60 MB postinstall). Falls back to system `ffmpeg`/`ffprobe` on `PATH` when bundled binaries are unavailable (corporate proxy / `--ignore-scripts`); fails with an install-hint error when neither exists.
  - Conversion target: AAC in M4A, mono 48 kHz 96 kbps with `+faststart`. Plays cleanly in HTML5 `<audio>` with no buffering pause; matches storage's existing `audio/mp4 → .m4a` mapping.
  - I/O is temp-file based (`os.tmpdir()` + `crypto.randomUUID()` names, `try/finally` cleanup) — M4A's `moov` atom needs random-access output, and stdin/stdout streaming would force a second multi-GB Buffer in memory alongside the original upload.
  - Server-side conversion → `/api/transcribe` returns the converted audio as base64 inside the JSON response (avoids re-uploading; storage layer's `writeAudio` requires the note to exist first, so server-side direct save would have forced a flow reorder for marginal gain).
  - Architecture: new `src/lib/core/ffmpeg-runtime.ts` (memoized binary resolver) + `src/lib/core/audio-extract.ts` (`hasVideoStream`, `extractAudio`, `writeUploadToTemp`); both consumed by the route and the CLI per the `core/` seam discipline. `scripts/pack-standalone.js` explicitly copies binaries with chmod 0o755 (Next's tracer misses native binaries reached via path-export tricks). `scripts/build-cli.js` marks both `*-static` packages external in esbuild so their `__dirname`-based path lookups keep resolving at runtime.
  - Cover-art false positive (album art in `.mp4`) handled — `ffprobe`'s `disposition.attached_pic` flag distinguishes cover-art "video" streams from real video tracks, so audio-in-mp4 and Voice Memo `.m4a`-renamed-`.mp4` pass through unchanged.

- **2026-04-27 — exit flow polish**: -claude
  - Removed the 3-second countdown after the Stop Scriber confirm. `window.close()` now fires immediately after `/api/shutdown` resolves, in the same async-handler tick (no `useEffect` round-trip), so it stays inside the click's user-gesture context.
  - Diagnosed why auto-close was inconsistent: per the HTML spec, browsers only honor `window.close()` on a user-opened tab when `history.length === 1`. That's why Exit closes the tab cleanly from the initial Transcribe page, but is silently refused once the user has visited Notes or Settings — `history.length` grows on navigation and never shrinks (back-nav doesn't reduce it). No clean workaround exists short of having the tab opened via `window.open()` from a parent script, which doesn't apply here (the browser is launched by the OS `open` command in `bin/scriber.js`).
  - Fallback copy on the "Scriber stopped" screen updated from "This tab will close in {n}…" (which lied when the browser blocked the close) to a static "You can close this tab now." — only visible when the auto-close is refused.

- **v0.3.0-local (2026-04-25) — `scriber transcribe` headless CLI**: -claude
  - New subcommand: `scriber transcribe <file>`. JSON always to stdout (text + word-level timestamps + language + speaker IDs when diarized); progress to stderr. Exits 0 / 1 (usage) / 2 (transcription).
  - `-o <path...>` takes one or more output file paths; extension picks format (`.json`/`.srt`/`.md`/`.txt`). Extension-driven shape replaces the earlier `-o <dir>` design — one flag can write all four formats in a single invocation: `-o a.json a.srt a.md a.txt`.
  - Default saves to `~/.scriber/` (Note + audio copy, visible in the web app Notes tab, matches the web-app UX for non-technical users). `--no-store` skips it.
  - Flag coverage mirrors ElevenLabs options: `--language`, `--diarize`, `--num-speakers`, `--tag-audio-events`, `--keyterm` (repeatable; appended to config dictionary), `--no-keyterms`, `--title`, `--quiet`. Flags override `config.json` defaults per run.
  - Architecture: ElevenLabs fetch + retry loop extracted to `src/lib/core/transcribe.ts`. Both `/api/transcribe` and the CLI call into it; the API route is now a thin adapter. CLI source lives in `src/cli/` and is bundled to `.scriber-cli/index.cjs` by `scripts/build-cli.js` (esbuild, ~26 KB, self-contained CJS). Bundle step wired into `prepack`. This is the `core/` seam referenced in the managed-mode architecture notes.
  - Tests: new `test/` tree using `node:test` + `tsx` — 22 formatter unit tests, 8 CLI error-path tests, 2 real-API e2e tests gated behind `SCRIBER_E2E=1`. Writing the tests uncovered two formatter bugs (MD over-quoting plain-dash titles; SRT orphaning trailing punctuation into its own cue) which are fixed.
  - Driven by the AI auto-clipper workflow (YouTube long-form → audio → scriber JSON → LLM highlights → ffmpeg cuts).

- **2026-04-22 — default port moved off 3000**: -claude
  - `bin/scriber.js` default is now `7337`; `--port` override unchanged, `npm run dev` + `npm run dev:turbo` pinned to the same port. Closes the open half of the port-conflict concern (scriber-vs-other-dev-server) that single-instance detection didn't cover. README + CLAUDE.md references updated; CHANGELOG untouched (rolls up with the rest of the pre-release wins when v0.2.1 tags).

- **2026-04-22 — theme sync + single-instance**: -claude
  - Theme now persists to `~/.scriber/config.json` (localStorage kept as fast-boot cache + focus-based re-sync), so multiple Scriber instances sharing `~/.scriber/` no longer diverge on theme.
  - Single-instance enforcement: new `/api/health` endpoint lets `bin/scriber.js` detect an already-running Scriber and open the browser to it instead of spawning a duplicate. Partial progress on the "scriber shouldn't conflict with anything" idea — port fallback still triggers when 3000 is taken by *non-Scriber*.
  - Polish: gradual theme fade (0.2s CSS transition on color/bg/border); exit-button shows a 3-second countdown and attempts `window.close()` after shutdown confirm (browser may block close on user-opened tabs; the "run `scriber` again" fallback message still displays).

- **2026-04-21 — second-wave quick wins** (still pre-release; rolls up into the eventual v0.2.1+ tag): -claude
  - add to the `scriber help` docs that `-h` and `--help`, the generic options that devs might reach out to by default, work too and equivalent to `scriber help` (if I understand this correctly) -gaf
    - Added a new `FLAGS (any command)` section to the HELP block listing `-h/--help` and `-v/--version` as aliases. Code already supported them; this is docs-only. -claude
  - I think the web app needs an "exit" button that automatically kill the localhost. I figure normies (non-tech people) already got scared using this current version of scriber by having to go to the terminal and type `scriber`, at least we can make their life easier by providing an exit button in the web app so that they don't have to find the terminal and hit `ctrl + c`. -gaf
    - Shipped as a new Shutdown section at the bottom of Settings, with an AlertDialog confirmation. New `/api/shutdown` POST route handles the kill. Before `process.exit(0)` it prints `Scriber stopped via web UI. Run \`scriber\` again to restart.` to the terminal so whoever started the server gets a visible confirmation (not a silent exit). -claude
  - API key status banner + auto-probe on boot — invalid/missing ElevenLabs key is now loud and impossible-to-miss; Save in Settings auto-tests the key before committing, with a "Save anyway" escape hatch for scope-restricted keys. -claude
  - `package.json`: renamed `prepublishOnly` → `prepack` so `npm i -g .` from a clone auto-builds; name changed to scoped `@gafiegarcia/scriber` to avoid collision with an existing `scriber` on npm. -claude

- **v0.2.0-local (2026-04-21)** — first local-first release: filesystem storage, BYOK, `scriber` CLI, route flattening, CSRF + 127.0.0.1 bind.
