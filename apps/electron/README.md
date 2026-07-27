# Scriber

> **Archived at 0.6.0.** This Electron implementation is frozen. Its commands
> and product descriptions document that historical snapshot; active macOS work
> lives in [`../macos`](../macos).

<!-- TODO: REWORK ALL OF THIS! When I open this repo from private->public, I want this file to be written fully by me, without any hints, residue, or even actual work, of AI-generated text. later -gaf -->

A local-first voice transcription tool powered by **your own** ElevenLabs Scribe v2 account. Record or upload audio/video to create beautifully structured notes — stored on your machine, not in the cloud.

Scriber runs entirely on your laptop. Your API key, your notes, your audio. Nothing goes anywhere except to ElevenLabs when you transcribe.

## Why Scriber?

- **BYOK (Bring Your Own Key)** — you use your own ElevenLabs account, so you pay ElevenLabs directly and Scriber doesn't markup anything.
- **Local-first** — notes live as JSON files under `~/.scriber/`. Audio lives right next to them. Grep them, back them up, move them between machines.
- **Best-in-class STT** — ElevenLabs Scribe v2 handles 99 languages including code-switching (Bahasa + English in the same sentence).
- **Zero hosting** — no server to run, no accounts to manage, no data leaving your machine except when you transcribe.

## Install

Requires **Node.js ≥ 20**.

```bash
npm install -g scriber
```

The first install pulls down bundled `ffmpeg` + `ffprobe` binaries (~60 MB combined) so video uploads work out of the box. If that download is blocked (corporate proxy, `npm install --ignore-scripts`), Scriber falls back to a system `ffmpeg` on your `PATH` — install one with `brew install ffmpeg` (macOS) or your distro's package manager.

Then start it:

```bash
scriber
```

Your browser opens on `http://localhost:7337`. Paste your ElevenLabs key into the first-run prompt and you're done.

### macOS desktop app (internal beta)

Scriber also builds as a normal `Scriber.app`: it opens in its own window, runs
the private local backend invisibly, and does not require Terminal. The current
local Apple-silicon build is intentionally unsigned and is for development
testing only; the colleague-facing DMG is release-gated until Developer ID
signing and Apple notarization credentials are configured.

The desktop app supports Apple-silicon Macs (M1 and newer). Its download uses
`Apple-Silicon` in the filename so nontechnical users can identify the correct
installer without needing to know the term `arm64`.

Maintainer commands:

```bash
npm run desktop:package:mac  # unsigned local Scriber.app
npm run desktop:make:mac:local # unsigned, mount-verified internal-beta DMG
npm run desktop:make:mac     # signed + notarized DMG; refuses missing credentials
```

For a release, `desktop:make:mac` automatically detects a valid Developer ID
Application identity installed in macOS Keychain; `CSC_LINK` and `CSC_NAME`
remain available for CI. Notarization accepts App Store Connect API credentials,
Apple ID credentials, or a `notarytool` Keychain profile. Local beta commands
remain unsigned even when a Developer ID certificate is installed.

The packaged app uses a random per-launch token for its loopback API, bundles the
verified redistributable FFmpeg tools, keeps Chromium state in memory, and shuts
the hidden backend down when the app quits.

Transcripts are read-only inside Scriber so their original text and audio timing
stay intact. Copy or export a transcript as plain text, Markdown, or SRT, then
edit that copy in your preferred writing or subtitle app. Timestamped notes can
copy SRT directly from the Copy menu. Note titles and tags remain editable in
Scriber.

## Getting an ElevenLabs API Key

