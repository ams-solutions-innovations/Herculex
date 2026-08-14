---
phase: 09-analytics-consolidation-and-soft-delete-correctness
plan: 03
subsystem: analytics
tags: [flutter, drift, testing, soft-delete, regression-gate]

# Dependency graph
requires:
  - phase: 09-01
    provides: "deletedAt.isNull() filtering in TrainingSnapshot.load and AnalyticsRepository.weeklyTonnage/topOneRms"
  - phase: 09-02
    provides: "provider consolidation onto trainingSnapshotProvider (context only; this test exercises the domain/repository layer directly, not providers)"
provides:
  - "Automated regression test locking in ANLY-03/D-04: a soft-deleted set is excluded from TrainingSnapshot, weeklyTonnage, and topOneRms"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Soft-delete regression tests: insert a completed set, assert inclusion, soft-delete via {Table}Companion(deletedAt: Value(DateTime.now())), assert exclusion"

key-files:
  created:
    - test/analytics_soft_delete_test.dart
  modified: []

key-decisions:
  - "Tested against TrainingSnapshot.load and AnalyticsRepository directly (the domain/repository layer where the deletedAt filtering actually lives) rather than through Riverpod providers, matching the plan's interface examples and the existing test/repository_delete_paths_test.dart style."

patterns-established: []

requirements-completed: [ANLY-03]

# Metrics
duration: ~10min
completed: 2026-08-14
---

# Phase 9 Plan 03: Soft-delete analytics regression test Summary

**Added `test/analytics_soft_delete_test.dart` with three tests proving a soft-deleted completed set is excluded from `TrainingSnapshot.load`, `AnalyticsRepository.weeklyTonnage()`, and `AnalyticsRepository.topOneRms()` — the automated acceptance gate for ANLY-03 / 09-CONTEXT.md decision D-04.**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-08-14
- **Tasks:** 1 of 1 completed
- **Files modified:** 1 (test/analytics_soft_delete_test.dart, created)

## Accomplishments
- `test('TrainingSnapshot excludes a soft-deleted set')`: inserts a session → exercise → completed set (`isCompleted: true`, `weightKg: 60`, `reps: 5`), asserts `TrainingSnapshot.load(db).sets` has length 1 with the inserted set's id, soft-deletes the set via `SetEntriesCompanion(deletedAt: Value(DateTime.now()))`, and re-asserts `sets` is empty.
- `test('weeklyTonnage excludes a soft-deleted set')`: same insert tree with `startedAt: DateTime.now()` so it lands in the current week bucket; asserts the last (current) week's `tonnageKg` is `300` (60 × 5) before soft-delete and `0` after.
- `test('topOneRms excludes a soft-deleted set')`: same insert tree; asserts `topOneRms()` contains the inserted exercise's id before soft-delete and does not contain it after.
- `flutter test test/analytics_soft_delete_test.dart` passes with all 3 tests green.

## Task Commits

1. **Task 1: Write the soft-delete analytics regression test** - `b715258` (test)

## Files Created/Modified
- `test/analytics_soft_delete_test.dart` - new file, 3 tests covering `TrainingSnapshot.load`, `AnalyticsRepository.weeklyTonnage()`, `AnalyticsRepository.topOneRms()` against a soft-deleted set

## Decisions Made
- Followed the plan's exact insert-tree pattern (from `test/repository_delete_paths_test.dart`) and soft-delete write pattern (from `nutrition_repository.dart`'s style, applied here to `SetEntriesCompanion`), and matched `test/rb05_soft_delete_test.dart`'s `main()`/`group()`/`test()` shape rather than introducing a new test style.
- Explicitly passed `isCompleted: const Value(true)` on the inserted set per the plan's `<interfaces>` warning — `isCompleted` defaults to `false`, and an incomplete set would already be excluded by `TrainingSnapshot`'s own `!set.isCompleted` check regardless of soft-delete, which would make the test meaningless.

## Deviations from Plan

None - plan executed exactly as written. All three tests pass on the first run with no auto-fixes needed.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ANLY-03 (soft-delete correctness for analytics) is now enforced by an automated regression test, not just manual inspection — satisfying 09-CONTEXT.md decision D-04.
- This was the final plan (wave 3) of Phase 9 (analytics-consolidation-and-soft-delete-correctness). All three plans (09-01 domain-layer rewrite + soft-delete filtering, 09-02 provider consolidation, 09-03 this regression gate) are complete.
- No remaining blockers for this phase.

---
*Phase: 09-analytics-consolidation-and-soft-delete-correctness*
*Completed: 2026-08-14*

## Self-Check: PASSED

- FOUND: test/analytics_soft_delete_test.dart
- FOUND: b715258 (Task 1 commit)
