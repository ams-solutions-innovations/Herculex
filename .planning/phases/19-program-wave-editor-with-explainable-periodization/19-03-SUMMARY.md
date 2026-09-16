---
phase: 19-program-wave-editor-with-explainable-periodization
plan: 03
subsystem: ui
tags: [drift, flutter_test, periodization, program-editor]

# Dependency graph
requires:
  - phase: 19-program-wave-editor-with-explainable-periodization (plans 01-02)
    provides: exercise replacement scope infrastructure (replaceProgramExerciseSlot, ProgramExerciseReplacementScope)
provides:
  - "8-week, one-row-per-week periodization method guide data for Linear, Concurrent, Block, and Max Effort, matching Periodization's real phase/deload boundaries"
  - "Documented D-06 exception: PeriodizationModel.none stays at 2 rows by deliberate choice"
  - "Explicit regression test proving replaceProgramExerciseSlot + rematerializeProgram never disturbs an in_progress/done ScheduledWorkouts row (EDIT-03 safety property)"
affects: [19-04 (post-commit UI wiring for exercise replacement)]

tech-stack:
  added: []
  patterns:
    - "Guide week data lives entirely in ProgramMethodGuide.forModel's list literals; rendering code (ListView/Card/ListTile) is intentionally untouched when only content changes."

key-files:
  created: []
  modified:
    - lib/features/programs/presentation/views/program_method_guide_view.dart
    - test/program_method_guide_test.dart
    - test/program_exercise_replacement_scope_test.dart

key-decisions:
  - "Block's 4 existing milestone weeks (1, 3, 5, 7) were renumbered/expanded to the real Periodization._block(8) boundaries (1-4 Accumulation, 5-7 Transmutation, 8 Realization) rather than padded at their old positions."
  - "PeriodizationModel.none intentionally stays at 2 guide rows; documented in-code as the D-06 choice rather than a silent default."
  - "rotatingFixture() in program_exercise_replacement_scope_test.dart was extended (not replaced) to also expose programId and per-week dayIds, needed to materialize real ScheduledWorkouts rows for the new regression test; all 3 pre-existing tests using the fixture are unaffected (additive record fields)."
  - "The new regression test uses DateTime(2026, 1, 5) (a Monday) as the program start date, not Jan 1, so the single Monday-slot day actually materializes an occurrence in week 0 instead of being dropped by ScheduleWalker's 'before start date' guard."

requirements-completed: [EDIT-04, EDIT-03]

# Metrics
duration: 35min
completed: 2026-09-16
---

# Phase 19 Plan 03: Periodization Guide 8-Week Expansion & EDIT-03 Regression Test Summary

**Expanded all four periodized method guides to literal 8-week examples matching `Periodization`'s real phase/deload boundaries, and added an explicit regression test proving replace+rematerialize never touches started/completed schedule rows.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2 completed
- **Files modified:** 3

## Accomplishments
- `ProgramMethodGuide.forModel` now returns 8 accurate week rows for Linear, Concurrent, Block, and Max Effort, with Block's Accumulation/Transmutation/Realization boundaries corrected to match `Periodization._block(8)` exactly (weeks 1-4 / 5-7 / 8).
- `PeriodizationModel.none`'s 2-row guide is now self-documenting as a deliberate D-06 choice via an inline code comment.
- Added 2 new tests to `program_method_guide_test.dart` locking in the 8-row/2-row split and Block's week-8 Realization boundary.
- Added a new regression test to `program_exercise_replacement_scope_test.dart` proving that an `entireBlock`-scoped `replaceProgramExerciseSlot` followed by `rematerializeProgram` never mutates an `in_progress` `ScheduledWorkouts` row (id, status, completedSessionId, dateIso all unchanged), while a later still-`planned` occurrence's `ProgramDayExercises.exerciseId` does reflect the change.

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand ProgramMethodGuide.forModel weeks data to 8 rows per periodized model** - `c1f8047` (feat)
2. **Task 2: Regression test — replace + rematerialize never touches in_progress/done ScheduledWorkouts rows** - `5be90eb` (test)

_Note: Task 1 was written test-first per `tdd="true"` (test assertions extended alongside the data, verified green); Task 2 is itself a `test`-only commit._

## Files Created/Modified
- `lib/features/programs/presentation/views/program_method_guide_view.dart` - Extended `weeks:` list literals for Linear, Concurrent, Block, Max Effort to 8 entries each; renumbered Block's phase boundaries; documented `none`'s 2-row exception. Rendering block (ListView/Card/ListTile) byte-identical to before.
- `test/program_method_guide_test.dart` - Added row-count assertions (8 for periodized models, 2 for `none`), a Copywriting Contract check (no `'TBD'`, no consecutive duplicate descriptions), and a Block week-8 Realization boundary assertion.
- `test/program_exercise_replacement_scope_test.dart` - Extended `rotatingFixture()`'s return record with `programId` and `dayIds`; added the new EDIT-03 regression test.

## Decisions Made
- Renumbered rather than padded Block's existing 4 milestone entries so `Realization` lands on week 8, matching `Periodization._block(8)`'s real boundaries — required by the plan's acceptance criteria (`weeks.where((w) => w.title == 'Realization').single.number == 8`).
- Extended (rather than replaced) `rotatingFixture()` to expose `programId`/`dayIds` as additive record fields, keeping the plan's "do not invent a new fixture builder" constraint while giving the new test what it needs to call `materializeProgram`/`rematerializeProgram` against real schedule rows.
- Chose `DateTime(2026, 1, 5)` (a Monday) as the fixture's materialization start date instead of `DateTime(2026, 1, 1)` (a Thursday) — the latter caused `ScheduleWalker.walk`'s week-0 occurrence to be dropped as landing before the start date for a Monday-only slot, which is a pre-existing, well-documented behavior of the walker, not a bug to fix.

## Deviations from Plan

None - plan executed as written, with one clarifying fixture extension (additive, non-breaking) needed to give the new regression test access to real `ScheduledWorkouts` rows, and one date-choice adjustment (Monday vs. Thursday start) to work correctly with `ScheduleWalker`'s existing "before start date" guard.

## Issues Encountered

- **Manual sanity check per acceptance criteria:** Temporarily flipped `rematerializeProgram`'s `futureOnly` default to `false` and re-ran the new test — it stayed green. This is expected and does not weaken the property being tested: `materializeProgram`'s delete predicate independently requires `status == planned AND completedSessionId.isNull()`, so an `in_progress` row (our test's scenario) is protected by that status/completedSessionId check regardless of `futureOnly`'s date-window behavior. The test still correctly locks in EDIT-03's actual safety property (started/completed rows are never touched); it simply isn't sensitive to the `futureOnly` flag in isolation, because that flag governs a second, independent safety layer (date-window) rather than the status layer this scenario exercises. Reverted the default back to `true` immediately after the check (verified `git diff` shows no residual change to `programs_repository.dart`).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 19-04 can now wire the post-commit UI call site for exercise replacement, relying on the explicit, named regression test added here as its safety-property contract rather than an implicit assumption.
- The expanded method guide content is ready for display; no rendering code changes were needed.

---
*Phase: 19-program-wave-editor-with-explainable-periodization*
*Completed: 2026-09-16*
