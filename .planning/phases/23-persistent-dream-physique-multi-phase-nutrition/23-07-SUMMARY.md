---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 07
subsystem: physique
tags: [drift, repository, check-in, transaction, charts]
requires: ["23-02", "23-05", "23-06"]
provides:
  - PhysiqueAssessmentRepository (recordCheckIn, addBaselinePhoto, deleteCheckIn, reads)
  - CheckInTooSoonException, GoalNotActiveException, BaselineLimitException
  - PhysiqueSeriesRepository (watchWeightLogs, watchStrengthSamples, watchSessionDates)
affects: [23-08, 23-09, 23-10]
key-files:
  created:
    - lib/features/physique/data/physique_assessment_repository.dart
    - lib/features/physique/data/physique_series_repository.dart
    - test/features/physique/physique_assessment_repository_test.dart
    - test/features/physique/physique_series_repository_test.dart
decisions:
  - "Cap lookup includes soft-deleted check-ins; deleteCheckIn is soft so deleting cannot reopen the window"
  - "Baseline photos are capped separately and do not consume the weekly slot"
metrics:
  tasks: 2
  completed: 2026-10-02
---

# Phase 23 Plan 07: Check-in repository and chart series Summary

Transactional, soft-delete-proof 7-day check-in cap in `PhysiqueAssessmentRepository` with typed errors, plus read-only repository streams for bodyweight, canonical-lift e1RM samples and session dates.

## What was built

- `recordCheckIn` runs in one `_db.transaction`: requires an active goal, reads the newest check-in (soft-deleted included), applies `CheckInCapPolicy`, then inserts the assessment (verdict, band, confidence, reason, limitations, provenance) and the `checkin` photo. It is the only writer of `role = 'checkin'`.
- `addBaselinePhoto` (no cap, max 3 per goal), `deleteCheckIn` (soft delete, returns relative paths, rejects unknown or non-checkin ids), and watch/get reads.
- `PhysiqueSeriesRepository`: joins set_entries, workout_exercises, workout_sessions, exercise_catalog; completed, non-warmup, `standard` sets on canonical lift slugs, rep-based and loaded only; all soft-delete filtered. Read-only.
- Tests: 12 assessment tests (concurrency via Future.wait, soft-delete, DST, per-goal isolation, trigger-forced rollback) and 4 series tests including a live re-emission test.

## Deviations from Plan

None to the design. Test note: `openTestDatabase()` does not seed the bundled catalogue, so the series tests insert their own catalogue rows with the canonical slugs instead of looking them up.

## Verification

- `flutter test test/features/physique test/physique_sync_registration_test.dart`: 159 pass.
- `flutter analyze lib/features/physique test/features/physique`: no issues. `check_structure` names no physique file.

## Commits

- de9cf5c: feat(23-07): add PhysiqueAssessmentRepository with enforced 7-day check-in cap
- 94766a7: feat(23-07): add PhysiqueSeriesRepository for chart streams

## Requirements

PHYS-06 (cap) fully delivered at repository level. PHYS-01, PHYS-07, PHYS-08 are data-layer halves only (no UI/AI wiring yet), so left unticked for the orchestrator to reconcile.

## Self-Check: PASSED
