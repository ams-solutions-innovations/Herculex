---
phase: 20-active-workout-shell-calendar-execution-flow
plan: 05
subsystem: ui
tags: [flutter, riverpod, calendar, day-detail-sheet, month-calendar, week-board]

# Dependency graph
requires:
  - phase: 20-active-workout-shell-calendar-execution-flow (20-04)
    provides: "day_detail_sheet.dart._viewWorkout status-gated routing baseline this plan builds highlighting on top of"
provides:
  - "OpenDayCallback typedef (month_calendar.dart) — void Function(DateTime date, {int? scheduleId})"
  - "DayDetailSheet(initialScheduleId:) — scrolls to and highlights the matching _SessionCard on open, without collapsing the day's full session list"
  - "First dedicated widget test for month_calendar.dart"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "OpenDayCallback: an optional named arg (scheduleId) riding alongside a required positional date, so whole-day taps and specific-session taps share one callback type without an ambiguous overload"
    - "One-shot post-frame scroll-to-highlight: a GlobalKey + bool _didScrollToInitial guard inside addPostFrameCallback, so Scrollable.ensureVisible fires exactly once per sheet open even though scheduleByDateProvider rebuilds the sheet repeatedly as a live stream"

key-files:
  created:
    - test/widgets/month_calendar_test.dart
  modified:
    - lib/features/programs/presentation/widgets/month_calendar.dart
    - lib/features/programs/presentation/views/training_blocks_view.dart
    - lib/features/programs/presentation/sheets/day_detail_sheet.dart

key-decisions:
  - "day_detail_sheet.dart was already over the 600-line structure-check limit before this plan touched it (648 lines, one of CLAUDE.md's acknowledged 51-strong pre-existing debt list). This plan's edits push it to 691 lines. The plan's acceptance criteria only calls for a part/part-of split when the file 'newly exceeds' the limit 'as a result of this plan's edits' — since it already exceeded before any edit here, that condition doesn't trigger, and splitting a pre-existing violation is out of scope for a bugfix plan. Left as-is; tracked by the existing structure-check debt list, not newly introduced by this plan."
  - "Test 1 (whole-day tap) in month_calendar_test.dart taps the day-of-month text inside the grid cell rather than the cell's Container/GestureDetector directly — simpler finder, exercises the same onTap through GestureDetector's hit-test region."
  - "Test 2 needed tester.ensureVisible before tapping the SessionTile because MonthCalendar's full content (grid + selected-day list) overflows the default 600px test viewport when pumped without a scrollable ancestor; wrapped both test pumps in SingleChildScrollView and used ensureVisible for the off-screen tile, matching how the real BlocksView already hosts MonthCalendar inside a ListView."

requirements-completed: [FLOW-03]

# Metrics
duration: 24min
completed: 2026-09-16
---

# Phase 20 Plan 05: Session-Specific Calendar Tap Routing Summary

**MonthCalendar and WeekBoard session taps now carry `row.id` through to `DayDetailSheet(initialScheduleId:)`, which scrolls to and highlights the exact tapped session instead of just opening the day.**

## Performance

- **Duration:** 24 min
- **Started:** 2026-09-16T17:30:00Z (approx, first file edit)
- **Completed:** 2026-09-16T17:54:00Z
- **Tasks:** 2 completed
- **Files modified:** 3 (1 created)

## Accomplishments
- Added `OpenDayCallback` typedef (`void Function(DateTime date, {int? scheduleId})`) to `month_calendar.dart`; `MonthCalendar.onSelect` and `_SelectedDayList.onOpenSession` both carry it now, and `_SelectedDayList`'s `SessionTile.onTap` passes `scheduleId: row.id` — the D-04 fix. The whole-cell `_DayCell.onTap` is unchanged (`onSelect(date)`, no `scheduleId`).
- Created `test/widgets/month_calendar_test.dart` — the first dedicated widget test for this file — covering both the whole-day-cell tap (no `scheduleId`) and the session-tile tap (`scheduleId == row.id`).
- Widened `training_blocks_view.dart`'s `_openDay` to accept `int? initialScheduleId` and forward it into `DayDetailSheet.show`. Wired both callers: `WeekBoard.onOpenSession: (row) => _openDay(..., initialScheduleId: row.id)` — the previously un-named second instance of the same bug RESEARCH.md's Pitfall 3 called out — and `MonthCalendar.onSelect: (date, {scheduleId}) => _openDay(..., initialScheduleId: scheduleId)`.
- Converted `DayDetailSheet` from `ConsumerWidget` to `ConsumerStatefulWidget` carrying `initialScheduleId`. The matching row's `_SessionCard` is wrapped in a `KeyedSubtree` and rendered `highlighted: true` (2px `AppColors.primary` border vs. the default 1px outline); a one-shot `addPostFrameCallback` calls `Scrollable.ensureVisible` on it exactly once per sheet open via a `_didScrollToInitial` guard. Every session for the day still renders regardless of `initialScheduleId` (D-05 — no collapsing).

## Task Commits

Each task was committed atomically:

1. **Task 1: Thread scheduleId through MonthCalendar's session-tap callback** - `6d60ac1` (feat)
2. **Task 2: Wire both callers (MonthCalendar + WeekBoard) and add initialScheduleId highlighting** - `9b219fa` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `lib/features/programs/presentation/widgets/month_calendar.dart` - `OpenDayCallback` typedef; `_SelectedDayList`'s `SessionTile.onTap` now passes `scheduleId: row.id`
- `test/widgets/month_calendar_test.dart` - New: covers day-cell (no scheduleId) and session-tile (scheduleId == row.id) tap paths
- `lib/features/programs/presentation/views/training_blocks_view.dart` - `_openDay` widened with `initialScheduleId`; both `WeekBoard.onOpenSession` and `MonthCalendar.onSelect` forward it
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart` - `DayDetailSheet` is now `ConsumerStatefulWidget` with `initialScheduleId`; `_SessionCard` gained a `highlighted` bool; one-shot scroll-to-highlight on open

## Decisions Made
- Left `day_detail_sheet.dart`'s pre-existing 600-line structure-check violation unaddressed — it was already over the limit (648 lines) before this plan, and the plan's split trigger is scoped to newly-caused violations, not pre-existing debt tracked elsewhere in CLAUDE.md.
- Wrapped both `month_calendar_test.dart` pumps in `SingleChildScrollView` and used `tester.ensureVisible` for the session-tile tap, since `MonthCalendar`'s full month grid + selected-day list overflows the default unscrolled test viewport (mirrors how the real `TrainingBlocksView` already hosts it inside a `ListView`).

## Deviations from Plan

None - plan executed as written; both adjustments documented above under Decisions Made were required by the plan's own conditional logic (structure-check threshold) and by making the new widget test's pump actually renderable, not unplanned scope changes.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- FLOW-03 is closed: both the month view's per-day session list and the week view's `WeekBoard`/`DayColumnCard` now open `DayDetailSheet` scrolled to and highlighting the exact tapped session; whole-day taps and the sheet's multi-session rendering are unchanged.
- `month_calendar.dart` has its first dedicated widget test, establishing a pattern (seeded `ScheduledWorkoutRow` via a real test database, `scheduleByDateProvider` stream override) future calendar-widget tests can reuse.
- No blockers.

---
*Phase: 20-active-workout-shell-calendar-execution-flow*
*Completed: 2026-09-16*

## Self-Check: PASSED

All created/modified files and referenced commits (6d60ac1, 9b219fa) verified present.
