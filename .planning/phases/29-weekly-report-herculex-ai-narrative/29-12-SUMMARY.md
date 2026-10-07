---
phase: 29-weekly-report-herculex-ai-narrative
plan: 12
subsystem: weekly-report
tags: [calculators, correlation, recovery, physique, tdee, deterministic, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "IsoWeek and CausalLanguageGuard (29-01), section value classes (29-07)"
provides:
  - "CorrelationStatement: fixed-template, sign-aware 'tended to' sentences gated by n >= 8 and r2 >= 0.3"
  - "RecoverySectionCalculator.compute -> RecoverySection? (engines run as of windowEnd)"
  - "PhysiqueSectionCalculator.compute -> PhysiqueSection? plus PhysiqueCheckInInput and BodyweightLog"
  - "TdeeShiftCalculator.compute -> TdeeSection? delegating to TdeeEstimator.isMaterialShift"
  - "TdeeEstimatesRepository.latestAtOrBefore and latestBefore"
affects: [29-14, 29-16]

tech-stack:
  added: []
  patterns:
    - "Engines are called directly with asOf = windowEnd over a snapshot filtered to completedAt <= windowEnd, never through the analytics providers"
    - "Closed-vocabulary pass-through for stored text that reaches the model (verdict, confidence)"

key-files:
  created:
    - lib/features/weekly_report/domain/correlation_statement.dart
    - lib/features/weekly_report/domain/recovery_section_calculator.dart
    - lib/features/weekly_report/domain/physique_section_calculator.dart
    - lib/features/weekly_report/domain/tdee_shift_calculator.dart
    - test/features/weekly_report/correlation_statement_test.dart
    - test/features/weekly_report/section_calculators_recovery_test.dart
    - test/features/weekly_report/tdee_shift_test.dart
  modified:
    - lib/features/nutrition/data/tdee_estimates_repository.dart
    - test/tdee_estimates_repository_test.dart

key-decisions:
  - "A3 thresholds: CorrelationStatement.minSamples = 8 and minR2 = 0.3 as named constants; below either, the neutral 'No clear relationship yet ... (n = N).' sentence is produced"
  - "Direction is the sign of the sample covariance of result.points; a constant series (variance <= 1e-9), fewer than 2 points or any non-finite point yields direction none. BiometricCorrelationResult.interpretation is never read"
  - "Both correlation lines (sleep_rpe, hr_tonnage) are always emitted, neutral when data is thin, so the card and facts have a stable shape"
  - "Recovery runs MuscleRecoveryV3 with externalWorkouts: const [] and daysOfHealthHistory: 0: no live Health Connect reads at generation time, so the warnings reflect logged gym sets only"
  - "cnsReadinessPct is null (not 100) when no set exists on or before windowEnd, since an empty history says nothing about readiness"
  - "Correlation window is the 8 weeks ending at windowEnd, anchored with DateTime(y, m, d - 56) for DST safety; sets are selected by session.startedAt, health rows by dateIso"
  - "Physique confidence is also restricted to its closed vocabulary (low, medium, high, unknown), same as the verdict"
  - "TdeeSection.deltaKcal is signed (newest minus before); materiality uses the magnitude via isMaterialShift"

patterns-established:
  - "Calculators accept supersets of data and filter by date themselves, so a past report cannot depend on what the caller loaded"

requirements-completed: []
requirements-partial: [RPT-01, RPT-02, RPT-05]

duration: 35min
completed: 2026-10-03
---

# Phase 29 Plan 12: Correlation statements, recovery/physique and TDEE shift calculators Summary

**Sign-aware fixed-template correlation sentences, a recovery calculator that runs the CNS and muscle-recovery engines as of the window end, a closed-vocabulary physique calculator, and a TDEE drift calculator that reuses Phase 28's strict materiality rule over new repository history queries.**

## What was built

- `CorrelationStatement` (`domain/correlation_statement.dart`): `CorrelationKind` (`sleepRpe` = `sleep_rpe`, `hrTonnage` = `hr_tonnage`), `CorrelationDirection`, and `CorrelationStatement.from`. Four stated templates (more sleep goes with lower/higher RPE; higher resting heart rate goes with lower/higher volume, all "tended to") plus two neutral ones. Thresholds `minSamples = 8` and `minR2 = 0.3` are named constants (assumption A3) and are the only place to change them.
- `RecoverySectionCalculator` (`domain/recovery_section_calculator.dart`): averages for sleep (1 decimal), steps (rounded int) and resting HR (1 decimal) over in-week rows; CNS readiness percent and deload flag from `CnsTrends.compute(asOf: windowEnd)`; up to 5 warning messages from `MuscleRecoveryV3.warnings(compute(asOf: windowEnd))`; two correlation lines over the trailing 8 weeks. Null when the week holds no health sample and no completed set.
- `PhysiqueSectionCalculator` (`domain/physique_section_calculator.dart`): newest in-week check-in (verdict limited to `on_track` / `off_track` / `inconclusive`), last in-week bodyweight and a delta against the last earlier reading (2 decimals). Non-finite or non-positive weights are ignored. Null when there is neither.
- `TdeeShiftCalculator` (`domain/tdee_shift_calculator.dart`): null for a missing baseline, missing newest or a cold-start newest; otherwise a `TdeeSection` whose `material` flag is `TdeeEstimator.isMaterialShift`. No threshold constant exists in the file.
- `TdeeEstimatesRepository.latestAtOrBefore(t)` and `latestBefore(t)`: `_newestFirst(limit: 1)` plus an `estimatedAt` bound, so the soft-delete filter, id tie-break and `_toResult` validation are inherited.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | 7a315a9 | failing CorrelationStatement tests |
| 1 GREEN | 4f48338 | CorrelationStatement |
| 2 RED | 6162009 | failing recovery and physique tests |
| 2 GREEN | 2114320 | recovery and physique calculators |
| 2 docs | 160e199 | header wording so the plan's grep gate is clean |
| 3 RED | 5b7effa | failing TDEE shift and repository query tests |
| 3 GREEN | 847c33a | TdeeShiftCalculator and repository queries |

## Verification

- `flutter test test/features/weekly_report`: 237 passed (all of the folder, including 14 new correlation, 23 recovery/physique and 10 TDEE shift tests).
- `flutter test test/tdee_estimates_repository_test.dart`: 6 new query tests pass with the existing ones.
- `flutter analyze` over the touched lib and test paths: no issues. `check_structure` reports nothing for weekly_report or the repository.
- Greps: `interpretation` count 0 in `correlation_statement.dart`; `minSamples = 8` and `minR2 = 0.3` present; `asOf: windowEnd` present for both engines; no `recoveryV3Provider`, `cnsTrendsProvider`, `DateTime.now` or `flutter_riverpod` in the recovery and physique calculators; `TdeeEstimator.isMaterialShift` present and no `100` literal in the TDEE shift calculator.
- Determinism: a test shows that 20 sets completed after `windowEnd` would flip `deloadSuggested` if the engines saw them, and that the calculator output is identical with and without them. A past-week test checks readiness is computed as of that week's end.
- Strict boundary: 1500 to 1600 (delta exactly 100) is asserted not material; 1500 to 1610 is material.
- TDD gate: `test(...)` commits precede their `feat(...)` commits for all three tasks.

## Deviations from Plan

### Auto-added

**1. [Rule 2 - Missing critical] Physique confidence restricted to a closed vocabulary**
- **Found during:** Task 2
- **Issue:** The plan closes the verdict vocabulary but passes confidence through; both reach the model's facts and the stored column is free text that may have been pulled from the cloud.
- **Fix:** confidence is passed through only when it is `low`, `medium`, `high` or `unknown`.
- **Files modified:** physique_section_calculator.dart (with a test).

**2. [Rule 2 - Missing critical] Non-finite and constant-series guards in direction detection**
- **Issue:** Beyond the plan's "fewer than two points and zero covariance", a NaN point or a constant series whose mean rounds slightly would produce a spurious sign.
- **Fix:** any non-finite point or variance <= 1e-9 yields direction none.
- **Files modified:** correlation_statement.dart (with tests).

### Notes

- Two doc-comment rewordings (commit 160e199 and a line in `tdee_shift_calculator.dart`) keep the plan's literal grep gates (`DateTime.now`, `100\b`) at zero; no behaviour changed.
- The recovery tests also cover physique (the plan allots them to `section_calculators_recovery_test.dart`).

## Requirements

RPT-01, RPT-02 and RPT-05 remain partial (calculators only; repository wiring in plan 14 and the UI plans are still to land), so they are not checked off in REQUIREMENTS.md.

## Known Stubs

None.

## Threat Flags

None. T-29-47 (templates, thresholds, guard test over every template, interpretation unused), T-29-48 (direction from the points, test with r2 0.95 and negative points), T-29-49 (asOf windowEnd, filtered snapshot, trailing window by date, future-set test) and T-29-50 (delegation to `isMaterialShift`) are mitigated as planned.

## Self-Check: PASSED

All four domain files, the repository change and the three new test files exist; commits 7a315a9, 4f48338, 6162009, 2114320, 160e199, 5b7effa and 847c33a are present in git history.
