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
  - "Task 1 (soft-delete filtering in training_snapshot.dart / analytics_repository.dart) was NOT executed — see Blocked Task below. Reverted to committed state to keep the tree compiling."
  - "Tasks 2 and 3 executed as planned since they only require List<ResolvedSet> ergonomics and effective-load math, both of which already exist and do not depend on the missing deletedAt columns."

patterns-established:
  - "Effective-load consumers (balance, correlations) take List<ResolvedSet> rather than raw table rows + manual joins."

requirements-completed: [ANLY-04]  # ANLY-03 NOT completed — see Blocked Task below.

# Metrics
duration: ~20min
completed: 2026-08-14
---

# Phase 9 Plan 01: Effective-load rewrite of BalanceAnalyzer/BiometricCorrelations Summary

**BalanceAnalyzer and BiometricCorrelations now consume `List<ResolvedSet>` and compute from effective load (tonnageKg) instead of raw set counts/raw weight×reps; both hardcoded mock-fallback correlation point lists are deleted. Task 1 (soft-delete filtering) is BLOCKED — the `SyncTombstone`/`deletedAt` mechanism this plan assumes exists on `SetEntries`/`WorkoutExercises`/`WorkoutSessions`/`ExerciseCatalog`/`SetAccessories`/`SetBands`/`Accessories`/`Bands` does not exist anywhere in the current codebase.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-08-14
- **Tasks:** 2 of 3 completed (Task 1 blocked)
- **Files modified:** 2

## Accomplishments
- `BalanceAnalyzer.summary` now takes `List<ResolvedSet>` and sums `tonnageKg` (effective load) per push/pull category instead of counting raw sets.
- `BiometricCorrelations.sleepVsRpe` / `restingHrVsTonnage` now take `List<ResolvedSet>` and derive sessions from the resolved sets; `restingHrVsTonnage` sums `tonnageKg` instead of `weightKg * reps`.
- Deleted both hardcoded 5-point mock-fallback blocks (`CorrelationPoint(5.5, 8.5)` etc. and `CorrelationPoint(56.0, 4200.0)` etc.) that previously masked real low-sample correlation results. Low-sample runs now return the real `points`/`sampleSize`, and `BiometricCorrelationResult.interpretation`'s existing `"Insufficient sessions recorded yet."` copy is now reachable (it was dead code before this fix — the mock block always forced `sampleSize: 5`).

## Task Commits

1. **Task 2: Rewrite BalanceAnalyzer to consume ResolvedSet and use effective load** - `b509777` (feat)
2. **Task 3: Rewrite BiometricCorrelations to consume ResolvedSet, use tonnageKg, and drop the mock fallback** - `ef5b1d6` (feat)

**Task 1: Filter soft-deleted rows out of TrainingSnapshot and AnalyticsRepository — NOT EXECUTED.** See "Blocked Task" below.

## Files Created/Modified
- `lib/features/analytics/domain/balance_analyzer.dart` - `BalanceAnalyzer.summary` rewritten to take `List<ResolvedSet>`, sum `tonnageKg` per push/pull category
- `lib/features/analytics/domain/biometric_correlations.dart` - `sleepVsRpe`/`restingHrVsTonnage` rewritten to take `List<ResolvedSet>`; mock-fallback blocks deleted

## Decisions Made
- Reverted Task 1's edits rather than leaving the tree in a non-compiling state, since the plan's premise (deletedAt columns on 8 workout tables) does not hold — see Blocked Task.
- Proceeded with Tasks 2 and 3 out of their written order relative to Task 1's blocker, since neither depends on soft-delete filtering — both only need `ResolvedSet`'s existing `tonnageKg`/`exercise`/`session` fields, which are already correct today.

## Deviations from Plan

### Blocked Task (Rule 4 — architectural, requires user/planner decision)

**1. [Rule 4 - Architectural] Task 1 cannot be implemented as written: `SyncTombstone`/`deletedAt` does not exist on the 8 tables the plan and `09-CONTEXT.md` claim carry it**

