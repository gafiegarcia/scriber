# Third-Party Notices

Scriber depends on third-party software that is not owned or relicensed by the Scriber copyright holder. Each component remains subject to its own license.

This file is the repository-level compliance inventory. A distributed release must also include the exact notices and license texts required by the components actually present in that release artifact.

## Native macOS app

The native app currently uses Apple platform frameworks and does not declare a third-party Swift package dependency. Apple SDK and operating-system components are governed by Apple's terms and are not covered by Scriber's GPL license.

The candidate Scriber SVG artwork under [`apps/macos/Branding`](apps/macos/Branding) was created for this project from basic geometry and does not intentionally incorporate third-party artwork; see [`docs/ICON_PROVENANCE.md`](docs/ICON_PROVENANCE.md). The earlier unknown-provenance Icon Composer draft remains untracked and must not be incorporated into a release.

## Archived Electron app

The Electron implementation's JavaScript dependencies are enumerated in [`apps/electron/package-lock.json`](apps/electron/package-lock.json). Their individual license metadata and upstream license texts remain controlling.

Release-sensitive components include:

- `ffmpeg-static` 5.3.0 and `@derhuerst/ffprobe-static` 5.3.0, whose lockfile entries are labeled `GPL-3.0-or-later`. Their downloaded macOS binaries must not be redistributed by Scriber.
- The pinned release FFmpeg/ffprobe build described in [`apps/electron/docs/FFMPEG_DISTRIBUTION.md`](apps/electron/docs/FFMPEG_DISTRIBUTION.md), configured for an LGPL 2.1-or-later profile with GPL and nonfree components disabled. A release must follow that document's notice, corresponding-source, signing, and verification checklist.
- Sharp platform packages and their bundled libvips components, which use a combination of Apache 2.0, LGPL 3.0-or-later, MIT, or other package-specific terms depending on the selected platform artifact.
- Electron, Next.js, React, Lucide, and all other production dependencies listed in the lockfile, whose required notices must be generated from the exact dependency tree included in a release.

Before distributing any native or Electron build, produce and inspect an artifact-specific third-party notice bundle, preserve required copyright and license texts, and satisfy source-code or relinking obligations for bundled copyleft components. This repository file is not a substitute for that release-level audit.
