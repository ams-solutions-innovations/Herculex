# Phase 20: Active Workout Shell & Calendar Execution Flow - Context

**Gathered:** 2026-09-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 20 finishes the ad-hoc UI fixes Phase 15 shipped by giving them the "dedicated models and regression tests" the blueprint's Faza 5 calls for: (1) `workoutInputFocusedProvider`'s duplicated hide/`IgnorePointer`/`ExcludeSemantics` logic in `MainScaffold` and `ActiveWorkoutView` gets extracted into one reusable `KeyboardObstructionScope` widget any screen can opt into; (2) the month calendar's already-existing per-session `SessionTile` list gets wired to pass a concrete `scheduleId` (not just a date) so `DayDetailSheet.show` can open to a specific occurrence when a day has multiple workouts; (3) a real gap in status routing gets closed — completed and in-progress rows' "View workout" currently always shows the *planned* preview instead of the actual logged session, even though `schedule.completedSessionId` already links to it; (4) the inline `_WorkoutPlanPreviewSheet` becomes a standalone `PlannedWorkoutPreviewView` route, resolving its own data from a `scheduleId`, with a `Start workout` CTA for planned/moved rows. It does not touch program generation (Phase 17), prescription/time-budget logic (Phase 18), or the program/wave editor (Phase 19).

</domain>

<decisions>
## Implementation Decisions

### KeyboardObstructionScope (FLOW-01)
- **D-01:** `KeyboardObstructionScope` is extracted as a real, general-purpose ancestor widget in `design_system/components/` — not just added test coverage around the existing `workoutInputFocusedProvider`. Any descendant screen can opt into hiding itself when a tracked input is focused, not only the two known-today consumers (`MainScaffold`'s nav bar, `ActiveWorkoutView`'s action bar).
- **D-02:** The extraction is structural only — it preserves the exact current visual behavior (instant offscreen translation at -120/-140, `IgnorePointer`/`ExcludeSemantics` while hidden). No animation or offset redesign is in scope. This keeps Phase 15's `test/widgets/active_workout_keyboard_test.dart` assertions valid with minimal changes.
- **D-03:** Lives in `design_system/components/` per CLAUDE.md's "`core/` and `design_system/` must never import `features/`" rule — the widget only needs a focus/bool signal, no workout-specific state, so it's a shell/chrome primitive like `HxSheet`, not feature code.

### Calendar → Specific Occurrence (FLOW-03)
- **D-04:** The month-grid day cell's tiny status dots stay decorative and the whole-cell tap keeps opening `DayDetailSheet.show(date:, programId:)` unchanged (still lists all of that day's sessions). The per-occurrence entry point is the **already-existing** `_SelectedDayList`'s `SessionTile` row below the grid (`month_calendar.dart`) — its `onTap` currently discards `row.id` and calls `onOpenSession(date)`. This gets changed to thread `row.id` through to `DayDetailSheet.show(initialScheduleId: row.id, date:, programId:)`.
- **D-05:** `DayDetailSheet` still renders its full list of that day's sessions when opened with `initialScheduleId` — it does not collapse to single-session-only rendering. `initialScheduleId` only determines which card is scrolled-to/visually highlighted on open. No behavior change for opens without an `initialScheduleId` (whole-day taps).
- No new tap-target design work is needed on the grid cell itself — the ambiguity the blueprint calls out is already solved by the existing per-session list; this phase only wires the missing `row.id` plumbing.

### Done/In-Progress → History Routing (FLOW-03)
- **D-06:** A `done` row's "View workout" routes to `PlannedWorkoutPreviewView`'s sibling — the existing `WorkoutHistoryView(sessionId: schedule.completedSessionId)` route — instead of the planned-preview resolver. This closes a real bug: today `_viewWorkout` always calls `previewScheduledWorkout` regardless of status, so a completed day's "View workout" shows the plan, not what was actually logged, even though `completedSessionId` already points at the real session.
- **D-07:** `completedSessionId` is set at *start* time, not completion (`ScheduledWorkoutService.isStarted` already treats `completedSessionId != null` as "started") — so the exact same `WorkoutHistoryView(sessionId: completedSessionId)` route naturally also serves the `in-progress` case with live/partial data, no separate code path needed. In-progress rows' "View workout" is switched to this route too rather than kept on the planned preview.
- **D-08:** Navigation for both cases closes `DayDetailSheet` first (`Navigator.pop`) then pushes the route — consistent with how `_start` already pops the sheet before switching tabs. No sheet-on-top-of-route stacking.
- `planned`/`moved` rows are unaffected — they keep routing to the (now-standalone) `PlannedWorkoutPreviewView`. `skipped` rows are Claude's discretion (see below).

