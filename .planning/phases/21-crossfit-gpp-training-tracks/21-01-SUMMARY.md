---
phase: 21-crossfit-gpp-training-tracks
plan: 01
subsystem: data/local, features/programs/domain
tags: [drift, schema-migration, supabase, crossfit, gpp]
dependency-graph:
  requires: []
  provides:
    - SessionSegment enum
    - CrossfitSlotNeed descriptor
    - schemaVersion 44 (sessionSegment/supersetGroup/plannedSessionSegment columns)
  affects:
    - lib/features/programs/data/crossfit_program_planner.dart (future, 21-04)
    - lib/features/programs/data/gpp_program_planner.dart (future, 21-05)
    - lib/features/programs/data/smart_program_planner.dart (future, 21-06)
    - lib/features/programs/data/planned_session_resolver.dart (future)
tech-stack:
  added: []
  patterns:
    - "addIfMissing-guarded onUpgrade block (from < N && to >= N), mirrors the v43 block exactly"
    - "nullable enum-with-.id-string convention (fromId returns null, no orElse default), contrasts with SlotRole/SetType's non-null-fallback convention"
key-files:
  created:
    - lib/features/programs/domain/session_segment.dart
    - drift_schemas/drift_schema_v44.json
    - test/generated_migrations/schema_v44.dart
    - supabase/migrations/20260916000000_session_segment_v44.sql
  modified:
    - lib/data/local/tables.dart
    - lib/data/local/database.dart
    - lib/data/local/database.g.dart
    - test/generated_migrations/schema.dart
    - test/migration_test.dart
decisions:
  - "CrossfitSlotNeed lives in session_segment.dart (not in either Wave 2 planner file) so crossfit_program_planner.dart and gpp_program_planner.dart stay file-independent and can be built in parallel, per the plan's must_haves truth."
  - "SessionSegment.fromId returns null (no orElse fallback) since null is the common, correct state for every non-CrossFit/GPP row, deliberately diverging from SlotRole.fromId's/SetType.fromId's non-null-fallback convention."
metrics:
  duration: "~35 minutes"
  completed: "2026-09-26"
---

# Phase 21 Plan 01: SessionSegment Schema Primitive Summary

Added the session-segment tagging primitive (SessionSegment enum + 4 new nullable drift columns across 3 tables, bumped to schemaVersion 44) and the CrossfitSlotNeed public descriptor type that every other Phase 21 plan depends on, with a matching Supabase migration so sync never quarantines the new columns.

## What Was Built

**Task 1 — `lib/features/programs/domain/session_segment.dart`, `lib/data/local/tables.dart`:**
- `SessionSegment` enum (`warmup`/`skill`/`strength`/`metcon`/`cooldown`) with a null-safe `fromId` (no default fallback — null is a real, common state).
- `CrossfitSlotNeed` public descriptor class (pattern/muscle/role/preferredSlugs/segment/metconGroupKey/metconFormat/metconCapSeconds/metconMinutes), mirroring `smart_program_planner.dart`'s private `_SlotNeed` shape but kept in its own file so the two Wave 2 planner plans (21-04, 21-05) stay independent.
- New columns: `sessionSegment` (text, nullable) on `ProgramExerciseSlots` and `ProgramDayExercises`; `supersetGroup` (integer, nullable) on `ProgramDayExercises`; `plannedSessionSegment` (text, nullable) on `WorkoutExercises`.

**Task 2 — `lib/data/local/database.dart`, drift codegen, `test/migration_test.dart`:**
- `schemaVersion` bumped from 43 to 44.
- New `if (from < 44 && to >= 44)` onUpgrade block with its own `addIfMissing` closure (copied from the v43 block's exact shape), guarding all 4 `addColumn` calls against `pragma_table_info`.
- Ran `dart run drift_dev schema dump` and `schema generate`, then `dart run build_runner build --delete-conflicting-outputs` to regenerate `database.g.dart` (the schema-dump/generate step alone left the table getters as the DSL's `Column<T>` interface type rather than `GeneratedColumn<T>`, which failed to compile against the `addIfMissing` helper's parameter type — fixed by running full codegen; see Deviations).
- Retargeted every `migrateAndValidate(db, 43)` call in `test/migration_test.dart` to `44`, updated the header comment and the "current schema" test name, and added a new `'upgrades cleanly from a generated v43 fixture to v44'` replay test asserting all 4 new columns exist via `PRAGMA table_info`.

**Task 3 (BLOCKING) — `supabase/migrations/20260916000000_session_segment_v44.sql`:**
- 4 `alter table ... add column if not exists` statements matching the drift columns exactly (`session_segment` on `program_exercise_slots` and `program_day_exercises`, `superset_group` on `program_day_exercises`, `planned_session_segment` on `workout_exercises`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `dart run drift_dev schema generate` alone was insufficient to compile the new onUpgrade block**
- **Found during:** Task 2, first `flutter test test/migration_test.dart` run
- **Issue:** After adding the 4 new column getters to `tables.dart` and the new `addIfMissing` calls in `database.dart`, the compiler rejected `programExerciseSlots.sessionSegment` etc. as `Column<String>` not assignable to `GeneratedColumn<Object>` — the mixed-in table getters resolve to the DSL interface type until `database.g.dart` is regenerated with the new columns' concrete `GeneratedColumn` implementations.
- **Fix:** Ran `dart run build_runner build --delete-conflicting-outputs`, which regenerated `database.g.dart` (and other `.g.dart`/`.types.temp.dart` outputs) with the new columns properly typed.
- **Files modified:** `lib/data/local/database.g.dart` (regenerated)
- **Commit:** `3d23fe6`

No other deviations — plan executed as written otherwise.

## Verification

- `flutter analyze 2>&1 | tr '\r' '\n' | grep -c "error •"` → `0` (45 pre-existing info/warning-level issues unrelated to this plan, confirmed identical before and after this plan's changes).
- `flutter test test/migration_test.dart` → all 17 tests pass, including the new v43->v44 replay.
- `flutter test` (full suite, run as extra diligence beyond the plan's stated verification) → 1334 passed, 7 failed, all 7 in `test/schema_v25_test.dart` / `test/schema_v27_test.dart` / `test/schema_v28_test.dart` / `test/schema_v29_test.dart`. Confirmed via `git show HEAD~3:...` (state before this plan's first commit) that these 4 files already hardcoded stale targets (`39`) predating this plan by several schema bumps (v40-v43) — pre-existing, out-of-scope debt, not caused by this plan. Logged to `.planning/phases/21-crossfit-gpp-training-tracks/deferred-items.md`.

## Known Stubs

None — no UI or data-flow stubs introduced; this plan is purely schema/type scaffolding for downstream Wave 2 plans to consume.

## Threat Flags

None — the only new surface (4 nullable columns on already-synced tables) is exactly what the plan's threat model anticipated and mitigated via Task 3's Supabase migration.

## Self-Check: PASSED

- `lib/features/programs/domain/session_segment.dart` — FOUND
- `lib/data/local/tables.dart` (sessionSegment/supersetGroup/plannedSessionSegment columns) — FOUND
- `lib/data/local/database.dart` (schemaVersion 44, v44 onUpgrade block) — FOUND
- `drift_schemas/drift_schema_v44.json` — FOUND
- `test/generated_migrations/schema_v44.dart` — FOUND
- `supabase/migrations/20260916000000_session_segment_v44.sql` — FOUND
- Commit `cd0b1dc` — FOUND
- Commit `3d23fe6` — FOUND
- Commit `e79beb0` — FOUND
