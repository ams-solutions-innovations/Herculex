---
phase: 20-active-workout-shell-calendar-execution-flow
plan: 04
subsystem: workouts
tags: [go_router, riverpod, day-detail-sheet, navigation]

# Dependency graph
requires:
  - phase: 20-active-workout-shell-calendar-execution-flow (20-01)
    provides: "test/support/go_router_test_harness.dart — GoRouterTestHarness + StubRouteScreen"
  - phase: 20-active-workout-shell-calendar-execution-flow (20-03)
    provides: "AppRoutes.plannedWorkoutPreview / PlannedWorkoutPreviewView, day_detail_sheet.dart._viewWorkout as the route-pushing baseline this plan branches"
provides:
  - "ScheduledWorkoutRow.completedSessionId — delegate getter exposing schedule.completedSessionId"
  - "day_detail_sheet.dart._viewWorkout status-gated routing: done/in-progress rows -> WorkoutHistoryView(sessionId), everything else -> PlannedWorkoutPreviewView"
affects: [20-05-plan]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Status-gated navigation in _viewWorkout: branch on row.isDone/row.isInProgress before choosing which AppPaths.* to push, with a defensive SnackBar fallback (never push a null id) matching the same StateError-to-SnackBar shape _start already uses"

key-files:
  created: []
  modified:
    - lib/features/programs/domain/scheduled_workout_row.dart
    - lib/features/programs/presentation/sheets/day_detail_sheet.dart
    - test/widgets/day_detail_sheet_test.dart

key-decisions:
  - "The plan's <interfaces> section referenced 'the existing no longer exists SnackBar' in day_detail_sheet.dart as if already present — it isn't; Plan 20-03 moved that message into PlannedWorkoutPreviewView's empty-state Text widget, not a SnackBar in this file. Added the defensive SnackBar fresh in _viewWorkout using the same message text, matching T-20-04's mitigation requirement rather than assuming code that no longer exists in this file."
  - "New tests reuse DayDetailSheet.show(...) as the harness's real modal entry point (established by Plan 20-03's fix for the 'popped the last page' GoRouter assertion), rather than embedding DayDetailSheet as the harness's home directly."

requirements-completed: [FLOW-03]

# Metrics
duration: 14min
completed: 2026-09-16
---

# Phase 20 Plan 04: View Workout Routing Fix Summary

**Status-gated `DayDetailSheet._viewWorkout`: done/in-progress rows now open the real logged/live `WorkoutHistoryView(sessionId: completedSessionId)` instead of always showing the planned preview, with a defensive fallback when the link is unexpectedly missing.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-09-16T17:10:00Z (approx, first file edit)
- **Completed:** 2026-09-16T17:24:01Z
- **Tasks:** 2 completed
- **Files modified:** 3

## Accomplishments
- Added `ScheduledWorkoutRow.completedSessionId`, a one-line delegate getter to `schedule.completedSessionId` (nullable, populated at start time by `ScheduledWorkoutService.startScheduledWorkoutById` — already correct for both `in_progress` and `done` rows, per the plan's research).
- Rewrote `_SessionCard._viewWorkout` to branch on `row.isDone || row.isInProgress`: pushes `AppPaths.workoutHistory(completedSessionId)` when a session id is present, shows a defensive "This scheduled workout no longer exists." `SnackBar` (no navigation) when it's unexpectedly `null`, and otherwise (planned/moved/skipped) keeps the unchanged `AppPaths.plannedWorkoutPreview(row.id)` push from Plan 20-03. Both branches still pop the sheet before pushing, matching `_start`'s existing sequencing.
- Extended `createTestRow` with an optional `completedSessionId` param and added three regression tests: done-row routes to `WorkoutHistory:<id>`, in-progress-row shares the same route (D-07), and a done row with a `null` completedSessionId shows the SnackBar and pushes nothing — `day_detail_sheet_test.dart` now covers 6/6 reachable View-workout paths.
- Closes the real bug FLOW-03 named: a completed day's "View workout" no longer shows the stale plan when the actual logged session already exists.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add completedSessionId and rewrite _viewWorkout's routing** - `730c1af` (feat)
2. **Task 2: Regression-test all four reachable View-workout routes** - `686580c` (test)

**Plan metadata:** (this commit)

## Files Created/Modified
- `lib/features/programs/domain/scheduled_workout_row.dart` - Added `completedSessionId` delegate getter
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart` - `_viewWorkout` now status-gated: done/in-progress -> `WorkoutHistoryView`, else -> `PlannedWorkoutPreviewView`, with a defensive SnackBar for a missing session id
- `test/widgets/day_detail_sheet_test.dart` - `createTestRow` gained an optional `completedSessionId` param; three new tests cover done, in-progress, and null-session View-workout routing

## Decisions Made
- The plan's `<interfaces>` block assumed an existing "no longer exists" `SnackBar` already lived in `day_detail_sheet.dart` to reuse verbatim. It doesn't — Plan 20-03 relocated that copy into `PlannedWorkoutPreviewView`'s empty-state `Text` widget when it retired the inline `_WorkoutPlanPreviewSheet`. Added a fresh `SnackBar` with the same message text in `_viewWorkout`, satisfying the plan's acceptance criteria and T-20-04's mitigation without depending on code that no longer exists in this file.
- Followed Plan 20-03's established pattern of pumping `DayDetailSheet` via its real `.show()` entry point in the new tests (rather than as the harness's `home` directly), since `_viewWorkout`'s `Navigator.of(context).pop()` needs an imperative modal route on the stack to pop.

## Deviations from Plan

None - plan executed as written, adjusted only for the interface note documented above under Decisions Made (not a Rule 1-4 deviation — no behavior differs from spec, just where the message text was sourced from).

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- FLOW-03 is closed: done/in-progress rows' "View workout" opens the real logged/live session; planned/moved/skipped rows are unaffected.
- `ScheduledWorkoutRow.completedSessionId` is available for any future plan needing the same status-gated routing pattern elsewhere (e.g. calendar surfaces outside `DayDetailSheet`).
- No blockers.

---
*Phase: 20-active-workout-shell-calendar-execution-flow*
*Completed: 2026-09-16*