### PlannedWorkoutPreviewView (FLOW-02)
- **D-09:** `PlannedWorkoutPreviewView` becomes a standalone pushed route (`context.push`), not a modal sheet nested inside `DayDetailSheet` — matching `WorkoutHistoryView`'s existing "View" pattern and giving it a real back-stack entry instead of today's sheet-on-sheet stacking. Needs a new route constant in `app/router/routes.dart` (`AppRoutes.plannedWorkoutPreview` / `AppPaths.plannedWorkoutPreview(scheduleId)`) per CLAUDE.md's "route paths are constants" rule.
- **D-10:** The view takes only `scheduleId` and resolves its own data via a new Riverpod provider wrapping `previewScheduledWorkout` + the exercise catalog lookup — matching how `WorkoutHistoryView(sessionId:)` already resolves its own data, rather than threading pre-fetched `plan`/`exercises` through router `extra`. Keeps the UI-never-touches-drift-directly rule intact and survives deep-link/back-stack restoration.
- **D-11:** The preview screen gets its own `Start workout` CTA for `planned`/`moved` rows (calling `startScheduledWorkoutById`, same idempotent path `DayDetailSheet._start` already uses) rather than staying purely read-only — pairs preview and start into one flow instead of bouncing the user back to `DayDetailSheet`. `PRES-02`'s read-only guarantee ("renders... without writing to the database") still holds: no write happens merely from viewing, only from tapping Start.

### Claude's Discretion
- Exact prop/API name for `KeyboardObstructionScope`'s focus signal (e.g. `KeyboardObstructionScope.of(context)` vs. an exposed `ValueNotifier`) and whether `workoutInputFocusedProvider` is fully replaced or kept as the underlying state source the new widget wraps.
- Whether `HxSheet` also gains the opt-in `centerHeader` param mentioned in the blueprint (Faza 5) for `DayDetailSheet`'s centered date/CTA — small, low-ambiguity, not separately discussed.
- `skipped` rows' "View workout" target — left showing the planned preview (`PlannedWorkoutPreviewView`) since the blueprint's 3-way status table (planned/moved, in-progress, done) doesn't name skipped explicitly, and a skipped session still has a plan worth reviewing, not a real logged session.
- Whether the `_SelectedDayList`'s `LongPressDraggable` drag-to-move interaction needs any adjustment now that its `SessionTile.onTap` carries `row.id` — expected to be unaffected since drag already uses `row.id` via `LongPressDraggable<int>(data: row.id, ...)`, but left for implementation to verify no regression.
- Exact highlight/scroll treatment for D-05 (e.g. a brief background pulse vs. just `Scrollable.ensureVisible`) — left to planning/UI as long as the tapped card is visually distinguishable on open.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone & Blueprint Specs
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` §"Faza 5 — dokončanje active workout in koledarskega toka" (lines ~403-426) — Architecture blueprint, origin of FLOW-01–03, including `KeyboardObstructionScope`, `DayDetailSheet.show(initialScheduleId:)`, `PlannedWorkoutPreviewView`, the status-routing table, and the opt-in `HxSheet.centerHeader`.
- `.planning/REQUIREMENTS.md` §6 (FLOW-01–03) — Authoritative requirements for Phase 20.
- `.planning/ROADMAP.md` (Phase 20) — Milestone phase goal and success criteria.
- `.planning/PROJECT.md` — "Single Source of Truth" guiding principle, relevant to D-06/D-07's insistence that "View workout" show the actual executed session rather than a stale plan once one exists.
- `CLAUDE.md` — "Route paths are constants" (D-09) and "The UI never touches drift directly" (D-10) rules, directly load-bearing.

### Prior Phase Context
- `.planning/phases/15-program-generator-regression-fixes-interaction-hardening/15-02-SUMMARY.md` — Phase 15's original `workoutInputFocusedProvider` implementation (FIX-02/FIX-03) that D-01–D-03 extract into `KeyboardObstructionScope`.
- `.planning/phases/15-program-generator-regression-fixes-interaction-hardening/15-03-SUMMARY.md` — Phase 15's `ScheduledWorkoutService.startScheduledWorkoutById` transaction and `DayDetailSheet._start` tab-navigation pattern (FIX-04) that D-08 and D-11 reuse.

### Keyboard Obstruction Domain
- `lib/features/workouts/application/workouts_providers.dart:562` — `workoutInputFocusedProvider` (`StateProvider<bool>`), the state source D-01's widget wraps or replaces.
- `lib/features/shell/main_scaffold.dart:204` — Nav bar consumer of `workoutInputFocusedProvider`, the -120 offset/`IgnorePointer` logic to centralize.
- `lib/features/workouts/presentation/views/active_workout_view.dart:133` — Action bar consumer, the -140 offset logic to centralize.
- `lib/features/workouts/presentation/widgets/active_exercise_card.dart:1611-1633` — `_weightFocusNode`/`_repsFocusNode` listeners that set the focus signal; unaffected by the extraction unless the underlying provider is fully replaced.
- `test/widgets/active_workout_keyboard_test.dart` — Existing regression coverage (Phase 15) that D-02's structural-only constraint must keep passing.
- `lib/design_system/components/hx_sheet.dart` — Existing shell-component precedent (pattern `KeyboardObstructionScope` should follow, being another `design_system/components/` shell primitive).

### Calendar & Schedule Domain
- `lib/features/programs/presentation/widgets/month_calendar.dart` — `_DayCell` (lines ~123-165, decorative dots + whole-cell tap, unchanged), `_SelectedDayList` (lines ~104-109, ~280-311, the `SessionTile.onTap` currently discarding `row.id` per D-04).
- `lib/features/programs/presentation/views/training_blocks_view.dart:76-83` — `_openDay`, the sole current caller of `DayDetailSheet.show`; needs the `initialScheduleId` param threaded through `onSelect`/`onOpenSession`.
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart:30-49` — `DayDetailSheet` constructor/`show` factory to extend with `initialScheduleId`; lines 410-453 (`_start`, `_viewWorkout`) are the exact methods D-06–D-08 change.
- `lib/features/programs/domain/scheduled_workout_row.dart` — `ScheduledWorkoutRow.id`, `.isDone`, `.isInProgress`, `.status`; note there is **no** `completedSessionId` getter here today — it must be read off `schedule.completedSessionId` (the underlying `ScheduledWorkoutData` drift row) or a getter added.
- `lib/features/workouts/data/scheduled_workout_service.dart:34,132,154,165,192` — `isStarted` (`completedSessionId != null`), `previewScheduledWorkout`, `startScheduledWorkoutById` — the exact service methods D-06/D-07/D-11 rely on.
- `lib/features/programs/domain/schedule_status.dart` — `ScheduleStatus` constants/`isOpen`; the authoritative status vocabulary (`planned`, `inProgress`, `done`, `moved`, `skipped`) the routing decisions (D-06, discretion note on `skipped`) map onto.
- `lib/data/local/tables.dart:1063` — `completedSessionId` column definition (`ScheduledWorkouts` table), confirming it's nullable and FK-linked to a `WorkoutSessions` row.

