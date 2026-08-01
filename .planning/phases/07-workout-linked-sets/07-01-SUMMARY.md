---
phase: "07"
plan: "07-01"
subsystem: workouts
tags:
  - workout-ui
  - supersets
  - reorder
key-files:
  - lib/features/workouts/data/workouts_repository.dart
  - lib/features/workouts/presentation/active_workout_view.dart
  - lib/features/workouts/presentation/active_exercise_card.dart
  - lib/features/workouts/presentation/set_type_menu.dart
  - test/schema_v10_test.dart
metrics:
  tests: passed
---

## Summary

Implemented linked exercise groups for supersets and giant sets in the active workout UI.

## Changes

- Added repository methods to reorder workout exercises, link exercises into a shared `supersetGroup`, and unlink a single exercise.
- Converted the active workout list to `ReorderableListView` with a bottom-right delayed drag handle.
- Added visual rails, numbered nodes, and `SUPER SET` / `GIANT SET` labels for linked exercise groups.
- Added exercise menu actions to connect exercises or remove one from a linked group.
- Changed completion behavior so linked sets advance focus to the next exercise before starting rest after the final linked exercise.
- Hid `Giant Set` from the per-set type picker because linked sets now live at the exercise level.
- Added a repository regression test for linking, giant-set grouping, reorder, and unlink.

## Verification

- `flutter analyze` on the 4 changed Dart files: passed.
- `flutter test test/schema_v10_test.dart`: passed.
- `flutter test test/schema_v10_test.dart test/phase3_engines_test.dart`: passed before adding the repository regression; `schema_v10_test.dart` was re-run after.
- Full `flutter analyze`: still reports pre-existing project lint warnings outside this change.

## Self-Check

PASSED
