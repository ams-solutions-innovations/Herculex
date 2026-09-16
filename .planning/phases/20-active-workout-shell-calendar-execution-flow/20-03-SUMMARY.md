---
phase: 20-active-workout-shell-calendar-execution-flow
plan: 03
subsystem: workouts
tags: [go_router, riverpod, workout-preview, day-detail-sheet]

# Dependency graph
requires:
  - "test/support/go_router_test_harness.dart — GoRouterTestHarness + StubRouteScreen (20-01)"
provides:
  - "AppRoutes.plannedWorkoutPreview / AppPaths.plannedWorkoutPreview — new pushed route for viewing a scheduled workout's plan"
  - "plannedWorkoutPreviewProvider — FutureProvider.autoDispose.family<PlannedWorkoutPreviewData?, int> resolving a scheduleId's plan/catalog/status"
  - "PlannedWorkoutPreviewView — standalone pushed screen rendering the plan with a status-gated Start workout CTA"
affects: [20-04-plan, 20-05-plan]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Route-pushed detail view resolves its own data from a single id path param via a FutureProvider.autoDispose.family, matching WorkoutHistoryView/sessionSummaryProvider's existing shape — no `extra` payload, no direct drift query in the view."
    - "DayDetailSheet is only ever shown as a modal (HxSheet.show -> showModalBottomSheet), which pushes an imperative Route separate from GoRouter's declarative stack — so Navigator.of(context).pop() inside it pops the modal, not the underlying page. Widget tests exercising this must pump the sheet via its real .show() entry point under GoRouterTestHarness, not embed its body directly as the harness's page-level home."

key-files:
  created:
    - lib/features/workouts/presentation/views/planned_workout_preview_view.dart
    - test/widgets/planned_workout_preview_view_test.dart
  modified:
    - lib/app/router/routes.dart
    - lib/app/router/router.dart
    - lib/features/workouts/application/workouts_providers.dart
    - lib/features/programs/presentation/sheets/day_detail_sheet.dart
    - test/features/workouts/day_detail_sheet_preview_test.dart
    - test/widgets/day_detail_sheet_test.dart

key-decisions:
  - "Kept AppBar (not HxScreenShell) for PlannedWorkoutPreviewView per the plan's explicit interface spec, even though WorkoutHistoryView (the pattern precedent) uses HxScreenShell — the plan's <action> text said AppBar literally."
  - "Rewrote the 'View workout' widget test to pump DayDetailSheet through its real .show() entry point (a button that calls DayDetailSheet.show) instead of embedding it directly as GoRouterTestHarness's home, because _viewWorkout's Navigator.pop() now needs an imperative modal route on the stack above GoRouter's single declarative route — pumping the sheet body directly as home left nothing to pop and tripped GoRouter's 'popped the last page off the stack' assertion."

requirements-completed: [FLOW-02]

# Metrics
duration: 55min
completed: 2026-09-16
---

# Phase 20 Plan 03: Planned Workout Preview Route Summary

**Turned the inline `_WorkoutPlanPreviewSheet` (sheet-on-sheet inside `DayDetailSheet`) into a standalone pushed route, `PlannedWorkoutPreviewView`, resolving its own data from a `scheduleId` via `plannedWorkoutPreviewProvider` — with a status-gated Start workout CTA.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-09-16T16:47:00Z (approx, first file edit)
- **Completed:** 2026-09-16T17:03:58Z
- **Tasks:** 3 completed
- **Files modified:** 8 (2 created, 6 modified)

