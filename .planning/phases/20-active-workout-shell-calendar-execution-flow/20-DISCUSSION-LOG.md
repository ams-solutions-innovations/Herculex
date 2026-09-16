# Phase 20: Active Workout Shell & Calendar Execution Flow - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-16
**Phase:** 20-active-workout-shell-calendar-execution-flow
**Areas discussed:** KeyboardObstructionScope shape, Calendar → specific occurrence, Done → history routing (real gap), PlannedWorkoutPreviewView shape

---

## KeyboardObstructionScope shape

| Option | Description | Selected |
|--------|-------------|----------|
| Extract a real widget | Build a KeyboardObstructionScope InheritedWidget/wrapper owning focus-tracking + hide/IgnorePointer/ExcludeSemantics behavior | ✓ |
| Keep workoutInputFocusedProvider, just harden tests | Leave existing provider + duplicated offset code as-is, treat FLOW-01 as closing test gaps only | |

**User's choice:** Extract a real widget.

| Option | Description | Selected |
|--------|-------------|----------|
| Keep current visual behavior, refactor structure only | Same instant offscreen translation, same guarantees, just centralized | ✓ |
| Open up animation/offset tuning too | Let planning/implementation revisit offsets or add a transition animation | |

**User's choice:** Keep current visual behavior, refactor structure only.

| Option | Description | Selected |
|--------|-------------|----------|
| General-purpose ancestor widget | Reusable widget any descendant can opt into, not just the two known call sites | ✓ |
| Scoped to just the two known consumers | Narrower fix targeting only MainScaffold and ActiveWorkoutView | |

**User's choice:** General-purpose ancestor widget.

| Option | Description | Selected |
|--------|-------------|----------|
| design_system/components/ | Fits alongside HxSheet as shared shell chrome, no feature-specific logic | ✓ |
| core/utils/ or a new core/shell/ | Treat as app-shell infrastructure rather than a design-system primitive | |

**User's choice:** design_system/components/.

**Notes:** Extraction is structural only — no visual/animation redesign, keeps Phase 15's `active_workout_keyboard_test.dart` assertions valid.

---

## Calendar → specific occurrence

| Option | Description | Selected |
|--------|-------------|----------|
| Per-workout tap targets on the day cell | Each scheduled workout gets its own tap target opening DayDetailSheet.show(initialScheduleId:) | ✓ |
| Keep single day-tap, add initialScheduleId only for other callers | Month calendar keeps one tap target per day; multi-workout days still resolved by picking inside the sheet's list | |

**User's choice:** Per-workout tap targets (recommended direction).

**Notes:** Follow-up codebase check found the tiny grid-cell dots are decorative/whole-cell-tap only — the real per-session tap target already exists as `_SelectedDayList`'s `SessionTile` rows below the grid, which currently discard `row.id`.

| Option | Description | Selected |
|--------|-------------|----------|
| Wire through _SelectedDayList | Change SessionTile.onTap to pass row.id, thread to DayDetailSheet.show(initialScheduleId:) | ✓ |
| Also make the grid-cell dots individually tappable | Additionally redesign the tiny per-day dots to be tappable per-session | |

**User's choice:** Wire through _SelectedDayList.

| Option | Description | Selected |
|--------|-------------|----------|
| Still list all sessions, scroll/highlight tapped one | Keeps today's "N sessions" framing, initialScheduleId only affects visual emphasis | ✓ |
| Jump straight to just that session's detail | Skip the list entirely when a specific schedule is known | |

**User's choice:** Still list all sessions, scroll/highlight the tapped one.

---

## Done → history routing (real gap)

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, route to WorkoutHistoryView | Fixes the bug where done rows' "View workout" always shows the planned preview instead of what was actually logged | ✓ |
| Keep showing the planned preview for done rows too | No change | |

**User's choice:** Yes, route to WorkoutHistoryView.

| Option | Description | Selected |
|--------|-------------|----------|
| Close sheet then push route; in-progress View also shows live progress | Navigator.pop then push; in-progress rows also get real logged-so-far data instead of the stale plan | ✓ |
| Close sheet then push route; in-progress View keeps the planned preview | Same navigation handling, but in-progress stays on the planned preview | |

**User's choice:** Close sheet then push route; in-progress View also shows live progress.

**Notes:** Codebase check confirmed `completedSessionId` is set at start time (not completion) — `WorkoutHistoryView(sessionId: completedSessionId)` naturally covers both in-progress and done without new schema work.

---

## PlannedWorkoutPreviewView shape

| Option | Description | Selected |
|--------|-------------|----------|
| Full pushed route | context.push after closing DayDetailSheet, consistent with WorkoutHistoryView, real route/back-button/deep-link-ability | ✓ |
| Stay a modal sheet, just extracted to its own file | Keep current sheet-on-sheet UX, lower navigation-stack change | |

**User's choice:** Full pushed route.

| Option | Description | Selected |
|--------|-------------|----------|
| Take scheduleId, resolve via provider | Matches WorkoutHistoryView(sessionId:) pattern, survives deep-links | ✓ |
| Pass pre-fetched plan+exercises as route extra | Keep resolving data at call site, hand via go_router 'extra' | |

**User's choice:** Take scheduleId, resolve via provider.

| Option | Description | Selected |
|--------|-------------|----------|
| Add a Start CTA on the preview screen | Matches blueprint's "preview + Start" pairing as one flow | ✓ |
| Keep it purely read-only | Starting always goes back through DayDetailSheet's existing Start button | |

**User's choice:** Add a Start CTA on the preview screen.

---

## Claude's Discretion

- Exact prop/API name for KeyboardObstructionScope's focus signal, and whether `workoutInputFocusedProvider` is fully replaced or kept as the underlying state source.
- Whether `HxSheet` also gains the opt-in `centerHeader` param mentioned in the blueprint.
- `skipped` rows' "View workout" target (left on the planned preview — not named in the blueprint's 3-way status table).
- Whether `_SelectedDayList`'s `LongPressDraggable` drag-to-move needs adjustment now that `SessionTile.onTap` carries `row.id` (expected unaffected).
- Exact highlight/scroll treatment when opening `DayDetailSheet` with `initialScheduleId`.

## Deferred Ideas

None — discussion stayed within phase scope.