- **Found during:** Task 1 (filtering soft-deleted rows in `training_snapshot.dart` / `analytics_repository.dart`)
- **Issue:** The plan's `<interfaces>` section and `09-CONTEXT.md`'s "Established Patterns" section both assert that `ExerciseCatalog`, `WorkoutSessions`, `WorkoutExercises`, `SetEntries`, `SetAccessories`, `SetBands`, `Accessories`, `Bands` all `extends Table with SyncColumns, SyncTombstone` and carry a `deletedAt` column, citing `lib/data/local/tables.dart:22`. Verified against the actual file on this branch (base commit `3c36331`): no `SyncTombstone` or `SyncColumns` mixin exists anywhere in the repo (`grep -rn "SyncTombstone|SyncColumns" lib/` returns zero matches, and `git log --all --oneline | grep -i tombstone` returns zero commits). `deletedAt` exists on exactly two tables in the whole schema — `Foods` and `Recipes` (`lib/data/local/tables.dart:257,351`), both nutrition-domain, unrelated to workouts/analytics. Confirmed further that workout-entity deletes are hard SQL `DELETE` statements today (`workouts_repository.dart` `deleteSet`/`deleteSession` call `_db.delete(...).go()` directly), not soft-delete-via-`deletedAt`. There is a `PendingSyncOps` table, but it is an outbound cloud-sync operation queue for `profile | program | recipe | food | exercise` entities, not a tombstone marker on the workout tables, and it does not cover `SetEntries`/`WorkoutExercises`/`WorkoutSessions`/`SetAccessories`/`SetBands`/`Accessories`/`Bands` at all.
- **Why not auto-fixed:** Making Task 1's actual goal (soft-delete correctness) achievable would require: (1) a schema migration adding `deletedAt` columns to 8 tables, (2) rewiring every hard-delete call site across `workouts_repository.dart` (and any other repository touching these tables) from `DELETE` to `UPDATE ... SET deletedAt = ...`, (3) resolving the cascade-delete semantics that currently rely on `onDelete: KeyAction.cascade` FKs (soft-delete doesn't cascade automatically the way hard delete does), and (4) deciding what "cross-device sync" delete-propagation mechanism is supposed to write `deletedAt` in the first place, since no such mechanism exists today either. This is a multi-file schema/architecture change spanning outside this plan's 4 listed files and outside the analytics feature entirely — squarely Rule 4 territory, not a same-task auto-fix.
- **Files NOT modified (reverted after discovering the compile failure):** `lib/features/analytics/domain/training_snapshot.dart`, `lib/features/analytics/data/analytics_repository.dart` — both are back to their pre-plan committed state (verify via `git diff HEAD -- lib/features/analytics/domain/training_snapshot.dart lib/features/analytics/data/analytics_repository.dart` — no output).
- **Proposed alternatives for the orchestrator/planner:**
  - **(a)** Re-plan Task 1 as a proper schema-migration plan (add `deletedAt` to the 8 tables, bump schema version, migrate hard-deletes to soft-deletes in `workouts_repository.dart` and any sibling repositories, decide/implement the actual cross-device sync propagation mechanism this is meant to protect against). This is a correctly-scoped standalone plan, likely deserving its own wave before 09-02/09-03 can proceed, since 09-03's regression test (D-04: "soft-delete a set and assert it's excluded") also has no mechanism to exercise without this.
  - **(b)** Descope ANLY-03 from this phase entirely if soft-delete for workout entities is not actually planned/needed right now (hard-delete already means there's no "cross-device tombstone reappearing" bug today — the analytics-inflation risk this task guards against may not currently exist, since there's nothing to filter).
  - **(c)** If a soft-delete mechanism is added in a different, already-planned phase (check for overlap — none found in `10-CONTEXT.md`, which explicitly says Phase 10 shares only a schema-version slot, not soft-delete work), retarget this task at that phase's output instead.
- **Recommendation:** (a) or (b) — this needs a human/planner decision on whether soft-delete for workouts is in scope for the app at all before Task 1 (and ANLY-03, and Plan 09-03's D-04 acceptance gate) can be written correctly.

---

**Total deviations:** 1 blocked (Rule 4 — architectural, requires decision). Tasks 2 and 3 executed exactly as planned, no auto-fixes needed for those.
**Impact on plan:** ANLY-04 (effective-load push/pull + correlations) is fully delivered at the domain layer. ANLY-03 (soft-delete correctness) is not delivered and cannot be delivered as scoped — the plan's premise about existing schema was incorrect. Plan 09-02 (provider consolidation) can proceed using the Task 2/3 domain functions, but wiring `trainingSnapshotProvider`'s soft-delete-filtered output (as `09-CONTEXT.md` D-05 describes) has no `deletedAt` to filter on yet. Plan 09-03's D-04 regression test also cannot be written until the schema question above is resolved.

## Issues Encountered
None beyond the Task 1 blocker documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `BalanceAnalyzer` and `BiometricCorrelations` are ready for `analytics_providers.dart` to consume (`analytics_providers.dart:82,96,161` currently call these with the old signatures and will need updating — that update belongs to Plan 09-02's provider-consolidation work, or as a small follow-up if 09-02 doesn't already cover it, since `flutter analyze` on the whole project will currently fail at those three call sites until they're updated to pass `List<ResolvedSet>`).
- **Blocker for the phase:** ANLY-03 and Plan 09-03's D-04 acceptance gate cannot proceed until a decision is made on the soft-delete architecture question above (see "Blocked Task"). Recommend surfacing this to the user before continuing to Plan 09-02/09-03.

---
*Phase: 09-analytics-consolidation-and-soft-delete-correctness*
*Completed: 2026-08-14*

## Self-Check: PASSED

- FOUND: lib/features/analytics/domain/balance_analyzer.dart
- FOUND: lib/features/analytics/domain/biometric_correlations.dart
- FOUND: .planning/phases/09-analytics-consolidation-and-soft-delete-correctness/09-01-SUMMARY.md
- FOUND: b509777 (Task 2 commit)
- FOUND: ef5b1d6 (Task 3 commit)
- FOUND: d275b5f (SUMMARY commit)
