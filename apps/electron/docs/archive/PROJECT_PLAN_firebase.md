# Scriber — Project Plan

> Voice transcription PWA using ElevenLabs Scribe v2. Clone of Plaud AI as a web app.

## Status: Phase 13 In Progress 🔧 (Landing/pricing mockups + route migration)

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Clean slate + scaffold | ✅ Done |
| 1 | TypeScript types + localStorage storage | ✅ Done |
| 2 | Mobile-first UI shell (bottom tabs) | ✅ Done |
| 3 | File upload + batch transcription | ✅ Done |
| 4 | Voice recording | ✅ Done |
| 5 | Notes CRUD + export | ✅ Done |
| 6 | Polish (errors, loading, PWA) | ✅ Done |
| 7 | Post-MVP polish | ✅ Done |
| 8 | UI redesign | ✅ Done |
| 9 | Feature expansion (text input, tags, import, search highlights) | ✅ Done |
| 10A | Firebase Auth (Google OAuth + dev bypass) | ✅ Done |
| 10B | Firestore migration (replace localStorage) | ✅ Done |
| 10C | Scribe v2 advanced features (language, diarization, audio events) | ✅ Done |
| 10F | Sort options for notes list | ✅ Done |
| 11A | Audio storage (IndexedDB) | ✅ Done |
| 11B | Audio player in note detail | ✅ Done |
| 11C | Word-level sync highlighting + seek-by-click | ✅ Done |
| 12A | Note content editing + personal dictionary (keyterms) | ✅ Done |
| 12B | API error handling + retry | ✅ Done |
| 12C | PWA polish (apple-touch-icon, theme-color) | ✅ Done |
| 12D | Accessibility improvements | ✅ Done |
| 13 | Landing page + app route migration | 🔧 In Progress |

---

## What's Built

### Core Features
- **Voice Recording**: MediaRecorder API captures audio (webm/opus), sends to ElevenLabs Scribe v2 batch API, saves transcription as a note
- **File Upload**: Upload any audio/video file (Scribe v2 handles all formats natively, up to 3GB)
- **Notes Management**: Search, sort by date, card grid layout, individual note view
- **Note Detail**: Inline title editing, plain-text metadata line, ⋯ menu (export + delete), split copy button (plain / copy as Markdown/txt), edit button — all above content for long transcripts
- **Export**: Download as .txt / .txt+meta / .md / .md+meta / .srt via ⋯ menu submenu; copy as plain text, txt+meta, md, md+meta via split copy button
- **Settings**: Light/dark/system theme, transcription language (99 languages), speaker/sound options, personal dictionary, data management

### Mockups / Directional Surfaces
- **Landing page (`/`)**: Product-direction mockup used to visualize how the product should feel if it becomes a real business; not all claims on the page map to implemented app logic yet
- **Pricing page (`/pricing`)**: Future-business mockup based on the pricing model in `PRICING.md`; credit purchases, balances, estimates, and billing logic are **not implemented** in the app yet

### Technical
- **Next.js 16** (App Router) + React 19 + TypeScript
- **Tailwind CSS v4** + shadcn/ui (Base UI)
- **Inter variable font** (via rsms.me CDN)
- **ElevenLabs Scribe v2** batch API via server-side API route (key never exposed to browser)
- **Firestore** for note storage (per-user, real-time sync via `onSnapshot`)
- **PWA manifest** with SVG icon
- **Security headers**: X-Content-Type-Options, X-Frame-Options, Referrer-Policy
- **Error boundaries** + loading skeletons for all routes

### File Structure
```
src/
  app/
    page.tsx         — Landing page (marketing, always dark)
    pricing/         — Pricing mockup page
    landing.css      — Landing page design tokens (scoped CSS vars)
    app/             — Authenticated app shell (URL: /app)
      page.tsx       — Transcribe tab (record + upload)
      notes/         — Notes list + detail view
      settings/      — Theme, data management
      layout.tsx     — Bottom tab bar + toaster
      error.tsx      — Error boundary
      loading.tsx    — Loading skeleton
    (auth)/          — Login route group
    api/transcribe/  — ElevenLabs proxy endpoint
    layout.tsx       — Root layout (fonts, viewport)
    manifest.ts      — PWA config
    icon.svg         — Favicon
  components/
    bottom-tab-bar   — Mobile navigation
    file-upload      — Upload + transcribe flow
    voice-recorder   — Record + transcribe flow
    note-card        — Note preview card
    note-detail      — Full note view + actions
    notes-list       — Search + grid
    theme-provider   — Light/dark/system
    ui/              — shadcn/ui components
  lib/
    auth-context.tsx — Firebase Auth provider
    firebase.ts      — Firebase app/init
    firestore.ts     — Note CRUD in Firestore
    audio-db.ts      — IndexedDB audio blob storage
    dictionary-context.tsx
    transcribe-options-context.tsx
    export.ts        — txt/md/srt generation
    hooks/           — useAudioRecorder / useNote / useNotes
    types/           — Note, ElevenLabs types
```

---

## Completed Build Log

