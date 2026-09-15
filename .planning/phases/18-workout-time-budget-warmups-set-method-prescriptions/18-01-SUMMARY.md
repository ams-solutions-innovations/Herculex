---
phase: 18-workout-time-budget-warmups-set-method-prescriptions
plan: 01
subsystem: database
tags: [drift, sqlite, supabase, json-codec, migration]

# Dependency graph
requires: []
provides:
  - SlotPrescriptionCodec — versioned JSON encode/decode for SlotPrescription
  - Schema v43 local + Supabase, with prescription_codec_json, allow_time_saving_set_techniques, planned_allows_advanced_techniques columns
affects: [18-02, 18-03, 18-04, 18-05, 18-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Versioned JSON wire format with a hard codecVersion gate (no legacy-shape fallback) for domain objects persisted as opaque TEXT columns"
    - "addIfMissing(table, column) guarded onUpgrade step checked against pragma_table_info, replicated per schemaVersion bump"

key-files:
  created:
    - lib/features/programs/domain/slot_prescription_codec.dart
    - test/features/programs/slot_prescription_codec_test.dart
    - drift_schemas/drift_schema_v43.json
    - test/generated_migrations/schema_v43.dart
    - supabase/migrations/20260915000000_slot_prescription_codec_v43.sql
  modified:
    - lib/data/local/tables.dart
    - lib/data/local/database.dart
    - lib/data/local/database.g.dart
    - test/generated_migrations/schema.dart
    - test/migration_test.dart
    - test/active_workout_notification_target_test.dart
    - test/cns_breakdown_test.dart
    - test/features/analytics/muscle_volume_details_test.dart
    - test/features/workouts/circuit_stats_test.dart
    - test/gamification/achievement_evaluator_test.dart
    - test/phase3_engines_test.dart
    - test/recovery_engines_test.dart
    - test/session_summary_test.dart
    - test/weighted_calisthenics_test.dart
    - test/widgets/exercise_replacement_sheet_test.dart

key-decisions:
  - "SlotPrescriptionCodec.decode returns null on any codecVersion mismatch rather than attempting a soft migration (D-04: no legacy-shape fallback needed pre-ship)"
  - "New WorkoutExercises.plannedAllowsAdvancedTechniques boolean column, like all other boolean withDefault columns in this codebase, generates a required (non-nullable, non-defaulted) Dart constructor parameter — so every direct WorkoutExerciseData(...) call site needed an explicit value"

patterns-established:
  - "Versioned codec pattern: abstract final class with wireVersion const, encode/decode static methods, try/catch-returns-null on decode"

requirements-completed: [PRES-01]

# Metrics
duration: ~55min
completed: 2026-09-15
---

# Phase 18 Plan 01: SlotPrescriptionCodec + Schema v43 Summary

**Versioned JSON codec for SlotPrescription plus a full five-chore drift v43 migration adding prescription_codec_json, allow_time_saving_set_techniques, and planned_allows_advanced_techniques across local SQLite and Supabase.**

## Performance

- **Duration:** ~55 min
- **Started:** 2026-09-15T~16:40:00Z
- **Completed:** 2026-09-15T17:36:45Z
- **Tasks:** 2
- **Files modified:** 19 (5 created, 14 modified)

## Accomplishments
- `SlotPrescriptionCodec` encodes/decodes `SlotPrescription` to a versioned JSON wire format, round-tripping every field (sets/repsMin/repsMax/intent/percentOf1Rm/setType/restSeconds/meta) byte-equivalently, with a hard version gate and non-throwing decode.
- Local drift schema bumped 42 -> 43 with three new nullable/defaulted columns via a `pragma_table_info`-guarded `addIfMissing` onUpgrade step, matching the existing v40/v41 idiom.
- Matching Supabase migration keeps `program_day_exercises`, `programs`, and `workout_exercises` in lockstep so `SyncService`'s `SELECT *` forward never hits PGRST204.
- All 15 pre-existing migration replay tests retargeted to v43, plus one new replay test for the v42 -> v43 step asserting all three new columns exist.

## Task Commits

Each task was committed atomically:

1. **Task 1: Write SlotPrescriptionCodec (versioned JSON encode/decode)** - `ad4a4ca` (feat)
2. **Task 2: Schema v43 — three new columns, full CLAUDE.md five-chore migration** - `d8c7c9b` (feat)

## Files Created/Modified
- `lib/features/programs/domain/slot_prescription_codec.dart` - Versioned JSON codec (encode/decode/wireVersion)
- `test/features/programs/slot_prescription_codec_test.dart` - 6 tests covering round-trip fidelity and null-on-failure behavior
- `lib/data/local/tables.dart` - Adds `prescriptionCodecJson`, `allowTimeSavingSetTechniques`, `plannedAllowsAdvancedTechniques` columns
- `lib/data/local/database.dart` - `schemaVersion => 43`, guarded `from < 43` onUpgrade step
- `lib/data/local/database.g.dart` - Regenerated via `dart run build_runner build`
- `drift_schemas/drift_schema_v43.json` - Dumped schema snapshot
- `test/generated_migrations/schema_v43.dart`, `schema.dart` - Generated migration fixtures/registry
- `test/migration_test.dart` - All 16 `migrateAndValidate` calls retargeted to v43; new v42->v43 replay test
- `supabase/migrations/20260915000000_slot_prescription_codec_v43.sql` - Matching Postgres columns for all three synced tables
- 10 pre-existing test files (`active_workout_notification_target_test.dart`, `cns_breakdown_test.dart`, `muscle_volume_details_test.dart`, `circuit_stats_test.dart`, `achievement_evaluator_test.dart`, `phase3_engines_test.dart`, `recovery_engines_test.dart`, `session_summary_test.dart`, `weighted_calisthenics_test.dart`, `exercise_replacement_sheet_test.dart`) - added `plannedAllowsAdvancedTechniques: false` to direct `WorkoutExerciseData(...)` constructions

## Decisions Made
- Hard version gate in the codec (no legacy-shape fallback) per D-04 — the codec is pre-ship, so there is no old wire format to migrate from.
- Kept the new boolean columns as `withDefault(false)` (DB-side default) rather than introducing a Dart-side default, consistent with every other boolean column in this codebase — this is what surfaced the constructor-completeness issue below.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 10 test files broke on the new required `plannedAllowsAdvancedTechniques` constructor parameter**
- **Found during:** Task 2, post-migration full-suite verification
- **Issue:** Adding a non-nullable `BoolColumn` to `WorkoutExercises` makes drift's generated `WorkoutExerciseData` constructor require the field explicitly (drift's `withDefault` is server-side/SQL-level only, not a Dart default). 10 pre-existing test files construct `WorkoutExerciseData(...)` directly with the full field list, none aware of the new field, so the whole suite failed to compile.
- **Fix:** Added `plannedAllowsAdvancedTechniques: false` to every direct `WorkoutExerciseData(...)` call site (11 call sites across 10 files — `weighted_calisthenics_test.dart` has two).
- **Files modified:** `test/active_workout_notification_target_test.dart`, `test/cns_breakdown_test.dart`, `test/features/analytics/muscle_volume_details_test.dart`, `test/features/workouts/circuit_stats_test.dart`, `test/gamification/achievement_evaluator_test.dart`, `test/phase3_engines_test.dart`, `test/recovery_engines_test.dart`, `test/session_summary_test.dart`, `test/weighted_calisthenics_test.dart`, `test/widgets/exercise_replacement_sheet_test.dart`
- **Verification:** `flutter test` — 1287 passed, 0 failed (full suite)
- **Committed in:** `d8c7c9b` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to keep the suite compiling after the schema change; no scope creep — every touched line is exactly the one new required parameter.

