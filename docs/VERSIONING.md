# Scriber Versioning Policy

## Product lineage

Versions identify the Scriber product, not the age of a repository or a specific implementation. The retired Electron app reached `0.6.0`; the native macOS app is its successor on the `0.7.0` line. Rewriting the app in Swift and adopting a new native bundle identity did not restart the product at `0.1.0`.

Platform implementations do not have to ship every product version. The Electron source is no longer in the tree. It was never tagged under its own version; `v0.8.6` is the last tag whose tree still contains it.

## Separate identifiers

- **Marketing version** is the user-facing product line, stored as `MARKETING_VERSION` in the native Xcode project.
- **Bundle build** is `CFBundleVersion`, stored as `CURRENT_PROJECT_VERSION` in the native Xcode project. It distinguishes installable binaries but says nothing about release maturity.
- **Release label** is the maturity of an intentionally frozen Git snapshot, expressed by a tag such as `v0.7.0-alpha.8` or `v0.7.0`.

The native [Xcode project file](../Scriber.xcodeproj/project.pbxproj) is the only repository source of truth for the current bundle build. Do not copy that volatile number into README, roadmap, specification, or policy prose. An installed app may legitimately differ from the checked-out source.

An Xcode **Release** configuration is an optimized build configuration; it does not mean the product has been released.

## Tags and changelog

- Do not tag ordinary development commits or local builds.
- Do not call an untagged candidate `vX.Y.Z-alpha.N`. Use “bundle build N candidate” until the annotated tag actually exists.
- Record user-relevant changes under `Unreleased` in the root [`CHANGELOG.md`](../CHANGELOG.md), then move them under the exact version only when its tag is created.
- Treat pushed tags as immutable; a correction receives a new patch tag.
- Create a tag only when the documented personal-use behavior passes its release gates in [`ROADMAP.md`](ROADMAP.md).

Annotated tag messages carry engineering metadata that does not belong in the changelog: bundle build, credential and signing state, verification performed, known limitations, and confirmation that no credentials, recordings, local history, or machine-specific output are included.

## What a version claims

`v0.7.0` claims one thing: the documented personal-use behavior is accepted. It is the first tag on this line without a prerelease suffix, which is the whole point of cutting it — the project stops asking "is this alpha or beta yet?" and starts iterating on plain numbers.

It does **not** claim polish. The leading `0` carries that, and it is deliberate: this is a personal tool that works, not a finished product.

After `v0.7.0`, one question decides the next version:

- A fix or a small correction is a **patch** — `0.7.1`, `0.7.2`.
- A significant new capability, such as a long-form transcription workspace, is a **minor** — `0.8.0`.

Prerelease labels are retired. `alpha.N` was answering an unanswerable question: nothing distinguishes an alpha from a beta here, so the label was a guess that had to be defended every time. "Fix or new capability?" always has an answer. `v1.0.0` is a separate decision about the product being finished, not a milestone this scheme walks up to on its own.

## Distribution is a separate milestone

A source tag, code signing, and notarized binary distribution are independent of each other. Developer ID signing, notarization, Gatekeeper validation, and a supported downloadable binary belong to a later distribution-ready milestone, and no version number on the `0.x` line implies any of them.
