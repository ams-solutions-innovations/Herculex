---
phase: 29-weekly-report-herculex-ai-narrative
plan: 11
subsystem: weekly-report
tags: [calculators, nutrition, training, e1rm, deterministic, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "IsoWeek window (29-01) and NutritionSection/TrainingSection value classes (29-07)"
provides:
  - "NutritionSectionCalculator.compute -> NutritionSection? plus NutritionWeekInputs and FoodEntryName"
  - "TrainingSectionCalculator.compute -> TrainingSection? over List<ResolvedSet>"
affects: [29-14]

tech-stack:
  added: []
  patterns:
    - "Calculators take explicit inputs, an IsoWeek and (for training) a caller-supplied windowEnd; no clock parameter, null for an empty window (D-06)"
    - "e1RM movers reuse the topOneRms isRepBased && isLoaded gate and OneRepMax.estimate"

key-files:
  created:
    - lib/features/weekly_report/domain/nutrition_section_calculator.dart
    - lib/features/weekly_report/domain/training_section_calculator.dart
    - test/features/weekly_report/section_calculators_test.dart
  modified: []

key-decisions:
  - "A target with kcal <= 0 is treated as no target, so the adherence band never divides or compares against zero"
  - "Movers report 1-decimal rounded e1RM and delta; a mover requires the rounded delta to be > 0 so the card never shows +0.0"
  - "Mover ties break by exercise name ascending; top-food ties break by name ascending (deterministic output)"
  - "Sets landing exactly on endExclusive belong to the next week; sets after windowEnd are excluded even inside the week"
  - "A session counts toward 'sessions' only when endedAt is set, but unended-session sets still contribute tonnage"

patterns-established:
  - "Training test fixtures build ResolvedSet directly over drift data classes (no database), via a local _set helper"

requirements-completed: []
requirements-partial: [RPT-01, RPT-02]

duration: 20min
completed: 2026-10-03
---

# Phase 29 Plan 11: Nutrition and Training section calculators Summary

**Two pure, clock-free calculators that turn explicit inputs plus an IsoWeek into the nutrition and training report sections, reusing ResolvedSet.tonnageKg and OneRepMax.estimate and returning null for empty weeks.**

## What was built

- `NutritionSectionCalculator` (`domain/nutrition_section_calculator.dart`): `NutritionWeekInputs` (logged days, kcal/protein by date, per-day targets, food entries, `copyWith(targetByDate:)`), `FoodEntryName`, and `compute`. Presence-based: averages are over logged days only and a logged day with zero kcal still counts. `adherenceBandFraction = 0.10` is the single named constant. Target means and `adherenceDays` are null when no logged day has a target. Everything is filtered to `[week.startIso, week.endIso]`. Top foods: grouped by key, count desc then name asc, max 3, trimmed, capped at 60, empty names skipped.
- `TrainingSectionCalculator` (`domain/training_section_calculator.dart`): `compute(week, windowEnd, sets)`. Window sets are those with `completedAt` in `[week.start, min(week.endExclusive, windowEnd)]`; previous-week sets give `prevWeekTonnageKg` (null when none). Tonnage is the sum of `ResolvedSet.tonnageKg` (never weight times reps), sessions are distinct ended sessions. E1RM movers: per exercise, best week e1RM minus best prior e1RM (prior = anything before `week.start`), behind the `isRepBased && isLoaded` gate, top 3 by delta.
- `section_calculators_test.dart`: 22 tests (11 nutrition, 11 training), covering window filtering, presence-based zero-kcal days, no-target nulls, band edge, ranking and caps, regression and no-history exclusions, gate skips, unestimable sets and determinism.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | a3fdaeb | failing nutrition calculator tests |
| 1 GREEN | 2b130f8 | NutritionSectionCalculator |
| 2 RED | fd1d771 | failing training calculator tests |
| 2 GREEN | 592999c | TrainingSectionCalculator |

## Verification

- `flutter test test/features/weekly_report`: 189 passed (22 new).
- `flutter analyze lib/features/weekly_report test/features/weekly_report`: no issues.
- `check_structure`: nothing reported for weekly_report.
- Greps: `adherenceBandFraction = 0.10` present; no `DateTime.now`, `package:flutter`, `package:drift` or `package:flutter_riverpod` in either calculator; no `weightKg *` arithmetic in the training calculator; `isRepBased` and `tonnageKg` present.
- TDD gate: `test(...)` commits (a3fdaeb, fd1d771) precede their `feat(...)` commits.

## Deviations from Plan

None - plan executed exactly as written. The implementation files were drafted before the tests and moved aside so each RED commit genuinely failed to compile before its GREEN commit restored them.

## Requirements

RPT-01 and RPT-02 remain partial (calculators only; the repository/service wiring in plan 14 and the UI plans are still to land), so they are not checked off in REQUIREMENTS.md.

## Known Stubs

None.

## Threat Flags

None. T-29-44 (no clock or provider access, window from IsoWeek plus explicit windowEnd, determinism test), T-29-45 (same isRepBased && isLoaded gate as topOneRms, gate test) and T-29-46 (null on empty windows, averages only over non-empty sets, non-finite inputs treated as zero) are mitigated as planned.

## Self-Check: PASSED

Both calculators and the test file exist; commits a3fdaeb, 2b130f8, fd1d771 and 592999c are present in git history.
