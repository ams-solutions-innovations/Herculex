---
phase: 29-weekly-report-herculex-ai-narrative
plan: 21
subsystem: weekly_report
tags: [gap-closure, drift, sync, iso-week]
requires: []
provides:
  - "WeeklyReportRepository without hard delete; shared _pickWinner"
  - "IsoWeek.isSnapshotDue and WeeklyReportService.canSnapshot (consumed by 29-24)"
affects: [29-24]
key-files:
  modified:
    - lib/features/weekly_report/data/weekly_report_repository.dart
    - lib/features/weekly_report/data/weekly_report_service.dart
    - lib/features/weekly_report/domain/iso_week.dart
    - lib/features/weekly_report/application/weekly_report_providers.dart
    - test/features/weekly_report/weekly_report_repository_test.dart
    - test/features/weekly_report/weekly_report_service_test.dart
    - test/features/weekly_report/iso_week_test.dart
    - test/features/weekly_report/weekly_report_controller_test.dart
decisions:
  - "Winner order: has tdeeDecision, has narrativeJson, earliest generatedAt, syncUuid (null as empty), id"
  - "Running week is persisted only on Sunday at/after the configured report time; existing rows always returned"
metrics:
  tasks: 3
  completed: 2026-10-04
---

# Phase 29 Plan 21: Weekly report data gap closure Summary

Tombstoned weekly reports are never hard-deleted on regeneration, duplicate-week rows resolve to one deterministic winner for all reads and mutators, and the running week is no longer frozen mid-week.

## Commits
- 02d0e75: repository (WR-01, WR-02)
- 3815ac1: snapshot-due rule, service gate, provider wiring, rebased fixtures (WR-07 data)

## Deviations from Plan

**1. [Rule 3] syncUuid is nullable in the generated row class.** `_compare` uses `syncUuid ?? ''`.

**2. Fixture rebase.** Service and controller tests moved from Wednesday 2026-09-30 to Sunday 2026-10-04 18:00. The "data later than now" service test now logs on 2026-10-05 (next week) because Oct 2 is no longer in the future. The controller quota-day expectation became 2026-10-04. View and history view tests needed no change.

**3. Incident.** An accidental `dart format lib test` touched ~60 unrelated files; they were reverted with `git checkout -- <file>` before committing, so only plan files are in the commits.

## Verification
- Full `flutter test`: all passed (2720 pass, 9 skipped).
- `flutter analyze`: 48 issues, 0 errors, none in weekly_report files.
- `check_structure`: 57 pre-existing violations, none from this plan.
- No schema, tables.dart or supabase changes.

## Known Stubs
None.

## Self-Check: PASSED
