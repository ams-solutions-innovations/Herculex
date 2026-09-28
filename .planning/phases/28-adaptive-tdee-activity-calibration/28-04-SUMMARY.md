---
phase: 28-adaptive-tdee-activity-calibration
plan: 04
subsystem: nutrition
tags: [tdee, ewma, energy-balance, hysteresis, pure-dart]

requires:
  - phase: 28-adaptive-tdee-activity-calibration
    provides: TdeeEstimateResult / TdeeMethod / TdeeConfidence (plan 01), ActivityClassification (plan 01)
provides:
  - TdeeEstimator.estimateObserved (observed expenditure, gates, window self-selection, recency rule)
  - TdeeEstimator.recalibrate (time-based hysteresis, D-04 hold, classifier/cold-start fallback)
  - TdeeEstimator.shouldRecalibrate (cadence + weight-trend + step-shift triggers)
  - TdeeEstimator.isMaterialShift (D-09 threshold)
  - TdeeTuning (every assumption A1-A6 as a named constant)
  - WeightLog / TrendSeries (daily-grid EWMA weight trend)
affects: [28-06, 28-07, 28-08, 28-09, phase-29]

tech-stack:
  added: []
  patterns:
    - "Estimator is pure static Dart with an explicit asOf; no wall clock, no Flutter/drift"
    - "Tunables live on one abstract final class (DietPhaseCalculator precedent)"
    - "Hysteresis counts elapsed calendar days between qualifying rows, not row count"

key-files:
  created:
    - lib/features/nutrition/domain/tdee_estimator.dart
    - lib/features/nutrition/domain/tdee_trend.dart
    - test/tdee_estimator_test.dart
  modified: []

key-decisions:
  - "windowDays on an observed result is the winning candidate (35/28/21/14); the measured span is span_days in inputs and the UI prints span_days + 1"
  - "observedRecencyDays = cadenceDays - 1 (6) so a 7-day-old window fails the gate and the D-04 hold starts at the first cadence run after logging stops"
  - "Mean intake averages LOGGED days only (deliberately unlike the RESEARCH snippet, which averaged unlogged zeros in and biased TDEE low)"
  - "isMaterialShift is strict greater-than and unrounded, removing the RESEARCH rounding tie"
  - "Persisted rows restart the promotion clock: every recalibration that writes a qualified non-observed row means the next promotion needs a run 7+ days after THAT row"

patterns-established:
  - "ceilShare(share, n) subtracts 1e-9 before ceil so 0.7 * 10 gates at 7, not 8"
  - "TrendSeries.dayNumber(DateTime) gives DST-safe whole-day arithmetic for date-only comparisons"

requirements-completed: [TDEE-01, TDEE-03, TDEE-05]

duration: ~30min
completed: 2026-09-28
---

# Phase 28 Plan 04: Pure-Dart TdeeEstimator Summary

**Observed-expenditure estimator (EWMA-smoothed weight trend x 7700 kcal/kg over logged-day intake) with independent food/weight gates, widest-window self-selection, recency rule, time-based hysteresis and grace, and the D-09 material-shift rule, all unit-tested with fixed dates.**

## Performance

- **Duration:** ~30 min
- **Completed:** 2026-09-28
- **Tasks:** 2 of 2
- **Files:** 3 created (2 source, 1 test), 0 modified

## Accomplishments

