# FFmpeg distribution notes

Scriber uses `ffmpeg` and `ffprobe` as separate processes to extract audio from
video files. The colleague-facing Mac app must not redistribute the downloaded
`ffmpeg-static` package binaries: their current macOS builds contain nonfree
components and explicitly report that they are not legally redistributable.

## Pinned Mac-app build

- FFmpeg: **8.1.2** (official stable release, 2026-06-17)
- Source: <https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz>
- SHA-256: `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`
- License profile: LGPL 2.1 or later, with GPL, nonfree, version-3-only, external
  libraries, networking, devices, and hardware acceleration disabled
- Target: Apple-silicon macOS (arm64), minimum macOS 12

Run `npm run build:ffmpeg:mac` on macOS. The script downloads and verifies the
pinned official source, builds the arm64 tools using only Apple command-line
tools, and writes ignored artifacts to:

```text
.ffmpeg/
  darwin-arm64/{ffmpeg,ffprobe,BUILD_INFO.txt,LICENSE.md,COPYING.LGPLv2.1,...}
```

`npm run verify:ffmpeg:mac` checks CPU architecture, linkage, build flags,
license output, native AAC and MOV/MP4 support, and a real video-to-M4A
conversion on Apple silicon.

The desktop wrapper bundles only the arm64 artifacts and sets
`SCRIBER_FFMPEG_PATH` plus `SCRIBER_FFPROBE_PATH` to those signed resources.

## Release compliance checklist

FFmpeg's official legal page is the source of truth:
<https://ffmpeg.org/legal.html>.

Before distributing `Scriber.app`:

1. Sign and verify the nested `ffmpeg` and `ffprobe` executables as part of the
   app's hardened-runtime signing flow.
2. Run the functional verification natively on the arm64 release artifact.
3. Ship the LGPL notice and FFmpeg acknowledgment in the app's About/legal UI.
4. Host the exact `ffmpeg-8.1.2.tar.xz` corresponding source (plus the unmodified
   build scripts/configuration) on the same release server and link it beside
   every app download.
5. Do not add EULA language that prohibits the reverse engineering rights
   required by the LGPL.
6. Re-run this audit whenever FFmpeg, its flags, or any external library changes.

This file records the engineering safeguards; it is not legal advice.
