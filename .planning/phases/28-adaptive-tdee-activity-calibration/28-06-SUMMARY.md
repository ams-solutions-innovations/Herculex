---
phase: 28-adaptive-tdee-activity-calibration
plan: 06
subsystem: nutrition-data
tags: [tdee, drift, repository, adherence, clock]
requires:
  - phase: 28-01
    provides: TdeeEstimateResult, TdeeMethod, TdeeConfidence
  - phase: 28-03
    provides: tdee_estimates drift table (schema v45)
  - phase: 28-04
    provides: WeightLog (via tdee_estimator.dart re-export)
provides:
  - TdeeEstimatesRepository (record, latest, watchLatest, recent)
  - TdeeInputsRepository.load() returning TdeeInputs
affects: [28-07, 28-08, phase-29]
tech-stack:
  added: []
  patterns:
    - "Repository takes (AppDatabase, Clock); dateIso from Clock, never DateTime.now()"
    - "Closed-vocabulary validation on read via fromName; display-only JSON decoded in try/catch"
key-files:
  created:
    - lib/features/nutrition/data/tdee_estimates_repository.dart
    - lib/features/nutrition/data/tdee_inputs_repository.dart
    - test/tdee_estimates_repository_test.dart
    - test/tdee_inputs_repository_test.dart
  modified: []
key-decisions:
  - "History and observation reads are two repositories so baselineTargetsProvider can depend on history alone (no cycle with nutrition_providers.dart)."
  - "foodLoggedDays uses selectOnly distinct dateIso, not kcal > 0; a zero-kcal entry still marks the day logged."
  - "Per-day kcal is only taken from NutritionRepository.watchDailyTotalsForRange(...).first for days in foodLoggedDays."
requirements-completed: [TDEE-01, TDEE-02, TDEE-05]
duration: 25min
completed: 2026-09-28
---

# Phase 28 Plan 06: TDEE Data Repositories Summary

**Two Clock-injected repositories: validated estimate-history persistence and presence-based adherence inputs (food days, bodyweight, steps, health averages, workouts per week) for the estimator.**

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 | TdeeEstimatesRepository | 48bfae5 (RED), 01c050b (GREEN) |
| 2 | TdeeInputsRepository | 2eac198 (RED), ffde2d8 (GREEN) |

## What was built

- `TdeeEstimatesRepository`: `record` rejects kcal outside (0, 10000] and negative windowDays with `ArgumentError` before insert; stores `dateIso` from the Clock and `estimatedAt` from the result. Reads share one query (`deletedAt IS NULL`, `estimatedAt desc, id desc`). `_toResult` maps method/confidence through `fromName` fallbacks and decodes `inputsJson` to `{}` on any failure or non-object JSON. Never references `nutrition_targets`.
- `TdeeInputsRepository.load()` returns `TdeeInputs` over a 60-day lookback: distinct-dateIso food days, snapshot/recipe-aware per-day kcal, ascending `bodyweight` logs, `steps`-only map, 14-day means for `active_kcal`/`sleep_hours`/`resting_hr` (null when absent), and completed sessions in 28 days divided by 4.

## Verification

- 12 estimates tests and 11 inputs tests pass.
- `flutter analyze`: 0 errors; the only issues in touched areas are pre-existing (`macro_chart.dart` info).
- `tool/check_structure.dart`: no violations involving the new files (58 pre-existing).
- Grep gates: no `DateTime.now`, no `kcal > 0`, no `nutritionTargets` in the new files.

## Deviations from Plan

None functionally. Two cosmetic edits so the plan's literal grep gates return nothing: the workouts helper parameter is named `asOf` (the regex `DateTime.now` matches `DateTime now`), and a doc comment avoids the literal text `kcal > 0`. The `kind.equals` gate matches once for `steps` and once in a shared `_average(kind, ...)` helper that serves `active_kcal`, `sleep_hours` and `resting_hr`, rather than four separate literals.

## Notes for plan 07

- `watchDailyTotalsForRange` does not filter `deletedAt` on `food_entries`. This is harmless today because `deleteEntry` hard-deletes, but `foodLoggedDays` does filter it, so the two would disagree if food entries ever became soft-deleted.
- Each persisted qualified non-observed row restarts the 7-day promotion clock (from 28-04); `recent()` returns rows newest-first for that hysteresis.
- The UI shows `span_days + 1` as the data span (from 28-04).

## Known Stubs

None.

## Threat Flags

None. Mitigations T-28-22 to T-28-26 are implemented and covered by tests.

## Self-Check: PASSED

Files and commits (48bfae5, 01c050b, 2eac198, ffde2d8) verified present.
