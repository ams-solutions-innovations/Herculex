---
phase: 15-program-generator-regression-fixes-interaction-hardening
plan: 03
subsystem: calendar-workouts
tags: [calendar, scheduling, tab-navigation, resume, start, disambiguation]

# Dependency graph
requires:
  - 15-01
  - 15-02
provides:
  - "Disambiguated scheduled workout launching and idempotent resume by scheduleId"
  - "Atomic session materialization and schedule status updates inside db transaction"
  - "Automatic tab navigation to Workouts tab (index 2) upon starting or resuming from calendar"
  - "Strictly read-only preview of scheduled workout sessions"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ScheduleId-based lookup and atomic transaction wrapping to prevent same-day session collision or orphaned records"

key-files:
  created:
    - test/scheduled_workout_service_test.dart
    - test/widgets/day_detail_sheet_test.dart
  modified:
    - lib/features/workouts/data/scheduled_workout_service.dart
    - lib/features/programs/presentation/sheets/day_detail_sheet.dart

key-decisions:
  - "ScheduledWorkoutService queries and mutates strictly by scheduleId, preventing collisions when multiple workouts are scheduled on the same calendar date."
  - "Resuming an in-progress workout returns the existing session ID without generating duplicate WorkoutSessions rows."
  - "DayDetailSheet._start updates mainTabIndexProvider to 2 (Workouts tab) before popping the modal so the user lands directly in the active session."

requirements-completed: [FIX-04]

# Metrics
duration: ~15m
completed: 2026-09-13
---

# Phase 15 Plan 03: Calendar Schedule Launch Disambiguation & Tab Navigation Summary

Harden schedule lookup and resume handling by `scheduleId` in `ScheduledWorkoutService` and wired immediate tab transition to Workouts (Tab 2) in `DayDetailSheet`.

## Accomplishments
- Wrapped session materialization and schedule status updates in `ScheduledWorkoutService.startScheduledWorkoutById` in a single database transaction.
- Verified that resuming an in-progress scheduled workout returns the existing open session without creating duplicate `WorkoutSessions` records.
- Verified that previewing a scheduled workout via `previewScheduledWorkout` remains strictly read-only.
- Updated `DayDetailSheet._start` to transition the app's bottom navigation to `mainTabIndexProvider.state = 2` upon launching or resuming a session.
- Added tests in `test/scheduled_workout_service_test.dart` and `test/widgets/day_detail_sheet_test.dart` confirming collision-free same-day launching, idempotent resume, and tab navigation.
