# Scriber Versioning Policy

Status: decided.

Recorded: 2026-07-20.

## Product lineage

Versions identify the Scriber product line, not the age of a particular codebase or repository.

The archived Electron implementation reached `0.6.0`. The native macOS implementation is its successor and continues the product line at `0.7.0`, even though it was rewritten in Swift, began as the Scriber Dictate prototype, and adopted a clean bundle and data identity. The native app is expected to regain the legacy app's long-form transcription workflow later, alongside Dictation.

The original native `0.1.0` value describes an early Scriber Dictate prototype baseline. It remains valid in historical progress notes, but it is not the active Scriber version.

Current native status: `0.7.0` build `2`, alpha-stage.

## Three separate identifiers

- **Marketing version — `0.7.0`:** the user-facing product release line. It carries the product lineage forward from Electron `0.6.0`.
- **Bundle build — `2`:** the internal `CFBundleVersion` identifying a particular app bundle. It does not communicate alpha, beta, or stable maturity, and ordinary local Debug or Release-configuration recompiles do not require a new number. Increment it when producing another installable, distributed, or uploaded build that needs to be distinguished from an earlier one.
- **Prerelease label — alpha or beta:** the maturity of an intentionally identified testing snapshot. Use Git tags such as `v0.7.0-alpha.1`, then `v0.7.0-alpha.2` or `v0.7.0-beta.1`, only when preserving a specific build for testers or distribution.

An Xcode **Release** configuration is an optimized build configuration. Building it does not by itself make that app a stable Scriber release.

## Tag policy

The canonical repository had no tags when this policy was recorded. Do not tag every development commit or ordinary local build.

- Tag the first intentionally frozen alpha snapshot as `v0.7.0-alpha.1`.
- Advance the prerelease sequence when another distinct testing snapshot is worth preserving.
- Create the final `v0.7.0` tag only when `0.7.0` is genuinely ready to be treated as a stable release.
- Treat release tags as immutable; corrections receive a new prerelease or patch version rather than moving an existing tag.

Until such a snapshot is selected, the working native app remains untagged, alpha-stage `0.7.0` build `2`.

## Implementation boundaries

- Keep the native Xcode marketing version at `0.7.0` and bundle build at `2` until the next intentionally distinguishable build.
- Keep the archived Electron snapshot and its package metadata at historical version `0.6.0` unless active Electron development resumes.
- Do not reset the native product to `0.1.0` merely because its implementation was rewritten or its bundle identity was reset.
- Product-wide version progression does not imply that both platform implementations ship every numbered release.
