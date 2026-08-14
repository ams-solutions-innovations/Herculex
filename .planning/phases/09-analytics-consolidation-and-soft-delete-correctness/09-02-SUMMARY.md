---
phase: 09-analytics-consolidation-and-soft-delete-correctness
plan: 02
subsystem: analytics
tags: [flutter, riverpod, drift, provider-consolidation, dead-code-removal]

# Dependency graph
requires:
  - phase: 09-01
    provides: "BalanceAnalyzer.summary(List<ResolvedSet>) and BiometricCorrelations.sleepVsRpe/restingHrVsTonnage(resolvedSets:) taking effective-load-aware, soft-delete-filtered ResolvedSet lists"
provides:
  - "pushPullBalanceProvider, sleepVsRpeProvider, hrVsTonnageProvider all sourced from the shared trainingSnapshotProvider instead of independent unfiltered table scans"
  - "cnsFatigueProvider and muscleRecoveryProvider (and their backing domain files) fully removed"
  - "Insights screen renders exactly one recovery card (RecoveryDetailCard)"
affects: [09-03-soft-delete-regression-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "All analytics providers that need resolved sets now read trainingSnapshotProvider.future once instead of running their own independent, unfiltered table scans"

key-files:
  created: []
  modified:
    - lib/features/analytics/presentation/analytics_providers.dart
    - lib/features/analytics/presentation/insights_view.dart
    - test/health_integration_test.dart
  deleted:
    - lib/features/analytics/domain/muscle_recovery.dart
    - lib/features/analytics/domain/cns_fatigue.dart
    - lib/features/analytics/presentation/recovery_heatmap_widget.dart
    - test/recovery_engine_test.dart

key-decisions:
  - "Deleted test/recovery_engine_test.dart outright rather than porting it, since it exclusively exercised the now-removed MuscleRecovery/CnsFatigue classes with no remaining subject under test"
  - "Stripped the CnsFatigue.compute assertions out of test/health_integration_test.dart's climbing test while preserving its MuscleRecoveryV3 coverage, since that file mixed both engines in one test"

patterns-established:
  - "Providers needing resolved training sets consume trainingSnapshotProvider.future rather than issuing their own db.select(...).get() calls per table"

requirements-completed: [ANLY-01, ANLY-02]

# Metrics
duration: ~15min
completed: 2026-08-14
---

# Phase 9 Plan 02: Provider consolidation and dead recovery-engine removal Summary

**`analytics_providers.dart`'s balance/correlation providers now read from the shared, soft-delete-filtered `trainingSnapshotProvider` instead of independent raw table scans; the dead `cnsFatigueProvider`/`muscleRecoveryProvider` and their backing `muscle_recovery.dart`/`cns_fatigue.dart`/`recovery_heatmap_widget.dart` files are deleted, and Insights now renders exactly one recovery card.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-08-14T08:53:39Z
- **Tasks:** 2 of 2 completed
- **Files modified:** 6 (2 modified in lib, 3 deleted in lib, 1 modified + 1 deleted in test)

## Accomplishments
- `pushPullBalanceProvider` now does `final snapshot = await ref.watch(trainingSnapshotProvider.future); return BalanceAnalyzer.summary(sets: snapshot.sets);` instead of three independent unfiltered `db.select(...).get()` calls.
- `sleepVsRpeProvider` and `hrVsTonnageProvider` keep their own `healthSamples` query (not part of `TrainingSnapshot`) but now source `resolvedSets` from `trainingSnapshotProvider` instead of separate `setEntries`/`workoutExercises`/`workoutSessions` scans.
- `cnsFatigueProvider` and `muscleRecoveryProvider` deleted from `analytics_providers.dart`, along with their now-unused `cns_fatigue.dart`/`muscle_recovery.dart` imports.
- `insights_view.dart`'s `_RecoveryCard` widget (and its `_legendItem` helper and `recovery_heatmap_widget.dart` import) removed; `RecoveryDetailCard` is now the sole recovery card, first in the Insights list.
- Deleted the three now-fully-dead files: `lib/features/analytics/domain/muscle_recovery.dart`, `lib/features/analytics/domain/cns_fatigue.dart`, `lib/features/analytics/presentation/recovery_heatmap_widget.dart`.
- `flutter analyze lib/features/analytics/` reports no issues; `grep -rn "muscleRecoveryProvider|cnsFatigueProvider|_RecoveryCard|RecoveryHeatmapWidget" lib/` returns no matches.

## Task Commits

Each task was committed atomically:

1. **Task 1: Retarget balance/correlation providers onto trainingSnapshotProvider; delete dead providers** - `cb137cc` (feat)
2. **Task 2: Remove the duplicate recovery card and delete now-dead analytics files** - `57c2d41` (feat)

## Files Created/Modified
- `lib/features/analytics/presentation/analytics_providers.dart` - Deleted `cnsFatigueProvider`/`muscleRecoveryProvider`; rewrote `pushPullBalanceProvider`/`sleepVsRpeProvider`/`hrVsTonnageProvider` to read from `trainingSnapshotProvider`
- `lib/features/analytics/presentation/insights_view.dart` - Removed `_RecoveryCard` class and its `recovery_heatmap_widget.dart` import
- `lib/features/analytics/domain/muscle_recovery.dart` - deleted (dead)
- `lib/features/analytics/domain/cns_fatigue.dart` - deleted (dead)
- `lib/features/analytics/presentation/recovery_heatmap_widget.dart` - deleted (dead, only consumer was `_RecoveryCard`)
- `test/health_integration_test.dart` - Removed the `CnsFatigue.compute` import/call/assertions from the climbing test (Rule 3 fix — see Deviations); kept the `MuscleRecoveryV3` assertions intact
- `test/recovery_engine_test.dart` - deleted (Rule 3 fix — exclusively tested the removed `MuscleRecovery`/`CnsFatigue` classes)

## Decisions Made
- `test/recovery_engine_test.dart` was deleted rather than salvaged since every test in it targeted `MuscleRecovery.compute`/`.advisories` or `CnsFatigue.compute`, both now-deleted classes with no replacement API to port the assertions to.
- `test/health_integration_test.dart`'s climbing test mixed `CnsFatigue.compute` and `MuscleRecoveryV3.compute` assertions in one test body; only the `CnsFatigue` portion (import, call, and its two `expect`s) was removed, preserving the still-valid `MuscleRecoveryV3` coverage for that scenario.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed test compilation failures caused by deleting muscle_recovery.dart/cns_fatigue.dart**
- **Found during:** Task 2 (deleting the three dead analytics files)
- **Issue:** The plan's Task 2 stated the three files were "confirmed no remaining references after the above edit and Task 1," but `grep -rn "muscle_recovery\.dart|cns_fatigue\.dart|recovery_heatmap_widget\.dart"` across the repo (not just `lib/`) found two test files still importing the doomed classes: `test/recovery_engine_test.dart` (exclusively testing `MuscleRecovery`/`CnsFatigue`) and `test/health_integration_test.dart` (mixing `CnsFatigue.compute` with still-valid `MuscleRecoveryV3` assertions). Deleting the domain files as planned would have broken test compilation.
- **Fix:** Deleted `test/recovery_engine_test.dart` outright (no remaining subject under test). Edited `test/health_integration_test.dart` to remove the `cns_fatigue.dart` import and the `CnsFatigue.compute` call/assertions from its one affected test, keeping the `MuscleRecoveryV3` assertions unchanged.
- **Files modified:** `test/recovery_engine_test.dart` (deleted), `test/health_integration_test.dart`
- **Verification:** `flutter analyze lib/ test/` reports zero errors after the fix (13 pre-existing, unrelated info/warning-level issues remain, none touching analytics).
- **Committed in:** `57c2d41` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to keep the test suite compiling after the plan's file deletions; no scope creep — only the two tests directly wired to the deleted classes were touched.

## Issues Encountered
None beyond the deviation documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `analytics_providers.dart` now has exactly one soft-delete-filtered, effective-load-aware data path for recovery/CNS/balance/correlation, all sourced from `trainingSnapshotProvider`.
- Insights renders exactly one recovery card (`RecoveryDetailCard`), satisfying `09-CONTEXT.md` D-01/D-02 and the UI-SPEC "no new design, delete `_RecoveryCard`" contract.
- Plan 09-03's D-04 soft-delete regression test can proceed unblocked — the provider layer this test will exercise is now fully consolidated onto `trainingSnapshotProvider`.
- No remaining blockers for the phase from this plan.

---
*Phase: 09-analytics-consolidation-and-soft-delete-correctness*
*Completed: 2026-08-14*
