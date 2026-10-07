---
phase: 20-active-workout-shell-calendar-execution-flow
verified: 2026-09-16T20:30:00Z
status: passed
score: 9/9 must-haves verified
overrides_applied: 0
---

# Phase 20: Active Workout Shell & Calendar Execution Flow Verification Report

**Phase Goal:** Solidify interaction contracts between active workout execution, shell controls, and calendar navigation.
**Verified:** 2026-09-16T20:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `KeyboardObstructionScope` is a single shared widget driving both `MainScaffold`'s nav bar and `ActiveWorkoutView`'s action bar hide/ignore/exclude-semantics, replacing two hand-rolled copies | ✓ VERIFIED | `lib/design_system/components/keyboard_obstruction_scope.dart` implements `AnimatedPositioned → ExcludeSemantics → IgnorePointer → AnimatedOpacity`; `main_scaffold.dart:284` and `active_workout_view.dart:374` both construct `KeyboardObstructionScope(...)`. `flutter test test/widgets/active_workout_keyboard_test.dart` passes unchanged (2 tests). |
| 2 | Exact pre-existing offsets/timings (-120/-140, instant-hide/150ms-restore, 200ms easeOutCubic) preserved after extraction | ✓ VERIFIED | Source reads `duration: hidden ? Duration.zero : const Duration(milliseconds: 150)`, `AnimatedPositioned(duration: 200ms, curve: Curves.easeOutCubic, ...)`; callers pass `hiddenOffset: 120` / `hiddenOffset: 140` respectively. Regression test unchanged and green. |
| 3 | Viewing a planned/moved scheduled workout renders full exercise-by-exercise detail without creating a `WorkoutSessions` row | ✓ VERIFIED | `PlannedWorkoutPreviewView` (`lib/features/workouts/presentation/views/planned_workout_preview_view.dart`) renders via `plannedWorkoutPreviewProvider`, a read-only `FutureProvider`. `planned_workout_preview_view_test.dart` test "renders every exercise name and set summary; creates no session from rendering alone" passes. |
| 4 | A malformed/stale `scheduleId` renders an empty/error state instead of throwing | ✓ VERIFIED | `router.dart` uses `_intParam`/`_badParam` pattern for `plannedWorkoutPreview` route; provider returns `null` on missing row, rendered as "no longer exists" state, not an exception. |
| 5 | Tapping Start workout on the preview starts/resumes the session and switches to Workouts tab | ✓ VERIFIED | `planned_workout_preview_view.dart` contains `'Start workout'` CTA gated on `data.plan.exercises.isNotEmpty && status in {planned, moved}` (post-review fix, commit 39e3731, matching `DayDetailSheet`'s original gating). `day_detail_sheet_test.dart` "Tapping Start workout calls startScheduledWorkoutById and switches to Workouts tab" passes. |
| 6 | Calendar routing distinguishes preview/start, resume, and history detail by status | ✓ VERIFIED | `day_detail_sheet.dart._viewWorkout` (lines 471-490): `isDone`/`isInProgress` → `AppPaths.workoutHistory(completedSessionId)`; all other statuses → `AppPaths.plannedWorkoutPreview(row.id)`; null `completedSessionId` on a done/in-progress row shows "no longer exists" snackbar instead of navigating. All 3 branches covered by passing tests in `day_detail_sheet_test.dart`. |
| 7 | Tapping a specific session in month view's per-day list opens `DayDetailSheet` scrolled/highlighted to that exact occurrence | ✓ VERIFIED | `month_calendar.dart`: `OpenDayCallback` typedef, `SessionTile.onTap => onOpenSession(date, scheduleId: row.id)`. `day_detail_sheet.dart` accepts `initialScheduleId`, uses `GlobalKey` + `Scrollable.ensureVisible` one-shot post-frame callback, and `_SessionCard(highlighted: true)` renders a distinct border. `month_calendar_test.dart` (3 tests) + `day_detail_sheet_test.dart` pass. |
| 8 | Same fix applies to week view (`WeekBoard`/`DayColumnCard`) | ✓ VERIFIED | `training_blocks_view.dart`: `onOpenSession: (row) => _openDay(..., initialScheduleId: row.id)`, confirmed via grep at line 60. |
| 9 | Whole-day taps unaffected — still list every session, no highlight | ✓ VERIFIED | `_DayCell.onTap` still calls `onSelect(date)` with no `scheduleId` arg; `month_calendar_test.dart` "Tapping the month grid day cell invokes onSelect(date) with no scheduleId" passes; `DayDetailSheet` renders every row regardless of `initialScheduleId`. |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/design_system/components/keyboard_obstruction_scope.dart` | `KeyboardObstructionScope` widget | ✓ VERIFIED | Exists, exports the class, exact tree/timings, no `features/` import. |
| `test/support/go_router_test_harness.dart` + `_test.dart` | Reusable GoRouter test harness | ✓ VERIFIED | Exists; self-test passes; zero `AppRoutes.` references. |
| `lib/app/router/routes.dart` | `AppRoutes.plannedWorkoutPreview` / `AppPaths.plannedWorkoutPreview(id)` | ✓ VERIFIED | Both constants present (lines 29, 98). |
| `lib/features/workouts/application/workouts_providers.dart` (+ part file) | `plannedWorkoutPreviewProvider` | ✓ VERIFIED | Split into `workouts_providers.dart` (567 lines) + `workouts_providers/_planned_workout_preview.part.dart` (37 lines) — both under 600-line cap, post-review-fix commit 39e3731. |
| `lib/features/workouts/presentation/views/planned_workout_preview_view.dart` | `PlannedWorkoutPreviewView` | ✓ VERIFIED | Exists, renders exercises, gated Start CTA. |
| `lib/features/programs/domain/scheduled_workout_row.dart` | `completedSessionId` getter | ✓ VERIFIED | `int? get completedSessionId => schedule.completedSessionId;` at line 40. |
| `lib/features/programs/presentation/sheets/day_detail_sheet.dart` | Status-gated `_viewWorkout` + `initialScheduleId` highlight | ✓ VERIFIED | Both present; file is 691 lines, over the 600-line structure-check cap — documented pre-existing debt (was 648 before this phase), explicitly scoped out of this plan's split trigger per 20-05-SUMMARY.md and consistent with CLAUDE.md's acknowledged 51-file debt list. |
| `test/widgets/month_calendar_test.dart` | First dedicated widget test for month_calendar.dart | ✓ VERIFIED | Exists, 3 tests, all pass. |

### Key Link Verification

| From | To | Via | Status |
|------|-----|-----|--------|
| `main_scaffold.dart` | `keyboard_obstruction_scope.dart` | `KeyboardObstructionScope(hidden: hideWorkoutChrome, hiddenOffset: 120, ...)` | ✓ WIRED |
| `active_workout_view.dart` | `keyboard_obstruction_scope.dart` | `KeyboardObstructionScope(hidden: keyboardOpen, hiddenOffset: 140, ...)` | ✓ WIRED |
| `router.dart` | `planned_workout_preview_view.dart` | `GoRoute(path: AppRoutes.plannedWorkoutPreview, builder: ... PlannedWorkoutPreviewView(scheduleId: id))` | ✓ WIRED |
| `planned_workout_preview_view.dart` | `workouts_providers.dart` | `ref.watch(plannedWorkoutPreviewProvider(scheduleId))` | ✓ WIRED |
| `day_detail_sheet.dart` | `routes.dart` | `context.push(AppPaths.workoutHistory(completedSessionId))` / `context.push(AppPaths.plannedWorkoutPreview(row.id))` | ✓ WIRED |
| `month_calendar.dart` | `training_blocks_view.dart` | `onOpenSession(date, scheduleId: row.id)` | ✓ WIRED |
| `training_blocks_view.dart` (WeekBoard) | `day_detail_sheet.dart` | `initialScheduleId: row.id` forwarded to `DayDetailSheet.show` | ✓ WIRED |

### Behavioral Spot-Checks / Test Execution

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase-20-specific test files | `flutter test test/widgets/active_workout_keyboard_test.dart test/support/go_router_test_harness_test.dart test/widgets/planned_workout_preview_view_test.dart test/widgets/day_detail_sheet_test.dart test/features/workouts/day_detail_sheet_preview_test.dart test/widgets/month_calendar_test.dart` | 18/18 passed | ✓ PASS |
| Full suite | `flutter test` | 1347 passed / 9 skipped, 0 failures | ✓ PASS |
| Static analysis | `flutter analyze` | 0 errors, 42 warnings/info (pre-existing, none introduced by this phase's files) | ✓ PASS |
| Layout rules | `dart run tool/check_structure.dart` | 58 pre-existing violations (including `day_detail_sheet.dart` at 691 lines, up from 648 pre-phase — documented, out of this plan's split-trigger scope) | ✓ ACCEPTABLE (documented debt) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| FLOW-01 | 20-02 | `KeyboardObstructionScope` manages keyboard visibility, animations, hit-testing across shell and active workout screens | ✓ SATISFIED | Truths 1-2 above. |
| FLOW-02 | 20-01, 20-03 | `PlannedWorkoutPreviewView` renders full workout preview without writing to DB | ✓ SATISFIED | Truths 3-5 above. |
| FLOW-03 | 20-01, 20-04, 20-05 | Calendar entries route to Preview & Start, Resume, or History detail based on status | ✓ SATISFIED | Truths 6-9 above. |

No orphaned requirements found — REQUIREMENTS.md lists only FLOW-01–03 for Phase 20, all claimed and satisfied. (Note: REQUIREMENTS.md's own checkboxes/status column still show `[ ]`/"Pending" — this is a tracking-doc staleness issue, not a code gap; recommend updating REQUIREMENTS.md separately.)

### Anti-Patterns Found

None. Grep for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER|not yet implemented|coming soon` across all phase-20-modified files returned zero matches.

### Human Verification Required

None. All must-haves are verifiable via source inspection and automated tests; no visual/UX-only behaviors were left unverified.

### Gaps Summary

None. All 9 derived truths verified, all artifacts exist/are substantive/are wired, all key links confirmed, full test suite (1347/9 skip) and `flutter analyze` (0 errors) pass. The one code-review follow-up fix (commit 39e3731 — Start CTA gating + workouts_providers.dart split) is present and correctly wired.

---

_Verified: 2026-09-16T20:30:00Z_
_Verifier: Claude (gsd-verifier)_
