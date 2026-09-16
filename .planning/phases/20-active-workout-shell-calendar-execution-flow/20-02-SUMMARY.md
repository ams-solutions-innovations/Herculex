---
phase: 20-active-workout-shell-calendar-execution-flow
plan: 02
subsystem: ui
tags: [flutter, design_system, riverpod, refactor]

# Dependency graph
requires: []
provides:
  - "KeyboardObstructionScope reusable design_system/components/ primitive for hiding bottom-anchored chrome when the keyboard/a focused input obstructs it"
  - "MainScaffold nav bar and ActiveWorkoutView floating action bar both rendered through the shared primitive instead of duplicated widget trees"
affects: [active-workout-shell, design-system]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "design_system/components/ shell primitives take only bool/double/Widget params, no Riverpod, no features/ imports — caller passes in derived state (see hx_sheet.dart precedent)"

key-files:
  created: [lib/design_system/components/keyboard_obstruction_scope.dart]
  modified:
    - lib/features/shell/main_scaffold.dart
    - lib/features/workouts/presentation/views/active_workout_view.dart

key-decisions:
  - "KeyboardObstructionScope only wraps rendering, not state — workoutInputFocusedProvider and the local keyboardOpen/_keyboardOpen(context) computation stay exactly where they were, each consumer still derives its own hidden bool"
  - "Task 1 verification followed the plan literally (flutter analyze only, no standalone widget test for KeyboardObstructionScope in isolation) — the extraction's correctness is proven by the unmodified Phase 15 regression test in Task 2, which asserts the exact offsets/ignoring/opacity produced through both real call sites"

requirements-completed: [FLOW-01]

# Metrics
duration: 12min
completed: 2026-09-16
---

# Phase 20 Plan 02: Extract KeyboardObstructionScope Summary

**Extracted the duplicated keyboard/focus-driven chrome-hiding AnimatedPositioned/ExcludeSemantics/IgnorePointer/AnimatedOpacity stack from MainScaffold and ActiveWorkoutView into one `design_system/components/KeyboardObstructionScope` primitive, rewiring both consumers to it with zero behavior change.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-09-16T14:19:00Z
- **Completed:** 2026-09-16T14:31:24Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- `KeyboardObstructionScope` widget in `lib/design_system/components/keyboard_obstruction_scope.dart`: `StatelessWidget` with `hidden`, `hiddenOffset`, `child` params, importing only `package:flutter/material.dart`
- `MainScaffold`'s nav bar now renders via `KeyboardObstructionScope(hidden: hideWorkoutChrome, hiddenOffset: 120, ...)`
- `ActiveWorkoutView`'s floating action bar now renders via `KeyboardObstructionScope(hidden: keyboardOpen, hiddenOffset: 140, ...)`
- Phase 15 regression test (`test/widgets/active_workout_keyboard_test.dart`) passes unchanged — proves offsets (-120/-140), instant-hide/150ms-restore opacity, and 200ms easeOutCubic slide are preserved exactly

## Task Commits

Each task was committed atomically:

1. **Task 1: Create KeyboardObstructionScope** - `48a9486` (feat)
2. **Task 2: Wire both consumers to KeyboardObstructionScope** - `c6ce8ff` (refactor)

## Files Created/Modified
- `lib/design_system/components/keyboard_obstruction_scope.dart` - New shared primitive reproducing the exact AnimatedPositioned/ExcludeSemantics/IgnorePointer/AnimatedOpacity tree
- `lib/features/shell/main_scaffold.dart` - Nav bar chrome now built through `KeyboardObstructionScope`; `hideWorkoutChrome` computation from `workoutInputFocusedProvider` unchanged
- `lib/features/workouts/presentation/views/active_workout_view.dart` - Floating action bar now built through `KeyboardObstructionScope`; `keyboardOpen` computation (`_keyboardOpen(context) || inputFocused`) unchanged

## Decisions Made
- Kept `workoutInputFocusedProvider` and `_keyboardOpen`/`keyboardOpen` as the underlying state sources exactly as before per D-03 — `KeyboardObstructionScope` wraps only the rendering.
- Did not touch `_weightFocusNode`/`_repsFocusNode` listeners in `active_exercise_card.dart` — out of scope for this extraction, per plan instruction.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `KeyboardObstructionScope` is available in `design_system/components/` for any future bottom-anchored control needing keyboard-clearance behavior.
- No blockers for subsequent plans in Phase 20.

---
*Phase: 20-active-workout-shell-calendar-execution-flow*
*Completed: 2026-09-16*

## Self-Check: PASSED

- FOUND: lib/design_system/components/keyboard_obstruction_scope.dart
- FOUND: commit 48a9486
- FOUND: commit c6ce8ff
