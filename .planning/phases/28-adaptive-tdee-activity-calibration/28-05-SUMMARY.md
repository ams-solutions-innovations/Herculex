---
phase: 28-adaptive-tdee-activity-calibration
plan: 05
subsystem: database
tags: [supabase, postgres, rls, sync, migration, tdee]

requires:
  - phase: 28-03
    provides: local drift v45 TdeeEstimates table and syncTableSpecs entry
provides:
  - supabase/migrations/20260928000000_tdee_estimates_v45.sql (written, not applied)
  - test/tdee_supabase_migration_test.dart column-parity guard against drift
affects: [28-11 migration apply checkpoint, 25 sync hardening]

tech-stack:
  added: []
  patterns:
    - "Migration guard test derives expected remote columns from the drift class text"

key-files:
  created:
    - supabase/migrations/20260928000000_tdee_estimates_v45.sql
    - test/tdee_supabase_migration_test.dart
  modified: []

key-decisions:
  - "sync_uuid and synced_at are excluded from remote parity; sync_uuid maps to remote id and synced_at is local bookkeeping (verified against 0014, which has neither)"
  - "No check constraints on method/confidence; validation stays at the Dart repository boundary"
  - "Test collapses whitespace so SQL line wrapping cannot break assertions"

patterns-established:
  - "Parity test: parse class body of the drift table, snake_case each getter, add mixin columns, assert each appears in the SQL"

requirements-completed: [TDEE-05]

duration: 15min
completed: 2026-09-28
---

# Phase 28 Plan 05: tdee_estimates Supabase Migration Summary

**Owner-only `tdee_estimates` Postgres table (RLS, triggers, realtime, pull index) with a test proving column parity against the drift v45 definition. File written only, not applied.**

## Performance

- **Tasks:** 1 of 1 (TDD: RED then GREEN)
- **Files:** 2 created

## Accomplishments
- Migration mirrors `0014_joint_pain_logs.sql`: table, `enable row level security`, four `tdee_estimates_<op>_own` policies on `user_id = auth.uid()` (with check on insert/update), `t_set_updated_at_` and `t_record_tombstone_` triggers, `supabase_realtime` publication.
- Adds `tdee_estimates_user_updated_idx (user_id, updated_at, id)` so `pull()` is not a sequential scan.
- Header explains the SELECT * / PGRST204 quarantine mechanism, the ordering requirement (0015 then 0016 must be applied before this), and the project ref `ldzgyzigvbwofbswitrv`.
- Test suite (6 tests) covers columns, policies, triggers/publication/index, no vocabulary constraints, header content, and drift parity.

## Task Commits

1. **Task 1 RED:** `22e23b9` test(28-05): add failing guard test for tdee_estimates migration
2. **Task 1 GREEN:** `0448919` feat(28-05): add tdee_estimates Supabase migration (not applied)

## Deviations from Plan

None in scope. Two small test-authoring adjustments during GREEN: the "no check constraint" assertion was narrowed to ignore RLS `with check (...)`, and the test now collapses whitespace so the update policy can be split across lines (needed for the plan's `auth.uid()` count of at least 5).

## Issues Encountered
None.

## Verification
- `flutter test test/tdee_supabase_migration_test.dart`: 6/6 pass; `flutter analyze` on the test: no issues.
- `grep -c "create policy"` = 4; `grep -c "auth.uid()"` = 5.
- No Supabase command, MCP tool or `db push` was run.

## Next Phase Readiness
Chore 5 of the schema bump is complete on disk. Until plan 28-11 applies 0015, 0016 and this file, a v45 client would quarantine `tdee_estimates` rows on push (PGRST204 / 42P01).

## Self-Check: PASSED
- FOUND: supabase/migrations/20260928000000_tdee_estimates_v45.sql
- FOUND: test/tdee_supabase_migration_test.dart
- FOUND commits 22e23b9, 0448919