| Date | Phase | Commit | Summary |
|------|-------|--------|---------|
| 2026-03-23 | 0 | Initial | Deleted old Vite app, scaffolded Next.js 15 |
| 2026-03-23 | 0 | f2f7260 | CLAUDE.md, PROJECT_PLAN.md, shadcn components |
| 2026-03-23 | 1 | ac89509 | Note types + localStorage CRUD |
| 2026-03-23 | 2 | dd16dd7 | UI shell with bottom tabs, all pages |
| 2026-03-23 | 3 | 48059e4 | File upload + ElevenLabs batch API |
| 2026-03-23 | 4 | 6e42c6b | Voice recording with MediaRecorder |
| 2026-03-23 | 5 | cc8facc | Export (txt/md/srt) + enhanced note detail |
| 2026-03-23 | 6 | — | Error boundaries, loading, security headers |
| 2026-03-23 | 7 | — | Post-MVP polish: validation, abort, quota, beforeunload |
| 2026-03-23 | 8 | e22a999 | UI redesign: header logo, unified home, recording review step |
| 2026-03-23 | 9 | — | Feature expansion: text input, tags, import, search highlights |
| 2026-03-25 | 10A | — | Firebase Auth: Google OAuth + anonymous dev bypass |
| 2026-03-25 | 10B | — | Firestore migration: replace localStorage with per-user cloud storage |
| 2026-03-26 | 10C | cef0bca | Scribe v2 advanced features: language, diarization, audio events |
| 2026-03-26 | 10F | — | Sort options for notes list |
| 2026-03-26 | 11A | d254041 | IndexedDB audio storage — persist blobs locally |
| 2026-03-26 | 11B | d278dd2 | Audio player in note detail |
| 2026-03-26 | 11C | 5228c68 | Word-level sync highlighting + click-to-seek |
| 2026-03-26 | 12A | 9bbaaeb | Note content editing + personal dictionary keyterms |
| 2026-03-26 | 12A+ | e0aad5b–7d464ac | UI polish: Inter font, language picker, export options, scrollbars |
| 12A++ | b7604f0–02b1998 | Note detail redesign, sort button fix, Firestore undefined fix |
| 2026-03-26 | 12B | b5957e5 | API error handling + retry (server + client) |
| 2026-03-26 | 12C | 35faf05 | PWA polish: apple-touch-icon, theme-color, PNG icons |
| 2026-03-26 | 12D | 3000f66 | Accessibility: skip-to-content, ARIA, contrast fixes |
| 2026-03-29 | 13 | 4089768 | Landing page + move app routes from / to /app |
| 2026-03-29 | 13 | ad62c34 | Ignore Stitch design exports (stitch_/) |
| 2026-03-30 | 13 | 79756a0 | Polish hero text, fix overscroll bg, SVG logo |
| 2026-04-01 | 13 | — | Landing page polish: Roboto Flex headings, copy rewrites, Use Cases scroll, structural cleanup |

---

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Framework | Next.js 16 (not Vite+React) | API routes keep ElevenLabs key server-side |
| STT Engine | ElevenLabs Scribe v2 (not Whisper) | Best Bahasa Indonesia accuracy (≤5% WER) |
| Auth | Firebase Auth (Google OAuth + anonymous) | GCP-native, free tier, handles OAuth flow |
| Notes database | Firestore (implemented) | GCP-native, real-time sync, security rules for user isolation |
| Audio storage | IndexedDB for now, cloud storage later | Keeps development simple/free; cross-device sync can come later when the product is more real |
| Recording | MediaRecorder → batch API | Simpler than WebSocket proxy; real-time is post-MVP |
| UI Library | shadcn/ui v4 (Base UI) | Accessible, customizable, minimal bundle |

---

## Testing Instructions

1. `npm run dev` — landing page at http://localhost:3000, app at http://localhost:3000/app
2. **Transcribe tab** (default at /app): Upload an audio file or click the red mic button to record
3. **Notes tab**: See all transcriptions, search by title/content, click to view details
4. **Note detail**: Edit title (click pencil), copy markdown, export as txt/md/srt, delete
5. **Settings tab**: Toggle theme, export all notes as JSON, delete all notes
6. **PWA**: Open in mobile browser → "Add to Home Screen" for app-like experience

---

## Known Limitations

- Recording uses batch transcription (not real-time — transcript appears after recording stops)
- No PDF/DOCX export yet (txt/md/srt only)
- Audio blobs stored in IndexedDB (local-only, no cross-device sync)
- Personal dictionary (keyterms) stored in localStorage (local-only)

---

## Post-MVP Polish (Phase 7) — 2026-03-23

Improvements identified via visual testing with Playwright CLI:

| Fix | Description | Status |
|-----|-------------|--------|
| Word count edge case | Empty notes showed "1 words" instead of "0 words" | ✅ Done |
| beforeunload warning | Warn before leaving page while recording or transcribing | ✅ Done |
| Min recording duration | Reject recordings under 3s to avoid wasting API calls | ✅ Done |
| File size validation | Reject files >1GB, warn for files >100MB | ✅ Done |
| Upload cancellation | AbortController + cancel button on in-flight uploads | ✅ Done |
| localStorage quota | Catch QuotaExceededError in localStorage-backed preferences to avoid hard crashes | ✅ Done |
| Settings note count | Remove page reload after delete-all, update count in-place | ✅ Done |
| Stale duration ref | Use ref to capture recording duration at stop time | ✅ Done |

---

## Phase 8 — UI Redesign (2026-03-23)