### Preview & History View Domain
- `lib/features/workouts/presentation/views/workout_history_view.dart` — `WorkoutHistoryView({required this.sessionId})`, the existing full-route pattern D-09/D-10's `PlannedWorkoutPreviewView` should mirror.
- `lib/app/router/router.dart:127` / `lib/app/router/routes.dart:28,96` — `AppRoutes.workoutHistory` / `AppPaths.workoutHistory(id)` registration pattern to replicate for the new `plannedWorkoutPreview` route.
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart:426-453` — Current inline `_viewWorkout` method and private `_WorkoutPlanPreviewSheet` class being extracted/converted per D-09.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HxSheet` (`design_system/components/hx_sheet.dart`): Existing shell-component pattern to follow for `KeyboardObstructionScope`'s placement and API style.
- `WorkoutHistoryView(sessionId:)` + its router registration: Direct template for `PlannedWorkoutPreviewView`'s route shape and data-resolution pattern (D-09/D-10).
- `ScheduledWorkoutService.startScheduledWorkoutById`/`previewScheduledWorkout`: Already-built, transaction-safe methods this phase reuses rather than rebuilding (D-06, D-07, D-11).
- `_SelectedDayList`'s `SessionTile` rows: Already the correct per-occurrence UI element for D-04 — this phase wires existing `row.id` data through, it doesn't build new per-session UI.

### Established Patterns
- Phase 15's "repository write → immediate UI transition" pattern (`_start` pops sheet + sets `mainTabIndexProvider`) — D-08 extends this same close-then-navigate pattern to the new history/preview routes.
- CLAUDE.md's "route paths are constants" and "UI never touches drift directly" conventions — directly shape D-09/D-10's route and provider design.

### Integration Points
- `completedSessionId` is the single existing link between `ScheduledWorkoutRow` and the real workout session — it already covers both in-progress (D-07) and done (D-06) without new schema/data work, since it's populated at start time, not completion.
- `_SelectedDayList`'s `onOpenSession: ValueChanged<DateTime>` callback signature (`month_calendar.dart`) needs widening to carry a schedule id — the exact shape (new callback param vs. a small record/tuple) is left to planning.

</code_context>

<specifics>
## Specific Ideas

- Blueprint's status-routing table: `planned`/`moved` → preview + Start; `in progress` → Resume existing workout; `done` → workout history detail. This phase additionally routes `in progress`'s "View workout" (a distinct secondary action from the primary Resume CTA) to the same history detail surface, since `completedSessionId` already resolves for in-progress rows too.
- `KeyboardObstructionScope` keeps the exact -120/-140 offscreen values and instant (non-animated) hide from Phase 15 — this is a structural extraction, not a visual redesign.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 20-active-workout-shell-calendar-execution-flow*
*Context gathered: 2026-09-16*
