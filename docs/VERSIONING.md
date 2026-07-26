# Scriber Versioning Policy

Status: decided.

Recorded: 2026-07-20.

## Product lineage

Versions identify the Scriber product line, not the age of a particular codebase or repository.

The archived Electron implementation reached `0.6.0`. The native macOS implementation is its successor and continues the product line at `0.7.0`, even though it was rewritten in Swift, began as the Scriber Dictate prototype, and adopted a clean bundle and data identity. The native app is expected to regain the legacy app's long-form transcription workflow later, alongside Dictation.

The original native `0.1.0` value describes an early Scriber Dictate prototype baseline. It remains valid in historical progress notes, but it is not the active Scriber version.

Current native status: `0.7.0` build `11`, the locally certificate-signed candidate carrying the 2026-07-26 review pass, preserved as `v0.7.0-alpha.7`. Build `7` remains the `v0.7.0-alpha.6` snapshot. Builds `8` and `10` were same-day intermediates and were never tagged. The final provisioned Data Protection Keychain state is preserved as `v0.7.0-alpha.2`.

## Three separate identifiers

- **Marketing version — `0.7.0`:** the user-facing product release line. It carries the product lineage forward from Electron `0.6.0`.
- **Bundle build — `7`:** the internal `CFBundleVersion` identifying a particular app bundle. It does not communicate alpha, beta, or stable maturity, and ordinary local Debug or Release-configuration recompiles do not require a new number. Increment it when producing another intentionally identified installable, distributed, or uploaded build that needs to be distinguished from an earlier one.
- **Prerelease label — alpha or beta:** the maturity of an intentionally identified snapshot. Use Git tags such as `v0.7.0-alpha.1`, then `v0.7.0-alpha.2` or `v0.7.0-beta.1`, only when preserving a specific known-good source state, tester build, or distribution.

An Xcode **Release** configuration is an optimized build configuration. Building it does not by itself make that app a stable Scriber release.

## Stability and distribution

Product maturity is independent of Apple's distribution pipeline:

- A stable Git/source release means the behavior is accepted for Scriber's documented personal-use scope.
- Code signing gives a particular app bundle its identity and access to protected capabilities such as Scriber's Data Protection Keychain.
- Notarization is a Gatekeeper trust mechanism for distributing a Developer ID-signed binary to other Macs.

Developer ID signing and notarization are therefore not prerequisites for a stable source tag. A future stable `v0.7.0` may be published as a personal-use source release whose locally built binary uses Apple Development signing. Such a binary inherits its provisioning profile's lifetime and may need to be rebuilt even though the tagged source remains stable. A supported downloadable binary is a separate distribution-ready milestone.

## Tag policy

Do not tag every development commit or ordinary local build.

- The first intentionally frozen personal-use snapshot is `v0.7.0-alpha.1`, bundle build `3`.
- `v0.7.0-alpha.2` preserves the final build-3 source state that uses provisioned Data Protection Keychain storage.
- `v0.7.0-alpha.3` identifies the accepted build-4 personal installation using the login Keychain and ad-hoc signing.
- Build 5 was the untagged alpha.4 candidate; reboot validation exposed the generic SwiftData-store collision, so it was superseded.
- `v0.7.0-alpha.5` identifies the build-6 candidate with a dedicated Scriber history store and orphaned-audio recovery.
- `v0.7.0-alpha.6` identifies the build-7 candidate signed by the long-lived local Scriber identity so privacy permissions and login-Keychain authorization can persist across rebuilt Release bundles.
- `v0.7.0-alpha.7` identifies the build-11 candidate carrying the 2026-07-26 review pass: live-cursor delivery, keyboard-focus target selection, launch-time credential reporting, and 30-day retained-audio expiry.
- Advance the prerelease sequence when another distinct testing snapshot is worth preserving.
- Create the final `v0.7.0` tag when the documented personal-use behavior is genuinely accepted as stable; do not block that source tag solely on Developer ID signing or notarization.
- Treat release tags as immutable; corrections receive a new prerelease or patch version rather than moving an existing tag.

## Implementation boundaries

- Keep the native Xcode marketing version at `0.7.0` and bundle build at `11` until the next intentionally distinguishable build.
- Keep the archived Electron snapshot and its package metadata at historical version `0.6.0` unless active Electron development resumes.
- Do not reset the native product to `0.1.0` merely because its implementation was rewritten or its bundle identity was reset.
- Product-wide version progression does not imply that both platform implementations ship every numbered release.

## Annotated tag messages

Release and checkpoint tags are annotated tags. Their message records the snapshot purpose, marketing version and bundle build, credential-storage and signing state, verification performed, known limitations, and confirmation that no credentials, recordings, local history, or machine-specific build artifacts are included. Tags remain immutable and are not pushed or published without explicit approval.
