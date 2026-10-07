---
phase: 28-adaptive-tdee-activity-calibration
plan: 01
subsystem: nutrition
tags: [tdee, activity-classifier, domain, dart]

requires: []
provides:
  - "TdeeMethod, TdeeConfidence, TdeeEstimateResult, TdeeBadgeState (plain-Dart estimate types with locked badge copy)"
  - "ActivityClassifier.classify + ActivityClassification (continuous multiplier from steps + training, seed-blended)"
affects: [28-02, 28-03, 28-04, 28-05, 28-09]

tech-stack:
  added: []
  patterns:
    - "Static const tunables on the calculator class (DietPhaseCalculator precedent)"
    - "Named `unavailable` sentinel for insufficient data"

key-files:
  created:
    - lib/features/nutrition/domain/tdee_estimate.dart
    - lib/features/nutrition/domain/activity_classifier.dart
    - test/tdee_estimate_test.dart
    - test/activity_classifier_test.dart
  modified: []

key-decisions:
  - "Classifier returns a double multiplier, never an ActivityLevel bucket (TDEE-02)"
  - "active_kcal, sleep_hours, resting_hr are recorded in inputs only; they never affect multiplier or confidence"
  - "Classifier confidence is never high; classified+high badge is clamped to Medium defensively"
  - "Non-finite or negative step values are dropped before the day count (T-28-01 hardening)"
  - "avg_steps in toInputs() is rounded to an int for display"

patterns-established:
  - "Domain files in features/nutrition/domain import only dart:math and sibling package: imports"

requirements-completed: [TDEE-02, TDEE-04]

duration: 20min
completed: 2026-09-28
---

# Phase 28 Plan 01: Estimate Types and Activity Classifier Summary

**Plain-Dart `TdeeEstimateResult` (method, confidence, window, inputs) with locked badge copy, plus an `ActivityClassifier` that maps 14-day step averages and weekly workouts to a continuous 1.15-1.90 multiplier blended with the manual seed by data sparsity.**

## Performance

- **Tasks:** 2/2
- **Files created:** 4 (2 domain, 2 test)
- **Tests:** 33 passing (14 estimate types, 19 classifier)

## Accomplishments

- `tdee_estimate.dart` has no imports. `fromName` fallbacks (`coldStart` / `low`) make corrupt persisted text harmless (T-28-02). Badge labels match 28-UI-SPEC exactly, with classified+high clamped to Medium.
- `activity_classifier.dart` interpolates step anchors (3000/7500/10000/15000 to 1.20/1.375/1.55/1.725), adds a training bonus of 0.02 per weekly workout capped at 0.10, blends the seed when fewer than 14 step days exist, and clamps the result (T-28-01). It returns `ActivityClassification.unavailable` below 3 step days.
- Anchor coefficients are documented as LOW-confidence assumption A7, all tunable as `static const` on the class.

## Task Commits

1. **Task 1: Estimate value types and badge state** - `23e8183` (feat)
2. **Task 2: ActivityClassifier** - `e1dced5` (feat)

Each task's test file and implementation were committed together. Both test files were run red (compile failure against missing files) before the implementation existed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Unicode escapes are rewritten by `dart format`**
- **Found during:** Task 1
- **Issue:** The plan asked for `·` / `—` escapes in the badge strings and an acceptance grep for them. The repo's mandated `dart format lib test tool` rewrites them to the literal characters, so the escapes cannot be kept stable.
- **Fix:** Kept the formatter output (literal `·` and `—`). The test file asserts against explicit `·` / `—` escapes, so an encoding corruption of the source would fail the tests.
- **Files modified:** `lib/features/nutrition/domain/tdee_estimate.dart`
- **Commit:** `23e8183`

**2. [Rule 2 - Missing critical] Input sanitising in classify**
- **Found during:** Task 2
- **Issue:** T-28-01 says absurd or negative step values must not produce an absurd TDEE; the anchor clamp covers large values but NaN/negative entries would still skew the mean and day count.
- **Fix:** Non-finite and negative step values are dropped before counting; negative or non-finite `workoutsPerWeek` becomes 0.
- **Commit:** `e1dced5`

**Test adjustment:** The "rounded to 3 decimals" test uses 8123 steps (1.419) rather than the 8750 midpoint, because 1.4625 sits on a rounding tie and is float-fragile. The 8750 midpoint is still asserted separately with `closeTo`.

## Verification

- `flutter test test/activity_classifier_test.dart test/tdee_estimate_test.dart`: 33 passed.
- `flutter analyze` on the four new files: no issues.
- `dart run tool/check_structure.dart`: exits 1 with 58 pre-existing violations; none reference the new files.
- Acceptance greps: no Flutter/drift/riverpod/`DateTime.now` in either domain file; `tdee_estimate.dart` has 0 imports; `activity_classifier.dart` imports only `dart:math` and `tdee_estimate.dart`; no `TdeeConfidence.high` in the classifier.
- `dart analyze` crashes in this environment inside the custom_lint plugin, so `flutter analyze` was used instead.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- FOUND: lib/features/nutrition/domain/tdee_estimate.dart
- FOUND: lib/features/nutrition/domain/activity_classifier.dart
- FOUND: test/tdee_estimate_test.dart
- FOUND: test/activity_classifier_test.dart
- FOUND commits: 23e8183, e1dced5