- `TrendSeries` builds a daily grid with linear interpolation across weigh-in gaps and one EWMA step (alpha 0.1) per day, so gaps are not single-day jumps. Verified against the design-doc numbers (80.0 / 80.1 / 80.29).
- `estimateObserved` gates in order: recency (newest food day and newest weigh-in within 6 days of `asOf`), then per candidate window widest first: food coverage >= 70%, weigh-ins >= max(4, 2 x weeks) with one in each half, span >= 60% of the window, coverage inside the span, plausibility rails (intake >= 800, TDEE in [1000, 6000]). 28 dense days selects window 35 with `span_days` 27.
- `recalibrate` promotes classifier -> observed only when the newest qualified non-observed row is >= 7 calendar days old (forced or trigger runs a day apart never satisfy D-03), holds the last fresh observed estimate as `observedQualified: false`, `held: true`, `measured_at` until it is 14 days old (D-04), then falls back to classifier or cold start.
- `shouldRecalibrate` implements the three fixed triggers plus once-per-calendar-day and force; `isMaterialShift` matches D-09 at 100/101, 1500 and 3000/150/151.
- 91 tests pass across `tdee_estimator_test.dart`, `activity_classifier_test.dart`, `tdee_estimate_test.dart`. `flutter analyze`: 0 errors, no issues in the new files. `tdee_estimator.dart` is 498 lines; `check_structure` reports nothing for either new file (its 58 violations are pre-existing).

## Task Commits

1. **Task 1 RED:** `59491b0` test(28-04): add failing tests for observed-expenditure estimator
2. **Task 1 GREEN:** `feee235` feat(28-04): implement observed-expenditure estimator with EWMA trend
3. **Task 2:** `d9917d4` feat(28-04): add recalibrate, cadence gate and material-shift rule

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Floating-point ceil on adherence thresholds**
- **Found during:** Task 1 design
- **Issue:** `ceil(0.7 * n)` can overshoot on binary noise (0.7 x 10 -> 8), which would move the 70% bar by one day.
- **Fix:** `_ceilShare` subtracts 1e-9 before `ceil`.
- **Files modified:** `lib/features/nutrition/domain/tdee_estimator.dart`
- **Commit:** `feee235`

### Adjustments (not defects)

- **Task 2 TDD commits:** the Task 2 tests and implementation were committed together in `d9917d4` rather than as a separate RED commit. The tests were written first and failed to compile against the missing methods before implementation, but only the Task 1 RED state was committed on its own. Task 1's RED commit (`59491b0`) does not compile by design.
- **Test imports:** `test/tdee_estimator_test.dart` also imports `tdee_estimate.dart` and `activity_classifier.dart` (plan said only flutter_test and the file under test), because `TdeeConfidence` and `ActivityClassifier` are not re-exported from the estimator.
- **Public `TrendSeries.dayNumber`:** added so the estimator and the trend share one DST-safe day-arithmetic helper instead of duplicating it.
- **`TrendSeries` same-date rule:** "later" means the later timestamp, with input order as tiebreak (List.sort is not stable), rather than input order alone.
- **Plan's "span 14" for the falling fixture:** a 14-day window with data starting on its first day has span 13; the test derives the expected kcal from `TrendSeries` and the real span rather than the hand-figure 2275.

## Notes for Downstream Plans

- **Plan 07 (controller):** every persisted qualified non-observed row restarts the 7-day promotion clock. With the default cadence a user who is recalibrated weekly reaches observed on the second weekly run; a controller that persists extra trigger-driven runs delays promotion accordingly. Documented in `recalibrate`'s doc comment as by design.
- **Plan 09 (UI):** show `span_days + 1` as the data span and as the denominator of "Days with food logged"; never print `window_days`.
- `estimatedAt` comparisons use the date fields of the `DateTime` as given. Convert persisted UTC timestamps to local before passing them in.

## Known Stubs

None.

## Threat Flags

None. The estimator is pure Dart with no new network, auth, file or schema surface. T-28-12 through T-28-16 mitigations are all implemented: plausibility rails, daily-grid EWMA with per-half weigh-in gate, time-based hysteresis/grace/recency, no reference to `NutritionTargets`, no `DateTime.now`.

## Self-Check: PASSED

- FOUND: lib/features/nutrition/domain/tdee_estimator.dart
- FOUND: lib/features/nutrition/domain/tdee_trend.dart
- FOUND: test/tdee_estimator_test.dart
- FOUND commits: 59491b0, feee235, d9917d4
