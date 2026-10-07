---
phase: 21-crossfit-gpp-training-tracks
plan: 07
subsystem: workouts
tags: [drift, program-materialization, crossfit, gpp, testing]

# Dependency graph
requires:
  - phase: 21-crossfit-gpp-training-tracks (plan 21-01)
    provides: "ProgramDayExercises.sessionSegment/supersetGroup and WorkoutExercises.plannedSessionSegment schema v44 columns"
  - phase: 21-crossfit-gpp-training-tracks (plan 21-06)
    provides: "CrossfitProgramPlanner/GppProgramPlanner dispatch into smart_program_planner, which populates ProgramDayExercises.sessionSegment/supersetGroup"
provides:
  - "PlannedExerciseSnapshot.sessionSegment field"
  - "resolveProgramDay reads pde.sessionSegment/pde.supersetGroup into the snapshot (previously only resolveTemplate populated supersetGroup)"
  - "materialize() writes plannedSessionSegment onto WorkoutExercicesCompanion.insert, joining the already-correct supersetGroup write"
  - "Two end-to-end regression tests proving segment/superset tags and AMRAP capSeconds meta survive Program -> WorkoutExercises/SetEntries materialization"
affects: [phase-21-verification, future-active-workout-ui-work-that-reads-plannedSessionSegment]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Program-day resolution mirrors Template-path field population exactly: any PlannedExerciseSnapshot field sourced from a table column must be populated from both resolveProgramDay and resolveTemplate, not just one"

key-files:
  created: []
  modified:
    - lib/features/workouts/data/planned_session_resolver.dart
    - test/planned_session_resolver_test.dart

key-decisions:
  - "Added the two new end-to-end tests to the existing test/planned_session_resolver_test.dart (root of test/) rather than creating test/features/workouts/planned_session_resolver_test.dart, since the plan's own fallback instruction says to check for an existing file first — one already existed at a different (pre-restructure) path with the exact fixture conventions to mirror."

patterns-established: []

requirements-completed: [CF-01]

# Metrics
duration: 25min
completed: 2026-09-27
---

# Phase 21 Plan 07: Thread sessionSegment/supersetGroup through materialization Summary

**`resolveProgramDay`/`materialize` now thread `sessionSegment`/`supersetGroup` from `ProgramDayExercises` into `WorkoutExercises.plannedSessionSegment`/`supersetGroup`, closing the one seam Plan 21-06 left unproven — that CrossFit/GPP segment tags and AMRAP/EMOM/For-Time time caps actually survive into the active workout a user performs, not just onto the generated program.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-09-27T (session start)
- **Completed:** 2026-09-27
- **Tasks:** 2 completed
- **Files modified:** 2

## Accomplishments
- `PlannedExerciseSnapshot` gained a `sessionSegment` field; `resolveProgramDay`'s per-`ProgramDayExercises` loop now reads both `pde.sessionSegment` and `pde.supersetGroup` (the Program path never populated `supersetGroup` before this plan — only the Template path did, via `te.supersetGroup`).
- `materialize()`'s `WorkoutExercisesCompanion.insert` now writes `plannedSessionSegment: Value(exercise.sessionSegment)` alongside the pre-existing (and already-correct) `supersetGroup: Value(exercise.supersetGroup)` line.
- Added a regression test proving a hand-inserted `ProgramDayExercises` row with `sessionSegment: 'metcon'`/`supersetGroup: 7` survives both `resolveProgramDay` and `materialize` into the resulting `WorkoutExercises` row.
- Added a regression test proving an AMRAP `capSeconds: 600` meta value on a `prescriptionCodecJson`-encoded `SlotPrescription` survives, byte-for-byte, into `SetEntries.setTypeMetaJson` — confirming `_setsFromPrescription`/`SetEntriesCompanion.insert`'s existing generic meta-forwarding behavior works for the CrossFit case, with no production code change required for that half of the plan.
- This is the final plan in Phase 21 (crossfit-gpp-training-tracks) — the phase is now ready for verification.