1. Sign up at [elevenlabs.io](https://elevenlabs.io/).
2. Go to [Settings → API Keys](https://elevenlabs.io/app/settings/api-keys).
3. Create a new key — the free tier gives you enough minutes to try Scriber.
4. Paste it into Scriber's first-run modal (or Settings → API Key).

On macOS, the key is stored in your login Keychain. Existing plaintext keys are
moved there automatically and removed from `~/.scriber/config.json`. Linux and
Windows retain the config-file fallback. The key is only sent to ElevenLabs.

## CLI

```
scriber [command] [options]

COMMANDS
  serve                          Start the web UI on localhost (default)
  transcribe <file>              Headless: transcribe an audio file, print JSON to stdout
  credits                        Show remaining ElevenLabs credits for the stored key
  help        (-h, --help)       Show help
  version     (-v, --version)    Print the installed version
```

### `scriber serve` (default)

Boots the local web UI on `127.0.0.1`.

| Flag | Description |
|------|-------------|
| `-p, --port <n>` | Preferred port. Default `7337`. Falls back to `n+1`, then a random free port. |
| `--no-open` | Don't open the browser automatically (useful over SSH or in scripts). |

If another `scriber` instance is already running on the preferred port (or `port+1`), the new invocation reuses it instead of starting a second server.

### `scriber transcribe <file>`

Runs headlessly without opening a browser. JSON always goes to stdout (with word-level timestamps, speaker IDs if diarized, detected language, and any requested `additional_formats`); progress goes to stderr. By default the result is also saved as a Note in `~/.scriber/` so it shows up in the web app's Notes tab — pass `--no-store` to skip that.

**Supported input formats:** `.mp3`, `.m4a`, `.mp4`, `.wav`, `.webm`, `.ogg`, `.flac`
**Supported output formats:** `.json`, `.srt`, `.md`, `.txt` (picked from the `-o` file extension)

| Flag | Description |
|------|-------------|
| `-o, --output <path...>` | One or more output file paths; extension picks format. Repeat `-o` or list multiple paths after a single `-o`. |
| `--no-store` | Skip saving the result as a Note in `~/.scriber/`. |
| `--language <code>` | BCP-47 code (e.g. `en`, `id`), or `auto`. Overrides the default in `config.json` for this run. |
| `--diarize` | Enable speaker diarization (Speaker A/B/…). |
| `--num-speakers <n>` | Speaker count hint (positive integer). Requires `--diarize`. |
| `--tag-audio-events` | Tag non-speech events (laughter, music, applause) inline. |
| `--keyterm <term>` | Add a keyterm for this run. Repeatable; appended to the dictionary in `config.json`. |
| `--no-keyterms` | Disable all keyterms for this run (ignores the config dictionary). |
| `--title <text>` | Note title override. Defaults to the input basename without extension. |
| `-q, --quiet` | Suppress stderr progress output. |
| `-h, --help` | Show transcribe-specific help. |

**Exit codes:** `0` ok · `1` usage / input error (missing file, bad flag, unsupported format, no API key) · `2` ElevenLabs / transcription error.

**Defaults & overrides.** `--language`, `--diarize`, `--num-speakers`, and `--tag-audio-events` fall back to the `defaults` block in `~/.scriber/config.json` when not passed. Keyterms are merged: `config.dictionary + --keyterm …` unless `--no-keyterms` is set.

```bash
# Pipe JSON to another tool:
scriber transcribe interview.mp3 | jq '.words[0]'

# Write files next to the input (format inferred from extension):
scriber transcribe interview.mp3 -o interview.json interview.srt interview.md

# Script-friendly: skip the Notes tab, silence progress:
scriber transcribe interview.mp3 --no-store --quiet -o ./out.json

# Full option coverage (config.json defaults; flags override per run):
scriber transcribe interview.mp3 --diarize --num-speakers 2 \
  --language en --keyterm "Scriber" --keyterm "ElevenLabs" \
  --tag-audio-events --title "Q2 planning sync"
```

The API key is read from macOS Keychain (or `~/.scriber/config.json` on Linux and
Windows) — run `scriber` once and set it in the web app if you haven't yet.

### `scriber credits`

Prints remaining ElevenLabs credits for the stored key, alongside the current tier, used / limit, and next reset date. Same info the **Credits** card in Settings shows.

| Flag | Description |
|------|-------------|
| `--json` | Print the raw subscription JSON to stdout. |
| `-q, --quiet` | Print only a single `remaining / limit credits left` line. |
| `-h, --help` | Show credits-specific help. |

**Exit codes:** `0` ok · `1` no API key configured / usage error · `2` ElevenLabs request failed.

```bash
scriber credits                 # formatted summary
scriber credits --json | jq .   # raw data for scripting
scriber credits --quiet         # one line, easy to grep
```

Note: keys created with only the Scribe (speech-to-text) scope can't read subscription info. To use this command, generate a key with **User: Read** permission on ElevenLabs.

## Features

- **Voice recording** — tap to record, review before sending to ElevenLabs.
- **File upload** — audio (MP3, WAV, M4A, MP4, WebM, OGG, FLAC) and video (MOV, MP4, MKV, WebM, M4V, AVI), up to 1 GB. Video files are converted locally — Scriber strips the video track via ffmpeg before sending the audio to ElevenLabs, so uploads stay small and the in-app audio player works on the saved file.
- **99 languages** — auto-detect (recommended) or pick one.
- **Speaker diarization** — color-coded Speaker A/B/… labels.
- **Audio event tags** — inline markers for laughter, music, applause.
- **Personal dictionary** — add names, jargon, and domain terms as `keyterms` so Scribe recognizes them.
- **Word-level sync** — click any word in the transcript to jump the audio there; the active word highlights as it plays.
- **Search, sort, tags** — filter and organize notes in the list.
- **Keyboard shortcuts** — press `T` for a new transcription; press `⌘K` to jump to Notes search.
- **Export** — `.txt`, `.md`, `.srt`, with or without metadata.
- **Light/dark/system theme.**
- **PWA** — add to home screen on mobile if you're running it over your LAN.

## Where data lives

Everything lives in `~/.scriber/` (override with `$SCRIBER_HOME`):

```
~/.scriber/
├── config.json       # Transcription defaults, dictionary, theme (no key on macOS)
├── notes/            # One JSON per note, sorted by creation time
│   └── 2026-04-21T10-32-11_ab12cd34.json
└── audio/            # One audio file per note (optional)
    └── 2026-04-21T10-32-11_ab12cd34__meeting-notes.m4a
```

Filenames start with an ISO timestamp so `ls` shows them in order. Uploaded audio appends a slug of the original filename so you can spot it visually.

Settings → Data can download a complete compressed backup containing notes,
audio, dictionary, transcription defaults, theme, and a versioned manifest.
Restore can either **Merge** (keep current data and skip duplicates) or
**Replace All** (recreate the backup exactly). The archive is validated in a
private staging directory before current data changes, and unsafe paths or
malformed entries are rejected.

On macOS the API key intentionally stays in Keychain and is never included in a
backup; paste it again on a new Mac. Directly backing up `~/.scriber/` still
preserves the same notes, audio, and preferences.

## Run from source

```bash
git clone https://github.com/<you>/scriber
cd scriber/apps/electron
npm install
npm run dev            # Dev server at http://localhost:7337
npm run build          # Production build + standalone bundle
npm run lint           # ESLint
npm test               # Unit + CLI error-path tests (no network)
npm run test:e2e       # Above + a real ElevenLabs call against the smallest audio
                       # file in ~/.scriber/audio/ (burns API credit)
```

Once built, `node bin/scriber.js` boots the production server the same way the global install does. Run `node bin/scriber.js transcribe <file>` to exercise the headless path locally.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Next.js 16 (App Router, `output: "standalone"`) + React 19 + TypeScript |
| Styling | Tailwind CSS v4 + shadcn/ui (Base UI) |
| Transcription | ElevenLabs Scribe v2 (server-side proxy) |
| Storage | Filesystem — JSON + audio under `~/.scriber/`; API key in macOS Keychain |
| Multi-tab sync | `BroadcastChannel` |
| CLI | `bin/scriber.js` — programmatic Next.js server, `127.0.0.1` only |

## Security

- The server binds to `127.0.0.1` only — it is not reachable from the network.
- Mutating API routes check the `Origin` header against the server host to block cross-origin requests from other tabs.
- On macOS, your API key is stored in Keychain rather than plaintext. Scriber
  reads it server-side only when making an ElevenLabs request; `/api/config`
  exposes status but never the key itself.

## Troubleshooting

**`Port 7337 is in use`** — Scriber tries 7338 next, then a random port. Use `--port <n>` to pick one.

**Browser didn't open** — use `--no-open` and visit the printed URL manually, or run over SSH.

**"No ElevenLabs API key configured"** — paste one in Settings → API Key or the first-run modal.

**Data is gone** — check `~/.scriber/notes/` directly. If it's empty but you expect notes, check `$SCRIBER_HOME`.

**Windows** — data and the API-key config fallback live in
`%USERPROFILE%\.scriber\`. Everything else works the same.

## License

Original Scriber code in this archived implementation is licensed under
GPL-3.0-or-later. See [LICENSE](LICENSE). Third-party dependencies retain their
own licenses.
