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
  - "supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql — written, NOT applied to any live database"
  - "test/herculex_ai_program_briefs_supabase_migration_test.dart — automated SQL-text-level parity/RLS/trigger/index guard, 6/6 passing"
affects: [27-10-task-2, 27-12, 25]

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

requirements-completed: []  # AIP-04 remains unchecked — this plan's Task 1 only writes the migration SQL and its parity test. Task 2 (apply to the live ldzgyzigvbwofbswitrv project + independent verification) is the actual [BLOCKING] must-have and has NOT been executed in this run.

# Metrics
duration: ~20min
completed: 2026-09-30
---

# Phase 27 Plan 10 (Task 1 of 2): herculex_ai_program_briefs Migration + Parity Test Summary

**Wrote supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql (owner-only RLS, triggers, realtime, pull index) and its automated column-parity test against local drift schema v46 — NOT yet applied to any live database.**

## IMPORTANT: This plan is NOT complete

This summary covers **Task 1 only**. Task 2 — the `[BLOCKING]` checkpoint that runs
`supabase db push` against the live `ldzgyzigvbwofbswitrv` project and independently
verifies (via four read-only queries) that the table, RLS policies, triggers, and
index actually exist remotely — was **deliberately not attempted** in this run per
explicit scope instruction. It requires human sign-off before any live database is
touched. Per plan 27-10's own `<success_criteria>`, the table is not "fully
functional on the live Supabase project" until Task 2 completes and is independently
verified — do not treat this plan as done, and do not mark AIP-04, ROADMAP.md's
27-10 row, or REQUIREMENTS.md as complete on the basis of this summary alone.

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-09-30
- **Tasks:** 1/2 completed (Task 1 only; Task 2 deferred)
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

**Plan metadata:** not yet committed — this plan is not complete (Task 2 pending). STATE.md/ROADMAP.md/REQUIREMENTS.md are intentionally left unchanged, still showing 27-10 as not yet delivered.

## Files Created/Modified
- `supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql` - New migration SQL, written but not applied to any database (local or remote).
- `test/herculex_ai_program_briefs_supabase_migration_test.dart` - New SQL-text-level parity/RLS/trigger/index test, 6/6 passing.

## Decisions Made
- No ordering dependency on 0015/0016 for this migration, stated explicitly in the header (unlike tdee_estimates v45, which had to be sequenced after those two outstanding migrations) — this table is new at v46 with no predecessor rows.
- Parity test derives its `sync_uuid`/`synced_at`-exclusion reference check against `0014_joint_pain_logs.sql` rather than `20260928000000_tdee_estimates_v45.sql`, because the latter's header prose literally contains the string "sync_uuid" in an explanatory sentence, which broke the `isNot(contains('sync_uuid'))` assertion on first run (see Issues Encountered below) — fixed by pointing at a migration file with no such prose, matching the original tdee test template's own choice of 0014 as its reference.
- No CHECK constraints on `source`/`knowledge_version`/`model_version` — validation, if any, stays at the Dart repository boundary, matching the tdee_estimates `method`/`confidence` precedent per the plan's own guidance that this table has no special constraint requirement beyond NOT NULL.

## Deviations from Plan

None - plan executed exactly as written for Task 1. Task 2 was intentionally not attempted per this run's explicit scope boundary (see below), not a deviation from the plan itself.

## Issues Encountered
- First test run failed on the "every local drift column exists remotely" test: the parity check's reference-file assertion (`expect(referenceFile, isNot(contains('sync_uuid')))`) was initially pointed at `20260928000000_tdee_estimates_v45.sql` itself, whose header comment explains "`sync_uuid` maps to the remote `id`..." — the literal substring match caught this prose, not a SQL column. Fixed by retargeting the reference-file check to `0014_joint_pain_logs.sql` (plain SQL, no explanatory header prose), which is what the original `tdee_supabase_migration_test.dart` template itself uses for this exact check. All 6 tests pass after the fix.

## User Setup Required

**Task 2 of this plan is a `[BLOCKING]` human-verify checkpoint, not yet started.**
It requires:
1. `SUPABASE_ACCESS_TOKEN` available in the environment for a non-interactive
   `supabase db push` against project `ldzgyzigvbwofbswitrv` (confirm this ref, not
   `jioesomepkauponjrena`, before running anything).
2. Explicit user/orchestrator go-ahead before that push is attempted — this was
   intentionally excluded from this run's scope per the executor's own instructions.
3. After the push, four independent read-only verification queries (columns, 4 RLS
   policies, 2 triggers, 1 index) against the live project — see 27-10-PLAN.md's
   Task 2 `<action>`/`<how-to-verify>` for the exact queries and acceptance bar.
   Do not report success on a "push succeeded" message alone; STATE.md's 2026-09-28
   session log records a prior false "Pushed" claim for `tdee_estimates` that was
   later found to be untrue when actually checked — Task 2 exists specifically to
   avoid repeating that mistake.

## Next Phase Readiness
- The migration SQL and its parity test are ready for Task 2's live push, whenever
  the user authorizes it (likely via `/gsd:execute-phase 27` resuming at this plan's
  checkpoint, or a direct instruction to proceed).
- `HerculexAiBriefService.persistBrief()` (27-09) already writes to the local
  `HerculexAiProgramBriefs` table today; until Task 2 lands, every local
  `herculex_ai_program_briefs` row will fail to push to Supabase (PGRST204,
  quarantined after 8 attempts) — this is the exact failure mode plan 27-04's own
  summary flagged as an intentional, sequenced gap, now one step closer to closed.
- Do NOT advance STATE.md's Current Plan counter, ROADMAP.md's 27-10 status, or
  REQUIREMENTS.md's AIP-04 checkbox based on this summary — all three remain
  accurate as "pending Task 2" until the live push is independently verified.

## Self-Check: PASSED

- `supabase/migrations/20260929000000_herculex_ai_program_briefs_v46.sql` — FOUND on disk.
- `test/herculex_ai_program_briefs_supabase_migration_test.dart` — FOUND on disk.
- Commit `36dcf40` — FOUND in `git log --oneline -5`.

---
*Phase: 27-herculex-ai-program-generation*
*Completed (Task 1 only): 2026-09-30*
