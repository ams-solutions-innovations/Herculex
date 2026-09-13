---
phase: 15-program-generator-regression-fixes-interaction-hardening
plan: 02
subsystem: ui-interaction
tags: [ui, hx-sheet, keyboard-avoidance, focus, active-workout, substitution]

# Dependency graph
requires: []
provides:
  - "Canonical opaque HxSheet container on SmartSubstitutionSheet"
  - "workoutInputFocusedProvider synchronizing keyboard avoidance across MainScaffold and ActiveWorkoutView"
  - "Immediate negative-positioned hiding and pointer event disabling for active workout chrome upon focus"
affects: [15-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FocusNode-driven input focus synchronization with state provider for zero-latency UI chrome avoidance"

key-files:
  created:
    - test/widgets/exercise_replacement_sheet_test.dart
    - test/widgets/active_workout_keyboard_test.dart
  modified:
    - lib/features/workouts/presentation/sheets/smart_substitution_sheet.dart
    - lib/features/workouts/application/workouts_providers.dart
    - lib/features/workouts/presentation/widgets/active_exercise_card.dart
    - lib/features/workouts/presentation/views/active_workout_view.dart
    - lib/features/shell/main_scaffold.dart

key-decisions:
  - "SmartSubstitutionSheet migrated to canonical HxSheet with surfaceContainer to eliminate transparent modal bleed-through in light/dark themes."
  - "workoutInputFocusedProvider tracks focused set inputs to immediately drop navigation bar and workout action bar offscreen (-120 and -140) without waiting for platform viewInsets animation latency."
  - "Both chrome bars use ExcludeSemantics and IgnorePointer while hidden to protect against accidental user clicks or screen reader activation during typing."

requirements-completed: [FIX-02, FIX-03]

# Metrics
duration: ~15m
completed: 2026-09-13
---

# Phase 15 Plan 02: Opaque Replacement Sheets & Synchronized Active Workout Keyboard Obstruction Summary

Migrated exercise substitution sheets to canonical opaque `HxSheet` surfaces and unified input focus tracking to eliminate UI obstruction and accidental button hits while editing sets.

## Accomplishments
- Replaced hand-rolled `DraggableScrollableSheet` in `SmartSubstitutionSheet` with design system standard `HxSheet`, guaranteeing opaque `surfaceContainer` presentation in both light and dark themes.
- Added `workoutInputFocusedProvider` to `workouts_providers.dart`.
- Wired focus listeners on `_weightFocusNode` and `_repsFocusNode` in `ActiveExerciseCard`'s `_SetRowState` to update `workoutInputFocusedProvider`.
- Connected `ActiveWorkoutView` and `MainScaffold` to `workoutInputFocusedProvider`, instantly translating bottom navigation (-120) and floating actions (-140) offscreen and disabling hit-testing with `IgnorePointer(ignoring: true)`.
- Added unit and widget tests in `test/widgets/exercise_replacement_sheet_test.dart` and `test/widgets/active_workout_keyboard_test.dart`.
