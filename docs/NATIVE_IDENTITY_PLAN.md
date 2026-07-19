# Native Scriber Identity and Expansion Plan

Status: implementation steps 1–4 completed in commits `fa5b56d`, `ce10f39`, and `3a95cdf`; licensing and live signed acceptance remain open.

Recorded: 2026-07-19

## Purpose

Rename the active native macOS product from **Scriber Dictate** to **Scriber**, adopt the long-term bundle identity, and remove the old product name from project, module, file, type, test, and infrastructure identifiers. Preserve **Dictation** as feature vocabulary because dictation will remain one of several Scriber workflows.

The rename must leave room for a later long-form transcription workflow without prematurely implementing or displaying an empty feature.

## Locked decisions

- User-facing name: **Scriber**.
- Native marketing version: `0.7.0`.
- Native build number: `2`.
- Native bundle identifier: `com.gafiegarcia.scriber`.
- UI-test bundle identifier: `com.gafiegarcia.scriber.ui-tests`.
- Built product: `Scriber.app`.
- Perform a clean identity reset. Do not migrate existing native dictation history, preferences, onboarding state, pending audio, Launch-at-Login registration, or the existing `com.gafiegarcia.scriber-dictate` Keychain item.
- Gaf will re-enter the ElevenLabs API key, repeat onboarding, grant Microphone and Accessibility permissions, and re-enable Launch at Login as needed.
- Keep the Electron snapshot at its historical `0.6.0` identity and source state. Do not apply the native rename mechanically to `apps/electron`.
- Do not add an empty Transcription sidebar destination before the feature exists.

## Product and code rename map

Rename the native project comprehensively:

| Current | New |
| --- | --- |
| `Scriber Dictate` | `Scriber` |
| `Scriber Dictate.app` | `Scriber.app` |
| `com.gafiegarcia.scriber-dictate` | `com.gafiegarcia.scriber` |
| `ScriberDictate.xcodeproj` | `Scriber.xcodeproj` |
| Xcode target and scheme `ScriberDictate` | `Scriber` |
| `ScriberDictate/` | `Scriber/` |
| `ScriberDictateApp.swift` / `ScriberDictateApp` | `ScriberApp.swift` / `ScriberApp` |
| `ScriberDictate.entitlements` | `Scriber.entitlements` |
| `ScriberDictateCore/` / `ScriberDictateCore` | `ScriberCore/` / `ScriberCore` |
| `ScriberDictateTests/` | `ScriberCoreTests/` |
| `ScriberDictateUITests/` / `ScriberDictateUITests` | `ScriberUITests/` / `ScriberUITests` |

Also rename product-specific imports, Xcode references, test identifiers, notification names, multipart boundaries, queue labels, UserDefaults test suites, Keychain service and label, Application Support directories, window titles, menu labels, permission copy, and documentation paths.

Do not erase accurate domain terminology. Types such as `DictationRecord`, dictation shortcut logic, and dictation delivery states should retain their names.

## Navigation vocabulary

As part of the rename:

- Change the current generic sidebar destination **History** to **Dictation**.
- Rename `HistoryView` to `DictationHistoryView`.
- Rename generic history-focused commands and identifiers where they exclusively mean dictation history.
- Keep **Settings** as the second destination until long-form transcription exists.

The eventual sidebar is expected to contain:

1. **Dictation** — shortcut-driven short-form capture, automatic insertion or copy fallback, and its own history.
2. **Transcription** — long-form file/recording ingestion and its own Notes/history.
3. **Settings** — shared credentials, usage, language, keyterms, audio input, permissions, shortcuts, and app behavior.

## Future long-form transcription boundary

Long-form transcription is a separate workflow, not a renamed dictation record:

- Give it a separate persistence model such as `TranscriptionNote`.
- Let it own source-media retention, richer metadata, editing, export, speaker/timestamp presentation, and note lifecycle.
- Keep `DictationRecord` focused on short recordings, delivery state, retryable failures, and text insertion.
- Reuse `ScribeClient`, credential handling, usage checks, language rules, and keyterm validation only where both workflows genuinely consume the same behavior.
- Split coordinator responsibilities when the feature is implemented rather than growing one coordinator indefinitely.

## Clean-reset effects

The new app identity is expected to behave like a newly installed app:

- Existing native SwiftData history may remain on disk under the old identity but will not be imported.
- Existing preferences and onboarding completion will not be imported.
- Existing failed/interrupted audio under `Scriber Dictate/PendingAudio` will not be imported.
- The existing native API-key item will remain under its old Keychain service/access group; Scriber will create a new dedicated item after Gaf enters the key again.
- Microphone and Accessibility permissions must be checked and granted for the new signed identity.
- Launch at Login must be checked and enabled again if desired.

The previously run Electron development app used the same future bundle identifier but was never installed as the canonical app. Its local data and Keychain account are separate. Do not run an obsolete Electron build concurrently with the renamed native app; remove or unregister generated builds only if Launch Services later chooses the wrong app.

## Naming and icon cautions

- Treat **Scriber** as a provisional product name until a proper trademark clearance search is completed. `Scriber` is similar in sound and meaning to ElevenLabs' **Scribe** speech-to-text model and is used for related software, so the risk is not zero.
- Keep the repository private during the rename. Reassess the name before a broad public release, paid distribution, or trademark application.
- Do not add the new icon until its source URL, original author, exact license, modification permission, and required attribution are recorded. "Free SVG" is not enough provenance by itself.

## License decision

Open: choose the repository license in a separate change after discussing project goals and public perception.

The durable discussion and preliminary Electron dependency findings are recorded in [`LICENSING_NOTES.md`](LICENSING_NOTES.md).

Candidates:

- `MIT`: permissive and familiar; proprietary forks are allowed.
- `GPL-3.0-or-later`: strong copyleft when software is distributed.
- `AGPL-3.0-or-later`: GPLv3 copyleft plus source availability for modified versions offered to users over a network.

No standard open-source license forces publication of purely private modifications. A copyleft license does not prevent Gaf from selling Scriber, offering paid support, or later selling a managed service as the copyright holder. Before accepting substantial outside contributions, decide whether contributor terms are needed to preserve future relicensing or dual-licensing options.

## Implementation sequence

1. Commit this plan before code changes.
2. Change the native product identity, bundle identifiers, version/build, user-facing copy, storage identifiers, and Dictation navigation vocabulary. Verify and commit.
3. Rename the Xcode project/targets, Swift package/modules, directories, files, app type, tests, and remaining internal identifiers. Verify and commit.
4. Run a repository-wide stale-name audit and update native/root documentation plus migration progress. Verify and commit.
5. Decide and add the root license, copyright notice, trademark statement, and third-party notices in a separate commit.
6. Perform live acceptance from a stable signed `Scriber.app` path, including fresh onboarding, API-key save/readback, permissions, Launch at Login, shortcuts, insertion, history, Dock lifecycle, and pill activation.

## Automated verification after the internal rename

Run from the repository root with Xcode 27 beta:

```bash
swiftc -frontend -parse apps/macos/Scriber/*.swift apps/macos/ScriberCore/*.swift apps/macos/ScriberCoreTests/*.swift apps/macos/ScriberUITests/*.swift
swiftc -module-cache-path apps/macos/.build/module-cache -typecheck apps/macos/ScriberCore/CoreModels.swift apps/macos/ScriberCore/ScribeClient.swift apps/macos/ScriberCore/CredentialStore.swift
swift test --package-path apps/macos
plutil -lint apps/macos/Scriber/Info.plist apps/macos/Scriber/Scriber.entitlements
```

Build unsigned Debug and Release configurations from `apps/macos/Scriber.xcodeproj`. Run the credit-free UI suite in its isolated test mode. Normal automation must never contact ElevenLabs, access the real Keychain, mutate real SwiftData, or consume API credit.

## Completion checks

- The native source and build system contain no stale `ScriberDictate`, `Scriber Dictate`, or `scriber-dictate` product identifiers except explicit historical/migration documentation.
- `Scriber.app` builds with bundle identifier `com.gafiegarcia.scriber`, marketing version `0.7.0`, and build number `2`.
- The Swift package and all Xcode/UI tests pass under their new names.
- The sidebar presents Dictation and Settings; future Transcription ownership is documented but not falsely exposed.
- Electron remains a history-free `0.6.0` snapshot.
- The working tree is clean after each coherent commit, and nothing is pushed without Gaf's explicit request.