| Change | Description | Status |
|--------|-------------|--------|
| Header logo | Moved "Scriber" from centered hero to persistent top-left header bar | ✅ Done |
| Unified home page | Transcribe section + recent notes (last 5) on one screen | ✅ Done |
| Recording review step | Stop → review with Cancel/Send buttons instead of auto-transcribe | ✅ Done |
| Cancel during recording | "Cancel" link below timer to discard mid-recording | ✅ Done |

---

## Phase 13 — Landing Page + App Route Migration (2026-03-29 → in progress)

### Route Migration

Moved the authenticated app from `/` to `/app` to free the root URL for the landing page:

| Change | Description | Status |
|--------|-------------|--------|
| Directory rename | `src/app/(app)/` → `src/app/app/` (route group → real URL segment) | ✅ Done |
| Route updates | All 16 internal route references updated (`/` → `/app`, `/notes` → `/app/notes`, etc.) | ✅ Done |
| Auth redirect | `(auth)/layout.tsx` redirects to `/app` instead of `/` | ✅ Done |
| PWA manifest | `start_url` changed from `/` to `/app` | ✅ Done |
| Body overflow | Removed `h-dvh overflow-hidden` from root body; moved to app layout wrapper | ✅ Done |

### Landing Page

| Change | Description | Status |
|--------|-------------|--------|
| Page structure | `src/app/page.tsx` — server component, always dark, isolated from app theme | ✅ Done |
| CSS scoping | `src/app/landing.css` — CSS vars on `body:has(.landing)` (fixes macOS overscroll bg) | ✅ Done |
| SVG wordmark | Replaced text "Scriber" with SVG path logo in navbar | ✅ Done |
| Hero | "Premium transcriptions, no subscriptions." — two-line with `<br />`, accent on "no" | ✅ Done |
| Sections | Hero → Use Cases (scroll) → Accuracy → Intelligence (2×2) → Features (bullet list) → CTA → Footer | ✅ Done |
| Design source | Generated via Google Stitch, manually converted to JSX and refined | ✅ Done |
| Accent color | Blue `#60a5fa` — replaced original purple `#a58cff` | ✅ Done |
| Copy quality | Full copy rewrite: hero subtitle, use cases, pricing claim, Jaksel branding, section headings | ✅ Done |
| Footer year | Updated to © 2026 | ✅ Done |
| Mobile nav | Hamburger menu with all nav links + Sign In | ✅ Done |
| Interface mock | Hero shows realistic transcript mockup with speakers, code-switching, audio events | ✅ Done |
| Material Symbols | Replaced with lucide-react icons (no external font dependency) | ✅ Done |
| Typography | Roboto Flex variable font (`next/font/google`) for h1/h2 with exact Figma axes | ✅ Done |
| Heading weight | All headings at font-weight 600 — GRAD axis provides visual boldness | ✅ Done |
| Hero breathing room | Increased top padding (`pt-36 md:pt-44`) for separation from fixed navbar | ✅ Done |
| CTA consistency | Navbar CTA changed from "Get Started" to "Start Transcribing" (landing + pricing) | ✅ Done |
| Hero footnote | Removed "ElevenLabs Scribe v2" from subtitle; added asterisk footnote for transparency | ✅ Done |
| Jaksel branding | "Multilingual speakers" → "Jaksel-proof" with code-switching focus | ✅ Done |
| Language detection | Two-line display: "Language: Auto" / "Detected: ENG / IND" (matches API reality) | ✅ Done |
| Pricing claim fix | "$0.10" → "One credit pack lasts forever" (honest about $2 minimum) | ✅ Done |
| Use Cases scroll | Grid → horizontal snap-scroll with full-width cards (video-ready for future) | ✅ Done |
| Features section | Removed cards (PWA, Real-time sync); remaining 4 use inline FeatureBullet list | ✅ Done |
| CTA cleanup | Removed redundant badges below CTA; "Just open your browser" → "Your credits never expire" | ✅ Done |

Important clarification:
- The landing page is currently a **directional mockup** for how the product/business should look and feel when more of the business logic exists.
- The pricing page is also a **mockup**. Credit purchases, balances, cost estimation, AI cleanup billing, and intelligent-notes billing are not implemented yet.
- Treat the authenticated `/app` surface as the implementation truth for what users can actually do today.

### Known Issue: Turbopack HMR not working

