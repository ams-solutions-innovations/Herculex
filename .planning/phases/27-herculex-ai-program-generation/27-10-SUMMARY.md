---
phase: 27-herculex-ai-program-generation
plan: 10
subsystem: database
tags: [supabase, postgres, migration, drift, sync, rls]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation
    provides: "27-04's local drift HerculexAiProgramBriefs table (schema v46) and its exact snake_case column list, recorded in 27-04-SUMMARY.md, that this migration mirrors column-for-column"
provides:
  - "supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql — written AND applied to the live ldzgyzigvbwofbswitrv project, independently verified 2026-09-30"
  - "test/herculex_ai_program_briefs_supabase_migration_test.dart — automated SQL-text-level parity/RLS/trigger/index guard, 6/6 passing"
affects: [27-12, 25]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Owner-only RLS (4 policies) + updated_at/tombstone triggers + realtime publication + (user_id, updated_at, id) pull index — exact 20260928000000_tdee_estimates_v45.sql template, now applied to a second table"

key-files:
  created:
    - supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql
    - test/herculex_ai_program_briefs_supabase_migration_test.dart
  modified: []

key-decisions:
  - "Migration header explicitly states this table has NO 0015/0016 ordering dependency, unlike the v45 tdee_estimates precedent — herculex_ai_program_briefs is a wholly new table introduced at v46 with no predecessor rows, so RESEARCH.md's Assumption A2 (0015/0016 status inferred-not-reverified) does not apply here."
  - "program_id FK uses `uuid not null references public.programs(id) on delete cascade`, the confirmed convention from 0002_sync_schema_children.sql and 20260908200007_program_builder_v39.sql (not the auth.users(id) shape used for user_id)."
  - "Parity test's reference file for the sync_uuid/synced_at exclusion premise is 0014_joint_pain_logs.sql (bare SQL, no explanatory prose), not 20260928000000_tdee_estimates_v45.sql — that file's own header comment mentions the literal string \"sync_uuid\" in prose, which would produce a false-positive `isNot(contains(...))` failure if used as the reference."

requirements-completed: [AIP-04]

# Metrics
duration: ~35min
completed: 2026-09-30
---

# Phase 27 Plan 10: herculex_ai_program_briefs Migration Summary

**Wrote and APPLIED supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql (owner-only RLS, triggers, realtime, pull index) to the live ldzgyzigvbwofbswitrv Supabase project — independently verified via four read-only queries, not taken on the CLI's success message alone.**

## Task 2: live push + independent verification (2026-09-30)

Confirmed the linked project was `ldzgyzigvbwofbswitrv` (Herculex), not
`jioesomepkauponjrena` (SummitSki), via `supabase projects list` before touching
anything. `supabase migration list` showed 0015/0016 already applied remotely
(CLAUDE.md's "0015/0016 outstanding" note is stale as of this session — only
`20260929000000` was pending) and exactly one pending migration —
`20260929000000_herculex_ai_program_briefs_v46.sql`. Ran `supabase db push`;
it completed with `{"upToDate":false,"migrations":["20260929000000_herculex_ai_program_briefs_v46.sql"]}`.

Per the plan's explicit instruction not to trust a "push succeeded" message alone
(STATE.md's 2026-09-28 session recorded a prior false "Pushed" claim for a
different table), ran all four independent read-only queries via
`supabase db query --linked` against the live project:

1. **Columns (11/11 expected):** `id` (uuid), `user_id` (uuid, not null),
   `program_id` (uuid, not null), `brief_json` (text, not null), `source` (text,
   not null), `knowledge_version` (text, nullable), `model_version` (text,
   nullable), `confirmed_at` (timestamptz, not null), `active` (boolean, not
   null), `updated_at` (timestamptz, not null), `deleted_at` (timestamptz,
   nullable) — exact match to the local drift `HerculexAiProgramBriefs` class.
2. **RLS policies (4/4 expected):** `herculex_ai_program_briefs_select_own` (r),
   `_insert_own` (a), `_update_own` (w), `_delete_own` (d) — all four present.
3. **Triggers (2/2 expected):** `t_set_updated_at_herculex_ai_program_briefs`,
   `t_record_tombstone_herculex_ai_program_briefs` — both present.
4. **Index (1/1 expected, plus the automatic PK index):**
   `herculex_ai_program_briefs_user_updated_idx` present alongside
   `herculex_ai_program_briefs_pkey`.

All four checks passed. `herculex_ai_program_briefs` is now live and fully
functional on `ldzgyzigvbwofbswitrv`; `HerculexAiBriefService.persistBrief()`
(27-09)'s writes will sync instead of quarantining with PGRST204.

## Performance

- **Duration:** ~35 min (20 min Task 1 + ~15 min Task 2)
- **Completed:** 2026-09-30
- **Tasks:** 2/2 completed
- **Files modified:** 2 (both new)