## Accomplishments
- Added `AppRoutes.plannedWorkoutPreview` (`/planned-workout-preview/:id`) + `AppPaths.plannedWorkoutPreview(id)`, and registered the matching `GoRoute` in `router.dart` using the exact `_intParam`/`_badParam` pattern `workoutHistory` uses — a malformed/non-numeric `:id` renders `AppErrorScreen`, never an unhandled throw (T-20-02).
- Added `plannedWorkoutPreviewProvider` (`FutureProvider.autoDispose.family<PlannedWorkoutPreviewData?, int>`) wrapping `ScheduledWorkoutService.workoutForSchedule`/`previewScheduledWorkout` end-to-end — a deleted/never-existed `scheduleId` resolves to `null`, never a throw (T-20-03).
- Built `PlannedWorkoutPreviewView`, moving the exercise-by-exercise rendering (numbered badge, `ExerciseArtwork`/fallback icon, name, `formatPlannedExerciseSets` summary) out of `day_detail_sheet.dart` verbatim, plus a `Start workout` CTA (via `PremiumButton`) visible only when status is `planned`/`moved`, mirroring `DayDetailSheet._start`'s exact error handling (`StateError` → `SnackBar`).
- Deleted `_WorkoutPlanPreviewSheet`, `formatPlannedExerciseSets`, `_sameSetRun`, `_formatSetRun` from `day_detail_sheet.dart` (verified zero remaining references via grep) and changed `_viewWorkout` to pop the sheet then `context.push(AppPaths.plannedWorkoutPreview(row.id))` for every row status — status-based branching to `WorkoutHistoryView` for done/in-progress rows is Plan 20-04's job.
- Proved via widget test that rendering `PlannedWorkoutPreviewView` alone never calls `startScheduledWorkoutById` (FLOW-02's core "view ≠ start" guarantee), that a `null`-resolving `scheduleId` renders an empty state without throwing, and that tapping Start calls `startScheduledWorkoutById` exactly once and switches to the Workouts tab.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the plannedWorkoutPreview route** - `ca45e5b` (feat)
2. **Task 2: Add plannedWorkoutPreviewProvider** - `f785cab` (feat)
3. **Task 3: Create PlannedWorkoutPreviewView and retire the inline sheet** - `765001a` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `lib/app/router/routes.dart` - `AppRoutes.plannedWorkoutPreview` + `AppPaths.plannedWorkoutPreview(id)`
- `lib/app/router/router.dart` - `GoRoute` registration for `plannedWorkoutPreview` using `_intParam`/`_badParam`
- `lib/features/workouts/application/workouts_providers.dart` - `PlannedWorkoutPreviewData` + `plannedWorkoutPreviewProvider`
- `lib/features/workouts/presentation/views/planned_workout_preview_view.dart` - New standalone `PlannedWorkoutPreviewView` (created)
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart` - `_viewWorkout` pushes the new route; `_WorkoutPlanPreviewSheet` and its formatting helpers removed
- `test/features/workouts/day_detail_sheet_preview_test.dart` - Import retargeted to the new view file (four `formatPlannedExerciseSets` unit tests otherwise unchanged)
- `test/widgets/day_detail_sheet_test.dart` - "View workout" test rewritten under `GoRouterTestHarness`, pumping `DayDetailSheet` via its real `.show()` modal entry point
- `test/widgets/planned_workout_preview_view_test.dart` - New widget tests covering render, empty state, and Start CTA (created)

## Decisions Made
- Used `Scaffold` + `AppBar` for `PlannedWorkoutPreviewView` rather than `HxScreenShell` (the pattern `WorkoutHistoryView` uses) because the plan's `<action>` text specified "an AppBar titled 'Planned workout'" literally; `HxScreenShell` remains available for a future consistency pass if desired.
- The "View workout" test needed a structural fix beyond what the plan's `<action>` spelled out verbatim: pumping `DayDetailSheet` directly as `GoRouterTestHarness`'s `home` (as the plan's action text literally suggested) crashed with "You have popped the last page off of the stack" because `_viewWorkout`'s `Navigator.of(context).pop()` expects an imperative modal route (from `HxSheet.show`) above GoRouter's declarative stack, not to be the sole route itself. Fixed by pumping a button that calls `DayDetailSheet.show(...)` (its real production entry point) as `home`, tapping it first to open the modal, then proceeding with the original tap sequence — this exercises the exact same code path the app uses.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed GoRouter "popped the last page" crash in the rewritten View workout test**
- **Found during:** Task 3, running the rewritten `day_detail_sheet_test.dart`
- **Issue:** Pumping `DayDetailSheet` directly as `GoRouterTestHarness`'s `home` (matching the plan's literal action text) made `_viewWorkout`'s `Navigator.of(context).pop()` empty GoRouter's only route, tripping `GoRouterDelegate`'s `currentConfiguration.isNotEmpty` assertion — a crash never seen in production because `DayDetailSheet` is always shown via `HxSheet.show`'s `showModalBottomSheet`, which pushes a separate imperative route for `pop()` to target.
- **Fix:** Changed the harness's `home` to a button invoking `DayDetailSheet.show(context, ...)` (the sheet's real entry point), and added a tap step to open it before the existing "View workout" tap — mirrors actual app usage exactly.
- **Files modified:** `test/widgets/day_detail_sheet_test.dart`
- **Commit:** `765001a`

## Issues Encountered

None beyond the auto-fixed test-harness issue above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Plan 20-04 (FLOW-03) can now branch `DayDetailSheet._viewWorkout` and/or the calendar surfaces by schedule status, routing done/in-progress rows to `WorkoutHistoryView` while planned/moved rows continue to `PlannedWorkoutPreviewView` — both routes and providers are in place.
- `PlannedWorkoutPreviewData.status` is exposed and ready for any additional status-based UI Plan 20-04 needs beyond the Start CTA gating already implemented here.
- No blockers.

---
*Phase: 20-active-workout-shell-calendar-execution-flow*
*Completed: 2026-09-16*