Turbopack's file watcher (FSEvents) does not detect file changes on this machine (MacBook Air M4, macOS). Symptoms:
- Edits to server components (page.tsx) don't trigger recompilation
- Even `touch` from terminal doesn't trigger the watcher
- Workaround: reset bundler cache via Next.js dev tools bubble, then hard refresh (Cmd+Shift+R)
- `WATCHPACK_POLLING=true` has no effect (that's webpack-only; Next.js 16 forces Turbopack)
- macOS Full Disk Access permissions verified — no fix found yet
- A stale service worker (`sw.js`, registered 2026-03-23) was also found and unregistered — this was causing regular reloads to show blank pages

Design decisions:
- **`/app` URL instead of route groups** — Simpler than managing `(marketing)` + `(app)` route groups. The `/app` URL is clean and the PWA manifest `start_url` points directly to it.
- **Scoped CSS variables on `body:has(.landing)`** — Landing page is always dark, independent of the app's OKLCH theme system. Variables defined on `body:has(.landing)` so they cascade to `.landing` descendants AND make `var(--lp-bg)` available for the body background (prevents macOS elastic overscroll from flashing white).
- **No ThemeProvider** — Landing page doesn't use the app's ThemeProvider. Always renders in dark mode.
- **Roboto Flex for headings** — All h1/h2 use Roboto Flex variable font (via `next/font/google`) with exact axes from the Figma logo design (`GRAD 115, XOPQ 96, XTRA 477, YOPQ 79, YTAS 715, YTDE -203, YTFI 738, YTLC 570, YTUC 666, wdth 105, opsz 141`). Weight 600 for all headings — the GRAD axis adds visual boldness. Body text stays Inter.
- **lucide-react icons** — All icons are lucide-react components, no external font dependencies.

---

## Phase 9 — Feature Expansion (2026-03-23)

| Feature | Description | Status |
|---------|-------------|--------|
| Text input method | Dialog to type/paste text as a note (`source: "text"`) with auto-title | ✅ Done |
| Note tags / labels | Tag editor in note detail, tag chips on cards, tag filter bar in notes list | ✅ Done |
| Import notes (JSON) | Import from exported JSON with dedup by ID, validation, merge | ✅ Done |
| Search highlights | Yellow `<mark>` highlighting of search terms in note card title + content | ✅ Done |

New files: `src/components/text-input.tsx`
Modified: types, storage, note-detail, note-card, notes-list, settings page, home page

---

## Phase 10A — Firebase Auth (2026-03-25)

| Change | Description | Status |
|--------|-------------|--------|
| Firebase SDK | Installed `firebase` package, created `src/lib/firebase.ts` init | ✅ Done |
| Auth context | `AuthProvider` + `useAuth()` hook with Google sign-in, anonymous dev bypass, sign-out | ✅ Done |
| Login page | `(auth)/login/page.tsx` — Google button, "I'm the dev" bypass with password | ✅ Done |
| Route protection | `(app)/layout.tsx` redirects to `/login` if not authenticated | ✅ Done |
| Sign-out | LogOut button in header bar | ✅ Done |
| Providers | `Providers` component wraps root layout with `AuthProvider` + `Toaster` | ✅ Done |

New files: `src/lib/firebase.ts`, `src/lib/auth-context.tsx`, `src/components/providers.tsx`, `src/app/(auth)/layout.tsx`, `src/app/(auth)/login/page.tsx`
Modified: `src/app/layout.tsx`, `src/app/(app)/layout.tsx`, `.env.example`

---

## Phase 10B — Firestore Migration (2026-03-25)

| Change | Description | Status |
|--------|-------------|--------|
| Firestore CRUD | `src/lib/firestore.ts` — async equivalents of all localStorage functions | ✅ Done |
| Real-time hooks | `useNotes()` and `useNote()` hooks using Firestore `onSnapshot` | ✅ Done |
| Home page | Replaced sync `getNotes()` with `useNotes()` hook + loading skeleton | ✅ Done |
| Notes list | Replaced sync `getNotes()`/`getAllTags()` with `useNotes()` + derived tags | ✅ Done |
| Note detail | Async Firestore calls for update/delete/tags, real-time note via `useNote()` | ✅ Done |
| Create flows | `voice-recorder`, `file-upload`, `text-input` use async `createNote()` | ✅ Done |
| Settings | Export/import/delete-all use async Firestore, note count from `useNotes()` | ✅ Done |
| Cleanup | Deleted `src/lib/storage.ts` (no longer imported anywhere) | ✅ Done |

New files: `src/lib/firestore.ts`, `src/lib/hooks/use-notes.ts`, `src/lib/hooks/use-note.ts`
Deleted: `src/lib/storage.ts`
Modified: `page.tsx` (home), `notes-list.tsx`, `note-detail.tsx`, `notes/[id]/page.tsx`, `voice-recorder.tsx`, `file-upload.tsx`, `text-input.tsx`, `settings/page.tsx`

Data model: `/users/{uid}/notes/{noteId}` — each note is a Firestore document under the authenticated user's subcollection. Security rules (deployed in 10A) enforce user isolation.

---

## Phase 10C — Scribe v2 Advanced Features (2026-03-25)

| Change | Description | Status |
|--------|-------------|--------|
| Language selector | Dropdown to choose transcription language (Auto-detect + 10 languages) or leave as auto | ✅ Done |
| Speaker diarization | "Identify Speakers" toggle — adds `speaker_id` to words, renders labeled transcript | ✅ Done |
| Audio event tagging | "Tag Sounds" toggle — marks laughter, music, applause etc. inline in transcript | ✅ Done |
| Transcribe options panel | Collapsible options on home page + Settings section, persisted in localStorage | ✅ Done |
| Diarized transcript view | Color-coded speaker labels (Speaker A, B, ...) in note detail when diarization is on | ✅ Done |
| Export with speakers | SRT/TXT/MD exports include speaker labels when diarization data is present | ✅ Done |

New files: `src/lib/transcribe-options-context.tsx`, `src/components/transcribe-options.tsx`, `src/components/diarized-transcript.tsx`
Modified: `src/lib/types/index.ts`, `src/app/api/transcribe/route.ts`, `src/components/voice-recorder.tsx`, `src/components/file-upload.tsx`, `src/components/note-detail.tsx`, `src/app/(app)/page.tsx`, `src/app/(app)/settings/page.tsx`, `src/app/(app)/layout.tsx`, `src/lib/export.ts`

Scope note: "Filler removal" from the original plan was dropped — not a real Scribe v2 API parameter. "Keyterms" IS a real parameter and was implemented in Phase 12A.

---

## Phase 10F — Sort Options for Notes List (2026-03-25)

| Change | Description | Status |
|--------|-------------|--------|
| Sort hook | Extended `useNotes` sort option to support `"a-z"` and `"z-a"` (title sort) | ✅ Done |
| Sort dropdown | Icon-only sort button next to search bar with 4 options: Newest, Oldest, A-Z, Z-A | ✅ Done |

Modified: `src/lib/hooks/use-notes.ts`, `src/components/notes-list.tsx`

---

## Phase 11A — Audio Storage via IndexedDB (2026-03-26)

| Change | Description | Status |
|--------|-------------|--------|
| IndexedDB module | `src/lib/audio-db.ts` — save/get/delete/clear audio blobs keyed by noteId | ✅ Done |
| Voice recorder | Fire-and-forget `saveAudio()` after `createNote()` | ✅ Done |
| File upload | Same pattern — save uploaded file blob after transcription | ✅ Done |
| Note delete cleanup | `deleteAudio(noteId)` in note detail `handleDelete()` | ✅ Done |
| Delete-all cleanup | `deleteAllAudio()` in settings `handleDeleteAll()` | ✅ Done |

New files: `src/lib/audio-db.ts`
Modified: `src/components/voice-recorder.tsx`, `src/components/file-upload.tsx`, `src/components/note-detail.tsx`, `src/app/(app)/settings/page.tsx`

Design decision: **IndexedDB over Firebase Storage** — Firebase Storage requires the Blaze plan (paid). IndexedDB is local-only (no cross-device sync) but has large quotas, stores blobs natively, and needs zero setup. When the app goes to production, swap for a cloud storage backend.

No changes to Note type or Firestore — the audio player checks IndexedDB directly by noteId.

---

## Phase 11B — Audio Player (2026-03-26)

| Change | Description | Status |
|--------|-------------|--------|
| AudioPlayer component | Compact player: play/pause + seek bar + time display | ✅ Done |
| Note detail integration | Renders between metadata chips and date; self-hides when no audio blob exists | ✅ Done |
| Infinity duration fix | webm/opus blobs lack duration headers — workaround seeks to large value to force browser to resolve real duration | ✅ Done |

New files: `src/components/audio-player.tsx`
Modified: `src/components/note-detail.tsx`

Technical notes:
- Native `HTMLAudioElement` + `<input type="range">` — zero extra dependencies
- Audio loaded via `URL.createObjectURL(blob)` from IndexedDB, revoked on unmount
- `formatTime()` guards against `Infinity`/`NaN` while duration resolves

---

## Phase 11C — Word-Level Sync Highlighting (2026-03-26)

| Change | Description | Status |
|--------|-------------|--------|
| SyncedTranscript component | Renders every word as an individual `<span>` with click-to-seek | ✅ Done |
| Active word highlighting | Binary search on word timestamps synced to audio `currentTime` | ✅ Done |
| Auto-scroll | `scrollIntoView({ behavior: "smooth", block: "nearest" })` on active word | ✅ Done |
| Diarized support | Speaker-colored highlight backgrounds per segment | ✅ Done |
| AudioPlayer ref API | `forwardRef` + `useImperativeHandle` exposes `seek(time)` to parent | ✅ Done |
| Fallback | Falls back to static DiarizedTranscript / plain text when no audio available | ✅ Done |

New files: `src/components/synced-transcript.tsx`
Modified: `src/components/audio-player.tsx`, `src/components/note-detail.tsx`

Architecture: NoteDetail holds `audioTime` state, passes it to SyncedTranscript. AudioPlayer broadcasts time via `onTimeUpdate` callback. SyncedTranscript finds the active word via binary search and highlights it. Click on any word calls `seek()` on the player via ref.

---

## Phase 12A — Note Content Editing + Personal Dictionary (2026-03-26)

| Change | Description | Status |
|--------|-------------|--------|
| Content edit mode | Pencil button on transcript → textarea with Save/Cancel | ✅ Done |
| Dictionary context | `DictionaryProvider` + `useDictionary()` hook, localStorage storage | ✅ Done |
| Selection toolbar | Floating "Add to Dictionary" popup on text selection in transcripts | ✅ Done |
| API keyterms | Keyterms passed as repeated `keyterms` form fields to ElevenLabs API | ✅ Done |
| Settings UI | Dictionary section in Settings — add/remove/clear key terms | ✅ Done |
| CLAUDE.md terminology | Documented that "dictionary" = keyterms for transcription, NOT word lookup | ✅ Done |

New files: `src/lib/dictionary-context.tsx`, `src/components/selection-toolbar.tsx`
Modified: `src/components/note-detail.tsx`, `src/components/voice-recorder.tsx`, `src/components/file-upload.tsx`, `src/app/api/transcribe/route.ts`, `src/app/(app)/settings/page.tsx`, `src/app/(app)/layout.tsx`

**IMPORTANT — "Dictionary" in this project:** The "dictionary" feature is a **personal glossary of key terms** submitted as the `keyterms` parameter to ElevenLabs Scribe v2 to improve transcription accuracy for names, jargon, and domain-specific vocabulary. It is NOT a word-definition/lookup feature. Terms are stored in localStorage, managed by `DictionaryProvider`, and appended to every transcription request.

ElevenLabs `keyterms` constraints: max 1,000 terms, max 50 chars per term, max 5 words per term. Uses context-aware matching (not blind keyword biasing). Additional cost when >100 terms.

---

## Phase 12A+ — UI Polish Pass (2026-03-26)

This session covered a broad set of UX improvements and bug fixes after Phase 12A.

### Export Enhancements

| Change | Description | Status |
|--------|-------------|--------|
| Plain markdown export | New `toPlainMarkdown()` — markdown without metadata footer | ✅ Done |
| Text with metadata export | New `toTxtWithMeta()` — plain text with date/word-count/duration footer | ✅ Done |
| Export dropdown padding | Added `py-2.5` to export items for better touch targets | ✅ Done |
| 5 export formats | txt, txt+meta, md, md+meta, srt — all with diarization support | ✅ Done |

### Transcribe Options UX

| Change | Description | Status |
|--------|-------------|--------|
| Options below buttons | Moved options toggle below Record/Upload/Type to reduce friction | ✅ Done |
| Language moved to Settings | Language is a "set once" preference — removed from home page, kept in Settings only | ✅ Done |
| Options pill button | Replaced faint text link with visible pill button (border, SlidersHorizontal icon, press feedback) | ✅ Done |
| Removed ActiveChips | No more badges/chips when Options is collapsed — cleaner home page | ✅ Done |

### Language Picker

| Change | Description | Status |
|--------|-------------|--------|
| 99 Scribe v2 languages | Full list of all supported languages with correct ISO codes | ✅ Done |
| Searchable dialog | Dialog with search-as-you-type, scrollable list, checkmark on selected | ✅ Done |
| Auto-detect (Recommended) | Top option pinned above separator, clearly labeled as recommended | ✅ Done |
| "Bahasa Indonesia" | Full native name for Indonesian language | ✅ Done |
| Render function fix | Base UI SelectValue was showing raw value codes — fixed with explicit render functions | ✅ Done |

### Typography & Theming

| Change | Description | Status |
|--------|-------------|--------|
| Inter font | Switched from self-hosted Figtree to Inter variable font via rsms.me CDN | ✅ Done |
| Font feature settings | `'liga' 1, 'calt' 1` for Chrome ligature fix | ✅ Done |
| Deleted Figtree files | Removed `public/fonts/Figtree-*.woff2` (no longer used) | ✅ Done |
| Theme-aware scrollbars | Thin 6px scrollbar, transparent track, translucent thumb adapts to light/dark | ✅ Done |

### Bug Fixes

| Fix | Description | Status |
|-----|-------------|--------|
| Mobile hover states | Edit button was `opacity-0 group-hover:opacity-100` — moved to always-visible action bar | ✅ Done |
| Export text gray | shadcn Select placeholder color override made "Export" text gray — fixed with `data-placeholder:text-foreground` | ✅ Done |
| Export dropdown truncated | `w-(--anchor-width)` constrained dropdown width — fixed with `min-w-56` | ✅ Done |
| Chevron color mismatch | Export dropdown chevron was gray while text was black — fixed with `[&_svg]:text-foreground` | ✅ Done |
| Language code display | Select showed raw value ("id") instead of label ("Bahasa Indonesia") — fixed all SelectItem usages with explicit `label` props and render functions | ✅ Done |
| Legacy localStorage migration | Users with old `languageCode: ""` auto-migrated to `"auto"` on load | ✅ Done |

Modified files: `src/components/transcribe-options.tsx`, `src/components/note-detail.tsx`, `src/components/notes-list.tsx`, `src/components/voice-recorder.tsx`, `src/components/file-upload.tsx`, `src/lib/transcribe-options-context.tsx`, `src/lib/types/index.ts`, `src/lib/export.ts`, `src/app/(app)/page.tsx`, `src/app/layout.tsx`, `src/app/globals.css`

Deleted files: `public/fonts/Figtree-Variable.woff2`, `public/fonts/Figtree-Italic-Variable.woff2`

Design decisions:
- **Language in Settings only** — Inspired by Wispr Flow's approach. Language is a "set once and forget" setting, not a per-recording toggle. Home page Options only shows Speakers + Sounds.
- **Searchable dialog over dropdown** — 99 languages can't fit in a simple Select dropdown. Dialog with search input is more intuitive and touch-friendly.
- **Single language select** — Scribe v2 accepts one `language_code` (not an array). It handles code-switching/multilingual audio automatically, so Auto-detect is recommended for most use cases.
- **Inter font via CDN** — Free, variable-weight, excellent readability. CDN avoids self-hosting maintenance. `InterVariable` with `font-feature-settings` for proper ligatures.

---

## Phase 12A++ — Note Detail Redesign + Bug Fixes (2026-03-26)

### Note Detail Page Redesign

| Change | Description | Status |
|--------|-------------|--------|
| ⋯ menu in header | Three-dot menu at title level with Export submenu + Delete | ✅ Done |
| Export submenu | Export options grouped under "Export →" with tap-friendly Base UI submenu | ✅ Done |
| Split copy button | Copy plain text (left) + "Copy as..." dropdown (right, separated by divider) with Plain Text, Text+meta, Markdown, MD+meta options | ✅ Done |
| Actions above content | Copy + Edit moved above audio player/transcript — no more sticky bottom bar | ✅ Done |
| Metadata simplified | Replaced pill badges with single plain text line: "Mar 26, 2026 · 42 words · IND" | ✅ Done |
| Date-first ordering | Timestamp leads metadata line (orient *when*, then stats) | ✅ Done |
| Duration dropped from metadata | Already visible on audio player — no need to show twice | ✅ Done |

Layout order: `header (← title ⋯)` → `metadata line` → `tags` → `copy/edit actions` → `audio player` → `transcript`

### Notes List Fixes

| Change | Description | Status |
|--------|-------------|--------|
| Sort button alignment | Fixed icon pushed left by hidden SelectPrimitive.Icon wrapper — use `data-slot` selector + `justify-center` | ✅ Done |
| Sort moved to heading row | Sort control sits next to "Notes" heading (justify-between), shows label text (Newest/Oldest/A-Z/Z-A) | ✅ Done |
| Search bar standalone | Full-width search input on its own row, no competing elements | ✅ Done |

### Bug Fixes

| Fix | Description | Status |
|-----|-------------|--------|
| Firestore undefined field | `additionalFormats: undefined` rejected by Firestore — conditionally spread to omit when absent | ✅ Done |

New files: `src/components/ui/dropdown-menu.tsx` (shadcn, Base UI Menu primitive)
Modified: `src/components/note-detail.tsx`, `src/components/notes-list.tsx`, `src/app/(app)/notes/page.tsx`, `src/components/file-upload.tsx`

Design decisions:
- **Split copy button** — Inspired by common "button group" pattern. Default action (copy plain text) is one tap. Power users can copy as Markdown for Notion/Obsidian workflows via the chevron dropdown.
- **⋯ menu over bottom bar** — Export and Delete are secondary/destructive actions. Hiding them behind a menu reduces visual clutter while keeping them discoverable. Submenu groups 5 export formats under one entry.
- **Actions above content** — For long transcripts (2-hour meetings), a sticky bottom bar is insufficient and the actions should be immediately visible without scrolling.
- **Plain text metadata** — Pill badges were visually heavy for secondary info. A single `text-xs text-muted-foreground/60` line matches the note card style and reduces visual noise.

---

## Phase 12B — API Error Handling + Retry (2026-03-26)

### Server-side (API Route)

| Change | Description | Status |
|--------|-------------|--------|
| Exponential backoff retry | Auto-retries transient errors (5xx, 429) up to 2 times with 1s→2s backoff | ✅ Done |
| Structured error parsing | Parses ElevenLabs error body for specific messages (rate limit, auth, file size) | ✅ Done |
| Retryable flag | Response includes `retryable: boolean` so clients know whether to offer retry | ✅ Done |

### Client-side

| Change | Description | Status |
|--------|-------------|--------|
| Voice recorder retry | On failure, shows Retry + Discard buttons (keeps audio blob for re-attempt) | ✅ Done |
| File upload retry button | Upload button turns into retry icon (RotateCcw) when last upload failed | ✅ Done |
| File upload retry toast | Error toast includes "Retry" action button (8s duration) | ✅ Done |

Modified: `src/app/api/transcribe/route.ts`, `src/components/voice-recorder.tsx`, `src/components/file-upload.tsx`

Error handling strategy:
- **Server retries first** — transient ElevenLabs errors (5xx, network) are retried automatically with exponential backoff before the error reaches the client
- **Client retry as fallback** — if all server retries fail, the user gets a clear error message and a one-tap retry option that reuses the original audio blob/file
- **No retry for client errors** — 400/401/403/413 responses are returned immediately with specific messages (invalid file, auth failed, file too large)

---

## Phase 12C — PWA Polish (2026-03-26)

| Change | Description | Status |
|--------|-------------|--------|
| PNG icons | Generated 180/192/512px PNGs from SVG via sharp | ✅ Done |
| apple-touch-icon | 180px PNG for iOS home screen | ✅ Done |
| iOS meta tags | apple-mobile-web-app-capable, status-bar-style (black-translucent), app title | ✅ Done |
| Dynamic theme-color | White (#ffffff) for light mode, near-black (#0a0a0a) for dark mode via media queries | ✅ Done |
| Manifest icons | 4 entries: SVG (any), 192px PNG, 512px PNG (any), 512px PNG (maskable) | ✅ Done |
| .gitignore fix | Whitelisted `public/icon-*.png` so PWA icons are tracked | ✅ Done |

Modified: `src/app/layout.tsx`, `src/app/manifest.ts`, `.gitignore`
New files: `public/icon-180.png`, `public/icon-192.png`, `public/icon-512.png`

---

## Phase 12D — Accessibility Improvements (2026-03-26)

| Change | Description | Status |
|--------|-------------|--------|
| Skip-to-content | Hidden link at top of app layout, visible on focus, jumps to `#main-content` | ✅ Done |
| Nav landmark | `aria-label="Main navigation"` on bottom tab bar `<nav>` | ✅ Done |
| Active tab indicator | `aria-current="page"` on active bottom tab link | ✅ Done |
| Live regions | `role="status"` + `aria-live="polite"` on transcription spinner | ✅ Done |
| Timer role | `role="timer"` on recording duration with descriptive `aria-label` | ✅ Done |
| Search label | `aria-label="Search notes"` on search input | ✅ Done |
| Cancel label | `aria-label="Cancel recording"` on cancel button | ✅ Done |
| Decorative icons | `aria-hidden="true"` on chevrons, search icon, source badge icons, empty state mic | ✅ Done |
| Color contrast | Removed `/50` and `/60` opacity from `text-muted-foreground` across cards, metadata, timestamps, empty states, placeholders | ✅ Done |
| Sign-out contrast | Bumped from `text-muted-foreground/50` to `text-muted-foreground` | ✅ Done |

Modified: `src/app/(app)/layout.tsx`, `src/components/bottom-tab-bar.tsx`, `src/components/note-card.tsx`, `src/components/note-detail.tsx`, `src/components/notes-list.tsx`, `src/components/voice-recorder.tsx`

---

## Post-MVP Roadmap (in priority order)

### Near-term

1. **Landing page polish + production readiness** — keep refining the public-facing mockup until it is clear which parts are purely directional and which parts reflect shipped product behavior
2. **Cloud audio storage / cross-device sync** — replace IndexedDB-only audio with a real backend when the project is ready for that complexity/cost
3. **Real-time WebSocket transcription** — live transcript while recording (ElevenLabs streaming API)
4. **PDF + DOCX export** — server-side generation with pdfkit and docx packages
5. **Indonesian landing page + region detection** — Bahasa Indonesia translation of the landing page, auto-served via geo-detection when the visitor is in Indonesia (English for all other regions). Includes a quick language switcher for manual override.
6. **Business logic for credits/pricing** — if/when the app becomes a real business: credit balance model, purchase flow, pre-transcription estimates, usage deduction, and pricing transparency UI based on `PRICING.md`

### AI Intelligence Layer (multi-session, Plaud AI-inspired)

This is the big one. Requires dedicated design/planning session(s) with Plaud AI as reference. Implementation order TBD. Features below assume ElevenLabs Scribe v2 for ASR + a second AI API call (e.g. Claude/GPT) for post-processing.

**7. Post-transcription AI cleanup** — Second LLM API call after ASR to fix typos, remove speech disfluencies (ums, false starts), and normalize punctuation. Output replaces the raw transcript in the note.

**8. Automatic note-type detection** — AI classifies the audio into a note type based on transcript content:
- Personal note / memo
- Team meeting recording
- 1:1 / video call
- Webinar / lecture / class
- Interview
- (extensible)
Note type drives which AI tabs and analyses are generated.

**9. Dual-layer note structure (Sources + Notes tabs)** — Inspired by Plaud AI's two-panel layout:
- **Sources tab**: audio player, AI-generated outline (topic timestamps, like a document outline using timestamps as headings), full transcript with two-way sync highlighting + per-speaker labels + atomic timestamp separators (when diarization enabled)
- **Notes tab**: tabbed sub-views generated based on note type (see below)

**10. AI-generated Notes sub-tabs (note-type aware)**
- **Highlights** — Key events, remarks, and statements from the recording (e.g. "Speaker 6 raised an unresolved issue regarding X")
- **Overview / Executive Summary** — Concise summary of key points; for meetings may include team-level action items in checkboxes
- **Action Items / To-do List** — Checkboxed next-actionable items; grouped per person with topic headings
- **Power Dynamics** *(meetings/calls only)* — Analysis of team dynamics: role summaries per speaker, influence notes, topped with a Mermaid mindmap diagram of the power structure at the bottom of the panel

**11. Global speaker rename** — Speakers default to "Speaker 1", "Speaker 2", etc. Clicking any speaker name anywhere in the note opens an inline rename. Renaming propagates instantly across the entire note: transcript, outline timestamps, highlights, action items, power dynamics analysis, and the Mermaid diagram.

### Later

12. **Notion / Google Docs export** — OAuth integration
13. **Privacy Policy page** — `/privacy` route covering data collection, Firebase/Firestore usage, ElevenLabs API data handling, cookie policy. Footer link currently exists as a mockup placeholder on public pages — update to `/privacy` when created.
14. **Terms of Service page** — `/terms` route covering credit system terms, acceptable use, liability limitations. Footer link currently exists as a mockup placeholder on public pages — update to `/terms` when created.

### Production Readiness (when the app gets real users)

These are hardening concerns — intentional tradeoffs today that need addressing before real users are on the platform. They're not features; they're infrastructure/security work.

1. **Server-side search + pagination** — Client-side filtering currently fetches all notes from Firestore. At scale: add Firestore composite indexes, cursor-based pagination, or a dedicated search service to avoid pulling the full dataset on every query.

2. **Dev bypass removal** — Strip or feature-flag the `devSignIn` anonymous login code path before any public deploy. Currently gated by `NEXT_PUBLIC_DEV_PASSWORD` env var, but the code path itself shouldn't ship to production.

3. **Dictionary cloud sync** — Personal keyterms live in localStorage only. Move to Firestore (e.g. `/users/{uid}/settings/dictionary`) for cross-device consistency. Separate from the audio cloud sync item (#2 above) — this is a smaller, independent task.

4. **Rate limiting on `/api/transcribe`** — No per-user rate limiting exists today. A malicious or runaway client could rack up ElevenLabs API costs. Add per-user throttling before opening to the public.

5. **Firestore security rules audit** — Verify rules enforce strict user isolation, field validation, and document size limits before real traffic hits the platform.

---

## How to Run

```bash
npm install
npm run dev    # http://localhost:3000
```

Requires `.env.local` with `ELEVENLABS_API_KEY`. See `.env.example`.
