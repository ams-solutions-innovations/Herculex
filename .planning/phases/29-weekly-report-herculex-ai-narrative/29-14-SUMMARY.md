---
phase: 29-weekly-report-herculex-ai-narrative
plan: 14
subsystem: weekly-report
tags: [service, repository, snapshot, narrative, quota-safety, drift, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "WeeklyReportRepository (29-06), payload and facts (29-07), narrative service (29-09), nutrition/training calculators (29-11), recovery/physique/TDEE calculators and TDEE history queries (29-12), IsoWeek (29-01)"
provides:
  - "WeeklyReportInputsRepository.load(week, windowEnd) -> WeeklyReportInputs: deterministic week-scoped raw inputs, no time reads"
  - "WeeklyReportService.generate(week): get-or-freeze a snapshot row, persisted before any AI work"
  - "WeeklyReportService.generateNarrative(week) -> NarrativeOutcome: the single narrative path (auto first-open and manual retry)"
affects: [29-15, 29-16, 29-17, 29-18]

tech-stack:
  added: []
  patterns:
    - "Window passed as an argument to the loader (no clock) so late-generated past weeks equal on-time ones"
    - "Attempt counter incremented before the backend call; every short-circuit (saved, ineligible) makes zero calls"

key-files:
  created:
    - lib/features/weekly_report/data/weekly_report_inputs_repository.dart
    - lib/features/weekly_report/data/weekly_report_service.dart
    - test/features/weekly_report/weekly_report_inputs_repository_test.dart
    - test/features/weekly_report/weekly_report_service_test.dart
  modified: []

key-decisions:
  - "Everything dated after the window end is excluded at load time (food, health, weights, check-ins), not only in the calculators: for the current week that is today, so a meal planned for Friday is not in a Wednesday snapshot"
  - "trailingHealth reaches 56 days before the week start (superset of the recovery calculator's own 8-week window ending at windowEnd); the calculator does the exact filtering"
  - "NarrativeOutcome is a small value class (status enum plus optional failure kind) with static saved / alreadySaved / notEligible and a NarrativeOutcome.failed(kind) constructor"
  - "Facts are built before the attempt increment, so a facts bug throws without burning quota; only the backend call is wrapped, and any non-typed error there maps to failed(unavailable). A save error is not swallowed"
  - "saveNarrative returning false (another call won the race) is reported as alreadySaved"

patterns-established:
  - "Food entry identity key: food:<id>, recipe:<id>, else name:<lowercase name>"

requirements-completed: []
requirements-partial: [RPT-01, RPT-02, RPT-04, RPT-05]

duration: 40min
completed: 2026-10-03
---

# Phase 29 Plan 14: Weekly report inputs repository and service Summary

**A clock-free inputs loader plus `WeeklyReportService` that freezes an ISO week into one row (persisted before any AI work, returned untouched on every later call) and a single quota-safe, write-once narrative path that writes nothing but the attempt counter and the narrative columns.**

## What was built

- `WeeklyReportInputsRepository(db, nutrition, tdeeEstimates).load(week:, windowEnd:)`: presence-based logged days (`selectOnly distinct`, `deletedAt.isNull()`, both bounds), snapshot/recipe-aware kcal and protein from `watchDailyTotalsForRange(...).first` restricted to logged days, food names (snapshot name, then catalogue, then recipe, unresolvable skipped), health for the week and a trailing window, `TrainingSnapshot.load`, `checkin` assessments, bodyweight logs ascending, and `latestAtOrBefore(windowEnd)` / `latestBefore(week.start)` TDEE rows. No clock; the words `Clock` and `DateTime.now` do not appear in the file.
- `WeeklyReportService.generate`: existing live row returned unchanged (D-01, RPT-04); future week -> null; `windowEnd = week.windowEnd(now)`; load; targets from the injected resolver per logged day; the five calculators; `WeeklyReportPayload`; `!hasSignal` -> null (D-06); `insertSnapshot`.
- `WeeklyReportService.generateNarrative`: no row / unreadable payload / no narrative signal -> `notEligible`; narrative present -> `alreadySaved`; otherwise `incrementNarrativeAttempts` (line 167) before `_narrative.generate(facts)` (line 171), then `saveNarrative` with provenance. Failures map to `failed(kind)`.
- 31 tests (10 inputs, 21 service).

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | 1557e20 | failing inputs repository test |
| 1 GREEN | 8c9ac4a | WeeklyReportInputsRepository |
| 2 RED | 290bcc8 | failing service test |
| 2 GREEN | cb44a81 | WeeklyReportService |

## Verification

- `flutter test test/features/weekly_report`: 288 passed (whole folder).
- `flutter analyze lib/features/weekly_report test/features/weekly_report`: no issues. `dart format`: no changes. `check_structure` reports nothing for weekly_report.
- Greps: `DateTime.now` count 0 in both files; `Clock` count 0 in the inputs repository; `incrementNarrativeAttempts` (167) precedes `_narrative.generate(` (171); no `upsertTarget`, `nutritionTargets` or `NutritionRepository` in the service; 14 `package:herculex/` imports, no relative imports.
- Covered: RPT-04 back-edit/delete test, seeded-TDEE-history empty week (asserts the TDEE section would be computed, then null and zero rows), weight-only week (row, no narrative signal), attempt count observed as 1 inside the fake backend, hostile food name sanitised in the facts, all five `NarrativeFailureKind` values with a second-call retry reaching attempts 2, zero backend calls for saved / ineligible / no-row / unreadable payload, and an unchanged-tables test.
- TDD gate: `test(...)` commit precedes `feat(...)` for both tasks (the implementation was moved aside so each RED run genuinely failed to compile).

## Deviations from Plan

### Auto-added

**1. [Rule 2 - Correctness] Window end applied at load time**
- **Issue:** The plan bounds logged days by the week only. A current-week snapshot generated on Wednesday would otherwise include entries dated later in the week, contradicting D-04 (Monday through the moment of generation) and the training calculator's own `windowEnd` cut.
- **Fix:** All date-keyed reads use `min(week.endIso, dateIso(windowEnd))` as the upper bound. For a finished week this equals `week.endIso`, so the plan's behaviour is unchanged. Covered by a test.
- **Files:** weekly_report_inputs_repository.dart

### Notes

- `trailingHealth` is defined as 56 days before the week start rather than exactly "8 weeks ending at week.endIso": the recovery calculator anchors its window at `windowEnd`, which for a current week is earlier than `week.endIso`, so the wider load is the safe superset.

## Deferred Issues

- `NutritionRepository.watchDailyTotalsForRange` does not filter `food_entries.deletedAt`. The inputs repository restricts days to the live set, but a day holding one live and one tombstoned entry (only possible via sync pull, since local deletes are hard) would include the tombstone's kcal. The same query backs `TdeeInputsRepository` and the Today screen, so it is a shared-code change outside this plan.

## Known Stubs

None.

## Threat Flags

None. T-29-55 (the service has no handle on targets or other tables; unchanged-tables test), T-29-56 (increment before call; alreadySaved / notEligible make zero calls, tested), T-29-57 (RPT-04 test), T-29-58 (facts only via `WeeklyReportFacts`; hostile-name test) and T-29-59 (future and empty weeks return null with no row) are mitigated as planned.

## Requirements

RPT-01, RPT-02, RPT-04 and RPT-05 stay unchecked in REQUIREMENTS.md (partial-completion convention): providers, the de-duplicating controller, views and the dashboard entry point are plans 15 to 18.

## Hand-off

- Plan 15 wires providers: `WeeklyReportInputsRepository(db, nutritionRepo, tdeeEstimatesRepo)`, `WeeklyReportService(... targetForDay: effectiveTargetsProvider-backed ...)`, and the app-lifetime controller that gates the AUTO narrative call (this service does not gate; manual retry and auto both go through `generateNarrative`).
- `generate` does not catch errors; the controller is the fail-soft layer.

## Self-Check: PASSED

- Files present: both data files and both test files.
- Commits present: 1557e20, 8c9ac4a, 290bcc8, cb44a81.
