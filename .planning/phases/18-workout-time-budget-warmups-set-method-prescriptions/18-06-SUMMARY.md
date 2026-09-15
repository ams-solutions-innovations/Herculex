---
phase: 18-workout-time-budget-warmups-set-method-prescriptions
plan: 06
subsystem: ui
tags: [flutter, calendar-preview, prescription-formatting, warmup-resolver]

# Dependency graph
requires:
  - phase: 18-workout-time-budget-warmups-set-method-prescriptions
    provides: "18-04: resolveProgramDay reads through SlotPrescriptionCodec/WarmupResolver, giving previewScheduledWorkout and startScheduledWorkoutById structurally identical PlannedSessionSnapshot output"
provides:
  - "formatPlannedExerciseSets: groups a PlannedExerciseSnapshot's sets into consecutive identical-prescription runs and renders each as a WorkSegment.format()-style string (reps, %1RM/RIR, set-type label, warmup prefix, rest)"
  - "Calendar 'View workout' preview (_WorkoutPlanPreviewSheet) now renders full set-by-set detail instead of a compact count summary"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@visibleForTesting top-level formatting function in the same file as a private StatelessWidget, so pure-formatting logic stays testable without exposing the widget itself"

key-files:
  created:
    - test/features/workouts/day_detail_sheet_preview_test.dart
  modified:
    - lib/features/programs/presentation/sheets/day_detail_sheet.dart

key-decisions:
  - "Extracted the grouping/formatting logic to a public top-level `formatPlannedExerciseSets` function (marked @visibleForTesting) instead of keeping it as a private method on `_WorkoutPlanPreviewSheet`, since Dart's underscore privacy is per-file and the plan's stated test file lives outside this library file and needs direct unit-test access to the formatting behavior."
  - "Imported `slot_prescription.dart` under a `slot_prescription` prefix because its `Intent` enum collides with `flutter/material.dart`'s own `Intent` (keyboard shortcuts) — an unavoidable disambiguation, not a deviation from the plan's intended behavior."

patterns-established: []

requirements-completed: [PRES-01]

# Metrics
duration: ~20min
completed: 2026-09-15
---

# Phase 18 Plan 06: Calendar Preview Set-by-Set Detail Summary

**Calendar's "View workout" preview now renders sets×reps @%1RM/RIR, rest, and warmup/set-type labels per exercise via a new `formatPlannedExerciseSets` function, replacing the old "3 × 8-12 reps · 2 warm-up sets" one-line summary.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-09-15T19:15:00Z
- **Completed:** 2026-09-15T19:37:07Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- Replaced `_WorkoutPlanPreviewSheet._setSummary` with `formatPlannedExerciseSets`, which groups `exercise.sets` into consecutive runs sharing identical `(repsMin, repsMax, setType, intent, percentOf1Rm, isWarmup)` and formats each run in the same `"{count}x{reps} @{%1RM or RIR} {SetType label}"` convention as `WorkSegment.format()`, joining runs with `" + "` and appending `" · Rest {restSeconds}s"`.
- Warmup runs are prefixed `"Warmup: "`; set types other than `standard` render their human label (e.g. "Myo Reps") via `SetType.fromId(...).label` instead of the raw persisted id (`myo_reps`).
- Since this preview already resolves through `previewScheduledWorkout` -> `PlannedSessionResolver.resolveProgramDay` (18-04's rewritten, codec/warmup-backed resolver), the richer rendering is driven by the exact same data the real workout session uses — no separate re-implementation, so preview/session parity (D-02) stays structural.

## Task Commits

Each task was committed atomically:

1. **Task 1: Render per-segment set detail in the calendar preview sheet** - `a0fda03` (feat)

**Plan metadata:** (this commit, docs)

## Files Created/Modified
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart` - Replaced `_setSummary` with public `formatPlannedExerciseSets` (+ private `_sameSetRun`/`_formatSetRun` helpers); added `slot_prescription` (aliased) and `set_type` imports
- `test/features/workouts/day_detail_sheet_preview_test.dart` - New: 4 tests covering warmup/working-set grouping with %1RM, set-type label rendering, RIR fallback when no %1RM is prescribed, and the empty-sets placeholder

## Decisions Made
- Made the formatting function public (`@visibleForTesting`) and top-level rather than a private instance method, purely so `test/features/workouts/day_detail_sheet_preview_test.dart` (a separate library file) can unit-test the formatting behavior directly without needing to pump the full private widget through a `WidgetTester`.
- Aliased the `slot_prescription.dart` import (`as slot_prescription`) to resolve a naming collision between its `Intent` enum and `package:flutter/material.dart`'s `Intent` class (used for keyboard-shortcut intents) — mechanical fix, no behavior change.

## Deviations from Plan

None - plan executed as written. The only adjustments (extracting a public formatting function instead of a private method, and the import alias) were mechanical necessities to satisfy the plan's own acceptance criteria (a directly unit-testable function) and to compile at all (the `Intent` name collision), not scope changes.

## Issues Encountered
- Initial compile failed because `slot_prescription.dart`'s `Intent` enum collides with Flutter's own `Intent` class, both unprefixed-imported. Resolved with an import prefix on `slot_prescription.dart` (see Decisions Made).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- This is the final plan in Phase 18. `flutter analyze` reports 0 issues on both modified/created files; `flutter test test/features/workouts/day_detail_sheet_preview_test.dart` (4/4) and the existing `test/widgets/day_detail_sheet_test.dart` (3/3, unaffected by this change) both pass.
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart` was already over the project's 600-line hand-written-file limit before this plan (783 lines pre-change, now 827) — a pre-existing violation already tracked by `tool/check_structure.dart`'s 59-file list, not introduced by this plan. Splitting it is out of this plan's scope; noted here for whoever picks up the file-size cleanup backlog.
- No blockers.

---
*Phase: 18-workout-time-budget-warmups-set-method-prescriptions*
*Completed: 2026-09-15*
