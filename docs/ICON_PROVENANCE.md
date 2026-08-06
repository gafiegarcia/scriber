# Scriber Icon Provenance

Recorded: 2026-07-20

## Current artwork

The Scriber icon artwork was created specifically for this project from basic SVG geometry at Gafie Garcia's direction, with AI-assisted implementation by OpenAI Codex. Gaf then imported that clean geometric base into Figma and personally reshaped and simplified the microphone before exporting the current artwork.

The current design has a compact white microphone, recording cradle, and stand. Its default SVG places the mark on a `#000000` rounded square; its dark-appearance SVG places the white mark on transparency. Gaf subsequently adjusted the group scale, combined lighting, glass, translucency, and appearance visibility directly in Icon Composer. No third-party icon, font, logo, or SVG path is intentionally incorporated.

Files:

- [`../apps/macos/Branding/ScriberIcon-BlackBackground.svg`](../apps/macos/Branding/ScriberIcon-BlackBackground.svg)
- [`../apps/macos/Branding/ScriberIcon-Transparent.svg`](../apps/macos/Branding/ScriberIcon-Transparent.svg)
- [`../apps/macos/Scriber/AppIcon.icon`](../apps/macos/Scriber/AppIcon.icon), the Icon Composer source connected to the native app target

The artwork is offered under the MIT license in [`../LICENSE`](../LICENSE), to the extent that Gafie Garcia holds rights that can be licensed.

`AppIcon.icon` is tool-managed. Icon Composer may preserve or regenerate imported asset filenames when it saves; those internal names do not change the provenance of the canonical SVG artwork above.

## Superseded artwork

The original untracked `Untitled.icon` draft passed through several Figma Make and Claude Code iterations, and its upstream artwork source and license could not be established. Its unknown SVG assets were replaced and their path data was not reused or transformed into the current artwork. The cleaned Icon Composer document was renamed to `AppIcon.icon` only after it contained the newly created and Figma-edited SVGs.

Commit `531eac7` preserves the first clean geometric candidate in repository history; Gaf's Figma-edited SVGs supersede that candidate in the current tree. If the icon is substantially redesigned later, record the tools, source material, contributors, and license of the replacement here before distribution.
