# Scriber Licensing Notes

Status: decided and implemented. These are engineering notes, not legal advice.

Recorded: 2026-07-20

## Project-license goals

Gaf wants Scriber and distributed derivatives to remain open source, while retaining the option to charge for binaries, support, or a future managed-billing service.

- `MIT` is familiar and permissive, but permits proprietary forks.
- `GPL-3.0-or-later` requires source and the same freedoms when covered software is distributed, while allowing commercial use and sale.
- `AGPL-3.0-or-later` adds a corresponding-source obligation for a modified version used to provide a service over a network.
- No standard open-source license requires publication of purely private modifications.

Using GPL or AGPL as a beginner is not inherently presumptuous. The clearest framing is that copyleft expresses a product value—recipients should keep the same freedoms—not that other people are forbidden from earning money. Both licenses permit commercial use. Gaf can charge for Scriber itself or for a managed service as long as the applicable source obligations are honored; doing so is not hypocritical.

If substantial outside contributions are accepted later, relicensing or offering a separate proprietary license can become difficult without appropriate contributor terms. Decide that policy before such contributions accumulate.

## Decision

Scriber's original code and documentation are licensed under `GPL-3.0-or-later`.

This choice matches the current distributed desktop application and Gaf's goal that distributed derivatives remain open source. AGPL's network-use clause is not applied to the repository because a hosted Scriber service is hypothetical. A future independently developed service can receive its own deliberate license decision.

The root [`LICENSE`](../LICENSE) contains GNU's unmodified GPLv3 text. [`COPYRIGHT.md`](../COPYRIGHT.md) records the copyright and trademark boundary, and [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) records the third-party compliance inventory. The archived Electron package metadata now uses the same SPDX identifier without changing its historical `0.6.0` version or implementation.

## AI-assisted authorship scope

OpenAI's Terms state that, as between the user and OpenAI and to the extent permitted by law, the user owns output and OpenAI assigns any rights it has in that output. The Terms also warn that output may not be unique. Copyrightability of AI-generated material remains jurisdiction-dependent and can require human authorship.

The project license therefore covers only rights Gafie Garcia can grant, including protectable human selection, arrangement, edits, documentation, and other original contributions. It does not relicense third-party material or create copyright in material that applicable law does not protect. Preserve development history and audit third-party code and assets before public distribution.

AI-related references:

- OpenAI Terms of Use: <https://openai.com/policies/terms-of-use/>
- U.S. Copyright Office AI initiative and copyrightability report: <https://www.copyright.gov/ai/>

License references:

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

1. Complete trademark clearance before treating Scriber as a settled public product name.
2. Review the documented candidate icon in Icon Composer and live app contexts before treating it as final branding; never use the unknown-provenance draft.
3. Generate complete third-party notices from the actual native and Electron release artifacts, not only package manifests.
4. Re-run FFmpeg, Sharp/libvips, Electron, and other binary-component checks for each distributed platform.
5. Choose contributor terms before accepting substantial outside contributions if future relicensing flexibility matters.
