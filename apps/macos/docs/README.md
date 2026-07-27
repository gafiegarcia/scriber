# Native macOS Documentation

The native documentation is separated by purpose so current requirements and tasks do not become buried in historical progress notes.

- [`PRODUCT_SPEC.md`](PRODUCT_SPEC.md) — authoritative product behavior and locked implementation decisions.
- [`ROADMAP.md`](ROADMAP.md) — what is left to do: milestones, planned work, release gates.
- [`ACCEPTANCE.md`](ACCEPTANCE.md) — the manual checklist standing between the current build and stable `v0.7.0`. Needs a person and an installed build.
- [`TESTING.md`](TESTING.md) — verification commands, the launch smoke check, and what the UI suite can and cannot cover.
- [`PASTE_ENGINE_RESEARCH.md`](PASTE_ENGINE_RESEARCH.md) — how delivery decides where a transcript goes, and its regression baseline. Read before changing insertion.
- [`DEVELOPMENT_LOG.md`](DEVELOPMENT_LOG.md) — chronological implementation and verification history; consult only when historical context is needed.

Repository-wide product decisions remain in the root [`docs`](../../../docs) directory:

- [`NATIVE_IDENTITY_PLAN.md`](../../../docs/NATIVE_IDENTITY_PLAN.md) — identity, naming, and future Dictation/Transcription boundaries.
- [`VERSIONING.md`](../../../docs/VERSIONING.md) — product version, build number, and tag policy.
- [`ICON_PROVENANCE.md`](../../../docs/ICON_PROVENANCE.md) — app-icon origin and licensing record.
- [`LICENSING_NOTES.md`](../../../docs/LICENSING_NOTES.md) — licensing decision and release-compliance notes.
