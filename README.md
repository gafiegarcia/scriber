# Scriber

If you're looking for a dictation app for macOS to daily-drive, you might want to check out [these alternatives I wrote below](#better-alternatives) first (unless you're curious enough to build this yourself and try it out).

I asked Codex and Claude to build a Wispr Flow alternative (didn't like its RAM usage). Scriber is a native macOS dictation app that lives in the menu bar by default, built with Swift, SwiftUI, and AppKit. Let me rephrase: Scriber is an ElevenLabs Scribe v2 API wrapper written in Swift that works just like Wispr Flow (mostly).

- <100MB of RAM usage
- BYOK (only supports ElevenLabs)
- Auto-paste with paste-fail detection (jargon-y enough?)

## Why ElevenLabs?

Its Scribe v2 model is not just benchmark-accurate, but also cover my personal use cases:

- handles Bahasa Indonesia well, even when quickly code-switching between it and English (Whisper does this too, but only to a certain level with less accuracy)
- knows way more key terms and phrases internally than other providers like Deepgram and local models, including Whisper
- generous free monthly credits (for non-heavy dictation users, 10k credits, which equals to 2h30m of transcription via API, just won't run out)
- auto-punctuation, filler words removal, and (slight) grammar correction working so well means it doesn't need any post-processing at all (unless you need context-aware refinement, like querying text on the screen/around the cursor to give context to the post-processing AI, which I don't need)

## (Better) Alternatives...

I've been personally using Scriber for weeks, and the latest version accommodate my simple not-too-frequent needs just fine. I initially planned to keep maintaining it (read: report bugs and ask for features & improvements to tha clankers) and using it personally as I haven't found one I really like among the available free Wispr Flow alternatives I found. I now decided to **stop spending tokens to vibe-code and halt development of Scriber after I found [Spokenly](https://spokenly.app/)**.

### [Wispr Flow](https://wisprflow.ai/)

Seriously, if you're okay with its privacy policy (just got updated after the new Notetaker feature shipped), and how it uses >400MB of your RAM even when idle, just use Wispr Flow

- it's a trend-setter and used by many for a reason
- great ux, great onboarding, easy-to-use
- free users get 2000 words/week on desktop, 1000 words/week on mobile. more than enough for many
- aside from the word limit, most features (except for the history sync, command mode and synced scratchpad, as far as I remember) are *not paywalled*.
- app-aware transcription style customization. email format, casual/formal/original style (lowercase for chats, polished grammer and capitalization for email/the rest, etc.), etc. and very easy to understand and configure
- now also has a meeting transcription feature called "Notetaker" with real-time notes, speaker diarization, and summary notes (which I believe includes your jotted down notes as well)

### [Spokenly](https://spokenly.app/)

- what I currently use
- supports hosted, BYOK, and local models
- good UX (arguably better than Wispr Flow at some parts): smart paste, hold + toggle in one shortcut, etc.
- defaults to ElevenLabs Scribe v2 (biased...)
- only uses ~150MB ram (on my mac)
- app-aware formatting, with a different approach to Wispr Flow: it lets users add and configure the "templates", customize where each one triggers, manually select it during/after dictating, and set custom prompt for the post-processing, in contrast to Wispr Flows' approach of ready-made configs (can be confusing for normies or semi-normies like me, while Wispr Flow's settings is so easy to understand that your non-tech-y friends and family might be able to fully use and configure it given enough time)
- live mode (using realtime models)
- claude code & cowork, cursor, and codex integration via mcp (what?)
- cli

Ofc it comes with some minor caveats:

- unfamiliar settings UI
- so many features are not paywalled, except for the one I want to enable the most. it's sad that I must subscribe to select the option to have the dictation interface on the notch
- shipped with sane defaults, but you'll need to spend some time to learn all features and possible configurations
- *closed source*. I can't learn how it works (read: can't steal ideas from its code)

### Open source alternatives

here are the ones I found. tried some, but not really tested. you can just check them out

1. paid-turned-open-source: [https://github.com/Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)
2. [freeflow](https://github.com/zachlatta/freeflow) 
3. [unramble](https://github.com/mrinalwadhwa/unramble)

---

## Repository

- [`apps/macos`](apps/macos) contains the active native app.
- [`apps/electron`](apps/electron) is the frozen `0.6.0` Electron/Next.js
  implementation, retained as a feature reference and possible foundation for
  future Windows or Linux work.

The implementations are self-contained. There is no root JavaScript package or
shared runtime layer.

The native line continues the product version after Electron `0.6.0`. The Xcode
project is the source of truth for the bundle build number. See the
[changelog](CHANGELOG.md) for released snapshots and the
[versioning policy](docs/VERSIONING.md) for how versions, builds, and tags differ.

## Native macOS app

See the [native README](apps/macos/README.md) for prerequisites, building,
verification, installation, and first launch. Required behavior, planned work,
and the verification checks live under [`apps/macos/docs`](apps/macos/docs).

## License

Original Scriber source code and documentation are copyright © 2026 Gafie
Garcia and licensed under the [GNU General Public License, version 3 or
later](LICENSE).

Third-party components retain their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The GPL does not grant
trademark rights in the Scriber name or logo; see [COPYRIGHT.md](COPYRIGHT.md).
