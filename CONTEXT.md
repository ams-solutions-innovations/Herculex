# Herculex Context

Last updated: 2026-08-13

## What Herculex is

A local-first Flutter workout + nutrition tracker (MyFitnessPal + Hevy +
cycle/recovery intelligence), with an optional Supabase cloud sync layer.
Phone (Flutter/Dart) + a native Wear OS companion app. See `HANDOFF.md` for
the full feature roadmap (Phases 1–11) — that document is stale on sync status
specifically (still says Phase 10 "NOT STARTED"); this file is the current
source of truth for sync.

## Current state: RB-02 (cloud sync) is closed

The 2026-08-10 audit (`docs/app-audit-report-2026-08-10.md`) flagged that
cloud sync reported success without ever contacting a backend. That's fixed
and, as of this session, **proven against the live Supabase project**, not
just against a fake:

- `SyncService` (`lib/data/sync/sync_service.dart`) owns push/pull/tombstones/
  quarantine/retry. `lib/data/sync/sync_table_specs.dart` is the ~36-table
  registry (FK shapes, local-only columns, renames). Migrations
  `supabase/migrations/0001`–`0007` are applied.
- `test/sync/live_round_trip_test.dart` runs two `SyncService` instances
  against the real project (two in-memory Drift DBs, two authenticated
  `SupabaseClient`s) — skips itself without credentials, so `flutter test`
  stays offline by default. Run it with
  `flutter test test/sync/live_round_trip_test.dart --dart-define-from-file=.secrets/live_sync.json`.
  Ran green twice in a row on 2026-08-13.
- Local fake-backed coverage: `test/sync/sync_service_test.dart` (50 tests),
  `test/sync/sync_payload_test.dart` (FK payload paths), plus
  `test/widgets/sync_status_badge_test.dart` for the UI contract.

**Full detail, defects found and fixed, and what's still owed:**
`docs/rb02-sync-verification.md`. **Current open items:** `BLOCKERS.md`,
`TASKS.md`, `DEBT.md`.

## Current state: RB-01 (Gemini client secret) is closed

Flutter no longer ships, accepts, stores, or directly uses a Gemini API key.
Gemini requests now go through the Supabase Edge Function
`supabase/functions/gemini-analyze`. Details and verification:
`docs/rb01-gemini-secret-remediation.md`.

The external close-out is also done: `GEMINI_API_KEY` is set as a Supabase
Function secret on `jioesomepkauponjrena`, and `gemini-analyze` is deployed and
active with JWT verification enabled.

## Working agreement for this project

- **"Now" bar vs. backlog**: the app is still being built. Treat something as
  a blocker only if it stops current functionality from working — not
  "would be nice before a public release." Longer-term/deferred items belong
  in `TASKS.md`'s Later section or `DEBT.md`, not `BLOCKERS.md`.
- Three sync verification steps genuinely cannot be done headlessly (sign-in
  starting sync, the Profile badge, offline behavior) — they need a real
  device/emulator. Don't try to script around this; it's a real ceiling on
  what automated testing can prove here.
- Live-backend test credentials live in `.secrets/live_sync.json`
  (gitignored). Format documented in `docs/rb02-sync-verification.md`.

## Where things are tracked

| File | Purpose |
| --- | --- |
| `CONTEXT.md` (this file) | Current project state, updated per session |
| `BLOCKERS.md` | What's actually stopping current functionality, right now |
| `TASKS.md` | Backlog, split Now / Later |
| `DEBT.md` | Known shortcuts, stale docs, cleanup owed |
| `LESSONS.md` | Durable lessons — testing gotchas, architecture traps |
| `HANDOFF.md` | Long-range feature roadmap (Phases 4–11) — update its Phase 10 section, it's stale |
| `RELEASE.md` | Store-submission checklist — also stale, says "no backend to provision" |
| `docs/app-audit-report-2026-08-10.md` | The original 5-item release-blocker audit; RB-01/RB-02 closed, RB-03/04/05 still open |
| `docs/rb02-sync-verification.md` | Full RB-02 verification record |
