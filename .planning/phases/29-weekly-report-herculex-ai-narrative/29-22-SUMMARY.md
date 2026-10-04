---
phase: 29-weekly-report-herculex-ai-narrative
plan: 22
subsystem: weekly_report
tags: [tdee, drift-transaction, gap-closure, riverpod]
requires: [29-21]
provides:
  - WeeklyReportRepository.applyTdeeDecision (atomic target + decision write)
  - TdeeActionResult and a guarded TdeeDecisionActions
  - TDEE card that never stays busy
affects: [weekly_report]
tech-stack:
  patterns: [callback-in-transaction, private rollback exception, re-resolve before write]
key-files:
  modified:
    - lib/features/weekly_report/data/weekly_report_repository.dart
    - lib/features/weekly_report/application/weekly_report_tdee_actions.dart
    - lib/features/weekly_report/presentation/widgets/tdee_shift_card.dart
    - test/features/weekly_report/weekly_report_repository_test.dart
    - test/features/weekly_report/tdee_shift_test.dart
    - test/features/weekly_report/tdee_shift_card_test.dart
decisions:
  - "applyTdeeDecision picks the 29-21 winner row, runs the target write as beforeRecord in the same transaction, and rolls back via a private exception if the guarded decision update changes no row."
  - "update re-resolves the proposal (invalidate, then read) and writes the freshly resolved macros; a kcal or appliesTo mismatch, or any non-proposed status, is stale."
metrics:
  tasks: 3
  completed: 2026-10-04
---

# Phase 29 Plan 22: Atomic TDEE write and card busy fix Summary

Closes WR-03 and WR-06: the nutrition target and the "updated" decision are written in one drift transaction, guarded against stale proposals and non-actionable weeks, and the TDEE card clears busy in a finally block with a message for every outcome.

## Tasks

| Task | Commit | Notes |
| ---- | ------ | ----- |
| 1 Atomic repository method | 290f3d5 | `applyTdeeDecision`; shared `_validateDecision`; 6 new repo tests (rollback on throw, already decided, no row, validation, duplicate winner) |
| 2 Actions guard and typed result | ca2fba3 | `TdeeActionResult`; actionable-week guard, stale check, kcal range check inside actions; provider wiring reads everything at call time |
| 3 Card busy and messages | 40f42d5 | try/catch/finally, per-result snackbars, keep pre-validates kcal |

## Deviations from Plan

- The old direct `TdeeDecisionActions` tests were in `tdee_shift_test.dart` (not the card test); they were rewritten there for the new constructor and signatures, plus a provider-wiring test with a rule changed after render. The card test file was updated in Task 3 because the card and its fake had to change together, so the Task 2 commit alone leaves the card not compiling against the new signatures.
- keep shows no snackbar on success (the decided note renders instead), consistent with prior behaviour.

## Verification

- weekly_report tests pass; full `flutter test` 2777 passed, 9 skipped, 0 failed.
- `flutter analyze`: no errors (43 pre-existing issues, none in weekly_report). `check_structure`: 57 pre-existing violations, none new.
- `upsertTarget` appears once in lib/features/weekly_report (the actions file). No schema, tables, or supabase changes.

## Known Stubs

None.

## Self-Check: PASSED
