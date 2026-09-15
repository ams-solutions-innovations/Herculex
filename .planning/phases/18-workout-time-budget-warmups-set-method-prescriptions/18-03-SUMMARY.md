---
phase: 18-workout-time-budget-warmups-set-method-prescriptions
plan: 03
subsystem: presentation
tags: [flutter, riverpod, set-type-menu, gating]

# Dependency graph
requires: [18-01]
provides:
  - "isAdvancedTechniqueAllowed(SlotRole, bool) — single gate predicate for advanced set techniques"
  - "SetTypeMenu(allowAdvancedTechniques: bool) — hard-filters hypertrophy items and the amrap timed-item"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hard-hide via list-construction-time filtering (instance getters that read a required constructor field), not a disabled/greyed tile state"

key-files:
  created:
    - test/features/workouts/set_type_menu_gating_test.dart
  modified:
    - lib/features/workouts/presentation/widgets/set_type_menu.dart
    - lib/features/workouts/presentation/widgets/active_exercise_card.dart
    - lib/features/workouts/presentation/views/template_builder_view.dart

key-decisions:
  - "template_builder_view.dart's SetTypeMenu.show call site (manual workout templates, no SlotRole/program-opt-in context) passes allowAdvancedTechniques: true to preserve its pre-existing unrestricted behavior — the D-11/D-12 gate is scoped to generator-materialized workout exercises only, matching the plan's stated files_modified list."

patterns-established:
  - "isAdvancedTechniqueAllowed is the single source of truth for the != SlotRole.main check — future callers must use it rather than duplicating the check."

requirements-completed: [PRES-04]

# Metrics
duration: ~30min
completed: 2026-09-15
---

# Phase 18 Plan 03: Advanced Set-Type Menu Gating Summary

**Hard-hides drop/rest-pause/myo-reps/AMRAP from the live-workout set-type menu for SlotRole.main lifts unconditionally, and for every other role unless the program's allowTimeSavingSetTechniques opt-in (snapshotted per-exercise as plannedAllowsAdvancedTechniques) is set.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-09-15
- **Completed:** 2026-09-15
- **Tasks:** 2
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments
- `isAdvancedTechniqueAllowed(SlotRole role, bool programAllows)` added to `set_type_menu.dart`: returns `false` unconditionally for `SlotRole.main` (D-12), and for every other role only when `programAllows` is `true` (D-11).
- `SetTypeMenu` now requires `allowAdvancedTechniques`; `_hypertrophyItems` and `_timedItems` converted from `static final` lists to instance getters that filter `SetTypeInfo.all` at construction time — a gated technique is never inserted into the rendered `ListView` (D-13: hard hide, no disabled-but-visible state). Only the `amrap` entry within the `timed` category is gated; `emom` and `forTime` remain unaffected.
- `active_exercise_card.dart`'s `SetTypeMenu.show(...)` call site derives the gate from `workoutExercise.plannedSlotRole` (via `SlotRole.fromId`) and `workoutExercise.plannedAllowsAdvancedTechniques` (schema v43, from 18-01).

## Task Commits

Each task was committed atomically (TDD: RED then GREEN):

1. **RED — failing test for predicate + widget filtering** - `e05cd1a` (test)
2. **GREEN — predicate, SetTypeMenu filtering, and both call sites wired** - `59978d9` (feat)

## Files Created/Modified
- `test/features/workouts/set_type_menu_gating_test.dart` - 6 tests: 4 unit tests for `isAdvancedTechniqueAllowed` covering all 4 role/opt-in combinations for main vs. non-main, 2 widget tests asserting hypertrophy items + amrap are absent/present by `allowAdvancedTechniques`, and that `emom`/`forTime` are unaffected either way.
- `lib/features/workouts/presentation/widgets/set_type_menu.dart` - Adds `isAdvancedTechniqueAllowed`, `required this.allowAdvancedTechniques` on `SetTypeMenu` and `SetTypeMenu.show(...)`, converts `_hypertrophyItems`/`_timedItems` to filtered instance getters.
- `lib/features/workouts/presentation/widgets/active_exercise_card.dart` - Imports `slot_role.dart`; `onTypeTap` now computes `role`/`allowed` from `widget.workoutExercise` and passes `allowAdvancedTechniques: allowed` to `SetTypeMenu.show(...)`.
- `lib/features/workouts/presentation/views/template_builder_view.dart` - Its unrelated `SetTypeMenu.show(...)` call site (manual workout templates) now passes `allowAdvancedTechniques: true` to keep compiling and preserve prior behavior (see Deviations).

## Decisions Made
- Kept the gate predicate as a single top-level function in `set_type_menu.dart` rather than duplicating the `!= SlotRole.main` check at each call site, per the plan's explicit instruction.
- `template_builder_view.dart`'s call site is out of the plan's stated `files_modified`, but the `allowAdvancedTechniques` parameter is `required`, so this file could not compile without a fix (see Deviations).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `template_builder_view.dart` had an unlisted `SetTypeMenu.show(...)` call site that stopped compiling**
- **Found during:** Task 2, after adding `required this.allowAdvancedTechniques`
- **Issue:** `lib/features/workouts/presentation/views/template_builder_view.dart` (manual workout-template builder, not in the plan's `files_modified`) calls `SetTypeMenu.show(...)` without the new required parameter, so the whole app failed to compile once the parameter became required.
- **Fix:** Added `allowAdvancedTechniques: true` at that call site, with a comment explaining that manual templates have no `SlotRole`/program-opt-in context and the D-11/D-12 gate is scoped to generator-materialized workout exercises only (the surface this plan targets per its objective and truths).
- **Files modified:** `lib/features/workouts/presentation/views/template_builder_view.dart`
- **Verification:** `flutter analyze` (0 errors in touched files), `flutter test` (1304 passed, 9 skipped, full suite)
- **Committed in:** `59978d9` (Task 2 / GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to keep the app compiling after making the new parameter required; no behavior change to the plan's targeted surface (live-workout `active_exercise_card.dart`) — the template builder retains its prior unrestricted menu, which is outside this plan's scope (see `key-decisions`).

## Issues Encountered
- The widget tests initially failed to find `AMRAP`/hypertrophy items in the default 800×600 test viewport because `SetTypeMenu`'s `ListView` lazily builds only on-screen slivers — items further down the list (the `timed` category, third of three) were never mounted regardless of the filtering logic. Fixed by enlarging the test viewport (`tester.view.physicalSize = Size(800, 3200)`) rather than scrolling, since the test asserts on the full rendered set including items far down the list.

## User Setup Required
None.

## Next Phase Readiness
- `SetTypeMenu`'s `allowAdvancedTechniques` and `isAdvancedTechniqueAllowed` are the stable public surface for any future caller that needs to gate advanced set techniques by role/opt-in.
- Full suite green (1304 passed, 9 skipped) and `flutter analyze` reports 0 errors in all touched files.

---
*Phase: 18-workout-time-budget-warmups-set-method-prescriptions*
*Completed: 2026-09-15*

## Self-Check: PASSED
