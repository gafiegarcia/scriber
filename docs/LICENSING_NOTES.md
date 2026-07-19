# Scriber Licensing Notes

Status: open decision. These are preliminary engineering notes, not legal advice.

Recorded: 2026-07-20

## Project-license goals

Gaf wants Scriber and distributed derivatives to remain open source, while retaining the option to charge for binaries, support, or a future managed-billing service.

- `MIT` is familiar and permissive, but permits proprietary forks.
- `GPL-3.0-or-later` requires source and the same freedoms when covered software is distributed, while allowing commercial use and sale.
- `AGPL-3.0-or-later` adds a corresponding-source obligation for a modified version used to provide a service over a network.
- No standard open-source license requires publication of purely private modifications.

Using GPL or AGPL as a beginner is not inherently presumptuous. The clearest framing is that copyleft expresses a product value—recipients should keep the same freedoms—not that other people are forbidden from earning money. Both licenses permit commercial use. Gaf can charge for Scriber itself or for a managed service as long as the applicable source obligations are honored; doing so is not hypocritical.

If substantial outside contributions are accepted later, relicensing or offering a separate proprietary license can become difficult without appropriate contributor terms. Decide that policy before such contributions accumulate.

Official references:

- GNU GPLv3: <https://www.gnu.org/licenses/gpl-3.0.en.html>
- GNU GPLv3 guide: <https://www.gnu.org/licenses/quick-guide-gplv3.html>
- Why GNU recommends AGPL for network services: <https://www.gnu.org/licenses/why-affero-gpl.html.en>

## Preliminary Electron dependency findings

The GPL/LGPL note concerns packages in the archived Electron app, not the native Swift app:

- `apps/electron/package-lock.json` labels direct dependencies `ffmpeg-static` 5.3.0 and `@derhuerst/ffprobe-static` 5.3.0 as `GPL-3.0-or-later`.
- The lockfile includes optional Sharp/libvips platform packages labeled `LGPL-3.0-or-later` or combined with Apache/MIT terms. The Sharp JavaScript/platform wrapper entries themselves may use different licenses; the specific bundled component matters.
- A dependency's license metadata does not, by itself, prove that all Scriber source code must use that license. Obligations depend on what is copied, linked, modified, and distributed, so every release artifact still needs a component-level audit.

The existing Electron release safeguards deliberately do not redistribute the downloaded `ffmpeg-static` macOS binaries. `apps/electron/docs/FFMPEG_DISTRIBUTION.md` instead pins an FFmpeg source build configured for an LGPL 2.1-or-later profile with GPL and nonfree components disabled, and records the corresponding release checklist. That distinction is why the lockfile finding is a compliance item rather than an automatic conclusion that the whole repository is already GPL.

## Items to resolve before a public release

1. Choose the root project license and exact version form (`-only` or `-or-later`).
2. Add `Copyright © 2026 Gafie Garcia` and the chosen license text.
3. Decide how the provisional Scriber name and logo are treated separately from the code license after trademark clearance.
4. Generate complete third-party notices from the actual native and Electron release artifacts, not only package manifests.
5. Re-run FFmpeg, Sharp/libvips, Electron, and other binary-component checks for each distributed platform.