## Task Commits

Each task was committed atomically:

1. **Task 1: Thread sessionSegment/supersetGroup through resolveProgramDay and materialize** - `b3ab5b6` (feat)
2. **Task 2: End-to-end threading tests (segment tag, AMRAP cap preservation)** - `d3ad023` (test)

**Plan metadata:** (this commit, following SUMMARY.md/STATE.md/ROADMAP.md updates)

## Files Created/Modified
- `lib/features/workouts/data/planned_session_resolver.dart` - Added `sessionSegment` field to `PlannedExerciseSnapshot`; `resolveProgramDay` and `materialize` now thread it (and the pre-existing `supersetGroup` field) end-to-end.
- `test/planned_session_resolver_test.dart` - Two new tests: segment/superset-group threading through resolution + materialization, and AMRAP `capSeconds` survival into `SetEntries.setTypeMetaJson`.

## Decisions Made
- Extended the existing `test/planned_session_resolver_test.dart` (found via Glob at the repo's `test/` root, not under `test/features/workouts/`) rather than creating a new file at the path the plan's `<action>` guessed at, per the plan's own explicit fallback: "check with the Glob tool for the exact filename first; if no such file exists, follow ... and create the new file." One already existed with matching fixture conventions (`ProgramsCompanion.insert` / `ProgramWeeksCompanion.insert` / `ProgramDaysCompanion.insert` / `ProgramDayExercisesCompanion.insert` chain), so extending it kept fixture style consistent and avoided duplicating helper setup across two files.

## Deviations from Plan

None - plan executed exactly as written. `supersetGroup: Value(exercise.supersetGroup)` was already present in `materialize()` at the line the plan described (correctly serving the Template path); only `sessionSegment` needed a new write, plus both fields needed to be read in `resolveProgramDay`, exactly as scoped.

## Issues Encountered

`flutter test` (full suite) surfaced 7 pre-existing failures in `test/schema_v25_test.dart` (and 3 sibling `test/schema_v2*.dart` files) — all caused by Plan 21-01's `sessionSegment` column addition to `program_exercise_slots`/`program_day_exercises` at schema v44, against fixture files that were already stale at schema v39 before Plan 21-01 touched anything (confirmed via `git show HEAD~3:test/schema_v25_test.dart`). This is out of scope for this plan (SCOPE BOUNDARY: only auto-fix issues directly caused by the current task's changes) and was already logged in `.planning/phases/21-crossfit-gpp-training-tracks/deferred-items.md` during Plan 21-01's execution. No new deferred items added here. `flutter test test/planned_session_resolver_test.dart` (this plan's own scope) and `flutter analyze` (whole repo, 0 errors) both pass cleanly.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 21 (crossfit-gpp-training-tracks) is now complete — all 7 plans executed. CF-01's "segments show in the active workout" and "AMRAP/EMOM/For Time formats preserve time caps" success criteria are now provably closed end-to-end, from `ProgramDayExercises`/`ProgramExerciseSlots` generation (21-01, 21-06) through `resolveProgramDay`/`materialize` (this plan) into `WorkoutExercises`/`SetEntries`. Phase is ready for the phase-level verifier. The pre-existing `test/schema_v2*.dart` staleness (documented in `deferred-items.md`) remains an open chore for a future plan/phase that next touches the schema-bump checklist — it does not block this phase's own success criteria, which only require `test/migration_test.dart` and `flutter analyze` to pass.

---
*Phase: 21-crossfit-gpp-training-tracks*
*Completed: 2026-09-27*

## Self-Check: PASSED

- FOUND: lib/features/workouts/data/planned_session_resolver.dart
- FOUND: test/planned_session_resolver_test.dart
- FOUND: .planning/phases/21-crossfit-gpp-training-tracks/21-07-SUMMARY.md
- FOUND: commit b3ab5b6
- FOUND: commit d3ad023