## Accomplishments
- `supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql` written,
  structurally identical to `20260928000000_tdee_estimates_v45.sql`: `id`/`user_id`/
  `program_id` (FK to `public.programs(id)`)/`brief_json`/`source`/
  `knowledge_version`/`model_version`/`confirmed_at`/`active`/`updated_at`/
  `deleted_at` columns; RLS enabled with 4 owner-only policies
  (`herculex_ai_program_briefs_select_own`/`_insert_own`/`_update_own`/`_delete_own`,
  each scoped to `user_id = auth.uid()`); `t_set_updated_at_herculex_ai_program_briefs`
  and `t_record_tombstone_herculex_ai_program_briefs` triggers; realtime publication
  entry; `herculex_ai_program_briefs_user_updated_idx` pull index.
- `test/herculex_ai_program_briefs_supabase_migration_test.dart` written, mirroring
  `test/tdee_supabase_migration_test.dart`'s exact structure: 6 tests covering column
  definitions, RLS policy shape (4 policies, correct using/with-check clauses),
  triggers/realtime/index wiring, a no-CHECK-constraint guard (source/
  knowledge_version/model_version are free text, matching tdee's method/confidence
  precedent), header/project-ref assertions, and the critical automated parity test
  that regex-derives every column from the local drift `HerculexAiProgramBriefs`
  class in `lib/data/local/tables.dart`, snake-cases each, and asserts every one
  appears in the migration SQL text.
- `flutter test test/herculex_ai_program_briefs_supabase_migration_test.dart` — 6/6
  passing. `flutter analyze test/herculex_ai_program_briefs_supabase_migration_test.dart`
  — 0 issues.

## Task Commits

1. **Task 1: Write the herculex_ai_program_briefs migration and its column-parity test** - `36dcf40` (feat)
2. **Task 2: Apply migration to live Supabase project + independent verification** - no code commit (live infrastructure change only); this SUMMARY.md update plus the STATE/ROADMAP/REQUIREMENTS bookkeeping commit records it.

## Files Created/Modified
- `supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql` - New migration SQL, written but not applied to any database (local or remote).
- `test/herculex_ai_program_briefs_supabase_migration_test.dart` - New SQL-text-level parity/RLS/trigger/index test, 6/6 passing.

## Decisions Made
- No ordering dependency on 0015/0016 for this migration, stated explicitly in the header (unlike tdee_estimates v45, which had to be sequenced after those two outstanding migrations) — this table is new at v46 with no predecessor rows.
- Parity test derives its `sync_uuid`/`synced_at`-exclusion reference check against `0014_joint_pain_logs.sql` rather than `20260928000000_tdee_estimates_v45.sql`, because the latter's header prose literally contains the string "sync_uuid" in an explanatory sentence, which broke the `isNot(contains('sync_uuid'))` assertion on first run (see Issues Encountered below) — fixed by pointing at a migration file with no such prose, matching the original tdee test template's own choice of 0014 as its reference.
- No CHECK constraints on `source`/`knowledge_version`/`model_version` — validation, if any, stays at the Dart repository boundary, matching the tdee_estimates `method`/`confidence` precedent per the plan's own guidance that this table has no special constraint requirement beyond NOT NULL.

## Deviations from Plan

None — plan executed exactly as written. Task 2's automated non-interactive `supabase db push` succeeded on the first attempt (the CLI session was already authenticated and linked to `ldzgyzigvbwofbswitrv`), so the "stop and surface to the user" interactive-auth fallback path was not needed. The orchestrator paused via AskUserQuestion before running Task 2 regardless, since a live production database push is a hard-to-reverse action warranting explicit go-ahead beyond the plan's own automation-first instruction — the user chose "push now."

## Issues Encountered
- First test run failed on the "every local drift column exists remotely" test: the parity check's reference-file assertion (`expect(referenceFile, isNot(contains('sync_uuid')))`) was initially pointed at `20260928000000_tdee_estimates_v45.sql` itself, whose header comment explains "`sync_uuid` maps to the remote `id`..." — the literal substring match caught this prose, not a SQL column. Fixed by retargeting the reference-file check to `0014_joint_pain_logs.sql` (plain SQL, no explanatory header prose), which is what the original `tdee_supabase_migration_test.dart` template itself uses for this exact check. All 6 tests pass after the fix.

## User Setup Required

None remaining — both tasks are complete. `SUPABASE_ACCESS_TOKEN`/CLI auth was
already configured in this environment; `supabase db push` and
`supabase db query --linked` both ran non-interactively against the correctly
linked `ldzgyzigvbwofbswitrv` project.

## Next Phase Readiness
- `herculex_ai_program_briefs` is live on Supabase with correct schema, RLS,
  triggers and index, independently verified — plan 27-12 (rendering the brief's
  rationale) and Phase 25 (cloud sync/export hardening) can both rely on it.
- `HerculexAiBriefService.persistBrief()` (27-09)'s writes will now sync
  correctly instead of quarantining with PGRST204 after 8 attempts.

## Self-Check: PASSED

- `supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql` — FOUND on disk, applied to `ldzgyzigvbwofbswitrv`.
- `test/herculex_ai_program_briefs_supabase_migration_test.dart` — FOUND on disk, 6/6 passing.
- Commit `36dcf40` — FOUND in `git log --oneline -5`.
- Live table verified via 4 independent read-only queries (see "Task 2" section above).

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*
