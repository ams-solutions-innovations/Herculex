---
phase: 09-analytics-consolidation-and-soft-delete-correctness
verified: 2026-08-14T00:00:00Z
status: passed
score: 8/8 must-haves verified
overrides_applied: 0
---

# Phase 9: Analytics consolidation and soft-delete correctness Verification Report

**Phase Goal:** Make Insights report one correct number per metric, sourced from the shared effective-load snapshot, and make sure sync tombstones (`deletedAt`) can never inflate analytics after a cross-device delete.
**Verified:** 2026-08-14
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A soft-deleted (deletedAt set) completed set no longer contributes to weekly tonnage, top-1RM, or TrainingSnapshot-derived results | VERIFIED | `training_snapshot.dart:72-84` filters `deletedAt.isNull()` on all 8 SyncTombstone tables (setEntries, workoutExercises, workoutSessions, exerciseCatalog, setAccessories, setBands, accessories, bands). `analytics_repository.dart:48-50` and `:83-85` AND `deletedAt.isNull()` into `weeklyTonnage()`/`topOneRms()` joins. `test/analytics_soft_delete_test.dart` passes (3/3), directly proving exclusion post-soft-delete for all three read paths. |
| 2 | Push/pull balance is computed from effective load (tonnageKg), not a raw set count | VERIFIED | `balance_analyzer.dart:22-55`: `BalanceAnalyzer.summary({required List<ResolvedSet> sets})` sums `resolvedSet.tonnageKg` per push/pull category, no raw counting. |
| 3 | Sleep-vs-RPE and resting-HR-vs-tonnage correlations never substitute fabricated points when the real sample is small — they return the real (possibly empty/low-confidence) result | VERIFIED | `biometric_correlations.dart` — no hardcoded `CorrelationPoint(...)` mock-fallback blocks present; `sleepVsRpe`/`restingHrVsTonnage` build `points` solely from real `healthSamples`/`resolvedSets` input, returning real (possibly empty) `sampleSize`. `interpretation` getter's "Insufficient sessions recorded yet." branch (sampleSize < 3) is reachable, confirming no forced sampleSize:5 override remains. |
| 4 | Insights shows exactly one recovery card (RecoveryDetailCard); the legacy coarse recovery card is gone | VERIFIED | `grep -rn "_RecoveryCard" lib/` returns no matches; `insights_view.dart:46` renders `const RecoveryDetailCard()` as the sole recovery widget. |
| 5 | pushPullBalanceProvider, sleepVsRpeProvider, and hrVsTonnageProvider all read from trainingSnapshotProvider instead of independent unfiltered table scans | VERIFIED | `analytics_providers.dart:42-43` (`pushPullBalanceProvider` awaits `trainingSnapshotProvider.future`, passes `snapshot.sets`), `:49-53` (`sleepVsRpeProvider`), `:110-114` (`hrVsTonnageProvider`) — all three consume `trainingSnapshotProvider.future`. |
| 6 | No dead analytics provider or domain code remains (cnsFatigueProvider, muscleRecoveryProvider, muscle_recovery.dart, cns_fatigue.dart, recovery_heatmap_widget.dart) | VERIFIED | Files confirmed absent from filesystem (`ls` errors "No such file or directory" for all three). `grep -rn "muscleRecoveryProvider\|cnsFatigueProvider\|RecoveryHeatmapWidget" lib/ test/` returns zero matches. `test/recovery_engine_test.dart` also confirmed deleted (its only subject was the removed classes). |
| 7 | The `deletedAt.isNull()` filters actually landed in training_snapshot.dart and analytics_repository.dart (not reverted or lost in the mid-phase worktree/schema-v25 merge) | VERIFIED | Working tree is clean (`git status` — nothing to commit); commit `ba1c23e` ("feat(09-01): filter soft-deleted rows...") is present in `git log` for `training_snapshot.dart`; live grep of both files on current HEAD shows the filters present exactly as described (see truth #1 evidence). |
| 8 | Automated regression coverage exists and is non-vacuous for ANLY-03 | VERIFIED | `test/analytics_soft_delete_test.dart` (147 lines) contains 3 real tests: inserts a completed set via the full session→exercise→set insert tree, asserts inclusion in `TrainingSnapshot.load`, `weeklyTonnage()` (tonnageKg 300→0), and `topOneRms()` (exercise present→absent), then soft-deletes via `SetEntriesCompanion(deletedAt: Value(DateTime.now()))` and re-asserts exclusion in each. `flutter test test/analytics_soft_delete_test.dart` → 3/3 passing. |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/features/analytics/domain/training_snapshot.dart` | `deletedAt.isNull()` on every SyncTombstone table read | VERIFIED | 8 filtered reads confirmed at lines 72-84 |
| `lib/features/analytics/data/analytics_repository.dart` | `weeklyTonnage`/`topOneRms` exclude soft-deleted rows | VERIFIED | AND-ed `deletedAt.isNull()` predicates confirmed lines 48-50, 83-85 |
| `lib/features/analytics/domain/balance_analyzer.dart` | `List<ResolvedSet>` + tonnage-weighted split | VERIFIED | Full file read, matches spec |
| `lib/features/analytics/domain/biometric_correlations.dart` | `List<ResolvedSet>`, no mock fallback | VERIFIED | Full file read, no mock blocks present |
| `test/analytics_soft_delete_test.dart` | Regression coverage for ANLY-03 | VERIFIED | 3 non-vacuous tests, passing |
| `lib/features/analytics/domain/muscle_recovery.dart` | Deleted | VERIFIED | File absent |
| `lib/features/analytics/domain/cns_fatigue.dart` | Deleted | VERIFIED | File absent |
| `lib/features/analytics/presentation/recovery_heatmap_widget.dart` | Deleted | VERIFIED | File absent |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `training_snapshot.dart` | `tables.dart` | `deletedAt` column from `SyncTombstone` mixin | WIRED | grep confirms `deletedAt.isNull()` pattern present |
| `balance_analyzer.dart` | `training_snapshot.dart` | `ResolvedSet.tonnageKg` | WIRED | `resolvedSet.tonnageKg` used directly in summation |
| `analytics_providers.dart` | `balance_analyzer.dart` | `BalanceAnalyzer.summary(sets: snapshot.sets)` | WIRED | Exact call present at line 43 |
| `insights_view.dart` | `cns_recovery_cards.dart` (RecoveryDetailCard) | sole recovery widget | WIRED | `const RecoveryDetailCard()` present, `_RecoveryCard` absent |
| `test/analytics_soft_delete_test.dart` | `training_snapshot.dart` / `analytics_repository.dart` | `TrainingSnapshot.load(db)` / `AnalyticsRepository(db)` | WIRED | Both call patterns present and exercised in passing tests |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Soft-delete regression suite passes | `flutter test test/analytics_soft_delete_test.dart` | 3/3 tests passed | PASS |
| No new static-analysis errors introduced | `flutter analyze lib/ test/` | 13 pre-existing info/warning issues, none in analytics files, 0 errors | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| ANLY-01 | 09-02 | All recovery/CNS/balance/correlation providers read from shared trainingSnapshotProvider | SATISFIED | analytics_providers.dart lines 42-43, 49-53, 110-114 |
| ANLY-02 | 09-02 | Legacy recovery engine + duplicate recovery card removed | SATISFIED | Files deleted, `_RecoveryCard` absent, `RecoveryDetailCard` sole card |
| ANLY-03 | 09-01, 09-03 | Every analytics query excludes soft-deleted rows | SATISFIED | Filters present + regression test passing |
| ANLY-04 | 09-01 | Push/pull balance + correlations use effective load | SATISFIED | balance_analyzer.dart/biometric_correlations.dart use tonnageKg |

Note: `.planning/REQUIREMENTS.md` still shows ANLY-01–04 as unchecked `[ ]` / "Pending" in its tracking table — this is a documentation-sync gap only, not a code gap. Code evidence above directly satisfies all four requirements. Recommend updating REQUIREMENTS.md checkboxes as a follow-up, not a phase blocker.

### Anti-Patterns Found

None. No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers found in any of the phase's modified/created analytics files.

### Human Verification Required

None. All must-haves are verifiable via static code inspection and automated tests; no visual/UX/real-time behavior claims in this phase's scope require human judgment.

### Gaps Summary

No gaps. All 8 derived observable truths verified against live code on a clean working tree. The single documented mid-phase deviation (Task 1 initially blocked due to a stale worktree fork predating the schema v25 migration, then re-run successfully once schema v25 landed on master) was independently confirmed: commit `ba1c23e` is present in `training_snapshot.dart`'s history, the working tree is clean, and the `deletedAt.isNull()` filters are live in both `training_snapshot.dart` and `analytics_repository.dart` on current HEAD — the deviation was resolved correctly, not lost or reverted.

---

*Verified: 2026-08-14*
*Verifier: Claude (gsd-verifier)*