## Issues Encountered
- `dart run build_runner build --delete-conflicting-outputs` (needed to regenerate `database.g.dart` after editing `tables.dart`, not explicitly called out as a chore in the plan's action text but required by CLAUDE.md's own `tool/codegen.ps1` workflow) also touched Linux/macOS/Windows `generated_plugin_registrant.*` files and produced line-ending-only churn across `test/generated_migrations/schema_v2*.dart`. Both were reverted with `git checkout --` before committing since they are out-of-scope generated artifacts unrelated to this plan's columns.

## User Setup Required
None - no external service configuration required. Note: the Supabase migration file is written but, per CLAUDE.md's standing note, not yet applied to the live database — it joins `0015`/`0016` in the outstanding-migrations queue.

## Next Phase Readiness
- `SlotPrescriptionCodec` and all three v43 columns are in place and unused by any other code path yet, exactly as scoped ("No other file reads or writes the new columns yet").
- Plans 18-02 through 18-06 can now read/write `prescriptionCodecJson`, `allowTimeSavingSetTechniques`, and `plannedAllowsAdvancedTechniques` against a stable schema.
- Full suite green (1287 passed) and `flutter analyze` reports 0 errors.

---
*Phase: 18-workout-time-budget-warmups-set-method-prescriptions*
*Completed: 2026-09-15*
