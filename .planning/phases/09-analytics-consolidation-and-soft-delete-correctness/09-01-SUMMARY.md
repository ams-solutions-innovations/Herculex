---
phase: 09-analytics-consolidation-and-soft-delete-correctness
plan: 01
subsystem: analytics
tags: [flutter, drift, riverpod, effective-load, correlation]

# Dependency graph
requires:
  - phase: 08-samsung-now-bar-live-update
    provides: n/a (no functional dependency; sequential phase only)
provides:
  - "BalanceAnalyzer.summary(List<ResolvedSet>) computing tonnage-weighted push/pull split"
  - "BiometricCorrelations.sleepVsRpe/restingHrVsTonnage accepting List<ResolvedSet>, mock-fallback removed"
affects: [09-02-provider-consolidation, 09-03-soft-delete-regression-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Domain analytics functions take List<ResolvedSet> (already-resolved, effective-load-aware) instead of raw table row lists + separate join maps"

key-files:
  created: []
  modified:
    - lib/features/analytics/domain/balance_analyzer.dart
    - lib/features/analytics/domain/biometric_correlations.dart

key-decisions:
  - "Task 1 (soft-delete filtering in training_snapshot.dart / analytics_repository.dart) was originally BLOCKED because the worktree that first ran this plan was forked from a commit predating the schema v25 migration that added SyncColumns/SyncTombstone (deletedAt) to the 8 workout tables. That migration has since landed on master (RB-01..05 cross-device sync rewrite, schema v25). Re-run from a worktree forked off current HEAD confirmed all 8 tables (ExerciseCatalog, WorkoutSessions, WorkoutExercises, SetEntries, SetAccessories, SetBands, Accessories, Bands) carry `SyncTombstone`/`deletedAt`, and Task 1 was executed as originally planned."
  - "Tasks 2 and 3 executed as planned since they only require List<ResolvedSet> ergonomics and effective-load math, both of which already existed and did not depend on the (then-missing, now-present) deletedAt columns."

patterns-established:
  - "Effective-load consumers (balance, correlations) take List<ResolvedSet> rather than raw table rows + manual joins."
  - "Soft-delete filtering (deletedAt.isNull()) applied uniformly at every SyncTombstone-table read in the analytics domain layer, matching the existing pattern in nutrition_repository.dart."

requirements-completed: [ANLY-03, ANLY-04]

# Metrics
duration: ~20min (Tasks 2/3) + Task 1 re-run
completed: 2026-08-14
---

# Phase 9 Plan 01: Effective-load rewrite + soft-delete filtering for analytics Summary

**`TrainingSnapshot.load` and `AnalyticsRepository`'s `weeklyTonnage()`/`topOneRms()` now exclude soft-deleted rows via `deletedAt.isNull()` on every `SyncTombstone`-carrying table they read. `BalanceAnalyzer` and `BiometricCorrelations` consume `List<ResolvedSet>` and compute from effective load (tonnageKg) instead of raw set counts/raw weight×reps; both hardcoded mock-fallback correlation point lists are deleted. All 3 tasks are now complete.**

## Performance

- **Duration:** ~20 min (Tasks 2/3) + Task 1 re-run after schema v25 landed
- **Completed:** 2026-08-14
- **Tasks:** 3 of 3 completed
- **Files modified:** 4 (training_snapshot.dart, analytics_repository.dart, balance_analyzer.dart, biometric_correlations.dart)

## Accomplishments
- `TrainingSnapshot.load` now filters every one of the 8 `SyncTombstone`-carrying table reads (`setEntries`, `workoutExercises`, `workoutSessions`, `exerciseCatalog`, `setAccessories`, `setBands`, `accessories`, `bands`) with `deletedAt.isNull()`; `exerciseMuscles` is left unfiltered (no `deletedAt` column, static seed data).
- `AnalyticsRepository.weeklyTonnage()` and `.topOneRms()` join queries now AND `deletedAt.isNull()` predicates (on `setEntries`/`workoutExercises`/`workoutSessions` and `setEntries`/`workoutExercises`/`exerciseCatalog` respectively) into their existing `..where(...)` clauses.
- `BalanceAnalyzer.summary` now takes `List<ResolvedSet>` and sums `tonnageKg` (effective load) per push/pull category instead of counting raw sets.
- `BiometricCorrelations.sleepVsRpe` / `restingHrVsTonnage` now take `List<ResolvedSet>` and derive sessions from the resolved sets; `restingHrVsTonnage` sums `tonnageKg` instead of `weightKg * reps`.
- Deleted both hardcoded 5-point mock-fallback blocks (`CorrelationPoint(5.5, 8.5)` etc. and `CorrelationPoint(56.0, 4200.0)` etc.) that previously masked real low-sample correlation results. Low-sample runs now return the real `points`/`sampleSize`, and `BiometricCorrelationResult.interpretation`'s existing `"Insufficient sessions recorded yet."` copy is now reachable (it was dead code before this fix — the mock block always forced `sampleSize: 5`).

## Task Commits

1. **Task 1: Filter soft-deleted rows out of TrainingSnapshot and AnalyticsRepository** - `ba1c23e` (feat)
2. **Task 2: Rewrite BalanceAnalyzer to consume ResolvedSet and use effective load** - `b509777` (feat)
3. **Task 3: Rewrite BiometricCorrelations to consume ResolvedSet, use tonnageKg, and drop the mock fallback** - `ef5b1d6` (feat)

## Files Created/Modified
- `lib/features/analytics/domain/training_snapshot.dart` - `TrainingSnapshot.load` filters `deletedAt.isNull()` on all 8 tombstoned table reads
- `lib/features/analytics/data/analytics_repository.dart` - `weeklyTonnage()`/`topOneRms()` exclude soft-deleted sets/exercises/sessions
- `lib/features/analytics/domain/balance_analyzer.dart` - `BalanceAnalyzer.summary` rewritten to take `List<ResolvedSet>`, sum `tonnageKg` per push/pull category
- `lib/features/analytics/domain/biometric_correlations.dart` - `sleepVsRpe`/`restingHrVsTonnage` rewritten to take `List<ResolvedSet>`; mock-fallback blocks deleted

## Decisions Made
- Task 1 was initially reported BLOCKED (see below for the historical record) because the worktree that first attempted it was forked from a commit predating the schema v25 migration. On re-run from a worktree forked off current `master` HEAD (which includes the schema v25 `SyncColumns`/`SyncTombstone` migration), `lib/data/local/tables.dart` was verified to carry `SyncTombstone`/`deletedAt` on all 8 tables the plan targets, and Task 1 was executed exactly as originally planned — no architectural rework needed.
- Proceeded with Tasks 2 and 3 out of their written order relative to Task 1 originally, since neither depended on soft-delete filtering — both only needed `ResolvedSet`'s existing `tonnageKg`/`exercise`/`session` fields.

## Deviations from Plan

None on the final pass — Task 1 executed as written once the schema v25 migration (added by an earlier, unrelated commit to master) was present in the worktree base. No auto-fixes needed for Tasks 1, 2, or 3.

### Historical note: earlier blocked attempt (resolved)

An earlier execution attempt of Task 1 reported it BLOCKED under Rule 4 (architectural), because the worktree at that time was forked from a commit (`3c36331`) that predated the schema v25 migration adding `SyncColumns`/`SyncTombstone` (`deletedAt`) to `ExerciseCatalog`, `WorkoutSessions`, `WorkoutExercises`, `SetEntries`, `SetAccessories`, `SetBands`, `Accessories`, `Bands`. At that time, `grep -rn "SyncTombstone|SyncColumns" lib/` genuinely returned zero matches on that worktree's base commit, and the earlier attempt's analysis and recommendations (documented then) were correct for the state of the codebase at that point.

That schema v25 migration has since landed on `master` (RB-01..05 cross-device sync rewrite, referenced in `.planning/PROJECT.md`/`STATE.md` as recent work). This execution's worktree was forked from current `master` HEAD (commit `c27867d`, "feat: RB-01..05 cross-device sync rewrite, health/cycle/fasting integrations, schema v25"), which includes the migration. Verified via `grep -n "SyncTombstone\|SyncColumns\|class.*extends Table" lib/data/local/tables.dart` that all 8 target tables now `extends Table with SyncColumns, SyncTombstone`. Task 1 was therefore executed as originally scoped, with no schema/architecture rework required — the earlier blocker was a worktree-staleness issue, not an actual gap in the codebase.

---

**Total deviations:** 0 on this pass. All 3 tasks executed exactly as planned.
**Impact on plan:** ANLY-03 (soft-delete correctness) and ANLY-04 (effective-load push/pull + correlations) are both fully delivered at the domain layer. Plan 09-02 (provider consolidation) can proceed using all three fixed/rewritten functions, including wiring `trainingSnapshotProvider`'s soft-delete-filtered output as `09-CONTEXT.md` D-05 describes. Plan 09-03's D-04 regression test ("soft-delete a set and assert it's excluded") can now be written against real `deletedAt` semantics.

## Issues Encountered
None. The only prior issue (Task 1 blocker) was resolved by re-running from a worktree with the schema v25 migration present; see "Historical note" above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `BalanceAnalyzer` and `BiometricCorrelations` are ready for `analytics_providers.dart` to consume (`analytics_providers.dart:82,96,161` currently call these with the old signatures and will need updating — that update belongs to Plan 09-02's provider-consolidation work, since `flutter analyze` on the whole project will currently fail at those three call sites until they're updated to pass `List<ResolvedSet>`).
- `TrainingSnapshot.load` and `AnalyticsRepository` now correctly exclude soft-deleted rows, unblocking Plan 09-03's D-04 regression test and 09-CONTEXT.md's D-05 provider-wiring work.
- No remaining blockers for the phase from this plan.

---
*Phase: 09-analytics-consolidation-and-soft-delete-correctness*
*Completed: 2026-08-14*

## Self-Check: PASSED

- FOUND: lib/features/analytics/domain/training_snapshot.dart
- FOUND: lib/features/analytics/data/analytics_repository.dart
- FOUND: lib/features/analytics/domain/balance_analyzer.dart
- FOUND: lib/features/analytics/domain/biometric_correlations.dart
- FOUND: .planning/phases/09-analytics-consolidation-and-soft-delete-correctness/09-01-SUMMARY.md
- FOUND: ba1c23e (Task 1 commit)
- FOUND: b509777 (Task 2 commit)
- FOUND: ef5b1d6 (Task 3 commit)
